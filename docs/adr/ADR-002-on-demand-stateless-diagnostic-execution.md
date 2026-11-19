# ADR-002: On-Demand Stateless Diagnostic Execution

- **Status:** Accepted as target architecture direction
- **Date:** 2026-11-19
- **Decision owners:** DCC product/architecture

## Context

DCC was initially documented as a dashboard with a diagnostic-session workflow and optional temporary ECS worker. The product requirement is now explicit: developers/operators manually select and start each test; DCC supports pre-deployment performance/security validation and runtime diagnostics; there is no continuous monitoring agent and no DCC-owned application database or permanent test history.

## Decision

1. All tests are manually initiated by an authenticated user action.
2. DCC does not run continuous customer-side collectors or default scheduled tests.
3. Each test uses short-lived, bounded execution resources.
4. The preferred location for private AWS diagnostics is a temporary ECS Fargate task in the customer VPC.
5. Heavy load generation is isolated from the control plane and lightweight diagnostic runner.
6. DCC has no application database and does not retain permanent resource inventories or test reports.
7. Human authentication is delegated to an external OIDC identity provider; absence of a database does not mean anonymous API access.
8. Temporary job state is coordinated through ECS task state and short-lived signed references, not a process-local dictionary as the sole source of truth.
9. Results are returned to the initiating user. Optional large artifacts may use encrypted temporary object storage with a short TTL; strict zero-retention mode must avoid object storage.
10. MVP Auto Scaling functionality is observe/recommend only. DCC does not mutate customer application infrastructure.

## Consequences

### Positive
- No permanent monitoring/agent cost in the customer environment.
- No DCC-owned database administration, backup, migration, or retention burden.
- Lower default operational footprint when no tests are running.
- Tests run close to private customer resources.
- Workloads can be isolated and assigned per-test IAM and resource limits.

### Trade-offs
- A test cannot run if the user does not explicitly start it.
- No built-in historical trends, saved reports, or saved customer inventory.
- Authentication and tenant isolation still need a secure external identity model.
- Temporary artifact storage, if enabled, is still short-term data retention and must be disclosed.
- Long-running tests require robust task lifecycle, timeout, cancellation, and cleanup independent of browser/API process lifetime.
- Cross-account IAM and customer VPC deployment onboarding add setup complexity.

## Rejected alternatives

- **Always-on monitoring agent:** rejected because continuous collection is not required.
- **Permanent database for jobs/reports:** rejected because the product explicitly requires no DCC-owned database or permanent test history.
- **Process-memory-only orchestration:** rejected as the sole mechanism for production SaaS because it is lost on restart and is not shared between replicas.
- **Run all tests inside the Django API process:** rejected because load/security tools need isolation, resource controls, and independent timeouts.
- **Automatic production load/security tests:** rejected because active tests can affect customer workloads and require explicit scope and approval.

## Follow-up decisions required before implementation

- Choose the external OIDC provider and tenant-claim model.
- Choose strict zero-retention result delivery versus short-lived encrypted S3 artifacts.
- Decide how the customer provisions runner task definition, task role, subnets and security groups.
- Define initial runner CPU/memory, timeout, test concurrency and per-test quotas.
- Define security scan tool images and licensing/redistribution review.
- Define how the platform verifies customer ownership and approved DAST/load targets.
