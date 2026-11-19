locals {
  dcc_app_image = "${aws_ecr_repository.dcc_app.repository_url}@${var.dcc_app_image_digest}"
}

resource "aws_secretsmanager_secret" "dcc_django_key" {
  name                    = "dcc-app-django-secret-key"
  description             = "Django signing key for the private DCC ECS application."
  recovery_window_in_days = 7

  tags = {
    Name    = "dcc-app-django-secret-key"
    Project = "DCC"
  }
}

resource "aws_secretsmanager_secret_version" "dcc_django_key" {
  secret_id     = aws_secretsmanager_secret.dcc_django_key.id
  secret_string = var.dcc_django_secret
}

resource "aws_cloudwatch_log_group" "dcc_app" {
  name              = "${var.log_group_prefix}/dcc-app"
  retention_in_days = 7

  tags = {
    Name    = "dcc-app"
    Project = "DCC"
  }
}

resource "aws_service_discovery_service" "dcc_app" {
  name = "dcc-app"

  dns_config {
    namespace_id   = aws_service_discovery_private_dns_namespace.test_lab.id
    routing_policy = "MULTIVALUE"

    dns_records {
      ttl  = 10
      type = "A"
    }
  }

  tags = {
    Name    = "dcc-app"
    Project = "DCC"
  }
}

resource "aws_ecs_task_definition" "dcc_app" {
  family                   = "dcc-app"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 512
  memory                   = 1024
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.diagnostic_task.arn

  container_definitions = jsonencode([
    {
      name      = "dcc-app"
      image     = local.dcc_app_image
      essential = true
      user      = "10001:10001"
      environment = [
        { name = "DJANGO_DEBUG", value = "false" },
        { name = "DJANGO_ALLOWED_HOSTS", value = "dcc-app.dcc-test.internal,localhost,127.0.0.1" },
        { name = "DCC_CORS_ALLOWED_ORIGINS", value = "https://dcc-app.dcc-test.internal" },
        { name = "AWS_REGION", value = var.aws_region },
        { name = "AWS_DEFAULT_REGION", value = var.aws_region },
        { name = "DCC_ECS_CLUSTERS", value = aws_ecs_cluster.test_lab.name },
        { name = "DCC_ECS_CLUSTER", value = aws_ecs_cluster.test_lab.name },
        { name = "DCC_ECS_TASK_DEFINITION", value = aws_ecs_task_definition.diagnostic_runner.arn },
        { name = "DCC_ECS_SUBNETS", value = join(",", [for subnet in aws_subnet.private_application : subnet.id]) },
        { name = "DCC_ECS_SECURITY_GROUPS", value = aws_security_group.diagnostic_worker.id },
        { name = "DCC_ECS_CONTAINER_NAME", value = "diagnostic-runner" },
        { name = "DCC_ECS_ASSIGN_PUBLIC_IP", value = "false" },
        { name = "DCC_ECS_CLEANUP_ROLE_ARN", value = aws_iam_role.scheduler_cleanup.arn },
        { name = "DCC_ECS_CLEANUP_SCHEDULE_GROUP", value = aws_scheduler_schedule_group.dcc_cleanup.name },
        { name = "DCC_RUN_CAPABILITY_TTL_SECONDS", value = "1800" },
        { name = "DCC_STATELESS_RUN_API_ENABLED", value = "false" },
      ]
      secrets = [
        {
          name      = "DJANGO_SECRET_KEY"
          valueFrom = aws_secretsmanager_secret.dcc_django_key.arn
        }
      ]
      portMappings = [
        {
          name          = "http"
          containerPort = 8000
          hostPort      = 8000
          protocol      = "tcp"
        }
      ]
      healthCheck = {
        command     = ["CMD-SHELL", "python -c \"import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/api/health/', timeout=5)\""]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 30
      }
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.dcc_app.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "dcc"
        }
      }
    }
  ])

  tags = {
    Name    = "dcc-app"
    Project = "DCC"
  }
}

resource "aws_ecs_service" "dcc_app" {
  name            = "dcc-app-service"
  cluster         = aws_ecs_cluster.test_lab.id
  task_definition = aws_ecs_task_definition.dcc_app.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [for subnet in aws_subnet.private_application : subnet.id]
    security_groups  = [aws_security_group.dcc_control.id]
    assign_public_ip = false
  }

  service_registries {
    registry_arn = aws_service_discovery_service.dcc_app.arn
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.dcc_app.arn
    container_name   = "dcc-app"
    container_port   = 8000
  }

  depends_on = [
    aws_lb_listener.dcc_http,
    aws_cloudwatch_log_group.dcc_app,
    aws_cloudwatch_log_group.diagnostic_runner,
    aws_iam_role_policy.ecs_execution,
    aws_iam_role_policy.dcc_ecs_discovery,
    aws_iam_role_policy.dcc_scheduler_control,
    aws_iam_role_policy.dcc_run_diagnostic_task,
    aws_iam_role_policy.scheduler_cleanup,
    aws_secretsmanager_secret_version.dcc_django_key,
  ]

  tags = {
    Name    = "dcc-app-service"
    Project = "DCC"
  }
}

# The runner is a separate one-shot Fargate task, never a long-running service.
resource "aws_cloudwatch_log_group" "diagnostic_runner" {
  name              = "${var.log_group_prefix}/diagnostic-runner"
  retention_in_days = 7

  tags = {
    Name    = "dcc-diagnostic-runner"
    Project = "DCC"
  }
}

resource "aws_ecs_task_definition" "diagnostic_runner" {
  family                   = "dcc-diagnostic-runner"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.diagnostic_runner_task.arn

  container_definitions = jsonencode([
    {
      name      = "diagnostic-runner"
      image     = local.dcc_app_image
      essential = true
      user      = "10001:10001"
      command   = ["python", "-m", "apps.diagnostics.runner"]
      environment = [
        { name = "AWS_REGION", value = var.aws_region },
        { name = "AWS_DEFAULT_REGION", value = var.aws_region },
        { name = "LOG_LEVEL", value = "INFO" },
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.diagnostic_runner.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "runner"
        }
      }
    }
  ])

  tags = {
    Name    = "dcc-diagnostic-runner"
    Project = "DCC"
  }
}
