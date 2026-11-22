# Security Groups module

Creates an initial generic Security Group layer for the DCC Test Lab. It is not yet aligned with the Alfredo E-Commerce target application's ports.

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

All rules are managed exclusively with standalone `aws_vpc_security_group_ingress_rule` and `aws_vpc_security_group_egress_rule` resources. The `aws_security_group` resources intentionally do not declare inline `ingress` or `egress` arguments. This avoids mixing the two rule-management models and preserves a single Terraform owner for each rule.

## Safe defaults

- `operator_ingress_cidrs = []`: the ALB has no inbound rule until approved CIDRs are supplied.
- All public egress destination CIDR allowlists default to empty.
- Database and cache have no public ingress and no explicit egress rules.
- No SSH/RDP ingress is created.
- HTTP/80 is not exposed on the ALB. If needed, add it only with a separately implemented and reviewed HTTP-to-HTTPS redirect listener.

## Important review notes

- DCC Control currently uses TCP 8000. The generic application-under-test API rule currently uses TCP 8080 and its database rule uses PostgreSQL TCP 5432. The reviewed Alfredo E-Commerce backend container exposes TCP 8000 and requires MongoDB TCP 27017. Do not use the current generic rules for E-commerce until the SG module and tests are updated to those confirmed ports and workload boundaries.
- PostgreSQL and Redis ports are fixed at 5432 and 6379 for this lab design.
- Optional HTTPS and diagnostic HTTP/HTTPS egress are created only for explicitly supplied destination CIDRs. Empty allowlists create no public egress rules. Prefer VPC endpoints and the narrowest possible destination ranges.
- Security Groups are stateful; response traffic for permitted connections does not need a reverse rule.
- DNS resolver access is governed by the VPC resolver behavior and cannot be controlled with ordinary SG rules targeting the AmazonProvidedDNS address.
- These rules do not configure TLS certificates, ALB listeners, database authentication, Redis authentication, secrets, or application-level authorization.

## Usage

The regional root passes the Network module's VPC ID and common tags. Workload modules consume the exported SG IDs.
