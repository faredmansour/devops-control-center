# Security Groups module

Creates the DCC Test Lab's reusable least-privilege Security Group layer.

## Security boundaries

| Group | Inbound | Outbound |
|---|---|---|
| ALB | TCP 443 from explicitly approved operator/VPN CIDRs | TCP 8000 to DCC Control |
| DCC Control | TCP 8000 from ALB and Diagnostic Worker | TCP 8080 to Test API; optional HTTPS |
| Diagnostic Worker | None | TCP 8000 to DCC Control; TCP 8080 to Test API; optional HTTP/HTTPS probes and HTTPS |
| Test API | TCP 8080 from DCC Control and Diagnostic Worker | PostgreSQL 5432, Redis 6379; optional HTTPS |
| Test Worker | None | PostgreSQL 5432, Redis 6379; optional HTTPS |
| Database | PostgreSQL 5432 from Test API and Test Worker | No explicit egress rules |
| Cache | Redis 6379 from Test API and Test Worker | No explicit egress rules |

All rules are managed exclusively with standalone `aws_vpc_security_group_ingress_rule` and `aws_vpc_security_group_egress_rule` resources. The `aws_security_group` resources intentionally do not declare inline `ingress` or `egress` arguments. This avoids mixing the two rule-management models.

## Safe defaults

- `operator_ingress_cidrs = []`: the ALB has no inbound rule until approved CIDRs are supplied.
- All public egress flags default to `false`.
- Database and cache have no public ingress and no explicit egress rules.
- No SSH/RDP ingress is created.
- HTTP/80 is not exposed on the ALB. If needed, add it only with a separately implemented and reviewed HTTP-to-HTTPS redirect listener.

## Important review notes

- DCC Control listens on TCP 8000; the application-under-test API listens on TCP 8080. Confirm these ports against the deployed task/container definitions before apply.
- PostgreSQL and Redis ports are fixed at 5432 and 6379 for this lab design.
- Optional public HTTPS egress uses `0.0.0.0/0:443`; diagnostic public probes optionally use `0.0.0.0/0:80` and `:443`. Prefer VPC endpoints and narrower destination controls where practical.
- Security Groups are stateful; response traffic for permitted connections does not need a reverse rule.
- DNS resolver access is governed by the VPC resolver behavior and cannot be controlled with ordinary SG rules targeting the AmazonProvidedDNS address.
- These rules do not configure TLS certificates, ALB listeners, database authentication, Redis authentication, secrets, or application-level authorization.

## Usage

The regional root passes the Network module's VPC ID and common tags. Workload modules consume the exported SG IDs.
