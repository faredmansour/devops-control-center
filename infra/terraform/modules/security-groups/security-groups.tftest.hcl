mock_provider "aws" {}

run "creates_isolated_workload_groups_and_shared_alb_ingress" {
  command = plan

  variables {
    name_prefix       = "dcc-sg-test"
    vpc_id            = "vpc-0123456789abcdef0"
    alb_ingress_cidrs = ["203.0.113.10/32"]
    tags              = { Environment = "test" }
  }

  assert {
    condition     = length(aws_security_group.this) == 8
    error_message = "The module must create eight isolated workload Security Groups."
  }

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.alb_http) == 1 && length(aws_vpc_security_group_ingress_rule.alb_dcc_http) == 1
    error_message = "The shared ALB must allow only explicitly approved HTTP access on ports 80 and 8080."
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.ecommerce_backend_from_alb.from_port == 8000 && aws_vpc_security_group_ingress_rule.ecommerce_backend_from_diagnostic_worker.from_port == 8000 && aws_vpc_security_group_ingress_rule.ecommerce_backend_from_test_worker.from_port == 8000
    error_message = "The E-commerce API must accept traffic only from the shared ALB and approved temporary workers."
  }

  assert {
    condition     = aws_vpc_security_group_egress_rule.ecommerce_backend_to_atlas.from_port == 27017 && aws_vpc_security_group_egress_rule.ecommerce_backend_to_atlas.cidr_ipv4 == "0.0.0.0/0"
    error_message = "The E-commerce backend must have port-limited TCP 27017 egress for Atlas; Atlas IP Access List constrains the remote source."
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.cache_from_ecommerce_backend.from_port == 6379
    error_message = "The optional cache must accept connections only from the E-commerce backend."
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.dcc_control_from_alb.from_port == 8000 && aws_vpc_security_group_ingress_rule.dcc_control_from_agent.from_port == 8000 && aws_vpc_security_group_ingress_rule.dcc_control_from_test_worker.from_port == 8000
    error_message = "DCC control ingress must be limited to the shared ALB, integration agent, and temporary test workers."
  }
}

run "keeps_public_ingress_closed_when_no_client_cidr_is_approved" {
  command = plan

  variables {
    name_prefix       = "dcc-sg-test"
    vpc_id            = "vpc-0123456789abcdef0"
    alb_ingress_cidrs = []
  }

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.alb_http) == 0 && length(aws_vpc_security_group_ingress_rule.alb_dcc_http) == 0
    error_message = "The shared ALB must remain closed when no public client CIDR is approved."
  }
}

run "rejects_invalid_alb_cidr" {
  command = plan

  variables {
    name_prefix       = "dcc-sg-test"
    vpc_id            = "vpc-0123456789abcdef0"
    alb_ingress_cidrs = ["not-a-cidr"]
  }

  expect_failures = [var.alb_ingress_cidrs]
}
