# DCC Stateless Execution and Data Retention

**Status:** Target architecture v2.0 policy

## 1. Storage decision

DCC will not operate its own application database in the target architecture. Do not add a database to persist:
- user accounts or passwords;
- customer projects or AWS account inventories;
- discovered resource graphs;
- test definitions or schedules;
- test run history;
- diagnostic reports or analytics;
- long-lived session state.

Human identity is delegated to an external OIDC identity provider. Customer AWS access uses IAM roles and short-lived role sessions; DCC must not store long-lived AWS access keys.

## 2. Temporary data during a run

A running test necessarily has transient execution data: server-generated run ID, selected target and validated parameters, runner/task ARN and timestamps, current state and cancellation signal, measurements/findings, and temporary result payload.

This data exists only to execute and return the current request. It is not a permanent history or customer inventory.

## 3. Stateless coordination

Do not rely on one Django process's in-memory dictionary as the authoritative state for long-running jobs. It disappears on restart and is not shared across API replicas.

Preferred coordination:
1. API validates request and launches a preconfigured ECS task.
2. API returns an opaque run handle and task reference.
3. UI asks for status while the user is viewing that run.
4. API derives runner state from ECS task state and validates that the run reference belongs to the authenticated user/account scope.
5. Runner sends a bounded result callback or writes an encrypted, short-lived result artifact.
6. API returns the result to the user.
7. Temporary state/artifacts are deleted or expire.

The runner has a hard maximum runtime independent of the API. A control-plane restart must not disable runner timeout/cleanup.

If a message queue is later introduced, treat it as transient job transport with explicit retention and redrive limits, not permanent history. It is not required for the first implementation if direct ECS RunTask + task-state polling + callback is sufficient.

## 4. Result delivery options

### Option A — Direct callback/result response
Preferred for small results. Runner posts a normalized result to a short-lived, signed callback endpoint. The control plane returns it to the browser. Avoid keeping a long-running browser HTTP connection open for the duration of a load/security test.

### Option B — Temporary encrypted object
For larger reports (for example scanner JSON/SARIF or detailed load-test artifacts), write an encrypted object to a dedicated private bucket/prefix using short-lived scoped upload authorization. Require:
- server-generated object keys;
- encryption at rest;
- private bucket with public access blocked;
- short lifecycle expiration (initial proposal: 1 day maximum, subject to product decision);
- strict object-size limits;
- no customer-controlled bucket/key path;
- explicit delete after successful delivery where practical;
- redaction before upload.

S3 is temporary artifact transport, not a database or permanent report archive. If the product requirement is strict zero-retention, do not use Option B; return bounded results directly.

## 5. UI behavior

- A result is displayed for the active browser workflow.
- User may explicitly download the report.
- Refresh/reopen after result expiration does not restore old test history.
- DCC does not provide historical trends in the MVP.
- Do not imply that a report remains available after its TTL.
- Do not silently create a saved project profile; users provide/select target scope at run time or use a future client-side configuration file that remains under their control.

## 6. Secrets and sensitive data

- Never persist AWS access keys, passwords, database credentials, API tokens, cookies, or private keys in DCC storage.
- Prefer ECS Task Roles and cross-account AssumeRole with External ID.
- For secrets required by a test, use a narrowly scoped secret reference and retrieve it only at execution time through an approved secret provider. Do not place secret values in browser-visible configuration or logs.
- Redact secrets and sensitive response fields before returning reports.
- Keep only the minimum transient data required to execute the job.

## 7. Identity and SaaS implications

No DCC database does not mean anonymous access. A SaaS product still requires authentication and tenant isolation. Use an external identity provider and signed identity claims; the API validates authorization on every request.

A no-database MVP can avoid saving customer connection profiles and project history. The user supplies the account/role/environment context at run time. If future requirements demand persistent team membership, saved configurations, billing history, audit retention, or long-term reports, those require an explicit product decision and a revised retention policy. They are not part of this architecture.

## 8. Retention defaults

| Data | Default handling |
|---|---|
| AWS credentials | Never stored by DCC |
| OIDC access token | Validated per request; not logged or persisted |
| Run parameters | In-memory/transient for active execution only |
| Runner filesystem | Ephemeral task storage; discarded at task exit |
| Result response | Returned to current user; not retained as history |
| Optional report object | Encrypted, private, maximum 1-day TTL initially |
| Application logs | Operational logs only; exclude secrets and report bodies; retention configured separately and disclosed |
| Customer resource inventory | Not retained after the run |

The one-day artifact TTL is a proposed default, not a promise of zero retention. If strict zero-retention is selected, remove temporary object storage and use direct result delivery only.

## 9. Implemented stateless ECS run API (initial slice)

The initial API slice is exposed under `/api/diagnostic-sessions/runs/`:

- `POST /api/diagnostic-sessions/runs/` validates the versioned request, resolves the target task through live ECS discovery, requires the target to be RUNNING, launches the configured ECS diagnostic task, and returns a server-generated UUID plus a signed short-lived capability token.
- `GET /api/diagnostic-sessions/runs/{run_id}/` requires the token in `X-DCC-Run-Token` and derives current state from ECS `DescribeTasks`.
- `POST /api/diagnostic-sessions/runs/{run_id}/cancel/` requires the same capability and stops the exact ECS task referenced by the signed payload.

The token is signed with Django's `SECRET_KEY`, bound to the run ID and ECS execution reference, and expires according to `DCC_RUN_CAPABILITY_TTL_SECONDS` (default 1800 seconds). The browser must keep it only for the active run and must not log it or put it in a URL. A Django restart does not invalidate the token while the signing key remains unchanged, and no run registry is stored in process memory.

The feature is disabled by default with `DCC_STATELESS_RUN_API_ENABLED=false`. Enable it only behind a private, controlled ingress until proper OIDC authentication and tenant authorization are implemented. The capability token protects follow-up status/cancel calls; it does not authenticate or rate-limit the initial create request. CORS is not an access-control boundary.

Only `runtime_health` is accepted by the current run endpoint. Other schema test types remain reserved and are rejected until their execution adapters exist. ECS `STOPPED` is a task lifecycle state, not proof that a test passed. The API currently returns ECS lifecycle information only; normalized test result callbacks and result delivery are a separate implementation step.

The Test Lab Terraform now defines a separate one-shot Fargate task definition for the runtime-health runner, a dedicated read-only runner task role, and a DCC control-plane policy scoped to launching only that task definition. The runner inspects only the selected ECS task and writes a minimal operational completion event; it does not put task/container findings into CloudWatch Logs. The DCC task role also manages one-time cleanup schedules in its dedicated Scheduler group. These are source changes only until a reviewed Terraform plan is validated and applied.


## 10. Dedicated runtime-health runner (initial implementation)

A separate module, `apps.diagnostics.runner`, is executed as a one-shot ECS Fargate task. It is not the always-on Test Worker and does not accept arbitrary commands, task definitions, or URLs from the browser.

- DCC resolves and validates the selected RUNNING target task before launch.
- ECS launches the fixed `dcc-diagnostic-runner` task definition in private application subnets using the dedicated diagnostic-worker security group.
- The runner uses its own task role, limited to `ecs:DescribeTasks` in the configured Test Lab cluster.
- It classifies the target as `healthy`, `failed`, or `unknown` based on ECS task/container health signals.
- A one-time EventBridge Scheduler deadline independently stops the runner task.
- CloudWatch receives only a minimal operational completion event; detailed target/container findings are not written to logs.

**Important limitation:** The signed callback and transient result retrieval are implemented, but the result store is process-local and depends on the current single DCC task and one Gunicorn worker. ECS `STOPPED` must not be interpreted as a passed test when no callback result is available. The API feature flag stays disabled.


## 11. Short-lived signed result callback

The one-shot runner posts a bounded runtime-health result to the private DCC service-discovery address. The callback uses a separate Django-signed token scoped to one run and one purpose; it is passed only to the fixed runner container as an ECS environment override. The callback endpoint accepts one result per run and rejects expired, mismatched, duplicate, or schema-invalid payloads.

The API stores normalized results only in a process-local, thread-safe TTL store. The current Test Lab has one DCC ECS service task and Gunicorn starts with one worker and multiple threads; this is a deliberate constraint for this volatile-memory implementation. Results disappear after the configured 600-second TTL, and a DCC task restart also loses in-memory results. Do not scale the DCC service horizontally or increase Gunicorn worker count until a shared ephemeral transport is designed. This is not durable storage and is not a report-history feature.

The runner reaches DCC through private Cloud Map DNS. Security-group rules allow only the diagnostic-runner security group to reach the DCC task on port 8000. Detailed findings are returned only through the run capability endpoint; CloudWatch receives no detailed findings. Authentication is still deferred, so keep the stateless API disabled and do not expose it as a public SaaS endpoint.


The runner now sends an explicit `failed` callback when the ECS target inspection call returns an AWS/Boto error. If the runner process itself is terminated before it can send a callback (for example, forced task termination or network loss), the control plane can only report ECS lifecycle state; it must not infer a successful test result.
