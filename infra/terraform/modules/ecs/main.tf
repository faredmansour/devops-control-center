locals {
  log_group_names = {
    dcc                = "/ecs/${var.name_prefix}/dcc"
    ecommerce_frontend = "/ecs/${var.name_prefix}/ecommerce-frontend"
    ecommerce_backend  = "/ecs/${var.name_prefix}/ecommerce-backend"
  }
}

resource "aws_cloudwatch_log_group" "this" {
  for_each          = local.log_group_names
  name              = each.value
  retention_in_days = 7
  tags              = var.tags
}

resource "aws_ecs_cluster" "this" {
  name = "${var.name_prefix}-cluster"
  setting {
    name  = "containerInsights"
    value = "disabled"
  }
  tags = var.tags
}

resource "aws_lb" "this" {
  name               = substr("${var.name_prefix}-alb", 0, 32)
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.alb_security_group_id]
  subnets            = var.public_subnet_ids
  tags               = var.tags
}

resource "aws_lb_target_group" "ecommerce_frontend" {
  name        = substr("${var.name_prefix}-web-tg", 0, 32)
  port        = 80
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = var.vpc_id
  health_check {
    enabled             = true
    path                = "/"
    matcher             = "200-399"
    interval            = 30
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
  tags = var.tags
}

resource "aws_lb_target_group" "ecommerce_backend" {
  name        = substr("${var.name_prefix}-api-tg", 0, 32)
  port        = 8000
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = var.vpc_id
  health_check {
    enabled             = true
    path                = "/health"
    matcher             = "200"
    interval            = 30
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
  tags = var.tags
}

resource "aws_lb_target_group" "dcc" {
  name        = substr("${var.name_prefix}-dcc-tg", 0, 32)
  port        = 8000
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = var.vpc_id
  health_check {
    enabled             = true
    path                = "/api/health/"
    matcher             = "200-399"
    interval            = 30
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
  tags = var.tags
}

resource "aws_lb_listener" "ecommerce" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ecommerce_frontend.arn
  }
}

resource "aws_lb_listener_rule" "ecommerce_api" {
  listener_arn = aws_lb_listener.ecommerce.arn
  priority     = 10
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ecommerce_backend.arn
  }
  condition {
    path_pattern {
      values = ["/api/*", "/health", "/uploadimage", "/uploadimage/*"]
    }
  }
}

resource "aws_lb_listener" "dcc" {
  load_balancer_arn = aws_lb.this.arn
  port              = 8080
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.dcc.arn
  }
}

resource "aws_ecs_task_definition" "dcc" {
  family                   = "${var.name_prefix}-dcc"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = var.dcc_execution_role_arn
  task_role_arn            = var.dcc_task_role_arn
  container_definitions = jsonencode([{
    name         = "dcc"
    image        = var.dcc_image
    essential    = true
    portMappings = [{ containerPort = 8000, hostPort = 8000, protocol = "tcp" }]
    environment = [
      { name = "AWS_REGION", value = var.aws_region },
      { name = "DJANGO_DEBUG", value = "true" },
      { name = "DJANGO_ALLOWED_HOSTS", value = "${aws_lb.this.dns_name},localhost,127.0.0.1" },
      { name = "DCC_CLOUDWATCH_REGION", value = var.aws_region },
      { name = "DCC_CLOUDWATCH_CLUSTER_NAME", value = aws_ecs_cluster.this.name },
      { name = "DCC_CLOUDWATCH_SERVICE_NAME", value = "${var.name_prefix}-dcc" }
    ]
    healthCheck = {
      command     = ["CMD-SHELL", "python -c \"import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/api/health/', timeout=4).read()\""]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 45
    }
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.this["dcc"].name
        awslogs-region        = var.aws_region
        awslogs-stream-prefix = "ecs"
      }
    }
  }])
  tags = var.tags
}

resource "aws_ecs_task_definition" "ecommerce_frontend" {
  family                   = "${var.name_prefix}-ecommerce-frontend"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = var.ecommerce_execution_role_arn
  task_role_arn            = var.ecommerce_task_role_arn
  container_definitions = jsonencode([{
    name         = "ecommerce-frontend"
    image        = var.ecommerce_frontend_image
    essential    = true
    portMappings = [{ containerPort = 80, hostPort = 80, protocol = "tcp" }]
    healthCheck = {
      command     = ["CMD-SHELL", "wget -q -O /dev/null http://127.0.0.1/ || exit 1"]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 20
    }
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.this["ecommerce_frontend"].name
        awslogs-region        = var.aws_region
        awslogs-stream-prefix = "ecs"
      }
    }
  }])
  tags = var.tags
}

resource "aws_ecs_task_definition" "ecommerce_backend" {
  family                   = "${var.name_prefix}-ecommerce-backend"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 512
  memory                   = 1024
  execution_role_arn       = var.ecommerce_execution_role_arn
  task_role_arn            = var.ecommerce_task_role_arn
  container_definitions = jsonencode([{
    name         = "ecommerce-backend"
    image        = var.ecommerce_backend_image
    essential    = true
    portMappings = [{ containerPort = 8000, hostPort = 8000, protocol = "tcp" }]
    environment = [
      { name = "NODE_ENV", value = "production" },
      { name = "PORT", value = "8000" },
      { name = "CLIENT_URL", value = "http://${aws_lb.this.dns_name}" }
    ]
    secrets = [
      { name = "DB_URL", valueFrom = var.mongodb_atlas_secret_arn },
      { name = "JWT_SECRET", valueFrom = var.jwt_secret_arn }
    ]
    healthCheck = {
      command     = ["CMD-SHELL", "node -e \"fetch('http://127.0.0.1:8000/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))\""]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 60
    }
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.this["ecommerce_backend"].name
        awslogs-region        = var.aws_region
        awslogs-stream-prefix = "ecs"
      }
    }
  }])
  tags = var.tags
}

resource "aws_ecs_service" "dcc" {
  name                               = "${var.name_prefix}-dcc"
  cluster                            = aws_ecs_cluster.this.id
  task_definition                    = aws_ecs_task_definition.dcc.arn
  desired_count                      = var.enable_application_services ? 1 : 0
  launch_type                        = "FARGATE"
  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100
  network_configuration {
    subnets          = var.private_application_subnet_ids
    security_groups  = [var.dcc_security_group_id]
    assign_public_ip = false
  }
  load_balancer {
    target_group_arn = aws_lb_target_group.dcc.arn
    container_name   = "dcc"
    container_port   = 8000
  }
  depends_on = [aws_lb_listener.dcc]
  tags       = var.tags
}

resource "aws_ecs_service" "ecommerce_frontend" {
  name                               = "${var.name_prefix}-ecommerce-web"
  cluster                            = aws_ecs_cluster.this.id
  task_definition                    = aws_ecs_task_definition.ecommerce_frontend.arn
  desired_count                      = var.enable_application_services ? 1 : 0
  launch_type                        = "FARGATE"
  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100
  network_configuration {
    subnets          = var.private_application_subnet_ids
    security_groups  = [var.ecommerce_frontend_sg_id]
    assign_public_ip = false
  }
  load_balancer {
    target_group_arn = aws_lb_target_group.ecommerce_frontend.arn
    container_name   = "ecommerce-frontend"
    container_port   = 80
  }
  depends_on = [aws_lb_listener.ecommerce]
  tags       = var.tags
}

resource "aws_ecs_service" "ecommerce_backend" {
  name                               = "${var.name_prefix}-ecommerce-api"
  cluster                            = aws_ecs_cluster.this.id
  task_definition                    = aws_ecs_task_definition.ecommerce_backend.arn
  desired_count                      = var.enable_application_services ? 1 : 0
  launch_type                        = "FARGATE"
  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100
  network_configuration {
    subnets          = var.private_application_subnet_ids
    security_groups  = [var.ecommerce_backend_sg_id]
    assign_public_ip = false
  }
  load_balancer {
    target_group_arn = aws_lb_target_group.ecommerce_backend.arn
    container_name   = "ecommerce-backend"
    container_port   = 8000
  }
  depends_on = [aws_lb_listener_rule.ecommerce_api]
  tags       = var.tags
}
