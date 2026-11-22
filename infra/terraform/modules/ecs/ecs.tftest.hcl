mock_provider "aws" {}

run "plans_three_separate_fargate_services_behind_one_alb" {
  command = plan

  variables {
    name_prefix                    = "dcc-testlab"
    aws_region                     = "us-east-1"
    aws_account_id                 = "123456789012"
    vpc_id                         = "vpc-0123456789abcdef0"
    public_subnet_ids              = ["subnet-11111111", "subnet-22222222"]
    private_application_subnet_ids = ["subnet-33333333", "subnet-44444444"]
    alb_security_group_id          = "sg-11111111"
    dcc_security_group_id          = "sg-22222222"
    ecommerce_frontend_sg_id       = "sg-33333333"
    ecommerce_backend_sg_id        = "sg-44444444"
    dcc_execution_role_arn         = "arn:aws:iam::123456789012:role/dcc-execution"
    dcc_task_role_arn              = "arn:aws:iam::123456789012:role/dcc-task"
    ecommerce_execution_role_arn   = "arn:aws:iam::123456789012:role/ecommerce-execution"
    ecommerce_task_role_arn        = "arn:aws:iam::123456789012:role/ecommerce-task"
    dcc_image                      = "123456789012.dkr.ecr.us-east-1.amazonaws.com/dcc:bootstrap"
    ecommerce_frontend_image       = "123456789012.dkr.ecr.us-east-1.amazonaws.com/ecommerce:frontend-bootstrap"
    ecommerce_backend_image        = "123456789012.dkr.ecr.us-east-1.amazonaws.com/ecommerce:backend-bootstrap"
    mongodb_atlas_secret_arn       = "arn:aws:secretsmanager:us-east-1:123456789012:secret:ecommerce-db"
    jwt_secret_arn                 = "arn:aws:secretsmanager:us-east-1:123456789012:secret:ecommerce-jwt"
    enable_application_services    = true
    tags                           = { Environment = "test" }
  }

  assert {
    condition     = aws_lb.this.load_balancer_type == "application" && aws_lb_listener.ecommerce.port == 80 && aws_lb_listener.dcc.port == 8080
    error_message = "The test lab must use one ALB with E-commerce on port 80 and DCC on port 8080."
  }

  assert {
    condition     = contains(aws_ecs_task_definition.dcc.requires_compatibilities, "FARGATE") && contains(aws_ecs_task_definition.ecommerce_frontend.requires_compatibilities, "FARGATE") && contains(aws_ecs_task_definition.ecommerce_backend.requires_compatibilities, "FARGATE")
    error_message = "All three application task definitions must use Fargate."
  }

  assert {
    condition     = aws_ecs_service.dcc.desired_count == 1 && aws_ecs_service.ecommerce_frontend.desired_count == 1 && aws_ecs_service.ecommerce_backend.desired_count == 1
    error_message = "Each test application component must start with one task."
  }

  assert {
    condition     = contains(flatten([for condition in aws_lb_listener_rule.ecommerce_api.condition : [for path in condition.path_pattern : path.values]]), "/api/*") && contains(flatten([for condition in aws_lb_listener_rule.ecommerce_api.condition : [for path in condition.path_pattern : path.values]]), "/uploadimage/*")
    error_message = "E-commerce API, health, and upload paths must route to the backend target group."
  }

  assert {
    condition     = aws_ecs_task_definition.ecommerce_backend.container_definitions != ""
    error_message = "The E-commerce backend task definition must contain its container configuration."
  }
}
