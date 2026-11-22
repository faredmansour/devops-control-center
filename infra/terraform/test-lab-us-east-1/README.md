# DCC Test Lab — us-east-1

**Status:** Network module implementation started. Review and validation are still required; no AWS resources have been deployed by this change.

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

The root composes this module and exposes non-secret network outputs.

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

Security Groups, IAM, ECR, RDS, Redis, Cloud Map, ECS, ALB, HTTPS/ACM, VPC endpoints, remote state bootstrap, and cost validation are future stages. The SG design is documented in `SECURITY_GROUPS_DESIGN.md`, but it is not yet executable Terraform.

## Deployment blockers

- Confirm `10.81.0.0/16` does not overlap any connected networks.
- Approve the AWS account and region for this environment.
- Review NAT Gateway recurring costs and one-AZ egress dependency.
- Provision and approve an independent encrypted/versioned S3 state backend before deployment.
- Review the complete Terraform plan and verify that it cannot affect eu-north-1.
- Obtain explicit deployment approval before any `terraform apply`.
