# DCC Test Lab — us-east-1

**Status:** Network, Security Groups, IAM, ECR, Secrets Manager, ECS Fargate, and one shared HTTP ALB are composed in this independent root. Review and CI validation are required; no AWS resources have been deployed.

## Purpose and isolation

This is an independent Terraform root for a second DCC Test Lab in `us-east-1`. The existing `eu-north-1` environment and its Terraform state must remain untouched.

- Separate root directory and future remote-state key.
- Unique resource prefix: `dcc-testlab-use1`.
- Proposed VPC CIDR: `10.81.0.0/16`; connected-network overlap review is still required.
- No reuse of region-scoped IDs, endpoints, subnet IDs, SG IDs, or ECR image references from eu-north-1.
- No state migration, import, destroy, or apply against the existing regional environment.

## Current directory structure

```text
infra/terraform/
├── modules/
│   ├── network/
│   ├── security-groups/
│   ├── iam/
│   ├── ecr/
│   ├── secrets-manager/
│   └── ecs/
└── test-lab-us-east-1/
    ├── main.tf
    ├── variables.tf
    ├── locals.tf
    ├── providers.tf
    ├── versions.tf
    ├── outputs.tf
    ├── terraform.tfvars.example
    ├── SECURITY_GROUPS_DESIGN.md
    └── TERRAFORM_ARCHITECTURE.md
```

## Implemented in this stage

The reusable Network module currently defines:

- One VPC with DNS support and hostnames.
- Two public subnets.
- Two private application subnets.
- Two private data subnets.
- Internet Gateway and public route table.
- One optional NAT Gateway and private-application default route.
- A separate private-data route table with no internet default route.
- Subnet CIDR containment and overlap preconditions.
- Two-AZ selection and availability checks.

The root composes Network, Security Groups, IAM, ECR, Secrets Manager, and ECS modules. One public ALB serves E-commerce on port 80 (frontend by default, API/health/uploads to backend) and DCC on port 8080. Three independent Fargate services are defined for DCC, E-commerce frontend, and E-commerce backend in private application subnets. They default to desired count `0`; set `enable_application_services = true` only after all three images are pushed and both E-commerce secrets have values. CloudWatch log groups retain seven days. The ALB is closed by default until `alb_ingress_cidrs` is configured. DCC runs with `DJANGO_DEBUG=true` only for this restricted HTTP test phase; do not reuse this setting for production. The root exposes non-secret network, workload role, repository, cluster, service, ALB, and secret-ARN outputs. ECR defines four private repositories (DCC, E-commerce, Agent, Test Worker), enables scan-on-push and immutable tags, encrypts images with AES-256, and retains the ten most recent images. Each IAM execution role receives pull access only to its corresponding repository ARN. Secrets Manager creates metadata for the E-commerce MongoDB Atlas URI; the actual URI is deliberately not managed by Terraform. The E-commerce execution role receives read access only to that secret ARN.

## How to read the code

1. Start at this root's `main.tf` to see the complete environment composition.
2. Read `modules/network` for VPC and subnet layout.
3. Read `modules/security-groups` for the ALB and workload traffic boundaries.
4. Read `modules/iam` and `modules/secrets-manager` for runtime permissions and secret references.
5. Read `modules/ecr` for image repositories and `modules/ecs` for the ALB, task definitions, and services.

## Validation workflow

Run from this directory using an approved AWS credential profile. These commands do not create infrastructure:

```powershell
Copy-Item terraform.tfvars.example terraform.tfvars
terraform init -backend=false
terraform fmt -check -recursive
terraform validate
terraform plan -refresh=false -input=false
```

The plan with `-refresh=false` checks the proposed configuration without querying current AWS resource state; provider data sources may still require AWS read access. A later normal plan will require AWS read permissions and a completed CIDR overlap review. Neither plan authorizes apply.

## Image build and push

Two manual GitHub Actions workflows build immutable image tags and push to the regional ECR repositories:

- DCC: `.github/workflows/testlab-ecr.yml` in this repository.
- E-commerce: the same workflow path in `faredmansour/ecommerce-project`.

Before running either workflow:

1. Create a GitHub OIDC identity provider in AWS IAM if one does not already exist: issuer `https://token.actions.githubusercontent.com`, audience `sts.amazonaws.com`.
2. Create one IAM role per repository. Its trust policy must restrict `token.actions.githubusercontent.com:sub` to the exact repository and branch:
   - `repo:faredmansour/devops-control-center:ref:refs/heads/feat/test-lab-us-east-1-isolated`
   - `repo:faredmansour/ecommerce-project:ref:refs/heads/feat/aws-testlab-deployment`
   And `token.actions.githubusercontent.com:aud` must equal `sts.amazonaws.com`.
3. Give each role `ecr:GetAuthorizationToken` on `*`, and image upload actions (`ecr:BatchCheckLayerAvailability`, `ecr:InitiateLayerUpload`, `ecr:UploadLayerPart`, `ecr:CompleteLayerUpload`, `ecr:PutImage`) only on its repository ARN. DCC uses `dcc-testlab-use1-dcc`; E-commerce uses `dcc-testlab-use1-ecommerce`.
4. Add the matching role ARN as the repository Actions variable `AWS_ROLE_ARN` in each GitHub repository.
5. Run the workflow manually from Actions. It publishes tags based on the commit SHA; it does not deploy or start ECS services.

After successful image publication, update `dcc_image_tag`, `ecommerce_frontend_image_tag`, and `ecommerce_backend_image_tag` in a local, uncommitted `terraform.tfvars` with the exact tags shown in each workflow summary.

E-commerce uses MongoDB Atlas. Terraform creates only the Secrets Manager metadata; populate the two secret values (Atlas URI and JWT signing secret) securely in AWS Secrets Manager before enabling ECS services.

## Deployment blockers

- Confirm `10.81.0.0/16` does not overlap any connected networks.
- Approve the AWS account and region for this environment.
- Review NAT Gateway recurring costs and one-AZ egress dependency.
- Provision and approve an independent encrypted/versioned S3 state backend before deployment.
- Review the complete Terraform plan and verify that it cannot affect eu-north-1.
- Build and push all three images; enter both secret values securely.
- Set `enable_application_services = true` only after images and secrets are ready.
- Set `alb_ingress_cidrs` to the operator's public IPv4 `/32` before allowing HTTP test access.
- Obtain explicit deployment approval before any `terraform apply`.
