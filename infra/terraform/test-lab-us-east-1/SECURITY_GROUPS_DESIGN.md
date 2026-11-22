# Security Groups — us-east-1 Test Lab Design

**Status:** Initial implementation is available in `infra/terraform/modules/security-groups`. The module now defines separate Security Groups for DCC, E-commerce, and temporary workers. This is still a pre-deployment policy design; ALB listeners, TLS, target groups, Atlas access-list configuration, and the agent communication path require separate implementation and review. Review and plan validation are required before any apply.

## 1. Workload boundaries

The lab contains two separate application boundaries:
- **DCC Control Plane:** owns DCC orchestration and user-facing APIs.
- **E-commerce Target:** a separate application whose frontend, backend/API, and MongoDB database must be isolated from DCC.

The DCC Agent / Integration Kit and temporary Test Workers are separate execution identities/components. The agent must not expose a public management port. Test Workers must be temporary and restricted to explicitly approved targets.

**Decision: MongoDB Atlas is approved** as the managed E-commerce database. It is external to this VPC and is not shared with DCC. The E-commerce backend is the only normal MongoDB client; frontend tasks must never receive database credentials or connect directly to MongoDB. Atlas Network Access/IP Access List and TLS enforce the database-side boundary.

## 2. Currently implemented initial traffic matrix

| Source SG | Destination SG | Protocol/port | Direction | Current decision |
|---|---|---:|---|---|
| Approved admin CIDRs / VPN ingress | ALB SG | TCP 443 | Ingress | Allow only explicitly approved source ranges |
| ALB SG | DCC Control SG | TCP 8000 | Egress / ingress | Allow |
| Diagnostic Worker SG | DCC Control SG | TCP 8000 | Egress / ingress | Allow diagnostic result callbacks |
| DCC Control SG | Test API SG | TCP 8080 | Egress / ingress | Allow |
| Diagnostic Worker SG | Test API SG | TCP 8080 | Egress / ingress | Allow scoped diagnostic probes |
| E-commerce backend SG | MongoDB Atlas | TCP 27017 over TLS | Egress | Allow only through the selected Atlas connectivity path; Atlas allowlists the AWS egress identity |
| Test Worker SG | Database SG | TCP 5432 | Egress / ingress | Allow |
| Test API SG | Cache SG | TCP 6379 | Egress / ingress | Allow |
| Test Worker SG | Cache SG | TCP 6379 | Egress / ingress | Allow |

The module has been refactored for the reviewed E-commerce ports: frontend Nginx TCP 80, Express backend TCP 8000, and MongoDB Atlas TCP 27017/TLS. The E-commerce backend receives API traffic only from its frontend SG and approved temporary diagnostic/test worker SGs. Atlas is outside the VPC and has no AWS SG; its Network Access/IP Access List must allow only the selected AWS egress identity. The Atlas egress rule currently permits TCP 27017 to `0.0.0.0/0` because Security Groups cannot express Atlas FQDN destinations and Atlas endpoint IPs may change. This is a port-limited outbound exception, with the remote source restriction enforced by Atlas IP Access List and the stable NAT EIP.

The module now creates nine groups: `dcc_alb`, `ecommerce_alb`, `dcc_control`, `dcc_agent`, `diagnostic_worker`, `ecommerce_frontend`, `ecommerce_backend`, `test_worker`, and `cache`.

**Important:** Redis remains optional and is reachable only from the E-commerce backend. The DCC Agent SG currently has no ingress or egress rules; its authenticated control-plane communication path must be implemented and tested before deploying the agent. The E-commerce ALB ingress allowlist is independent from the DCC operator allowlist and defaults to empty.

## 3. Decisions still required for final topology

Do not add or apply final E-commerce rules until the E-commerce repository and deployment configuration have been reviewed. Confirm:
1. Confirm E-commerce public ingress CIDRs, domain, ACM certificate, and ALB listener/target group design.
2. Confirm frontend Nginx reverse-proxy configuration and backend health-check path.
3. Confirm Atlas cluster tier/region, NAT EIP allowlisting, TLS, credentials, and backup requirements.
4. Confirm the DCC ALB domain/certificate and operator/VPN CIDRs.
5. Confirm how DCC Test Workers are authorized to reach the E-commerce API and enforce test limits.
6. Implement the DCC Agent authenticated communication path; it currently has no SG rules.
7. Review the TCP 27017 egress exception and decide whether Atlas PrivateLink is warranted.

Do not assume the DCC and E-commerce applications should share one ALB, task role, secret, or security group.

## 4. Default-deny and optional public egress

- `operator_ingress_cidrs` defaults to an empty list. Until approved CIDRs are supplied, the ALB has no inbound rule.
- DCC and E-commerce ALB ingress use separate explicit CIDR allowlists, both empty by default.
- Optional HTTPS egress for DCC Control, Diagnostic Worker, and Test Worker is controlled by explicit destination CIDR allowlists, all empty by default.
- Diagnostic public HTTP/HTTPS probing uses a separate explicit destination CIDR allowlist, also empty by default.
- MongoDB Atlas is external and receives no AWS SG. The E-commerce backend has a documented TCP 27017 egress rule to any destination because Atlas FQDN/IP ranges are not directly enforceable in SGs. Atlas IP Access List must restrict the source to the NAT Gateway Elastic IP and TLS must be required. This remains a review gate before apply.
- No SSH/RDP ingress is created.
- ALB HTTP/80 is not exposed. If required, add it only with a separately implemented and reviewed HTTP-to-HTTPS redirect listener.

## 5. Required review gates before apply

1. Confirm approved admin CIDRs or VPN ingress.
2. Confirm actual container ports and health-check paths from the DCC and E-commerce deployment definitions.
3. Confirm whether ALB is shared or separate, and verify host/path routing and TLS design.
4. Confirm ACM certificate ARN and domain ownership in `us-east-1`, if a public HTTPS ALB is selected.
5. Confirm all VPC/subnet CIDRs are non-overlapping with connected networks.
6. Confirm ECR images have been built/pushed in `us-east-1` and task definitions pin immutable digests.
7. Confirm Atlas Network Access/IP Access List permits only the approved AWS NAT Elastic IP or PrivateLink path; confirm only backend/approved maintenance workloads hold the Atlas secret.
8. Review the TCP 27017 `0.0.0.0/0` egress exception and approve or replace it with PrivateLink before apply.
9. Verify no `0.0.0.0/0` ingress except an explicitly approved HTTPS entry point.
10. Inspect the full Terraform plan: no reference to or change against the `eu-north-1` state/resources.
11. Preserve independent state and backend key for this environment.

## 6. Important limitations

- This module defines AWS network-layer permissions only. It does not create ALB listeners, TLS certificates, application authentication, Atlas users/clusters/IP Access List entries, database credentials, Redis authentication, secrets, or VPC endpoints.
- Optional public egress rules are restricted to explicitly supplied destination CIDRs; broad `0.0.0.0/0` egress is not configured by this module. Prefer VPC endpoints where practical.
- Security Groups are stateful; response traffic for permitted connections does not need a reverse rule.
- DNS resolver access is governed by VPC resolver behavior and cannot be controlled with ordinary SG rules targeting AmazonProvidedDNS.
- A plan review and, after approval, read-only post-deployment inspection must verify the effective AWS rules.

## 7. State safety

The module is composed only into `test-lab-us-east-1`. Do not run state migration, apply, or destroy against the existing `eu-north-1` environment as part of this work. Documentation updates do not provision or modify AWS resources.
