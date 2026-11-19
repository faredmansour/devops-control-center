# Current Repository vs Target Architecture v2.0

**Purpose:** distinguish repository behavior already documented from the proposed on-demand product architecture. This is a documentation review, not code execution or deployment verification.

## 1. Current documented baseline

The current repository documentation describes:
- React + TypeScript frontend and Django REST API;
- one production Docker image serving the SPA and API;
- AWS ECS discovery through configured cluster allowlists;
- CloudWatch/Prometheus metrics and Loki log providers;
- an in-memory diagnostic-session lifecycle;
- an optional ECS diagnostic worker provider;
- baseline/during/post impact reporting for the current diagnostic session;
- no application database, no Celery/Redis queue, and no persisted report history;
- no application-level authentication or user/role identity in the current API contract.

These are repository-document claims and must be checked against implementation/tests before being treated as verified runtime behavior.

## 2. Important gaps against v2.0

| Area | Current documented state | v2.0 target / required work |
|---|---|---|
| Product execution model | Diagnostic session focused on running ECS task | Explicit catalog of separate pre-deployment and runtime tests |
| User trigger | Start/stop API; no authenticated identity | Every test requires authenticated user action and server authorization |
| Identity | Anonymous operational API | External OIDC validation, authorization scopes, tenant/account isolation |
| Customer-side execution | Optional ECS worker for a diagnostic session | General temporary runner profiles for discovery, security, load and runtime tests |
| Job state | Process-local memory | Stateless coordination using ECS task state + signed short-lived run/result references |
| Discovery | Configured ECS cluster discovery | On-demand multi-resource discovery: ECS, ALB, RDS, CloudWatch, Auto Scaling, VPC, ECR |
| Security testing | Guardrail documentation, no complete catalog | SAST, dependency, image, IaC, secret scan and controlled DAST adapters |
| Performance testing | Impact measurements for current diagnostic | Staged progressive load testing with backend + database metrics and stop conditions |
| API/DB testing | API execution is not part of current impact report | Allowlisted API tests and safe DB connectivity/read-only tests |
| Impact | Baseline/during/post concept exists | Explicit target impact + DCC runner overhead and workload-step correlation |
| Auto Scaling | Not a complete controlled workflow | Observe/recommend only; no automatic changes |
| Result retention | Process-local and lost on restart | No permanent database/history; transient result delivery and explicit TTL |
| Cleanup | Request-driven/session cleanup limitations documented | Runner hard timeout plus independent expired-task cleanup |

## 3. Migration principles

- Preserve the existing frontend/backend separation and single-image control-plane deployment unless implementation proves a change is needed.
- Do not add a database to solve job-state coordination.
- Do not add a permanent customer-side agent.
- Reuse existing provider abstractions only after checking their contracts and test coverage.
- Separate lightweight discovery from heavy load generation.
- Keep current implementation docs as historical/current-state references until code is actually migrated.
- Do not claim a test type is implemented because a document or UI label exists.

## 4. Recommended implementation sequence

### Stage 0 — Baseline verification
Inspect code, routes, tests, Terraform, Docker and deployment docs. Verify which current features are real, mocked, process-local, or only planned. Add an implementation inventory with file references.

### Stage 1 — Identity and run contract
Integrate external OIDC validation; define tenant/account/environment scope; create a versioned run request/result contract; reject anonymous execution.

### Stage 2 — Stateless temporary runner lifecycle
Implement configured ECS RunTask/DescribeTasks/StopTask flow with hard runtime limit, ownership tags, idempotent cancellation, independent cleanup, and short-lived result delivery.

### Stage 3 — On-demand discovery
Implement AWS adapters and a temporary relationship graph for ECS, ALB/Target Groups, RDS, CloudWatch, Auto Scaling, VPC and ECR.

### Stage 4 — Runtime safe diagnostics
Add manual health, API read-only, DB connectivity/read-only query, network and configuration checks.

### Stage 5 — Pre-deployment security suite
Add source/artifact input handling and adapters for SAST, dependency, secret, image and IaC scanning; then staging DAST with strict scope controls.

### Stage 6 — Pre-deployment performance suite
Add isolated progressive load generation, DB measurements, baseline/during/post collection, stop thresholds and report normalization.

### Stage 7 — Reports and product hardening
Finalize transient report delivery, expiry, download behavior, tenant isolation tests, cleanup resilience and documentation.

## 5. Explicit non-goals

- continuous monitoring;
- default schedules;
- permanent customer resource inventory;
- permanent test history;
- DCC-owned application database;
- automatic production scaling changes;
- unrestricted security scanning or load testing.
