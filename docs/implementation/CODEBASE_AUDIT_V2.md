# DCC Codebase Audit — Target Architecture v2.0

**Review date:** 2026-11-19  
**Branch reviewed:** master  
**Scope:** repository source and documentation available at review time  
**Important:** this is a static GitHub source review. No code was executed, no CI workflow was run, and no AWS account/resources were inspected during this audit.

## 1. Executive summary

The repository already has useful foundations for an on-demand product: React + TypeScript UI and Django REST API; AWS ECS discovery; configurable CloudWatch/Prometheus/Loki providers; no application database; an in-memory diagnostic-session lifecycle; an ECS Fargate task launcher/st stopper abstraction; and baseline/during/post impact measurement.

However, the current implementation is still a **single diagnostic-session feature**, not yet the complete on-demand test platform defined in architecture v2.0. The current API is anonymous, job state is process-local, the ECS provider is a generic configured task launcher, and the repository does not yet provide a full pre-deployment security/load test catalog with isolated engines and result contracts.

## 2. Verified source observations

### 2.1 No application database

backend/config/settings.py does not configure a Django database and the documented runtime contract says no DB/Celery/Redis persistence is used. This matches the no-DCC-database requirement. **Keep this decision.** Do not add a database just to retain projects, jobs, reports, or test history.

### 2.2 Authentication is currently absent

backend/config/settings.py currently declares DEFAULT_AUTHENTICATION_CLASSES as an empty list and DEFAULT_PERMISSION_CLASSES as rest_framework.permissions.AllowAny. The existing backend-boundary and diagnostic-security documents also explicitly state there is no application login, user, role, or identity.

This is a blocking gap for a public SaaS/multi-customer service. Network-level restriction and CORS are not substitutes for user authentication or tenant authorization.

**Required:** integrate external OIDC/JWT validation and enforce account/environment/test scopes at the API. This can be done without a DCC user database.

### 2.3 DEBUG defaults to true in Django settings

backend/config/settings.py computes DEBUG from DJANGO_DEBUG with a default of true. The Dockerfile sets DJANGO_DEBUG=false in the runtime image and the ECS task template also supplies false, but a deployment that omits the variable can start with debug enabled.

**Required:** change the application default to false and make development opt-in explicitly. Add tests asserting production settings fail closed when required secrets/hosts are absent.

### 2.4 Current diagnostic state is in process memory

backend/apps/diagnostics/services.py stores sessions in dictionaries/deques protected by an RLock. backend/apps/diagnostics/impact.py stores measurements in dictionaries and starts a sampling thread.

This is compatible with a single-process prototype but not a robust multi-replica SaaS job coordinator. A process restart loses the run state; multiple API replicas do not share it.

**Required:** use ECS task state plus signed short-lived run/result references for coordination. Do not replace this with a permanent database.

### 2.5 Current measurement sampling is session-scoped

backend/apps/diagnostics/impact.py captures a baseline, samples during an active diagnostic session at a bounded interval, and attempts a post-test measurement. This is not an always-on collector; it is tied to a manually started session.

This is a useful concept to retain, but the measurement model must expand to cover each test type and both target impact and runner overhead.

### 2.6 Current ECS provider is a generic temporary-task launcher

backend/apps/diagnostics/ecs_provider.py validates a configured task definition/container, calls ECS RunTask, passes a diagnostic session ID, target task ID, and discovered target cluster ARN as container environment overrides, and returns the started task ARN. It also has a stop operation for the execution reference.

The configuration uses fixed server-side cluster/task definition/subnet/security-group/container settings. This is safer than accepting arbitrary infrastructure parameters from the browser.

The current contract does not yet express a general typed job specification for selecting discovery, API, database, load, or security test engines. It should evolve into a runner contract with explicit test type, target scope, bounded profile, environment, timeout, and result schema. Do not allow arbitrary command or container overrides from users.

### 2.7 Current test trigger is manual, but the UI/API is session-centric

backend/apps/diagnostics/views.py exposes a POST to start a diagnostic session and a POST to stop it. This aligns with manual initiation in principle.

It does not yet represent the broader product workflow where the user selects a distinct test category/profile, environment, target scope, and safety parameters before pressing Run.

### 2.8 Test catalog and security engines are not yet represented as a complete implementation

The reviewed diagnostic API files define session lifecycle and impact reporting. The target catalog needs separate adapters for SAST, dependency and secret scanning, container image scanning, IaC scanning, DAST, progressive load generation, safe API checks, and safe database connectivity/query tests.

The repository has a CI security workflow and existing tooling references, but that is not the same as a user-triggered in-product test runner that normalizes results and returns them to the user.

### 2.9 Existing impact report limitations

backend/apps/diagnostics/impact.py reads configured metrics/dependency providers and correlates them to a session. Existing docs note that CloudWatch may return service aggregates rather than per-task samples.

The v2 report must identify actual measurement scope (task, service, ALB, DB); include sample timestamps/windows and source; include workload ramp timestamps; separately measure diagnostic runner CPU/memory/network; mark missing metrics unavailable; and avoid asserting causality from simple before/during/after correlation.

### 2.10 CI branch mismatch risk

The repository default branch is master, while .github/workflows/ci.yml currently lists push trigger branch main. Pull requests still trigger CI, but pushes to master may not trigger the push workflow as intended.

**Required:** align workflow branch filters with the actual default branch or intentionally migrate the repository default branch.

## 3. Gap priority

| Priority | Gap | Why it blocks the target |
|---|---|---|
| P0 | Anonymous API / no user identity | Unsafe for SaaS and cross-customer access |
| P0 | Process-local job state as the only coordinator | Runs can become unobservable after restart or with multiple API replicas |
| P0 | Runner lifecycle lacks independent hard timeout/cleanup guarantee | Temporary tasks could outlive the user request/control plane |
| P1 | No generalized test request/result contract | Cannot safely add multiple independent test engines |
| P1 | No complete security test adapters/catalog | Pre-deployment security workflow is not implemented end-to-end |
| P1 | No isolated progressive load-generator workflow | Backend/DB capacity testing is not yet available as a bounded product feature |
| P1 | No database test adapter with safe query policy | DB checks need explicit allowlist and read-only defaults |
| P1 | Impact report does not fully measure runner overhead/workload steps | Results could be misleading |
| P2 | Discovery scope is primarily ECS-focused | Need ALB, RDS, Auto Scaling, VPC, ECR relationships |
| P2 | Result delivery/expiry policy not fully implemented | Need transient result UX without permanent history |
| P2 | CI push branch mismatch | CI may not run on default-branch pushes |

## 4. Recommended implementation order

1. **Security foundation:** fail-closed Django settings, external OIDC validation, per-request authorization, tenant/account/environment scoping.
2. **Run contract:** versioned test request/result DTOs; test catalog registry; strict schema and server-side limits.
3. **Ephemeral orchestration:** ECS task launch/describe/stop, hard runner timeout, cancellation, ownership tags, independent cleanup, no process-memory-only authority.
4. **On-demand discovery:** ECS, ALB/Target Groups, RDS, CloudWatch, Auto Scaling, VPC and ECR adapters with a temporary relationship graph.
5. **Runtime tests:** passive AWS checks, bounded API health checks, network reachability, safe DB connection/read-only query checks.
6. **Security suite:** source/artifact intake and SAST, dependency, secret, image, IaC, then staging DAST.
7. **Performance suite:** isolated load generator, progressive ramp, DB/backend metrics, safety stops, recovery measurements.
8. **Report delivery:** transient result response, optional short-lived artifact, redaction, expiry and cleanup tests.
9. **UI workflows:** pre-deployment test workspace and runtime diagnostics workspace, both explicitly user-triggered.

## 5. Decisions that should not be implemented implicitly

- OIDC provider and tenant claim model;
- strict zero-retention vs encrypted S3 artifacts with a short TTL;
- customer-runner provisioning model (customer deploys task definition vs DCC launches a customer-approved task definition);
- supported security scanner versions and licensing;
- allowed DAST profiles and ownership verification;
- default runner sizes, concurrency, duration, RPS and VU ceilings;
- whether runtime users can download reports after leaving the current page.

## 6. Static review limitations

This audit is based on the source files inspected on the GitHub default branch. It does not certify that every code path behaves as documented, and it does not include execution of tests, deployment plans, or AWS live-state checks. Implementation work must start with targeted tests and source-level verification of the affected modules.