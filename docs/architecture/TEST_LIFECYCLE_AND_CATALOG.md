# DCC Test Lifecycle and Test Catalog

**Status:** Target behavior for architecture v2.0

## 1. Execution policy

All tests are **manual and on-demand**. A test starts only after an authenticated developer/operator presses **Run Test** and the backend accepts the request. Opening a dashboard, discovering resources, deploying an application, or connecting an AWS account must never start a test.

Every test request identifies the customer/account and AWS region, target environment, test category/profile, approved target scope, bounded parameters, and initiating user identity from verified authentication claims.

The backend rejects unknown test types, unsupported parameters, unapproved targets, and values outside server-enforced limits.

## 2. Lifecycle state machine

Draft → Validating → Rejected or Queued → Provisioning → Running → Collecting → Delivering → Completed / Failed / Cancelled / Timed Out → Expired.

A safety-triggered stop is not a generic success; report the exact stop reason and partial measurements.

## 3. Test catalog

### A. Pre-deployment / Staging

| Test | Purpose | Default environment | Main output |
|---|---|---|---|
| Backend Load Test | Find backend throughput and latency limits | Staging | RPS, VUs, p50/p95/p99, errors, saturation point |
| Database Performance Test | Evaluate safe query and connection behavior | Staging | query latency, connection behavior, DB metrics |
| End-to-End Performance Test | Measure application behavior under realistic flows | Staging | latency, throughput, bottlenecks |
| SAST | Detect code-level security patterns | Source artifact/repository | findings by severity and file/line |
| Dependency Scan | Detect vulnerable direct/transitive dependencies | Source artifact/repository | package, version, advisory, fix version |
| Container Scan | Inspect image OS and application packages | Built image | package vulnerabilities and severity |
| IaC Scan | Inspect Terraform/configuration for risky settings | IaC artifact/repository | misconfiguration findings |
| Secret Scan | Detect accidentally committed credentials | Source artifact/repository | redacted finding and location; never echo secret |
| DAST | Test deployed application behavior for common web vulnerabilities | Staging only by default | findings, request evidence, confidence |

Possible tool adapters include Trivy, Semgrep, Bandit, pip-audit, npm audit, Checkov, Gitleaks, and OWASP ZAP. Tool choice is an adapter decision; DCC must normalize findings without claiming that a scanner alone proves security.

### B. Runtime / Production

| Test | Purpose | Default impact |
|---|---|---|
| AWS Resource Discovery | Build a current resource snapshot | Read-only AWS API calls |
| ECS Health Check | Inspect service/task state and health | Read-only |
| ALB Target Health | Inspect target registration and health | Read-only |
| API Health Check | Call approved health/read-only endpoints | Low, bounded HTTP requests |
| Database Connectivity | Open a connection and run a safe read-only query | Low, bounded DB activity |
| CloudWatch Snapshot | Retrieve selected recent metrics/alarms | Read-only AWS API calls |
| Auto Scaling Review | Inspect policies, targets, and recent activities | Read-only |
| Network Reachability | Test approved host/port combinations | Bounded connection attempts |
| Configuration Security Check | Inspect selected AWS configuration and IAM posture | Read-only |
| Active Security Check | Run an explicitly approved, bounded check | Depends on test; not enabled by default in production |

Production load testing, destructive database testing, broad active DAST, fuzzing, and exploit validation are excluded from the normal runtime catalog.

## 4. Performance/load test profile

The user chooses a named profile or bounded values:
- target API/service;
- workload pattern and HTTP methods;
- virtual users or request rate;
- ramp-up steps;
- steady-state duration;
- cool-down;
- maximum total requests;
- allowed error/latency thresholds;
- stop thresholds.

Use progressive load, not an immediate unbounded spike. Example ramp values are illustrative only and must be calibrated to the environment. Stop when a configured safety threshold is breached. Capture target baseline, during-test measurements, and recovery.

Measure backend CPU/memory, task count, request rate, latency percentiles, HTTP error rate, restarts, and throttling where available. Measure database CPU, connections, freeable memory, read/write latency, IOPS, and query latency where supported.

A load test can identify the saturation point but cannot guarantee zero impact. It deliberately creates load. Production execution must be a separate exceptional workflow with explicit approval, maintenance window, and strict caps.

## 5. Database test safety

Allowed by default:
- DNS and TCP reachability;
- TLS negotiation where configured;
- authentication validation without exposing credentials;
- a simple read-only health query;
- bounded read-only query latency checks.

Not allowed by default:
- DROP, TRUNCATE, arbitrary UPDATE/DELETE;
- unbounded table scans;
- schema migrations;
- uncontrolled connection storms;
- writes to business tables.

If write/capacity behavior must be tested, use a dedicated test database/schema and generated test data, with a cleanup plan and strict transaction/time bounds. Rollback alone is not a guarantee against every side effect.

## 6. API test safety

- Use an explicit endpoint allowlist and approved HTTP methods.
- Prefer health/read-only GET endpoints for runtime diagnostics.
- Do not automatically call payment, order creation, email, notification, or other business-changing endpoints.
- Use staging test accounts/data for functional POST/PUT/PATCH/DELETE tests.
- Require endpoint-specific authorization, idempotency keys where supported, and cleanup strategy.
- Reject arbitrary URLs and redirects that escape the approved target scope (SSRF protection).
- Bound request body size, response size, redirects, concurrency, rate, and timeout.
- Redact authorization headers, cookies, tokens, PII, and secrets from logs/reports.

## 7. Security testing scope and gates

Security testing is a collection of test classes, not one universal "secure/insecure" switch.

- **SAST/dependency/secret/IaC/container scans:** run before deployment against source/build artifacts; they do not require attacking the live application.
- **DAST:** runs against a deployed target. Staging is the default. Production DAST requires explicit authorization, narrow scope, safe scan policy, and approval.
- **Penetration testing/exploit validation:** not an MVP automated default. It requires a separately approved engagement scope and human security review.
- **AWS posture checks:** read-only inspection of IAM, networking, encryption, public exposure, and selected service configuration.

A clean scan does not prove an application is secure. Reports include scanner/version, scan scope, exclusions, timestamp, severity, confidence, and limitations. Do not label an application "fully secure" solely because no findings were returned.

## 8. Stop and cleanup rules

A runner stops on maximum runtime, user cancellation, configured target latency/error/CPU/memory/DB threshold, request/concurrency budget, target scope mismatch, revoked authorization, or unrecoverable runner failure.

Cleanup is attempted on every terminal path. The runner also needs a hard local deadline so a control-plane failure cannot leave it running indefinitely.
