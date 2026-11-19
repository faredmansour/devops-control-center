# DCC Diagnostic Safety and Impact Model v2.0

## 1. Safety objective

DCC cannot promise that active tests have zero impact. Load tests, DAST, API calls, and database queries consume target resources by design. The objective is to minimize, measure, bound, and stop test impact.

Passive AWS API discovery and metric reads generally avoid deliberate application load, but still consume API quota and incur small control-plane/network overhead.

## 2. Two impact domains

### Target impact
Measure, when supported:
- ECS task/service CPU and memory;
- task count, deployments, restarts, and health;
- ALB request count, target response time, healthy/unhealthy hosts, 4xx/5xx;
- API request rate, p50/p95/p99 latency, status/error rate;
- RDS CPU, connections, freeable memory/storage, IOPS, read/write latency, database load;
- Auto Scaling activities and desired/running task counts.

### DCC runner overhead
Measure:
- runner CPU and memory;
- network bytes and throughput;
- generated requests/connections and concurrency;
- AWS API call count, throttling, retries, and duration;
- test orchestration overhead and collection gaps.

Do not hide runner overhead: a diagnostic that saturates its own runner can produce misleading target results.

## 3. Measurement phases

1. **Pre-test baseline:** collect a bounded window before load starts.
2. **During test:** sample relevant metrics at a declared interval and record exact test ramp/step timestamps.
3. **Post-test recovery:** continue bounded collection after load stops to observe recovery.

Every metric carries source, unit, timestamp/window, aggregation, sample count, and availability state. Missing metrics are unavailable/null, never silently converted to zero.

Reports distinguish observed change during the test, possible relationship to the test, and evidence insufficient to attribute causation.

## 4. Load test guardrails

- start in staging;
- require a named bounded profile;
- use progressive ramp-up and cool-down;
- enforce maximum RPS/VUs, request count, duration, payload size, and concurrent tests;
- stop on configurable latency/error/CPU/memory/DB connection thresholds;
- provide an immediate user stop control;
- isolate load generation from the control plane and lightweight discovery runner;
- verify target allowlist and environment immediately before execution;
- do not run against third-party or unowned targets.

Production load testing is a separate, disabled-by-default path requiring explicit approval, a maintenance window, and stricter server-enforced ceilings.

## 5. Database guardrails

Default tests are connection/TLS checks and bounded read-only queries. Never execute destructive SQL or unbounded table scans. Write/load testing requires a dedicated test database/schema, explicit authorization, bounded data volume, and a documented cleanup procedure.

## 6. Security scan guardrails

Source and artifact scans (SAST, dependency, secret, container, IaC) run against supplied or explicitly connected build inputs. DAST and active checks require a verified target allowlist and staging environment by default.

Production active security testing requires proof of target ownership/authorization, exact host/path scope, approved scan profile and exclusions, explicit operator confirmation, rate/concurrency/time caps, safe request policy, and emergency stop.

Do not run destructive payloads, denial-of-service checks, credential attacks, persistence, lateral movement, or exploit chains as part of the standard DCC automated catalog.

## 7. Auto Scaling

MVP behavior is observe and recommend only. During a load test, correlate request/latency changes with ECS desired/running task counts and recorded scaling activities. Report whether scale-out happened and how quickly, where data is available.

DCC must not change desired count, scaling policies, alarms, or capacity providers in the MVP. Any future apply feature requires separate explicit approval, narrowly scoped IAM, a previewed change plan, audit evidence, limits, and rollback.

## 8. Cleanup and failure handling

The runner enforces its own hard deadline and stops the load generator when user cancellation, safety thresholds, maximum runtime/request budget, target identity/scope failure, loss of required authorization/connectivity, or unrecoverable runner error occurs.

Temporary ECS tasks must be stopped on completion/failure. A separate cleanup mechanism must identify and terminate expired DCC-owned diagnostic tasks if the control plane or callback fails. Tag temporary resources with a DCC ownership marker, run ID, creation time, and expiration metadata. Never tag or mutate customer application resources as part of cleanup.

## 9. Report interpretation

A test report is evidence for engineering decisions, not a certification. Security findings require triage; performance results are specific to the tested environment, data, workload, region, and time. Include scanner/test version, configuration, limits, target identity, environment, timestamps, and limitations.
