# DCC Agent IAM and network requirements

## Agent task role (read-only)

Attach the following policy to the ECS task role used by the agent task.
Do not attach discovery permissions to the ECS task execution role.

~~~json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ReadEcsInventory",
      "Effect": "Allow",
      "Action": [
        "ecs:ListClusters",
        "ecs:DescribeClusters",
        "ecs:ListServices",
        "ecs:DescribeServices",
        "ecs:DescribeTasks"
      ],
      "Resource": "*"
    }
  ]
}
~~~

This is an initial same-account, single-region policy. ECS list/describe actions
may require wildcard resources. Narrow the scope further where the AWS service
supports resource-level permissions, and use a dedicated task role for the
agent rather than reusing an application role.

The ECS task execution role remains responsible for pulling the image from
ECR and writing container logs. It is not the identity used by Boto3 for
discovery. Never set static AWS access keys in task environment variables.

## Control Plane role (separate identity)

The DCC backend role is separate from the agent role. It needs only permissions
required to launch and manage the configured diagnostic task:
- ecs:DescribeTaskDefinition
- ecs:RunTask constrained to the approved agent task definition and runner cluster
- ecs:DescribeTasks and ecs:StopTask constrained to the runner cluster/task where supported
- iam:PassRole restricted to the exact agent task role and execution role
- EventBridge Scheduler create/delete permissions restricted to the DCC schedule group and stop-task target role

Do not grant the agent permission to launch or stop arbitrary customer workloads.

## Network

The agent needs:
- outbound HTTPS to AWS service endpoints (or configured VPC endpoints)
- outbound connectivity to the private DCC result callback URL for control-plane runs
- DNS resolution for those endpoints

The DCC callback endpoint must not be exposed publicly without the deferred
authentication and authorization layer. Keep it behind a private network /
security-group boundary. Result callback capabilities are short-lived and
single-run scoped, but they are not a replacement for user authentication.

## Scope and portability limitations

The first discovery adapter covers ECS clusters and services in the account and
region selected by the task role/region. It does not yet assume a customer
cross-account role, discover ALB/VPC/ECR/RDS, or map relationships between
services. Those are follow-up adapters and must be added explicitly.
