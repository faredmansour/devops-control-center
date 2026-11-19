# Stateless Runtime Health — AWS Preflight

## Purpose

This is a read-only preflight for the first on-demand runtime_health run. It verifies that the deployed DCC task, dedicated runner task definition, private networking, callback path, and security-group relationship are present.

It does not start an ECS task, enable DCC_STATELESS_RUN_API_ENABLED, change Terraform/IAM/security groups/ECS services/task definitions, run Terraform apply/destroy, or push an image.

## Current deployment context

The latest checked-in AWS apply record identifies these expected values:
- AWS account: 366314473733
- Region: eu-north-1
- ECS cluster: dcc-testlab-cluster
- DCC ECS service: dcc-app-service
- Private Cloud Map callback host: dcc-app.dcc-test.internal:8000

These are repository-recorded expected values, not a live AWS assertion. The script independently checks the active AWS identity and fails closed if the account differs.

## Run the preflight

From the repository root in PowerShell:

\`\`\`powershell
.\\scripts\\preflight-stateless-run.ps1
\`\`\`

Optional explicit parameters:

\`\`\`powershell
.\\scripts\\preflight-stateless-run.ps1 -Region eu-north-1 -ExpectedAccount 366314473733
\`\`\`

Prerequisites:
- AWS CLI installed and authenticated using the approved credential chain.
- Read permissions for STS, ECS describe/list, EC2 network-interface/security-group describe, and CloudWatch Logs describe.
- Access to the intended AWS account and region.

## Checks performed

1. AWS account identity matches the recorded environment.
2. DCC ECS service is active and stable at 1 desired / 1 running / 0 pending.
3. Exactly one DCC task is running and its container reports healthy.
4. DCC task ENI has no public IPv4 address.
5. DCC task definition keeps DCC_STATELESS_RUN_API_ENABLED=false.
6. DCC is configured to use the private Cloud Map callback base URL and no-public-IP runner networking.
7. Dedicated dcc-diagnostic-runner task definition is ACTIVE, Fargate-compatible, awsvpc, non-root, and uses the fixed runtime-health module with 256 CPU / 512 MiB.
8. DCC ingress allows TCP 8000 from the runner security group, and runner egress allows TCP 8000 to the DCC security group.
9. The dedicated runner CloudWatch log group exists.

The script prints only resource identifiers/status needed for diagnosis; it does not print secret values.

## Stop conditions

Stop and do not start a run if any check fails. In particular:
- wrong AWS account or region;
- unstable/unhealthy DCC service;
- public IP on the DCC task;
- missing or inactive runner task definition;
- API feature flag is enabled;
- callback host is not the expected private Cloud Map name;
- missing SG-to-SG callback path;
- missing runner log group.

Do not bypass a failed check by broadening security groups to 0.0.0.0/0, assigning public IPs, attaching AdministratorAccess, or enabling the run API.

## Why this preflight does not start the first test

The public DCC ALB is currently HTTP-only, and authentication/tenant authorization were deliberately deferred. A signed run capability protects status/cancel after a run is created; it does not authenticate the initial create request. Therefore the run API must remain disabled while the application is reachable through the public ALB.

The first live runtime-health test is gated on:
1. an approved authentication mechanism or a private operator-only ingress boundary;
2. a reviewed Terraform plan that leaves unrelated resources unchanged;
3. a successful run of this read-only preflight;
4. explicit operator initiation of the one test against a selected, authorized ECS task.

The existing local Terraform state must remain with the operator's working copy. This preflight intentionally does not initialize or migrate Terraform state and does not invoke the repository-wide redeployment script.

## Expected success

\`\`\`text
PREFLIGHT=PASS
No diagnostic task was started. No AWS resources were changed.
\`\`\`

A PASS means only that the inspected AWS prerequisites are present. It is not a successful diagnostic test and does not enable the API.
