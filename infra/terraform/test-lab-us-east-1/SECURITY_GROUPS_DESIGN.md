# Security Groups — us-east-1 Test Lab Design Review

**Status:** Proposal for review only. No AWS resources or existing security groups are changed by this document.

## Design principles

- Create a new VPC and new security groups in `us-east-1`; never import or reference IDs from `eu-north-1`.
- Keep ECS tasks in private application subnets with `assign_public_ip = false`.
- Keep RDS and Redis in private data subnets, with no public ingress.
- Use security-group references for east-west application traffic; do not use VPC-wide CIDRs for database/API access.
- Prefer explicit standalone ingress/egress rule resources and avoid mixing inline rules with standalone rule resources for the same SG.
- No broad ingress on any task or data security group.

## Proposed traffic matrix

| Source SG | Destination SG | Protocol/port | Direction | Decision |
|---|---|---:|---|---|
| Approved admin CIDRs / VPN ingress | DCC ALB SG | TCP 443 | Ingress | Allow only approved source ranges; do not default to world-open |
| DCC ALB SG | DCC Control SG | TCP 8000 | Egress / ingress | Allow |
| Diagnostic Worker SG | DCC Control SG | TCP 8000 | Egress / ingress | Allow signed result callback |
| DCC Control SG | Test API SG | TCP 8080 | Egress / ingress | Allow |
| Diagnostic Worker SG | Test API SG | TCP 8080 | Egress / ingress | Allow scoped diagnostic access |
| Test API SG | RDS SG | TCP 5432 | Egress / ingress | Allow |
| Test Worker SG | RDS SG | TCP 5432 | Egress / ingress | Allow |
| Test API SG | Redis SG | TCP 6379 | Egress / ingress | Allow |
| Test Worker SG | Redis SG | TCP 6379 | Egress / ingress | Allow |

## Required changes versus the current regional template

1. **ALB listener:** the existing template documents HTTP/80 only. The new environment should use an HTTPS/443 listener with an ACM certificate. If HTTP/80 is retained, it should only redirect to HTTPS and should not forward application traffic.
2. **ALB source restriction:** parameterize allowed ingress CIDRs. Default should be empty / fail closed until an approved operator CIDR or VPN range is supplied. Do not silently expose the DCC dashboard to `0.0.0.0/0`.
3. **Outbound HTTPS:** existing task SG rules permit TCP/443 to `0.0.0.0/0`. Keep this only where required for image startup and external AWS APIs; prefer VPC endpoints for ECR API/DKR, CloudWatch Logs, Secrets Manager, and S3 where supported. Document any remaining external destinations and consider an egress proxy/firewall for FQDN-aware policy.
4. **Database/cache:** preserve SG-to-SG ingress only. Never add public CIDR ingress for 5432 or 6379.
5. **Default egress:** explicitly review whether provider-created default egress is removed. Do not assume that an SG with no inline egress block is deny-all. The resulting AWS rules must be checked from a fresh plan and read-only post-deployment inspection.
6. **Rule ownership:** do not declare empty inline `ingress`/`egress` collections alongside standalone `aws_vpc_security_group_*_rule` resources. The previous Test Lab encountered drift/removal plans from that pattern.
7. **Authentication boundary:** the DCC API currently defers application authentication. Do not make unauthenticated API endpoints publicly reachable. Until auth is implemented, restrict ALB ingress to an approved operator network/VPN and keep internal APIs private.

## Review gates before apply

- Confirm allowed admin CIDRs or VPN ingress.
- Confirm ACM certificate ARN / domain ownership in `us-east-1`.
- Confirm every VPC/subnet CIDR is non-overlapping with all connected networks.
- Confirm no cross-region SG IDs, subnet IDs, RDS endpoints, Redis endpoints, or Cloud Map namespace IDs are reused.
- Confirm ECR images have been built/pushed in `us-east-1` and task definitions pin immutable digests.
- Inspect the full Terraform plan: no reference to or change against the `eu-north-1` state/resources.
- Verify no `0.0.0.0/0` ingress except an explicitly approved HTTPS public entry point.
- Verify RDS/Redis are private and database ingress is SG-scoped.
- Preserve independent state and backend key for this environment.

## Current scope

This is a security design review artifact, not an executable SG module. The existing regional Terraform stack has dependencies across networking, IAM, ECR, Cloud Map, RDS, Redis, ECS and DCC. A full independent stack must be copied/refactored and validated as a whole before applying; do not run Terraform from this documentation directory.
