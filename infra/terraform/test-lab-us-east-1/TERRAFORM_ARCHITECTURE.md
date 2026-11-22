# Terraform Architecture and Learning Guide — us-east-1 Test Lab

**Status:** Architecture baseline for implementation. This document describes the intended organization; it does not claim that the modules have already been implemented.

## 1. Design goals

1. **Easy to navigate:** one clear responsibility per module and file.
2. **Easy to explain:** every module has a purpose, inputs, outputs, and explicit dependencies.
3. **Safe isolation:** a separate Terraform root, backend key, naming prefix, and state from the existing `eu-north-1` Test Lab.
4. **Reusable:** modules accept inputs rather than hard-coding region-specific resource IDs.
5. **Reviewable:** changes are validated in small stages, with plans reviewed before any apply.
6. **Least privilege:** SG rules use SG references for internal traffic; IAM policies scope resources and actions.
7. **No hidden coupling:** module outputs are passed explicitly; modules do not reach into each other's internal resources.

## 2. Target directory layout

The new regional root should evolve toward this structure:

```text
infra/terraform/
├── modules/
│   ├── network/
│   │   ├── main.tf          # VPC, subnets, IGW, NAT and route tables
│   │   ├── variables.tf     # CIDRs, AZs, naming, NAT switch
│   │   ├── outputs.tf      # VPC and subnet IDs
│   │   └── README.md       # purpose, traffic flow, examples
│   ├── security-groups/
│   │   ├── main.tf          # SG resources and explicit rule resources
│   │   ├── variables.tf     # VPC ID, ports, approved ingress CIDRs
│   │   ├── outputs.tf      # SG IDs
│   │   └── README.md
│   └── iam/
│       ├── main.tf          # ECS trust roles and scoped policies
│       ├── variables.tf     # naming, ARNs, cluster scope, policy inputs
│       ├── outputs.tf      # role ARNs
│       └── README.md
└── test-lab-us-east-1/
    ├── versions.tf          # Terraform/provider constraints
    ├── providers.tf         # AWS provider and regional data sources
    ├── backend-template/    # inactive, credential-free backend template
    ├── main.tf              # module composition only
    ├── variables.tf         # environment-level inputs
    ├── locals.tf            # common names and tags
    ├── outputs.tf           # selected environment outputs
    ├── terraform.tfvars.example
    ├── README.md
    └── SECURITY_GROUPS_DESIGN.md
```

As implementation grows, add separate modules for `ecr`, `data-services`, `service-discovery`, `ecs`, `load-balancer`, and `diagnostic-runner`. Do not create empty module directories just to make the tree look complete; add each module when its resources and tests are ready.

## 3. Responsibility boundaries

| Module | Owns | Must not own |
|---|---|---|
| network | VPC, subnets, IGW, NAT, route tables | SG policy, ECS, databases |
| security-groups | SGs and ingress/egress rules | VPC/subnets, application resources |
| iam | trust policies, task/execution roles, scoped policies | ECS service lifecycle, network |
| ecr (later) | repositories, lifecycle and immutability | image build/push credentials |
| data-services (later) | RDS/ElastiCache and subnet groups | application schema/migrations |
| ecs (later) | cluster, task definitions, services | VPC creation, IAM policy authoring |
| load-balancer (later) | ALB, listeners, target groups, ACM attachment | application authentication |
| root | composition, environment values, outputs | detailed resource implementation |

## 4. Dependency flow

```text
Environment inputs (region, CIDRs, prefix, tags)
                  |
                  v
              Network
                  |
             VPC + subnets
                  |
        +---------+----------+
        |                    |
        v                    v
  Security Groups           IAM
        |                    |
        +---------+----------+
                  |
          Later service modules
      (ECR, data, ECS, ALB, runner)
```

The root module wires outputs to inputs. For example, the network module exports `vpc_id` and subnet IDs; the security-groups module consumes `vpc_id`; ECS later consumes private subnet IDs, SG IDs, and IAM role ARNs.

## 5. File conventions

- `main.tf`: resources and data sources for that responsibility only.
- `variables.tf`: typed inputs, descriptions, validations, safe defaults only.
- `outputs.tf`: values needed by other modules or operators; never output secrets.
- `locals.tf`: derived names/tags/expressions; avoid hiding important business decisions.
- `versions.tf`: Terraform and provider constraints at the root; child modules should not independently pin provider versions unless required.
- `README.md`: purpose, architecture, inputs, outputs, example, security notes, and cost implications.

Naming:
- Terraform labels: descriptive snake_case (e.g. `private_application`).
- AWS Name tags: `<name_prefix>-<purpose>`.
- Resource prefixes for this region: `dcc-testlab-use1`.
- Avoid unexplained abbreviations and avoid embedding region-specific values inside reusable modules.

## 6. Security-group policy rules

- No public ingress on application, worker, database, cache, or diagnostic task SGs.
- ALB HTTPS ingress must be restricted to approved operator/VPN CIDRs until application authentication is implemented.
- HTTP/80, if retained, is redirect-only to HTTPS.
- Internal access uses source SG references, not broad VPC CIDRs.
- PostgreSQL 5432 and Redis 6379 are allowed only from their intended workload SGs.
- Every outbound rule needs a written reason. Prefer VPC endpoints for AWS services where practical; security groups cannot enforce DNS/FQDN destination allowlists.
- Do not mix inline SG ingress/egress blocks with standalone `aws_vpc_security_group_*_rule` resources for the same SG.
- Verify the effective planned rules; an omitted egress block does not by itself prove deny-all egress.

## 7. State and regional isolation

- The new root uses a unique backend key, for example `dcc/test-lab/us-east-1/terraform.tfstate`.
- The backend bucket must be approved and provisioned separately with versioning, encryption, public-access blocking, TLS enforcement, and least-privilege access.
- Never run `terraform init -migrate-state`, `terraform state mv`, or `terraform destroy` against the old regional root as part of this parallel-environment setup.
- Do not reuse resource IDs, endpoints, subnet IDs, SG IDs, Cloud Map IDs, or region-scoped ECR repository URLs from `eu-north-1`.
- Push immutable images to the new region and reference their digests.

## 8. Implementation and review sequence

| Stage | Deliverable | Validation gate |
|---|---|---|
| 0 | Directory/design baseline | Review module boundaries and naming |
| 1 | Network module | fmt, validate, CIDR positive/negative checks |
| 2 | Security Groups module | fmt, validate, mocked policy tests, ingress/egress matrix review |
| 3 | IAM module | trust-policy and least-privilege review |
| 4 | Root composition | init/validate and dependency review |
| 5 | ECR and image replication | immutable digest exists in us-east-1 |
| 6 | Data services and ECS | private networking, secret handling, task health |
| 7 | ALB + HTTPS | approved CIDRs, ACM certificate, redirect behavior |
| 8 | Full plan | zero unintended changes; no eu-north-1 state/resources |
| 9 | Apply | only after separate explicit deployment approval |

Each stage should be a small reviewable commit or PR update. Keep an operator-facing runbook separate from the learning guide.

## 9. How to explain this architecture

A concise explanation for a technical review:

> Terraform is split into reusable modules by responsibility. The regional root composes those modules using explicit inputs and outputs. Network creates the isolated VPC and subnets; Security Groups defines which components may communicate; IAM defines which AWS actions each workload may perform. This separation makes each layer independently reviewable and reusable. The new us-east-1 environment has a separate Terraform state and naming boundary, so it cannot accidentally manage the existing eu-north-1 lab.

## 10. Current implementation status

Current implementation status: the reusable Network module and the us-east-1 root composition are present. CI formatting, initialization, and validation checks have passed. Network lifecycle preconditions now enforce the two-AZ requirement, configured-AZ availability, subnet containment, and non-overlap as blocking plan/apply conditions. Automated Terraform tests for valid CIDRs, out-of-range subnet CIDRs, overlapping subnet CIDRs, and unavailable AZs are passing in CI. The reusable Security Groups module is implemented and composed into the us-east-1 root. It creates seven tiers (ALB, DCC Control, Diagnostic Worker, Test API, Test Worker, Database, Cache), with no public ingress by default and optional public egress disabled by default. Its three mocked Terraform policy tests are passing in CI. IAM remains design/planning only. CI checks do not create AWS resources. The next coding stage is IAM design and implementation.
