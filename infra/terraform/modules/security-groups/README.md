# Security Groups module

Creates separate AWS Security Groups for the DCC control plane, reusable agent, temporary workers, and the E-commerce target. MongoDB Atlas is the approved managed E-commerce database and is external to this VPC; it does not get an AWS Security Group.

## Workload traffic matrix

| Source | Destination | Protocol/port | Purpose |
|---|---|---:|---|
| Approved operator/VPN CIDRs | DCC ALB | TCP 443 | Restricted DCC UI/API entry |
| Approved client CIDRs | E-commerce ALB | TCP 443 | E-commerce public entry; empty by default |
| DCC ALB | DCC Control | TCP 8000 | DCC API |
| E-commerce ALB | E-commerce Frontend | TCP 80 | Nginx frontend |
| E-commerce Frontend | E-commerce Backend | TCP 8000 | Frontend reverse proxy to Express API |
| Diagnostic Worker | E-commerce Backend | TCP 8000 | Diagnostic/API probes |
| Test Worker | E-commerce Backend | TCP 8000 | Authorized test execution |
| Test Worker | DCC Control | TCP 8000 | Test lifecycle/result callbacks |
| E-commerce Backend | MongoDB Atlas | TCP 27017 | TLS database connection; Atlas IP Access List is the remote allowlist |
| E-commerce Backend | Optional Redis Cache | TCP 6379 | Private cache access |

The module creates nine groups: `dcc_alb`, `ecommerce_alb`, `dcc_control`, `dcc_agent`, `diagnostic_worker`, `ecommerce_frontend`, `ecommerce_backend`, `test_worker`, and `cache`.

## Security defaults and limitations

- DCC operator ingress and E-commerce ingress are independent CIDR allowlists. Both default to empty.
- No SSH/RDP ingress is created. No direct public ingress exists for application tasks, agent, workers, or cache.
- The DCC Agent has no inbound rules. It may initiate TCP 8000 to DCC Control, and DCC Control accepts that traffic from the agent SG only. Application-level authentication and authorization remain mandatory.
- MongoDB Atlas is external to the VPC. Only the E-commerce backend should receive the Atlas connection secret. Require TLS and restrict Atlas Network Access/IP Access List to the NAT Gateway Elastic IP (or use PrivateLink after a separate design review).
- Public Atlas connectivity requires backend egress on TCP 27017. Because Atlas endpoint IPs can change and Security Groups do not support FQDN allowlists, this rule currently uses `0.0.0.0/0` on **only TCP 27017**. Atlas IP Access List and the stable NAT EIP provide the remote restriction. This is an explicit, documented exception—not unrestricted all-port egress. If a stricter network boundary is required, evaluate Atlas PrivateLink or maintained destination prefix lists before apply.
- Redis is optional and private; it accepts connections only from the E-commerce backend.
- This module does not create ALBs/listeners, TLS certificates, Atlas users/clusters/IP allowlist entries, secrets, Redis resources, or application-level authorization.
- Security Groups are stateful. Rules are managed only through standalone `aws_vpc_security_group_ingress_rule` and `aws_vpc_security_group_egress_rule` resources, not inline rules.

## Validation

The Terraform native tests use a mocked AWS provider and do not create AWS resources:

```bash
terraform init -backend=false
terraform test
```

Review the full plan and actual workload ports before any apply.