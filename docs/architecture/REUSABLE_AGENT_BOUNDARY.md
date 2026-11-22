# Reusable DCC Agent Boundary

**Status:** Initial implementation boundary  
**Decision:** Separate reusable agent image from the DCC Control Plane.

## Responsibilities

### DCC Control Plane
- Owns the dashboard and API.
- Validates a user's explicit request and its scope.
- Starts a configured, short-lived agent task.
- Supplies a versioned job contract and a short-lived result callback capability.
- Exposes the run state/result to the initiating user.
- Does not contain project-specific customer credentials.

### DCC Agent Image
- Is a standalone, reusable Docker image.
- Runs one bounded job and exits.
- Uses the runtime's AWS identity (ECS Task Role) rather than static access keys.
- Performs only the requested discovery or diagnostic.
- Returns a normalized result and does not persist project inventory or result history.

## Lifecycle

The image is not intended to run as a permanent sidecar or daemon. The Control
Plane launches an ephemeral ECS/Fargate task only after an explicit user action.
A separate hard timeout and cleanup mechanism must stop the task if the process
or callback fails.

## Portability

The same image digest can be used by multiple projects and environments. Only
runtime configuration changes: project/environment identifiers, AWS region,
network placement, task role, and the requested operation. Customer-specific
configuration and credentials must never be embedded in the image.

## Initial implementation scope

The first image release contains:
- runtime_health: inspect one explicitly selected ECS task and send its result
  to the existing Control Plane callback.
- discover_ecs: on-demand, read-only discovery of ECS clusters and services.

The first release does not yet discover ALB, VPC, RDS, ECR, IAM, CloudWatch, or
build a complete cross-service relationship graph. It does not implement SAST,
DAST, load generation, or database performance testing.

## Current integration status

The current feature branch wires the stateless run API to the reusable image
through the existing ECS lifecycle. The Terraform Test Lab now defines a
dedicated ECR repository and one-shot task definition for the Agent image,
separate from the long-running DCC application image.

The Control Plane supports explicit ECS discovery requests and runtime-health
requests. ECS discovery is limited to the cluster allowlist configured in
DCC_ECS_CLUSTERS; the Agent does not enumerate every cluster in the AWS account.
The callback payload is signed, validated, size-bounded, and retained only in
the existing volatile result store.

The integration is not yet considered production-ready until CI passes, the
agent image is built and pushed, the Terraform plan is reviewed, the private
network boundary is verified, and a real AWS end-to-end run succeeds.

Keep Control Plane orchestration, signed run capabilities, cancellation,
cleanup, and UI in the existing backend/frontend. Continue moving execution
engines into the Agent incrementally without rewriting the application or
removing the legacy diagnostic session path prematurely.
