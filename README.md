# DevOps Control Center (DCC)

[![CI](https://github.com/faredmansour/dashboard_test/actions/workflows/ci.yml/badge.svg)](https://github.com/faredmansour/dashboard_test/actions/workflows/ci.yml)
[![Security](https://github.com/faredmansour/dashboard_test/actions/workflows/security.yml/badge.svg)](https://github.com/faredmansour/dashboard_test/actions/workflows/security.yml)
[![Terraform](https://github.com/faredmansour/dashboard_test/actions/workflows/terraform.yml/badge.svg)](https://github.com/faredmansour/dashboard_test/actions/workflows/terraform.yml)

**DevOps Control Center** is an AWS-first, on-demand infrastructure diagnostics and testing platform. Developers and engineering teams explicitly launch tests before deployment (typically in staging) or run bounded diagnostics while an application is operating.

DCC is not intended to be a continuously running monitoring agent. Its target architecture uses temporary diagnostic execution tasks, user-triggered test runs, bounded safety policies, and transient result delivery. The product direction intentionally avoids a DCC-owned application database and permanent test history.

> **Architecture status:** the v2.0 documents describe the target architecture. They do not mean that every test engine, identity integration, or temporary-runner workflow is already implemented. See the current-vs-target and codebase audit documents before treating a capability as available.

## Product workflows

### Pre-deployment / Staging
- Backend/API progressive load and capacity tests.
- Database connectivity, query latency, and controlled performance tests.
- Security checks: SAST, dependency, secret, container, IaC scanning, and approved staging DAST.
- Bottleneck analysis and evidence-based release-readiness reports.

### Runtime / Production
- On-demand AWS resource discovery and infrastructure health checks.
- ECS service/task and ALB target health checks.
- Bounded API health/read-only checks and safe database connectivity checks.
- CloudWatch metric snapshots and Auto Scaling behavior review.
- Selected security/configuration checks with explicit scope and approval.

All tests require an explicit user action. Load tests and active security scans can affect target systems; they are bounded, measured, and stopped when configured safety limits are reached. Production active testing is disabled by default and requires explicit authorization.

## Target architecture

The target request flow is:

1. Developer signs in and selects an AWS account/environment and test.
2. DCC validates identity, authorization, target scope, and test limits.
3. DCC starts a temporary ECS Fargate diagnostic runner in the customer-approved network.
4. The runner performs on-demand discovery and executes only the selected test.
5. The runner measures both target impact and its own resource overhead.
6. DCC returns the result to the initiating user and releases temporary execution resources.

The browser never receives AWS credentials. The target architecture delegates human identity to an external OIDC provider and uses IAM roles/short-lived sessions for AWS access. No long-lived customer AWS keys should be stored by DCC.

## Technology stack

- **Frontend:** React, TypeScript, Vite, Tailwind CSS, Radix UI, Lucide, Recharts.
- **Backend:** Python, Django, Django REST Framework, Boto3, Gunicorn, WhiteNoise.
- **Cloud and containers:** AWS ECS/Fargate, ECR, ALB, RDS, CloudWatch, IAM.
- **Infrastructure as Code:** Terraform.
- **CI/CD and security tooling:** GitHub Actions, Trivy and repository security checks.
- **Optional telemetry integrations:** CloudWatch, Prometheus-compatible metrics, Loki logs.

## Repository structure

```text
.
├── backend/                 # Django + DRF control plane
├── frontend/                # React + TypeScript + Vite
├── test-app/                # Standalone FastAPI test laboratory
├── infra/terraform/test-lab # AWS infrastructure as code
├── deploy/ecs/              # ECS deployment templates
├── docs/                    # Architecture, deployment and handoff docs
├── scripts/                 # Deployment/helper scripts
├── Dockerfile               # Production multi-stage image
└── .github/workflows/       # CI, security and Terraform automation
```

## Architecture documentation

- [Target Architecture v2.0](docs/architecture/TARGET_ARCHITECTURE_V2.md)
- [Test Lifecycle and Catalog](docs/architecture/TEST_LIFECYCLE_AND_CATALOG.md)
- [Stateless Execution and Data Retention](docs/architecture/STATELESS_EXECUTION_AND_RETENTION.md)
- [Diagnostic Safety and Impact Model](docs/architecture/DIAGNOSTIC_SAFETY_AND_IMPACT_V2.md)
- [Current vs Target Architecture](docs/implementation/CURRENT_VS_TARGET_V2.md)
- [Codebase Audit and Gap Analysis](docs/implementation/CODEBASE_AUDIT_V2.md)
- [ADR-002: On-Demand Stateless Execution](docs/adr/ADR-002-on-demand-stateless-diagnostic-execution.md)

Existing deployment and feature documents describe current implementation details and may be superseded by the v2.0 target decisions. Check the implementation audit before assuming a documented target capability is already available.

## Local development

### Backend

```bash
cd backend
python -m venv .venv
# Windows PowerShell
.venv\\Scripts\\Activate.ps1
python -m pip install -r requirements.txt
python manage.py check
python manage.py test
python manage.py runserver
```

### Frontend

```bash
cd frontend
npm ci
npm run typecheck
npm run build
npm run dev
```

### Production Docker image

```bash
docker build -t dcc:local .
docker run --rm -p 8000:8000 -e DJANGO_DEBUG=false -e DJANGO_SECRET_KEY=replace-me -e DJANGO_ALLOWED_HOSTS=localhost,127.0.0.1 dcc:local
```

Production configuration must supply a strong secret, explicit allowed hosts, HTTPS ingress, and the required identity integration before exposing operational endpoints.

## Security and safety

- AWS access is backend/runner-only; the browser never receives AWS credentials.
- Customer resources and targets must be explicitly allowlisted and authorized.
- Runtime API/database checks default to bounded read-only behavior.
- Load and active security tests require explicit scope, caps, and stop conditions.
- Secrets, tokens, cookies, and sensitive response fields must be redacted from reports and logs.
- No production scaling or customer infrastructure mutation is performed by the MVP.
- Temporary runner tasks require hard timeouts and cleanup on success, failure, cancellation, and control-plane interruption.

## Portfolio note

This repository demonstrates cloud-native application architecture, infrastructure as code, automation, and DevSecOps concepts. Target architecture documents are design intent, not proof that every AWS resource or product capability is deployed and running in production.