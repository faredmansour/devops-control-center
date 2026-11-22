# Terraform Architecture and Learning Guide — us-east-1 Test Lab

**Status:** Architecture baseline for implementation. This document describes the intended organization; it does not claim that all modules, workloads, or AWS resources have been implemented or deployed.

## 1. Design goals

1. **Easy to navigate and explain:** one clear responsibility per module and file.
2. **Safe isolation:** a separate Terraform root, backend key, naming prefix, and state from the existing `eu-north-1` Test Lab.
3. **Reusable:** modules accept inputs rather than hard-coding region-specific resource IDs.
4. **Reviewable:** changes are validated in small stages, with plans reviewed before any apply.
5. **Least privilege:** SG rules use SG references for internal traffic; IAM policies scope resources and actions.
6. **No hidden coupling:** module outputs are passed explicitly; modules do not reach into each other's internal resources.
7. **Real target validation:** this lab must deploy both DCC and a separate E-commerce application so DCC can execute meaningful tests against a real target.

## 2. Test Lab scope: two independent applications

The us-east-1 lab is not a DCC-only deployment. It contains two distinct application boundaries:

### A. DCC Control Plane

DCC provides the user-facing control plane: project/environment registration, test authorization and orchestration, execution tracking, and result presentation. It must not be treated as the application under test in the E-commerce validation scenario.

### B. E-commerce Target Application

E-commerce is a separately deployed application and the primary target used to validate DCC's capabilities. Its React/Vite frontend, Node.js/Express 5 backend/API, and dedicated MongoDB database (Mongoose) belong to the E-commerce workload boundary. The MongoDB database is dedicated to E-commerce and is not shared with DCC. Redis is an optional cache integration; it is not a substitute for the persistent MongoDB data store.

**Target repository:** [faredmansour/ecommerce-project](https://github.com/faredmansour/ecommerce-project), branch `master` (reviewed for this design). The repository contains `frontend/` (React/Vite), `backend/` (Node.js/Express 5), root `docker-compose.yml`, and separate frontend/backend Dockerfiles. The backend listens on TCP 8000; the frontend container serves static assets through Nginx on TCP 80. The exact AWS routing/ALB arrangement still needs to be selected and validated before creating listeners or services. Do not infer final topology from the generic Test API SG.

### C. Reusable DCC Integration Kit / Agent

The long-term product goal is a small reusable DCC integration image/component that can be attached to or deployed alongside future projects. It is an integration/communication component, not the E-commerce application itself and not a permanent dependency required for the target application to stay online.

Its communication model should be secure and narrowly scoped. Prefer outbound-initiated authenticated communication where practical; do not expose an agent management port publicly. The agent's exact runtime placement (standalone task/service, job-side integration, or another adapter) remains a design decision to validate against the execution lifecycle.

### D. On-demand Test Workers

Temporary workers execute explicitly authorized API, load, security, performance, or infrastructure checks. Their lifecycle is independent of Django process memory and must support bounded execution, cancellation, timeout, result delivery, and cleanup. Active tests must be scoped to the registered E-commerce target and governed by rate, duration, and impact limits.

## 3. Workload boundaries and data ownership

| Workload | Responsibility | Owns | Must not own |
|---|---|---|---|
| DCC Control Plane | Orchestration and user interface/API | DCC application runtime and its required configuration | E-commerce database or E-commerce lifecycle |
| E-commerce Frontend | Customer-facing web UI | Frontend runtime/assets | DCC credentials or database access |
| E-commerce Backend | E-commerce API/business logic | Backend runtime and application configuration | DCC control-plane permissions |
| E-commerce MongoDB | E-commerce persistence | Dedicated database and credentials | DCC application data |
| DCC Agent / Integration Kit | Secure target-side integration | Minimal integration configuration/identity | Broad AWS administrator permissions |
| Test Workers | Temporary test execution | Ephemeral execution state and bounded test artifacts | Permanent target credentials or unrestricted target access |

DCC and E-commerce must use separate workload identities, security boundaries, secrets, and resource naming. Do not share a database, task role, or application security group between them. The DCC Control Plane being unavailable must not automatically stop the E-commerce application.

## 4. Target directory layout

The regional root should evolve toward this structure:

```text
infra/terraform/
├── modules/
│   ├── network/
│   ├── security-groups/
│   ├── iam/
│   ├── ecr/                 # when image repositories are designed
│   ├── ecs/                 # reusable ECS task/service resources
│   ├── load-balancer/       # listeners, target groups and TLS
│   ├── data-services/       # dedicated E-commerce DB/cache if selected
│   └── diagnostic-runner/   # temporary DCC test execution
└── test-lab-us-east-1/
    ├── versions.tf
    ├── providers.tf
    ├── backend-template/
    ├── main.tf              # composition only
    ├── variables.tf
    ├── locals.tf
    ├── outputs.tf
    ├── terraform.tfvars.example
    ├── README.md
    ├── TERRAFORM_ARCHITECTURE.md
    └── SECURITY_GROUPS_DESIGN.md
```

Do not create empty module directories just to make the tree look complete. Add each module when its resources and tests are ready.

## 5. Responsibility boundaries

| Module | Owns | Must not own |
|---|---|---|
| network | VPC, subnets, IGW, NAT, route tables | SG policy, ECS, databases |
| security-groups | SGs and ingress/egress rules | VPC/subnets, application resources |
| iam | trust policies, task/execution roles, scoped policies | ECS service lifecycle, network |
| ecr | repositories, lifecycle and immutability | image build/push credentials |
| ecs | clusters, task definitions, services | VPC creation, IAM policy authoring |
| load-balancer | ALB, listeners, target groups, ACM attachment | application authentication |
| data-services | E-commerce MongoDB/Redis and subnet groups, if selected | application schema/migrations |
| diagnostic-runner | temporary test task definitions and execution configuration | permanent application lifecycle |
| root | composition, environment values, outputs | detailed resource implementation |

## 6. IAM workload identity design (planning)

IAM roles must be designed per workload, not shared across the entire lab:

| Identity | Intended permissions | Explicit exclusions |
|---|---|---|
| DCC ECS execution role | Pull DCC image from its ECR repository; write container logs; retrieve only explicitly referenced runtime secrets if required | No E-commerce MongoDB access; no broad discovery permissions |
| DCC task role | Only the AWS APIs required by implemented DCC control-plane features | No blanket administrator or wildcard resource mutation |
| E-commerce execution role | Pull E-commerce images; write its container logs; retrieve only its own runtime secrets if required | No DCC control-plane permissions |
| E-commerce backend task role | Only application-specific AWS integrations confirmed from source code | No DCC discovery/test permissions |
| DCC Agent role/identity | Authenticate to DCC and perform only its approved integration actions; AWS permissions only if a concrete feature requires them | No broad account discovery or administrative access by default |
| Test Worker role | Read-only discovery/test permissions scoped to approved resources and the test session | No application deployment, IAM mutation, or unrestricted infrastructure changes |

Repository review confirms the E-commerce stack is React/Vite + Node.js/Express 5 + MongoDB/Mongoose, with Redis and Cloudinary as optional integrations. The current Compose file points `DB_URL` to `mongodb://host.docker.internal:27017/e-commerce` but does not define a MongoDB service. It also builds the frontend with `VITE_API_URL=http://localhost:8000/api`, which is a local-development value and must be replaced at build time for the AWS URL/routing design. The Compose file publishes Redis on the host and configures it as a cache; production network exposure must instead be private and SG-scoped. The Render blueprint's frontend `rootDir` is `frontend final project`, while the repository directory is `frontend`; do not rely on that blueprint as-is for AWS deployment. The AWS staging design must provide a reachable, persistent MongoDB endpoint and inject `DB_URL` through a secret/configuration mechanism. The final policies depend on source-code review and the selected execution model. Use separate task roles even when two containers happen to run in one ECS task. Prefer short-lived credentials, scoped resource ARNs, and explicit trust relationships. Do not create the IAM module until the required API actions, resource scopes, and trust principals have been documented and reviewed.

## 7. Network and security boundaries

- Keep the regional VPC isolated from the existing `eu-north-1` lab and verify CIDR overlap against connected networks before apply.
- Keep application workloads private where the selected ingress architecture allows it.
- Do not assume DCC and E-commerce should share one public ALB. Decide whether they need separate ALBs, listeners, host-based routing, or a private target path after reviewing domains, authentication, and exposure requirements.
- Keep E-commerce frontend, backend, and database access paths explicit. A frontend must not receive database credentials.
- E-commerce MongoDB is dedicated to E-commerce and accepts connections only from the E-commerce backend (and explicitly approved migration/maintenance path).
- DCC-to-target test traffic must be limited to the required E-commerce API/health endpoints and approved test-worker sources.
- Prefer an authenticated outbound agent/control channel where possible; do not create public inbound access to the agent.
- Test Workers must be temporary, isolated, bounded, and unable to reach unrelated workloads.
- No public ingress on application, worker, database, cache, or diagnostic task SGs.
- Internal access uses source SG references, not broad VPC CIDRs.
- Every outbound rule needs a written reason. Prefer VPC endpoints for AWS services where practical; security groups cannot enforce DNS/FQDN destination allowlists.
- Do not mix inline SG rules with standalone `aws_vpc_security_group_*_rule` resources for the same SG.

## 8. Current Security Groups interpretation

The currently implemented seven groups (`alb`, `dcc_control`, `diagnostic_worker`, `test_api`, `test_worker`, `database`, `cache`) are an initial generic policy layer, not yet a complete proof of the final two-application topology.

In particular:
- `test_api` and `test_worker` are generic application-under-test tiers. Their final names and ownership must be aligned with the E-commerce workload once its deployment design is confirmed.
- The current `database` SG rules are hard-coded to PostgreSQL TCP 5432 and `test_api` is hard-coded to TCP 8080. The reviewed E-commerce backend listens on TCP 8000 and requires MongoDB TCP 27017. These are material mismatches: the current SG module must be refactored and its tests updated before E-commerce can safely use it.
- The current ALB-to-DCC path does not establish how E-commerce is exposed to users or how DCC test traffic reaches it.
- Separate E-commerce frontend/backend/database groups and possibly a separate ALB may be required. Do not add or apply these rules until ports, ingress, and routing are confirmed from the E-commerce deployment design.

## 9. State and regional isolation

- The new root uses a unique backend key, for example `dcc/test-lab/us-east-1/terraform.tfstate`.
- The backend bucket must be approved and provisioned separately with versioning, encryption, public-access blocking, TLS enforcement, and least-privilege access.
- Never run `terraform init -migrate-state`, `terraform state mv`, or `terraform destroy` against the old regional root as part of this parallel-environment setup.
- Do not reuse resource IDs, endpoints, subnet IDs, SG IDs, Cloud Map IDs, or region-scoped ECR repository URLs from `eu-north-1`.
- Push immutable images to the new region and reference their digests.

## 10. Cost and operational considerations

- One NAT Gateway is cheaper than one per AZ but creates an AZ dependency and possible cross-AZ data charges. It also incurs hourly and data-processing charges while provisioned.
- ECS Fargate, ALB, NAT, and managed MongoDB each have independent recurring costs. A managed database should be selected only after the E-commerce persistence and budget requirements are reviewed.
- A containerized database may reduce initial lab cost but introduces persistence, backup, recovery, and operational responsibilities. It must not be treated as disposable if E-commerce data needs to survive deployments.
- Load and security testing can create target, worker, data-transfer, and logging costs. Set hard test limits and clean up temporary workers.

## 11. Implementation and review sequence

| Stage | Deliverable | Validation gate |
|---|---|---|
| 0 | Two-application architecture baseline | Review DCC/E-commerce/Agent/Worker boundaries |
| 1 | Network module | fmt, validate, CIDR positive/negative checks |
| 2 | Initial Security Groups module | fmt, validate, mocked policy tests, traffic matrix review |
| 3 | E-commerce source/deployment review | Repository and stack confirmed; resolve Compose MongoDB and frontend API URL configuration |
| 4 | Final network/SG topology | Confirm ingress, routing, agent and test-worker paths |
| 5 | IAM design and module | Trust-policy and least-privilege review for every workload |
| 6 | ECR and image build/push | Immutable image digests exist in us-east-1 |
| 7 | E-commerce deployment | Frontend/API/MongoDB connectivity healthy and isolated |
| 8 | DCC deployment and integration image | DCC can securely register/reach the target |
| 9 | On-demand test workers | Cancellation, timeout, bounded tests and cleanup verified |
| 10 | Full Terraform plan | Zero unintended changes; no eu-north-1 state/resources |
| 11 | Apply | Only after separate explicit deployment approval |

Each stage should be a small reviewable commit. A successful DCC deployment alone is not acceptance. The first milestone is: deploy E-commerce, register it in DCC, establish secure connectivity/integration, and demonstrate resource/target discovery. The next milestone is a bounded API/health smoke test with an evidence-backed result. Load, security, performance, cancellation, and cleanup scenarios follow in later validation stages; they are not prerequisites for the first integration milestone.

## 12. How to explain this architecture

> The lab contains two independent applications. DCC is the control plane that authorizes and orchestrates tests; E-commerce is a separate target application with its own frontend, backend, database, security groups, and IAM identities. A small reusable DCC integration component and temporary test workers provide the bridge for executing bounded tests against the target. This separation means a DCC outage does not automatically take E-commerce offline, and it prevents the monitoring platform from inheriting broad permissions over the application it tests.

## 13. Current implementation status

The reusable Network module and the us-east-1 root composition are present. The reusable Security Groups module is composed into that root and currently defines seven initial workload tiers with no public ingress by default and explicit destination CIDR allowlists for optional public egress. Historical CI runs reported the Network and mocked Security Groups tests passing; check the latest workflow run before relying on that status. These modules and CI checks do not create AWS resources. The seven-group policy is an initial baseline and must be reconciled with the final E-commerce topology. IAM, E-commerce infrastructure, DCC Agent deployment, and temporary test-worker infrastructure remain design/implementation work. No `terraform apply` is authorized by this document.
