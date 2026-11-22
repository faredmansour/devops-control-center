locals {
  security_groups = {
    alb = {
      description = "Shared HTTP entry point for the isolated DCC and E-commerce test applications."
    }
    dcc_control = {
      description = "DCC control-plane API; accepts traffic only from the shared ALB and approved test workers."
    }
    dcc_agent = {
      description = "Reusable DCC integration agent; no inbound network access."
    }
    diagnostic_worker = {
      description = "Temporary diagnostic workers; no inbound network access."
    }
    ecommerce_frontend = {
      description = "E-commerce frontend served by Nginx on TCP 80."
    }
    ecommerce_backend = {
      description = "E-commerce Node.js/Express API on TCP 8000; sole Atlas client."
    }
    test_worker = {
      description = "Temporary test workers; no inbound network access."
    }
    cache = {
      description = "Optional private Redis cache; reachable only from the E-commerce backend."
    }
  }
}

resource "aws_security_group" "this" {
  for_each = local.security_groups

  name                   = "${var.name_prefix}-${each.key}"
  description            = each.value.description
  vpc_id                 = var.vpc_id
  ingress                = []
  egress                 = []
  revoke_rules_on_delete = true

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-${each.key}"
    Tier = each.key
  })
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  for_each = toset(var.alb_ingress_cidrs)

  security_group_id = aws_security_group.this["alb"].id
  description       = "HTTP test access to the shared ALB on ports 80 and 8080."
  cidr_ipv4         = each.value
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "alb_dcc_http" {
  for_each = toset(var.alb_ingress_cidrs)

  security_group_id = aws_security_group.this["alb"].id
  description       = "HTTP test access to the DCC listener on port 8080."
  cidr_ipv4         = each.value
  from_port         = 8080
  to_port           = 8080
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "dcc_control_from_alb" {
  security_group_id            = aws_security_group.this["dcc_control"].id
  description                  = "DCC control API traffic from the shared ALB."
  referenced_security_group_id = aws_security_group.this["alb"].id
  from_port                    = 8000
  to_port                      = 8000
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "dcc_control_from_agent" {
  security_group_id            = aws_security_group.this["dcc_control"].id
  description                  = "Authenticated integration-agent requests to DCC control."
  referenced_security_group_id = aws_security_group.this["dcc_agent"].id
  from_port                    = 8000
  to_port                      = 8000
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "dcc_control_from_test_worker" {
  security_group_id            = aws_security_group.this["dcc_control"].id
  description                  = "Test-worker result callbacks to DCC control."
  referenced_security_group_id = aws_security_group.this["test_worker"].id
  from_port                    = 8000
  to_port                      = 8000
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "ecommerce_frontend_from_alb" {
  security_group_id            = aws_security_group.this["ecommerce_frontend"].id
  description                  = "HTTP from the shared ALB to the Nginx frontend."
  referenced_security_group_id = aws_security_group.this["alb"].id
  from_port                    = 80
  to_port                      = 80
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "ecommerce_backend_from_alb" {
  security_group_id            = aws_security_group.this["ecommerce_backend"].id
  description                  = "API and health-check traffic from the shared ALB."
  referenced_security_group_id = aws_security_group.this["alb"].id
  from_port                    = 8000
  to_port                      = 8000
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "ecommerce_backend_from_diagnostic_worker" {
  security_group_id            = aws_security_group.this["ecommerce_backend"].id
  description                  = "Scoped API and diagnostic probes from temporary diagnostic workers."
  referenced_security_group_id = aws_security_group.this["diagnostic_worker"].id
  from_port                    = 8000
  to_port                      = 8000
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "ecommerce_backend_from_test_worker" {
  security_group_id            = aws_security_group.this["ecommerce_backend"].id
  description                  = "Authorized test traffic from temporary DCC test workers."
  referenced_security_group_id = aws_security_group.this["test_worker"].id
  from_port                    = 8000
  to_port                      = 8000
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "cache_from_ecommerce_backend" {
  security_group_id            = aws_security_group.this["cache"].id
  description                  = "Optional Redis access from the E-commerce backend only."
  referenced_security_group_id = aws_security_group.this["ecommerce_backend"].id
  from_port                    = 6379
  to_port                      = 6379
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "alb_to_dcc_control" {
  security_group_id            = aws_security_group.this["alb"].id
  description                  = "Forward DCC listener traffic to the DCC API."
  referenced_security_group_id = aws_security_group.this["dcc_control"].id
  from_port                    = 8000
  to_port                      = 8000
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "alb_to_ecommerce_frontend" {
  security_group_id            = aws_security_group.this["alb"].id
  description                  = "Forward E-commerce web traffic to Nginx."
  referenced_security_group_id = aws_security_group.this["ecommerce_frontend"].id
  from_port                    = 80
  to_port                      = 80
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "alb_to_ecommerce_backend" {
  security_group_id            = aws_security_group.this["alb"].id
  description                  = "Forward E-commerce API, health, and upload traffic to Express."
  referenced_security_group_id = aws_security_group.this["ecommerce_backend"].id
  from_port                    = 8000
  to_port                      = 8000
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "ecommerce_backend_to_atlas" {
  security_group_id = aws_security_group.this["ecommerce_backend"].id
  description       = "MongoDB Atlas TLS connection; Atlas IP Access List constrains the remote source."
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 27017
  to_port           = 27017
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "ecommerce_backend_to_cache" {
  security_group_id            = aws_security_group.this["ecommerce_backend"].id
  description                  = "Optional private Redis cache connection."
  referenced_security_group_id = aws_security_group.this["cache"].id
  from_port                    = 6379
  to_port                      = 6379
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "dcc_agent_to_control" {
  security_group_id            = aws_security_group.this["dcc_agent"].id
  description                  = "Agent-initiated authenticated communication to the DCC control API."
  referenced_security_group_id = aws_security_group.this["dcc_control"].id
  from_port                    = 8000
  to_port                      = 8000
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "diagnostic_worker_to_ecommerce_backend" {
  security_group_id            = aws_security_group.this["diagnostic_worker"].id
  description                  = "Diagnostic probes to the E-commerce API only."
  referenced_security_group_id = aws_security_group.this["ecommerce_backend"].id
  from_port                    = 8000
  to_port                      = 8000
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "diagnostic_worker_to_dcc_control" {
  security_group_id            = aws_security_group.this["diagnostic_worker"].id
  description                  = "Diagnostic result callbacks to the DCC control API."
  referenced_security_group_id = aws_security_group.this["dcc_control"].id
  from_port                    = 8000
  to_port                      = 8000
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "test_worker_to_ecommerce_backend" {
  security_group_id            = aws_security_group.this["test_worker"].id
  description                  = "Authorized API/load/security test traffic to the E-commerce backend."
  referenced_security_group_id = aws_security_group.this["ecommerce_backend"].id
  from_port                    = 8000
  to_port                      = 8000
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "test_worker_to_dcc_control" {
  security_group_id            = aws_security_group.this["test_worker"].id
  description                  = "Test result and lifecycle callbacks to DCC control."
  referenced_security_group_id = aws_security_group.this["dcc_control"].id
  from_port                    = 8000
  to_port                      = 8000
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "dcc_control_https" {
  for_each = toset(var.dcc_control_https_egress_cidrs)

  security_group_id = aws_security_group.this["dcc_control"].id
  description       = "Optional outbound HTTPS to explicitly approved DCC destinations."
  cidr_ipv4         = each.value
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "diagnostic_worker_https" {
  for_each = toset(var.diagnostic_worker_https_egress_cidrs)

  security_group_id = aws_security_group.this["diagnostic_worker"].id
  description       = "Optional outbound HTTPS to explicitly approved diagnostic destinations."
  cidr_ipv4         = each.value
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "test_worker_https" {
  for_each = toset(var.test_worker_https_egress_cidrs)

  security_group_id = aws_security_group.this["test_worker"].id
  description       = "Optional outbound HTTPS to explicitly approved test destinations."
  cidr_ipv4         = each.value
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "diagnostic_worker_http" {
  for_each = {
    for pair in setproduct(var.diagnostic_public_http_egress_cidrs, [80, 443]) :
    "${pair[0]}-${pair[1]}" => {
      cidr = pair[0]
      port = pair[1]
    }
  }

  security_group_id = aws_security_group.this["diagnostic_worker"].id
  description       = "Optional HTTP/HTTPS probes to explicitly approved public destinations."
  cidr_ipv4         = each.value.cidr
  from_port         = each.value.port
  to_port           = each.value.port
  ip_protocol       = "tcp"
}
