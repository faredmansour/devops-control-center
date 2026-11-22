# Security Groups — us-east-1 Test Lab Design

**Status:** Initial implementation is available in `infra/terraform/modules/security-groups`; review and plan validation are still required before any apply.

## Design principles

- Create new Security Groups in the independent `us-east-1` VPC; never import or reference IDs from `eu-north-1`.
- Keep ECS tasks in private application subnets with `assign_public_ip = false`.
- Keep RDS and Redis in private data subnets, with no public ingress.
- Use security-group references for east-west traffic; do not use VPC-wide CIDRs for workload-to-workload access.
- Manage all rules with standalone `aws_vpc_security_group_*_rule` resources. The `aws_security_group` resources must not declare inline `ingress` or `egress` arguments.
- No broad ingress on any task or data security group.

## Implemented traffic matrix

| Source SG | Destination SG | Protocol/port | Direction | Decision |
|---|---|---:|---|---|
| Approved admin CIDRs / VPN ingress | ALB SG | TCP 443 | Ingress | Allow only explicitly approved source ranges |
| ALB SG | DCC Control SG | TCP 8000 | Egress / ingress | Allow |
| Diagnostic Worker SG | DCC Control SG | TCP 8000 | Egress / ingress | Allow diagnostic result callbacks |
| DCC Control SG | Test API SG | TCP 8080 | Egress / ingress | Allow |
| Diagnostic Worker SG | Test API SG | TCP 8080 | Egress / ingress | Allow scoped diagnostic probes |
| Test API SG | Database SG | TCP 5432 | Egress / ingress | Allow |
| Test Worker SG | Database SG | TCP 5432 | Egress / ingress | Allow |
| Test API SG | Cache SG | TCP 6379 | Egress / ingress | Allow |
| Test Worker SG | Cache SG | TCP 6379 | Egress / ingress | Allow |

The module creates seven groups: `alb`, `dcc_control`, `diagnostic_worker`, `test_api`, `test_worker`, `database`, and `cache`.

## Default-deny and optional public egress

- `operator_ingress_cidrs` defaults to an empty list. Until approved CIDRs are supplied, the ALB has no inbound rule.
- Public HTTPS egress for DCC Control, Diagnostic Worker, Test API, and Test Worker is controlled by explicit destination CIDR allowlists, all empty by default.
- Diagnostic public HTTP/HTTPS probing uses a separate explicit destination CIDR allowlist, also empty by default.
- Database and Cache have no public ingress and no explicit public egress rules.
- No SSH/RDP ingress is created.
- ALB HTTP/80 is not exposed. If required, add it only with a separately implemented and reviewed HTTP-to-HTTPS redirect listener.

## Required review gates before apply

1. Confirm approved admin CIDRs or VPN ingress.
2. Confirm the actual container ports: DCC Control TCP 8000 and Test API TCP 8080.
3. Confirm ACM certificate ARN and domain ownership in `us-east-1`.
4. Confirm all VPC/subnet CIDRs are non-overlapping with connected networks.
5. Confirm no cross-region SG IDs, subnet IDs, RDS endpoints, Redis endpoints, or Cloud Map namespace IDs are reused.
6. Confirm ECR images have been built/pushed in `us-east-1` and task definitions pin immutable digests.
7. Inspect the full Terraform plan: no reference to or change against the `eu-north-1` state/resources.
8. Verify no `0.0.0.0/0` ingress except an explicitly approved HTTPS entry point.
9. Verify RDS/Redis are private and database/cache ingress is SG-scoped.
10. Preserve independent state and backend key for this environment.

## Important limitations

- This module defines network-layer permissions only. It does not create ALB listeners, TLS certificates, application authentication, database credentials, Redis authentication, secrets, or VPC endpoints.
- Optional public egress rules are restricted to explicitly supplied destination CIDRs; broad `0.0.0.0/0` egress is not configured by this module. Prefer VPC endpoints where practical.
- Security Groups are stateful; response traffic for permitted connections does not need a reverse rule.
- DNS resolver access is governed by VPC resolver behavior and cannot be controlled with ordinary SG rules targeting AmazonProvidedDNS.
- A plan review and, after approval, read-only post-deployment inspection must verify the effective AWS rules.

## State safety

The module is composed only into `test-lab-us-east-1`. Do not run state migration, apply, or destroy against the existing `eu-north-1` environment as part of this work.
