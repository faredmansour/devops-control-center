mock_provider "aws" {}

run "creates_nine_separate_workload_security_groups_with_safe_ingress_defaults" {
  command = plan

  variables {
    name_prefix            = "dcc-sg-test"
    vpc_id                 = "vpc-0123456789abcdef0"
    operator_ingress_cidrs = ["203.0.113.10/32"]
    tags                   = { Environment = "test" }
  }

  assert {
    condition     = length(aws_security_group.this) == 9
    error_message = "The module must create nine isolated workload Security Groups."
  }

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.dcc_alb_https) == 1 && length(aws_vpc_security_group_ingress_rule.ecommerce_alb_https) == 0
    error_message = "Only the explicitly approved DCC operator CIDR should receive ingress by default."
  }

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.ecommerce_backend_from_frontend) == 1 && length(aws_vpc_security_group_ingress_rule.ecommerce_backend_from_diagnostic_worker) == 1 && length(aws_vpc_security_group_ingress_rule.ecommerce_backend_from_test_worker) == 1
    error_message = "The E-commerce API must accept traffic only from the frontend and approved temporary workers."
  }

  assert {
    condition     = aws_vpc_security_group_egress_rule.ecommerce_backend_to_atlas.from_port == 27017 && aws_vpc_security_group_egress_rule.ecommerce_backend_to_atlas.cidr_ipv4 == "0.0.0.0/0"
    error_message = "The E-commerce backend must have only TCP 27017 egress for public Atlas connectivity; Atlas IP Access List constrains the remote source."
  }

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.cache_from_ecommerce_backend) == 1
    error_message = "The optional cache must accept connections only from the E-commerce backend."
  }

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.dcc_control_from_alb) == 1 && length(aws_vpc_security_group_ingress_rule.dcc_control_from_agent) == 1 && length(aws_vpc_security_group_ingress_rule.dcc_control_from_test_worker) == 1
    error_message = "DCC control ingress must be limited to its ALB, integration agent, and temporary test workers."
  }

  assert {
    condition     = aws_vpc_security_group_egress_rule.dcc_agent_to_control.from_port == 8000
    error_message = "The integration agent must initiate its control channel to DCC; no inbound agent rule is allowed."
  }
}

run "allows_only_explicit_public_ingress_and_optional_https_egress" {
  command = plan

  variables {
    name_prefix               = "dcc-sg-test"
    vpc_id                    = "vpc-0123456789abcdef0"
    operator_ingress_cidrs    = []
    ecommerce_ingress_cidrs   = ["198.51.100.10/32"]
    dcc_control_https_egress_cidrs = ["198.51.100.0/24"]
    diagnostic_worker_https_egress_cidrs = ["198.51.101.0/24"]
    test_worker_https_egress_cidrs = ["198.51.102.0/24"]
    diagnostic_public_http_egress_cidrs = ["203.0.113.0/24"]
  }

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.dcc_alb_https) == 0 && length(aws_vpc_security_group_ingress_rule.ecommerce_alb_https) == 1
    error_message = "Each public ALB ingress policy must be controlled by its own explicit allowlist."
  }

  assert {
    condition     = length(aws_vpc_security_group_egress_rule.dcc_control_https) == 1 && length(aws_vpc_security_group_egress_rule.diagnostic_worker_https) == 1 && length(aws_vpc_security_group_egress_rule.test_worker_https) == 1 && length(aws_vpc_security_group_egress_rule.diagnostic_worker_http) == 2
    error_message = "Optional public egress must create only explicitly configured rules."
  }
}

run "rejects_invalid_operator_or_ecommerce_cidr" {
  command = plan

  variables {
    name_prefix             = "dcc-sg-test"
    vpc_id                  = "vpc-0123456789abcdef0"
    operator_ingress_cidrs  = ["not-a-cidr"]
    ecommerce_ingress_cidrs = ["also-not-a-cidr"]
  }

  expect_failures = [
    var.operator_ingress_cidrs,
    var.ecommerce_ingress_cidrs,
  ]
}
