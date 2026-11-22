locals {
  security_groups = {
    alb = {
      description = "HTTPS entry point; ingress is restricted to approved operator CIDRs."
    }
    dcc_control = {
      description = "DCC control-plane API; accepts requests from the ALB and diagnostic workers."
    }
    diagnostic_worker = {
      description = "On-demand diagnostic workers; no inbound traffic."
    }
    test_api = {
      description = "Application-under-test API; accepts traffic from DCC control and diagnostic workers."
    }
    test_worker = {
      description = "Background workers for the application under test; no inbound traffic."
    }
    database = {
      description = "Database tier; PostgreSQL ingress is limited to test API and test worker."
    }
    cache = {
      description = "Cache tier; Redis ingress is limited to test API and test worker."
    }
  }
}

resource "aws_security_group" "this" {
  for_each = local.security_groups

  name                   = "${var.name_prefix}-${each.key}"
  description            = each.value.description
  vpc_id                 = var.vpc_id
  revoke_rules_on_delete = true

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-${each.key}"
    Tier = each.key
  })
}

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  for_each = toset(var.operator_ingress_cidrs)

  security_group_id = aws_security_group.this["alb"].id
  description       = "HTTPS from an explicitly approved operator or VPN CIDR."
  cidr_ipv4         = each.value
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "dcc_control_from_alb" {
  security_group_id            = aws_security_group.this["dcc_control"].id
  description                  = "DCC control API traffic from the ALB."
  referenced_security_group_id = aws_security_group.this["alb"].id
  from_port                    = 8000
  to_port                      = 8000
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "dcc_control_from_diagnostic_worker" {
  security_group_id            = aws_security_group.this["dcc_control"].id
  description                  = "Signed diagnostic result callbacks from diagnostic workers."
  referenced_security_group_id = aws_security_group.this["diagnostic_worker"].id
  from_port                    = 8000
  to_port                      = 8000
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "test_api_from_dcc_control" {
  security_group_id            = aws_security_group.this["test_api"].id
  description                  = "Scoped test API access from the DCC control plane."
  referenced_security_group_id = aws_security_group.this["dcc_control"].id
  from_port                    = 8080
  to_port                      = 8080
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "test_api_from_diagnostic_worker" {
  security_group_id            = aws_security_group.this["test_api"].id
  description                  = "Diagnostic probes from on-demand diagnostic workers."
  referenced_security_group_id = aws_security_group.this["diagnostic_worker"].id
  from_port                    = 8080
  to_port                      = 8080
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "database_from_test_workloads" {
  for_each = toset(["test_api", "test_worker"])

  security_group_id            = aws_security_group.this["database"].id
  description                  = "PostgreSQL only from the test API and test worker."
  referenced_security_group_id = aws_security_group.this[each.value].id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "cache_from_test_workloads" {
  for_each = toset(["test_api", "test_worker"])

  security_group_id            = aws_security_group.this["cache"].id
  description                  = "Redis only from the test API and test worker."
  referenced_security_group_id = aws_security_group.this[each.value].id
  from_port                    = 6379
  to_port                      = 6379
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "alb_to_dcc_control" {
  security_group_id            = aws_security_group.this["alb"].id
  description                  = "Forward HTTPS listener traffic to the DCC control API."
  referenced_security_group_id = aws_security_group.this["dcc_control"].id
  from_port                    = 8000
  to_port                      = 8000
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "dcc_control_to_test_api" {
  security_group_id            = aws_security_group.this["dcc_control"].id
  description                  = "DCC control plane to the application-under-test API."
  referenced_security_group_id = aws_security_group.this["test_api"].id
  from_port                    = 8080
  to_port                      = 8080
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "diagnostic_worker_to_dcc_control" {
  security_group_id            = aws_security_group.this["diagnostic_worker"].id
  description                  = "Diagnostic worker result callback to DCC control plane."
  referenced_security_group_id = aws_security_group.this["dcc_control"].id
  from_port                    = 8000
  to_port                      = 8000
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "diagnostic_worker_to_test_api" {
  security_group_id            = aws_security_group.this["diagnostic_worker"].id
  description                  = "Diagnostic worker probes to the application-under-test API."
  referenced_security_group_id = aws_security_group.this["test_api"].id
  from_port                    = 8080
  to_port                      = 8080
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "test_api_to_database" {
  security_group_id            = aws_security_group.this["test_api"].id
  description                  = "Test API to PostgreSQL."
  referenced_security_group_id = aws_security_group.this["database"].id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "test_api_to_cache" {
  security_group_id            = aws_security_group.this["test_api"].id
  description                  = "Test API to Redis."
  referenced_security_group_id = aws_security_group.this["cache"].id
  from_port                    = 6379
  to_port                      = 6379
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "test_worker_to_database" {
  security_group_id            = aws_security_group.this["test_worker"].id
  description                  = "Test worker to PostgreSQL."
  referenced_security_group_id = aws_security_group.this["database"].id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "test_worker_to_cache" {
  security_group_id            = aws_security_group.this["test_worker"].id
  description                  = "Test worker to Redis."
  referenced_security_group_id = aws_security_group.this["cache"].id
  from_port                    = 6379
  to_port                      = 6379
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "dcc_control_https" {
  count = var.enable_dcc_control_https_egress ? 1 : 0

  security_group_id = aws_security_group.this["dcc_control"].id
  description       = "Optional outbound HTTPS for external APIs and AWS service endpoints."
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "diagnostic_worker_https" {
  count = var.enable_diagnostic_worker_https_egress ? 1 : 0

  security_group_id = aws_security_group.this["diagnostic_worker"].id
  description       = "Optional outbound HTTPS for external diagnostic integrations."
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "test_api_https" {
  count = var.enable_test_api_https_egress ? 1 : 0

  security_group_id = aws_security_group.this["test_api"].id
  description       = "Optional outbound HTTPS for application-under-test integrations."
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "test_worker_https" {
  count = var.enable_test_worker_https_egress ? 1 : 0

  security_group_id = aws_security_group.this["test_worker"].id
  description       = "Optional outbound HTTPS for background worker integrations."
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "diagnostic_worker_http" {
  for_each = var.enable_diagnostic_public_http_egress ? toset(["80", "443"]) : toset([])

  security_group_id = aws_security_group.this["diagnostic_worker"].id
  description       = "Optional public HTTP/HTTPS probes for diagnostic jobs."
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = tonumber(each.value)
  to_port           = tonumber(each.value)
  ip_protocol       = "tcp"
}
