# DCC Target Architecture v2.0

**Status:** Proposed target architecture  
**Product model:** On-demand infrastructure diagnostics and testing  
**Cloud scope:** AWS-first  
**Execution:** Explicit user-triggered, short-lived diagnostic jobs  
**Persistence:** No DCC-owned application database and no permanent test-result history

## 1. Product definition

DevOps Control Center (DCC) is an on-demand AWS infrastructure diagnostics and testing platform. It lets an authorized developer or operator discover an AWS application environment, choose a diagnostic or test, explicitly start it, inspect the result, and release temporary execution resources.

DCC is not a continuous monitoring platform. It does not continuously poll customer workloads, run tests on a schedule by default, or require a permanent customer-side agent.

Two test windows are first-class workflows:

1. **Pre-deployment / Staging validation:** load and capacity testing, application/API testing, database performance checks, and security validation before a production release.
2. **Runtime diagnostics:** manually requested, bounded health, connectivity, API, dependency, configuration, and selected security checks while the application is running.

Every test is initiated by a user action. A test must never start merely because a project was connected, a page was opened, a resource was discovered, or a deployment occurred.

## 2. Core principles

- **Explicit execution:** every job requires an authenticated user action and server-side authorization.
- **No continuous collectors:** no always-running customer agent, polling daemon, or default scheduled test.
- **Ephemeral execution:** create a runner only for the requested job; enforce a maximum duration and clean it up.
- **No DCC application database:** do not add PostgreSQL, Redis, or another database to store projects, users, infrastructure inventory, jobs, or result history.
- **No permanent result retention:** return results to the current user and discard temporary state/artifacts after a short, documented TTL.
- **Least privilege:** separate read-only discovery permissions from permissions required to launch runners or perform active tests.
- **Environment-aware safety:** staging and production have different default policies; production active tests require stronger confirmation and stricter bounds.
- **Evidence, not assumptions:** report measured values, data sources, missing data, and limitations. Do not claim causality from correlation.
- **Customer network locality:** private resources are tested from an authorized execution task placed in the customer VPC.

## 3. Logical architecture

The logical request path is:

Developer / Operator → DCC React UI → DCC Django API / Control Plane → identity and policy validation → temporary ECS Fargate Diagnostic Runner → AWS discovery and selected test engine → customer application/API/database → normalized result → DCC UI.

The runner may use a temporary encrypted object only for large reports. The object is not a permanent report archive and must expire under a short TTL.

The browser never receives AWS credentials and never calls AWS APIs directly.

## 4. Deployment boundaries

### 4.1 DCC Control Plane

The existing React + TypeScript frontend and Django REST API remain the control plane. The control plane is responsible for identity-token validation, authorization, accepting a narrowly defined test request, validating target/environment/profile/limits, starting a configured runner, exposing job state, receiving results, and enforcing expiration.

The API must not accept arbitrary task definitions, subnets, security groups, IAM roles, container overrides, shell commands, or arbitrary target URLs from the browser.

### 4.2 Customer-side diagnostic runner

The preferred execution location for private AWS resources is a short-lived ECS Fargate task in the customer's AWS account and VPC. It is launched only after a user explicitly starts a test.

The runner receives a server-validated job specification, uses its ECS Task Role for AWS discovery, performs only selected test modules, measures target impact and its own resource overhead, returns normalized results, and exits after completion or a hard timeout.

A permanent sidecar or always-running agent is not required.

### 4.3 Runner isolation

Use separate task definitions or strongly isolated runner profiles for:
- lightweight discovery and health diagnostics;
- security scanning;
- load/performance generation.

Heavy load generation must not share the same CPU/memory budget as the orchestration/control process. Prefer a dedicated temporary load-generator task or task set with explicit CPU, memory, network, concurrency, and duration ceilings.

## 5. Test lifecycle

1. User authenticates and selects a customer account/environment.
2. User selects a test type and reviews its scope and safety impact.
3. UI collects only the parameters required for that test.
4. API validates identity, authorization, environment, target allowlist, parameters, quotas, and approval gates.
5. Control plane starts a temporary runner with a server-generated run ID and bounded configuration.
6. Runner performs on-demand discovery only for the selected scope.
7. Runner captures a baseline where relevant, executes the test, measures target impact and runner overhead, and captures post-test recovery.
8. Runner sends the result to the control plane or writes a short-lived encrypted artifact to an approved temporary location.
9. UI displays the result and offers an explicit download action where appropriate.
10. Runner exits. Temporary artifacts and execution metadata expire or are deleted under the retention policy.

A failed callback or control-plane restart must not leave an unbounded runner. The runner must have its own hard maximum runtime and an independent cleanup/expiration mechanism.

## 6. Test categories

### Pre-deployment / Staging
- progressive backend and API load tests;
- database connection, query-latency, and controlled capacity tests;
- end-to-end performance and bottleneck analysis;
- SAST and source/dependency scanning;
- container image and filesystem vulnerability scanning;
- IaC and cloud-configuration security checks;
- DAST against explicitly approved staging targets;
- release-readiness summary with findings and evidence.

### Runtime / Production
- on-demand ECS service/task health;
- ALB listener and target-group health;
- API health and bounded read-only endpoint checks;
- database connectivity and safe read-only query latency;
- AWS configuration and IAM posture checks;
- CloudWatch metric snapshots and scaling-policy/scale-activity review;
- narrowly scoped passive security/configuration checks;
- explicitly approved low-impact active checks.

Do not run aggressive load tests or intrusive security scans against production by default.

## 7. Discovery model

Discovery is on-demand and scope-limited. The runner uses AWS APIs with read-only permissions to inspect supported resources, then builds a temporary relationship graph.

Initial AWS discovery scope:
- ECS clusters, services, tasks, task definitions;
- ALB/NLB, listeners, target groups and health;
- RDS instances/clusters and relevant configuration/CloudWatch metrics;
- CloudWatch metrics and alarms;
- Application Auto Scaling targets, policies, and activities;
- VPC, subnets, route tables, and security groups;
- ECR repositories/images and image metadata where authorized.

Resource discovery does not prove network reachability. A private RDS instance can be visible through AWS APIs while still being unreachable from the runner because of subnet routes or security-group rules.

Do not claim support for every AWS service in the MVP. Add integrations through explicit, versioned discovery adapters.

## 8. Identity, account access, and authorization

- Use an external OIDC identity provider for human authentication; do not create a DCC user database.
- Validate issuer, audience, signature, expiry, and required scopes/claims server-side.
- Derive tenant/customer/account scope from verified identity claims and explicit authorization, never from untrusted request fields alone.
- For cross-account access, prefer customer-created IAM roles with External ID and tightly scoped trust. Do not store long-lived AWS access keys.
- The customer-side runner should use its ECS Task Role where possible.
- Separate read-only discovery permissions from runner-launch and any future mutation permissions.
- MVP is read-only with respect to customer infrastructure except for creating/stopping the temporary diagnostic task itself. Do not change customer ECS desired counts, scaling policies, RDS settings, security groups, or application resources.

Authentication is a prerequisite for a SaaS multi-customer product. The current repository's anonymous operational API is not acceptable for a public multi-tenant SaaS deployment.

## 9. Stateless job orchestration and temporary results

No DCC-owned database is required.

Preferred job tracking:
- the control plane starts the runner and returns an opaque run ID plus the ECS task reference;
- status is derived from ECS task state and a signed, short-lived result reference;
- the runner publishes a bounded result payload to a control-plane callback or a temporary encrypted object;
- temporary artifacts use a short TTL and lifecycle deletion;
- the browser polls only while the user is viewing the active run; no background polling continues after the session ends.

Do not use process memory as the sole source of truth for long-running jobs in a multi-instance deployment. It is not durable and is not shared across replicas. ECS task state and short-lived signed result references provide a better stateless coordination boundary.

S3, if used, is temporary artifact transport/storage, not a database. Set encryption, object-size limits, access isolation, lifecycle expiration, and explicit deletion after successful delivery where practical. If the product requirement is strict zero-retention, use bounded callback delivery and do not persist report objects.

## 10. Impact measurement

For active tests, capture:
- **Target impact:** target CPU/memory, request rate, p50/p95/p99 latency, error rate, task count/restarts, DB connections, DB CPU/IO/latency, and scaling activity where available.
- **DCC overhead:** runner CPU/memory, network, generated request rate, concurrency, AWS API calls, and execution duration.

Use baseline → during → post phases. Label source, timestamp, aggregation window, sample count, missing metrics, and limitations. Do not attribute an observed change to the test as proven causality; describe it as observed during the test window unless stronger evidence exists.

## 11. Safety requirements

- hard maximum duration at runner level;
- request-rate, concurrency, payload-size, and total-request caps;
- progressive load ramp and cool-down;
- configurable stop thresholds for latency, errors, CPU/memory, and DB connections;
- explicit environment and target allowlists;
- no destructive DB statements or business-changing API operations by default;
- staging-only defaults for load and active DAST;
- production confirmation and maintenance-window acknowledgement for exceptional active tests;
- independent cleanup on normal completion, failure, timeout, and control-plane loss;
- auditable user action metadata in transient execution context, without permanent history unless a future explicit retention feature is approved.

## 12. Auto Scaling scope

MVP: observe and explain existing ECS/Application Auto Scaling configuration and activity during a test. Report whether scaling occurred, when it occurred, and how workload/latency changed, where data is available.

Do not automatically change desired count or scaling policies. A future controlled-apply feature would require separate explicit approval, scoped mutation IAM, a bounded change plan, audit evidence, and rollback strategy.

## 13. MVP boundary

Included:
- AWS-first on-demand discovery;
- ECS + ALB/Target Groups + RDS + CloudWatch + Auto Scaling;
- temporary runner lifecycle;
- pre-deployment performance/load tests in staging;
- safe database tests;
- baseline security checks and approved staging DAST;
- runtime health/API/connectivity checks;
- impact and runner-overhead measurement;
- temporary report delivery without permanent database/history.

Excluded initially:
- continuous monitoring and always-on agent;
- scheduled/automatic tests;
- permanent project/resource inventory;
- permanent report history and analytics;
- automatic production scaling changes;
- destructive or intrusive production tests;
- multi-cloud and Kubernetes support;
- AI root-cause claims;
- full enterprise compliance certification.

## 14. Supersession note

This document defines target architecture v2.0. Existing repository documents describing current in-memory diagnostic sessions, anonymous API, current providers, or existing ECS worker are implementation-state references until code is migrated. They must not be interpreted as proof that v2.0 is already implemented.
