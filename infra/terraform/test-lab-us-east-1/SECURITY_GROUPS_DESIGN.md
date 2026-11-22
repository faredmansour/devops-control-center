# Security Groups — us-east-1 Test Lab Design

**Status:** Initial implementation is available in `infra/terraform/modules/security-groups`. This is an initial policy layer, not yet the final Security Group topology for the DCC + E-commerce lab. Review and plan validation are required before any apply.

## 1. Workload boundaries

The lab contains two separate application boundaries:
- **DCC Control Plane:** owns DCC orchestration and user-facing APIs.
- **E-commerce Target:** a separate application whose frontend, backend/API, and MongoDB database must be isolated from DCC.

The DCC Agent / Integration Kit and temporary Test Workers are separate execution identities/components. The agent must not expose a public management port. Test Workers must be temporary and restricted to explicitly approved targets.

E-commerce MongoDB must be dedicated to E-commerce. It must not be shared with DCC. The E-commerce backend is the normal MongoDB client; frontend tasks must never connect directly to PostgreSQL.

## 2. Currently implemented initial traffic matrix

| Source SG | Destination SG | Protocol/port | Direction | Current decision |
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

The module currently creates seven groups: `alb`, `dcc_control`, `diagnostic_worker`, `test_api`, `test_worker`, `database`, and `cache`.

**Important:** `test_api`, `test_worker`, `database`, and `cache` are currently generic application-under-test tiers. They are not yet a confirmed final mapping for the E-commerce frontend/backend/database. In particular, the current database rule permits both Test API and Test Worker; the final E-commerce database should instead allow only the E-commerce backend and explicitly approved maintenance/migration path. Reconcile these rules before creating the E-commerce data tier.

## 3. Decisions still required for final topology

Do not add or apply final E-commerce rules until the E-commerce repository and deployment configuration have been reviewed. Confirm:
1. Frontend hosting/runtime and whether it needs an inbound application SG.
2. Backend/API container port and health-check path.
3. PostgreSQL deployment choice, persistence, backup and migration requirements.
4. Whether E-commerce uses a public ALB, separate ALB, or host-based routing on a shared ALB.
5. How DCC Test Workers reach the E-commerce API and how the target authorizes test traffic.
6. Whether the reusable DCC Agent is a standalone task/service or another integration pattern; prefer outbound authenticated communication and no public inbound agent port.
7. Which egress destinations are genuinely required by each workload.

Do not assume the DCC and E-commerce applications should share one ALB, task role, secret, or security group.

## 4. Default-deny and optional public egress

- `operator_ingress_cidrs` defaults to an empty list. Until approved CIDRs are supplied, the ALB has no inbound rule.
- Public HTTPS egress for DCC Control, Diagnostic Worker, Test API, and Test Worker is controlled by explicit destination CIDR allowlists, all empty by default.
- Diagnostic public HTTP/HTTPS probing uses a separate explicit destination CIDR allowlist, also empty by default.
- MongoDB and Cache have no public ingress and no explicit public egress rules.
- No SSH/RDP ingress is created.
- ALB HTTP/80 is not exposed. If required, add it only with a separately implemented and reviewed HTTP-to-HTTPS redirect listener.

## 5. Required review gates before apply

1. Confirm approved admin CIDRs or VPN ingress.
2. Confirm actual container ports and health-check paths from the DCC and E-commerce deployment definitions.
3. Confirm whether ALB is shared or separate, and verify host/path routing and TLS design.
4. Confirm ACM certificate ARN and domain ownership in `us-east-1`, if a public HTTPS ALB is selected.
5. Confirm all VPC/subnet CIDRs are non-overlapping with connected networks.
6. Confirm ECR images have been built/pushed in `us-east-1` and task definitions pin immutable digests.
7. Confirm E-commerce MongoDB ingress is limited to its backend and approved maintenance path only.
8. Verify no `0.0.0.0/0` ingress except an explicitly approved HTTPS entry point.
9. Inspect the full Terraform plan: no reference to or change against the `eu-north-1` state/resources.
10. Preserve independent state and backend key for this environment.

## 6. Important limitations

- This module defines network-layer permissions only. It does not create ALB listeners, TLS certificates, application authentication, MongoDB credentials, Redis authentication, secrets, or VPC endpoints.
- Optional public egress rules are restricted to explicitly supplied destination CIDRs; broad `0.0.0.0/0` egress is not configured by this module. Prefer VPC endpoints where practical.
- Security Groups are stateful; response traffic for permitted connections does not need a reverse rule.
- DNS resolver access is governed by VPC resolver behavior and cannot be controlled with ordinary SG rules targeting AmazonProvidedDNS.
- A plan review and, after approval, read-only post-deployment inspection must verify the effective AWS rules.

## 7. State safety

The module is composed only into `test-lab-us-east-1`. Do not run state migration, apply, or destroy against the existing `eu-north-1` environment as part of this work. Documentation updates do not provision or modify AWS resources.
