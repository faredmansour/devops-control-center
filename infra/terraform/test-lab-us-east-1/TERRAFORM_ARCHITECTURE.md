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

E-commerce is a separately deployed application and the primary target used to validate DCC's capabilities. Its React/Vite frontend and Node.js/Express 5 backend/API belong to the E-commerce workload boundary. **Decision: MongoDB Atlas is the approved managed database for E-commerce.** Atlas is dedicated to E-commerce and is not shared with DCC. The application connects to Atlas over TLS; the backend alone receives the MongoDB connection secret. Redis is an optional cache integration, not a substitute for persistent MongoDB storage.

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
| E-commerce MongoDB Atlas | Managed E-commerce persistence | Dedicated Atlas cluster/database, database user and connection secret | DCC application data or direct frontend access |
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
│   ├── ecr/                 # private repositories for workload images
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
| data-services | AWS-hosted data services such as optional Redis, if selected | MongoDB Atlas resources/network access configuration owned outside this AWS Terraform root |
| diagnostic-runner | temporary test task definitions and execution configuration | permanent application lifecycle |
| root | composition, environment values, outputs | detailed resource implementation |

## 6. IAM workload identity design (implemented baseline)

IAM roles must be designed per workload, not shared across the entire lab:

| Identity | Intended permissions | Explicit exclusions |
|---|---|---|
| DCC ECS execution role | Pull DCC image from its ECR repository; write container logs; retrieve only explicitly referenced runtime secrets if required | No E-commerce MongoDB access; no broad discovery permissions |
| DCC task role | Only the AWS APIs required by implemented DCC control-plane features | No blanket administrator or wildcard resource mutation |
| E-commerce execution role | Pull E-commerce images; write its container logs; retrieve only its own runtime secrets if required | No DCC control-plane permissions |
| E-commerce backend task role | Only application-specific AWS integrations confirmed from source code | No DCC discovery/test permissions |
| DCC Agent role/identity | Authenticate to DCC and perform only its approved integration actions; AWS permissions only if a concrete feature requires them | No broad account discovery or administrative access by default |
| Test Worker role | Read-only discovery/test permissions scoped to approved resources and the test session | No application deployment, IAM mutation, or unrestricted infrastructure changes |

Repository review confirms the E-commerce stack is React/Vite + Node.js/Express 5 + MongoDB/Mongoose, with Redis and Cloudinary as optional integrations. The current Compose file points `DB_URL` to `mongodb://host.docker.internal:27017/e-commerce` but does not define a MongoDB service. It also builds the frontend with `VITE_API_URL=http://localhost:8000/api`, which is a local-development value and must be replaced at build time for the AWS URL/routing design. The Compose file publishes Redis on the host and configures it as a cache; production network exposure must instead be private and SG-scoped. The Render blueprint's frontend `rootDir` is `frontend final project`, while the repository directory is `frontend`; do not rely on that blueprint as-is for AWS deployment. The AWS staging design must inject the Atlas `DB_URL` through AWS Secrets Manager (or an equivalently protected secret mechanism), with no URI committed to Git or baked into images. The final policies depend on source-code review and the selected execution model. Use separate task roles even when two containers happen to run in one ECS task. Prefer short-lived credentials, scoped resource ARNs, and explicit trust relationships. The initial reusable IAM module now creates separate ECS execution and task roles for DCC, E-commerce, the Agent, and Test Workers. Execution-role policies are parameterized by workload-specific ECR repository ARNs, CloudWatch log group ARNs, Secrets Manager secret ARNs, and optional KMS key ARNs. Application task roles are empty by default. DCC test-worker orchestration is disabled by default and can be enabled only when exact task-definition, cluster, task-resource, and worker role ARNs are supplied. This is a least-privilege baseline; further permissions such as EC2 discovery, S3 inventory, CloudWatch metrics, and other integrations remain excluded until source-code/API requirements and resource scopes are confirmed.

## 7. Network and security boundaries

- Keep the regional VPC isolated from the existing `eu-north-1` lab and verify CIDR overlap against connected networks before apply.
- Keep application workloads private where the selected ingress architecture allows it.
- Do not assume DCC and E-commerce should share one public ALB. Decide whether they need separate ALBs, listeners, host-based routing, or a private target path after reviewing domains, authentication, and exposure requirements.
- Keep E-commerce frontend, backend, and database access paths explicit. A frontend must not receive database credentials.
- MongoDB Atlas is external to the VPC and dedicated to E-commerce. Only the E-commerce backend (plus an explicitly approved migration/maintenance path) receives its credentials. Atlas access must be restricted using its Network Access/IP Access List and TLS. Do not create an in-VPC MongoDB SG or expose MongoDB to the public internet.
- DCC-to-target test traffic must be limited to the required E-commerce API/health endpoints and approved test-worker sources.
- Prefer an authenticated outbound agent/control channel where possible; do not create public inbound access to the agent.
- Test Workers must be temporary, isolated, bounded, and unable to reach unrelated workloads.
- No public ingress on application, worker, database, cache, or diagnostic task SGs.
- Internal access uses source SG references, not broad VPC CIDRs.
- Every outbound rule needs a written reason. Prefer VPC endpoints for AWS services where practical; security groups cannot enforce DNS/FQDN destination allowlists.
- Do not mix inline SG rules with standalone `aws_vpc_security_group_*_rule` resources for the same SG.

## 8. Current Security Groups interpretation

The implemented Security Groups module now creates nine groups: `dcc_alb`, `ecommerce_alb`, `dcc_control`, `dcc_agent`, `diagnostic_worker`, `ecommerce_frontend`, `ecommerce_backend`, `test_worker`, and `cache`.

In particular:
- The E-commerce frontend is expected on TCP 80 behind its own ALB; its Express backend is expected on TCP 8000. Diagnostic and test workers have SG-referenced paths to the backend.
- MongoDB Atlas is external to the VPC. The backend alone receives its connection secret. TCP 27017 egress is limited to that port, while Atlas IP Access List must restrict the source to the NAT Gateway Elastic IP. This public-connectivity exception remains a pre-apply review item.
- The DCC Agent has an outbound-initiated TCP 8000 path to DCC Control and no inbound SG rules. Application-level authentication is still required.
- ALB listeners, certificates, target groups, DNS, and final ingress CIDRs remain separate deployment work.

## 9. State and regional isolation

- The new root uses a unique backend key, for example `dcc/test-lab/us-east-1/terraform.tfstate`.
- The backend bucket must be approved and provisioned separately with versioning, encryption, public-access blocking, TLS enforcement, and least-privilege access.
- Never run `terraform init -migrate-state`, `terraform state mv`, or `terraform destroy` against the old regional root as part of this parallel-environment setup.
- Do not reuse resource IDs, endpoints, subnet IDs, SG IDs, Cloud Map IDs, or region-scoped ECR repository URLs from `eu-north-1`.
- Push immutable images to the new region and reference their digests.

## 10. Cost and operational considerations

- One NAT Gateway is cheaper than one per AZ but creates an AZ dependency and possible cross-AZ data charges. It also incurs hourly and data-processing charges while provisioned.
- ECS Fargate, ALB, NAT, and MongoDB Atlas each have independent recurring costs. Atlas is approved to reduce database operations; select its cluster tier and region with the lab budget in mind. The AWS NAT Gateway's Elastic IP is the candidate stable egress identity for Atlas IP Access List when using public TLS connectivity. Atlas PrivateLink is an alternative to evaluate separately because it changes the network design and cost.
- MongoDB Atlas handles the managed database infrastructure; we remain responsible for database users/roles, network access rules, secret rotation, application-level backup/restore requirements, and selecting an appropriate Atlas backup/tier configuration.
- Load and security testing can create target, worker, data-transfer, and logging costs. Set hard test limits and clean up temporary workers.

## 11. Implementation and review sequence

| Stage | Deliverable | Validation gate |
|---|---|---|
| 0 | Two-application architecture baseline | Review DCC/E-commerce/Agent/Worker boundaries |
| 1 | Network module | fmt, validate, CIDR positive/negative checks |
| 2 | Initial Security Groups module | fmt, validate, mocked policy tests, traffic matrix review |
| 3 | E-commerce source/deployment review | Repository and stack confirmed; replace local Compose MongoDB dependency with Atlas secret injection and correct frontend API URL configuration |
| 4 | Final network/SG topology | Confirm ingress/routing, agent and test-worker paths, NAT EIP or Atlas PrivateLink connectivity, and narrowly scoped Atlas access |
| 5 | IAM module baseline | Separate execution/task roles, scoped ECR/log/secret inputs, optional worker orchestration; add feature-specific policies only after source review |
| 6 | ECR repositories | Four private workload repositories with scan-on-push, immutable tags, and lifecycle retention; build/push images as a separate step |
| 7 | E-commerce deployment | Frontend/API/MongoDB connectivity healthy and isolated |
| 8 | DCC deployment and integration image | DCC can securely register/reach the target |
| 9 | On-demand test workers | Cancellation, timeout, bounded tests and cleanup verified |
| 10 | Full Terraform plan | Zero unintended changes; no eu-north-1 state/resources |
| 11 | Apply | Only after separate explicit deployment approval |

Each stage should be a small reviewable commit. A successful DCC deployment alone is not acceptance. The first milestone is: deploy E-commerce, register it in DCC, establish secure connectivity/integration, and demonstrate resource/target discovery. The next milestone is a bounded API/health smoke test with an evidence-backed result. Load, security, performance, cancellation, and cleanup scenarios follow in later validation stages; they are not prerequisites for the first integration milestone.

## 12. How to explain this architecture

> The lab contains two independent applications. DCC is the control plane that authorizes and orchestrates tests; E-commerce is a separate target application with its own frontend, backend, database, security groups, and IAM identities. A small reusable DCC integration component and temporary test workers provide the bridge for executing bounded tests against the target. This separation means a DCC outage does not automatically take E-commerce offline, and it prevents the monitoring platform from inheriting broad permissions over the application it tests.

## 13. Current implementation status

The reusable Network, Security Groups, and IAM modules are composed into the us-east-1 root. The Security Groups module defines nine workload tiers; the IAM module creates eight isolated ECS roles (four execution roles and four task roles). Mocked IAM tests are included in the Terraform workflow. Confirm the latest workflow result before treating formatting, validation, and tests as passed. The IAM baseline does not yet grant application task permissions for EC2 discovery, S3 inventory, CloudWatch metrics, or ECS worker orchestration. The ECR module is implemented and composed into the root; it creates repository resources only when a later approved apply runs. Image build/push, E-commerce ECS infrastructure, ALBs/listeners, DCC Agent deployment, and temporary test-worker infrastructure remain to be implemented. No `terraform apply` is authorized by this document.
