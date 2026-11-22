locals {
  security_groups = {
    alb = {
      name        = "alb"
      description = "Public entry point; ingress is restricted to approved operator CIDRs."
    }
    application = {
      name        = "application"
      description = "Application tasks; accepts traffic only from the ALB."
    }
    worker = {
      name        = "worker"
      description = "Background worker tasks; no inbound traffic."
    }
    database = {
      name        = "database"
      description = "Database tier; accepts PostgreSQL only from application and worker tasks."
    }
    cache = {
      name        = "cache"
      description = "Cache tier; accepts Redis only from application and worker tasks."
    }
    diagnostics = {
      name        = "diagnostics"
      description = "On-demand diagnostic tasks; no inbound traffic."
    }
  }
}

resource "aws_security_group" "this" {
  for_each = local.security_groups

  name                   = "${var.name_prefix}-${each.value.name}"
  description            = each.value.description
  vpc_id                 = var.vpc_id
  revoke_rules_on_delete = true
  ingress                = []
  egress                 = []

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-${each.value.name}"
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

resource "aws_vpc_security_group_ingress_rule" "application_from_alb" {
  security_group_id            = aws_security_group.this["application"].id
  description                  = "Application HTTP traffic from the ALB only."
  referenced_security_group_id = aws_security_group.this["alb"].id
  from_port                    = 80
  to_port                      = 80
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "database_from_application" {
  for_each = toset(["application", "worker"])

  security_group_id            = aws_security_group.this["database"].id
  description                  = "PostgreSQL from approved workload security groups."
  referenced_security_group_id = aws_security_group.this[each.value].id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "cache_from_application" {
  for_each = toset(["application", "worker"])

  security_group_id            = aws_security_group.this["cache"].id
  description                  = "Redis from approved workload security groups."
  referenced_security_group_id = aws_security_group.this[each.value].id
  from_port                    = 6379
  to_port                      = 6379
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "alb_to_application" {
  security_group_id            = aws_security_group.this["alb"].id
  description                  = "Forward ALB traffic to the application target port."
  referenced_security_group_id = aws_security_group.this["application"].id
  from_port                    = 80
  to_port                      = 80
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "application_to_database" {
  security_group_id            = aws_security_group.this["application"].id
  description                  = "Application to PostgreSQL."
  referenced_security_group_id = aws_security_group.this["database"].id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "application_to_cache" {
  security_group_id            = aws_security_group.this["application"].id
  description                  = "Application to Redis."
  referenced_security_group_id = aws_security_group.this["cache"].id
  from_port                    = 6379
  to_port                      = 6379
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "worker_to_database" {
  security_group_id            = aws_security_group.this["worker"].id
  description                  = "Background worker to PostgreSQL."
  referenced_security_group_id = aws_security_group.this["database"].id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "worker_to_cache" {
  security_group_id            = aws_security_group.this["worker"].id
  description                  = "Background worker to Redis."
  referenced_security_group_id = aws_security_group.this["cache"].id
  from_port                    = 6379
  to_port                      = 6379
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "application_https" {
  count = var.enable_application_https_egress ? 1 : 0

  security_group_id = aws_security_group.this["application"].id
  description       = "Optional outbound HTTPS for external APIs and AWS service endpoints."
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "worker_https" {
  count = var.enable_worker_https_egress ? 1 : 0

  security_group_id = aws_security_group.this["worker"].id
  description       = "Optional outbound HTTPS for external integrations."
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "diagnostics_http" {
  for_each = var.enable_diagnostics_http_egress ? toset(["80", "443"]) : toset([])

  security_group_id = aws_security_group.this["diagnostics"].id
  description       = "Optional diagnostic probe traffic to public HTTP/HTTPS endpoints."
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = tonumber(each.value)
  to_port           = tonumber(each.value)
  ip_protocol       = "tcp"
}
