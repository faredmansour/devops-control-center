# IAM workload identity module

Creates isolated ECS task execution roles and application task roles for DCC Control Plane, E-commerce, DCC Integration Agent, and temporary Test Workers.

## Role separation

Each workload receives two roles:
- **Execution role:** ECS/Fargate uses this to pull that workload's ECR image, write its CloudWatch logs, and retrieve only explicitly configured Secrets Manager secrets.
- **Task role:** credentials exposed to the application container. All four task roles start with no permissions. Add application permissions only after source-code review proves the exact AWS API calls and resource scope.

ECR authorization-token retrieval requires Resource `*`. Image-layer and manifest actions are scoped to configured ECR repository ARNs. Log writes are scoped to configured log group ARNs. Secret reads are scoped to configured secret ARNs. KMS decrypt is added only when both secret ARNs and customer-managed KMS key ARNs are provided, and is constrained through Secrets Manager in the selected region.

## Optional DCC test-worker orchestration

`enable_test_worker_orchestration` defaults to `false`. When explicitly enabled with the exact ECS cluster, worker task-definition ARNs, task ARN pattern, worker task role ARNs, and worker execution role ARNs, the DCC task role receives:
- `ecs:RunTask` and `ecs:DescribeTaskDefinition` on approved worker task definitions, constrained to the dedicated ECS cluster.
- `ecs:DescribeTasks` and `ecs:StopTask` on the supplied task ARN pattern.
- `iam:PassRole` only for the two supplied worker roles and only when passed to `ecs-tasks.amazonaws.com`.

Do not enable this until the DCC backend's actual job runner uses this ECS lifecycle and the worker task definition/roles exist.

## Explicit exclusions

- No AdministratorAccess or broad AWS managed policies.
- No IAM create/update/delete permissions.
- No E-commerce task access to DCC resources.
- No Atlas credentials in IAM. MongoDB Atlas access uses the backend's scoped Secrets Manager secret and Atlas network controls.
- No S3, EC2 discovery, CloudWatch metrics, or other DCC task permissions are granted by default. Add narrowly scoped policies only after confirming implementation and required actions.
- Agent and test-worker task roles are empty by default.
- Tests use the mocked AWS provider and do not deploy resources.

## Inputs

The `ecr_repository_arns`, `log_group_arns`, `secret_arns`, and `kms_key_arns` maps use workload keys `dcc`, `ecommerce`, `agent`, and `test_worker`.

Never commit secret values, Atlas connection strings, API keys, or credentials. Pass only secret ARNs to this module. Store actual values in Secrets Manager.