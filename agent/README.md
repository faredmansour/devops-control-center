# DCC Agent

The DCC Agent is a reusable, one-shot Docker image. It is designed to run as an
ephemeral ECS/Fargate task (or another explicitly started container job), not as
an always-on daemon or monitoring sidecar.

The same image is used with different projects. Project identity, AWS region,
network placement, and IAM permissions are supplied at deployment/job runtime;
they are not baked into the image.

## Build

Run from the repository root:

~~~bash
docker build -f agent/Dockerfile -t dcc-agent:0.1.0 .
~~~

## Supported modes in this initial release

### Runtime health

The control plane starts the image for one explicitly requested runtime-health
run. The task receives the target ECS task, cluster, run ID, and signed result
callback capability as environment overrides.

Required environment:
- DCC_AGENT_MODE=runtime_health
- AWS_REGION
- DIAGNOSTIC_SESSION_ID
- TARGET_TASK_ID
- TARGET_CLUSTER_ARN
- DCC_RESULT_CALLBACK_URL
- DCC_RESULT_CALLBACK_TOKEN

The agent inspects the selected ECS task using its ECS Task Role and returns one
normalized result to the control plane.

### ECS discovery

Run discovery only when explicitly requested:

~~~bash
docker run --rm \
  -e DCC_AGENT_MODE=discover_ecs \
  -e AWS_REGION=us-east-1 \
  dcc-agent:0.1.0
~~~

The container uses the AWS credential provider chain. In ECS, attach a
least-privilege Task Role; do not pass static AWS access keys or bake credentials
into the image. Discovery is bounded to 20 clusters and 50 services per cluster.

The first release discovers ECS clusters and services only. ALB, VPC, RDS, ECR,
CloudWatch and relationship-graph discovery are not yet implemented by this
agent.

## Security and lifecycle

- Runs as a non-root user.
- Contains no Django or frontend runtime.
- Performs read-only AWS discovery/inspection.
- Does not persist inventory, jobs, or results.
- Does not poll continuously, schedule tests, or start tests automatically.
- Uses the AWS SDK credential chain; no static AWS keys in image layers.
- The orchestrator must apply a hard task timeout and stop/cleanup policy.
- Do not expose callback tokens in logs or command output.
