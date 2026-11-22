# DCC Test Lab — us-east-1

**Status:** Network, Security Groups, IAM, ECR, and Secrets Manager Terraform modules are composed in this independent root. Review and CI validation are required; no AWS resources have been deployed.

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
│   └── network/
│       ├── main.tf
│       ├── variables.tf
│       ├── outputs.tf
│       ├── versions.tf
│       └── README.md
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

The root composes Network, Security Groups, IAM, and ECR modules and exposes non-secret network, workload role, and repository outputs. ECR defines four private repositories (DCC, E-commerce, Agent, Test Worker), enables scan-on-push and immutable tags, encrypts images with AES-256, and retains the ten most recent images. Each IAM execution role receives pull access only to its corresponding repository ARN. Secrets Manager creates metadata for the E-commerce MongoDB Atlas URI; the actual URI is deliberately not managed by Terraform. The E-commerce execution role receives read access only to that secret ARN.

## How to read the code

1. Start at this root's `main.tf`: it shows which modules make up the environment.
2. Open `modules/network/variables.tf`: these are the inputs the module needs.
3. Open `modules/network/main.tf`: this is where AWS network resources are created.
4. Open `modules/network/outputs.tf`: these are the values other modules can consume.
5. Read `modules/network/README.md` for the network flow, cost, and security explanation.

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

## Not implemented yet

ECS, ALB, HTTPS/ACM, VPC endpoints, remote state bootstrap, image build/push automation, and cost validation are future stages. E-commerce uses MongoDB Atlas as an external managed database; Atlas cluster/network/user setup and the secure population of its Secrets Manager connection secret are external follow-up steps; Terraform creates the secret container only. The SG design is documented in `SECURITY_GROUPS_DESIGN.md`, but it is not yet executable Terraform.

## Deployment blockers

- Confirm `10.81.0.0/16` does not overlap any connected networks.
- Approve the AWS account and region for this environment.
- Review NAT Gateway recurring costs and one-AZ egress dependency.
- Provision and approve an independent encrypted/versioned S3 state backend before deployment.
- Review the complete Terraform plan and verify that it cannot affect eu-north-1.
- Obtain explicit deployment approval before any `terraform apply`.
