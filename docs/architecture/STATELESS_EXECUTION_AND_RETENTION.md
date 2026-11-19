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
