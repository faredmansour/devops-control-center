# Security Groups module

Creates a reusable, least-privilege Security Group layer for the DCC Test Lab.

## Security boundaries

| Group | Inbound | Outbound |
|---|---|---|
| ALB | TCP 443 from explicitly approved operator/VPN CIDRs | TCP 80 to application SG |
| Application | TCP 80 from ALB SG | PostgreSQL 5432, Redis 6379; optional HTTPS |
| Worker | None | PostgreSQL 5432, Redis 6379; optional HTTPS |
| Database | PostgreSQL 5432 from application and worker SGs | None explicitly configured |
| Cache | Redis 6379 from application and worker SGs | None explicitly configured |
| Diagnostics | None | Optional TCP 80/443 to public IPv4 destinations |

All Security Groups are created with empty inline ingress and egress lists. Rules are managed only through standalone `aws_vpc_security_group_*_rule` resources; do not mix the two management styles.

## Safe defaults

- `operator_ingress_cidrs = []`: the ALB has no inbound rule until approved CIDRs are supplied.
- Application, worker, and diagnostic public egress flags default to `false`.
- Database and cache have no public ingress and no explicit egress rules.
- No SSH/RDP ingress is created.
- HTTP/80 is not exposed on the ALB. Add it only alongside a separately implemented and reviewed HTTP-to-HTTPS redirect listener.

## Important review notes

- This module assumes the ALB target port is TCP 80 and that the application target group uses the application SG.
- PostgreSQL and Redis ports are fixed at 5432 and 6379 for this initial lab design.
- Public HTTPS egress uses `0.0.0.0/0:443`; it is intentionally opt-in. Prefer VPC endpoints and narrower destination controls where practical.
- Diagnostic HTTP/HTTPS egress is intentionally opt-in because diagnostic jobs may need to probe external targets.
- Security Groups are stateful; response traffic for permitted connections does not need a reverse rule.
- DNS resolver access is governed by the VPC resolver behavior and cannot be controlled with ordinary SG rules targeting the AmazonProvidedDNS address.
- These rules do not configure TLS certificates, ALB listeners, database authentication, Redis authentication, secrets, or application-level authorization.

## Usage

The regional root passes the Network module's VPC ID and common tags. Workload modules consume the exported SG IDs.
