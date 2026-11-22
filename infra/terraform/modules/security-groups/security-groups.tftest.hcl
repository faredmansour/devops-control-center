mock_provider "aws" {}

run "creates_six_isolated_security_groups_with_safe_defaults" {
  command = plan

  variables {
    name_prefix            = "dcc-sg-test"
    vpc_id                 = "vpc-0123456789abcdef0"
    operator_ingress_cidrs = ["203.0.113.10/32"]
    tags                   = { Environment = "test" }
  }

  assert {
    condition     = length(aws_security_group.this) == 6
    error_message = "The module must create exactly six tier-specific Security Groups."
  }

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.alb_https) == 1
    error_message = "Only the explicitly approved operator CIDR should receive ALB HTTPS ingress."
  }

  assert {
    condition     = length(aws_vpc_security_group_egress_rule.application_https) == 0 && length(aws_vpc_security_group_egress_rule.worker_https) == 0 && length(aws_vpc_security_group_egress_rule.diagnostics_http) == 0
    error_message = "Public egress must remain disabled by default."
  }

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.database_from_application) == 2 && length(aws_vpc_security_group_ingress_rule.cache_from_application) == 2
    error_message = "Database and cache ingress must be limited to the application and worker Security Groups."
  }
}

run "allows_public_egress_only_when_explicitly_enabled" {
  command = plan

  variables {
    name_prefix                     = "dcc-sg-test"
    vpc_id                          = "vpc-0123456789abcdef0"
    operator_ingress_cidrs          = []
    enable_application_https_egress = true
    enable_worker_https_egress      = true
    enable_diagnostics_http_egress  = true
  }

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.alb_https) == 0
    error_message = "An empty approved CIDR list must leave the ALB without inbound rules."
  }

  assert {
    condition     = length(aws_vpc_security_group_egress_rule.application_https) == 1 && length(aws_vpc_security_group_egress_rule.worker_https) == 1 && length(aws_vpc_security_group_egress_rule.diagnostics_http) == 2
    error_message = "Explicit egress opt-ins must create only their documented rules."
  }
}

run "rejects_invalid_operator_cidr" {
  command = plan

  variables {
    name_prefix            = "dcc-sg-test"
    vpc_id                 = "vpc-0123456789abcdef0"
    operator_ingress_cidrs = ["not-a-cidr"]
  }

  expect_failures = [
    var.operator_ingress_cidrs,
  ]
}
