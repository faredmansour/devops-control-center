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

## Migration rule

Move execution engines into the standalone agent package incrementally. Keep
Control Plane orchestration, run authorization, lifecycle management, and UI in
the existing backend/frontend. Do not rewrite the existing application or
remove the legacy diagnostic session path until the new image is wired into
the existing ECS lifecycle and validated end-to-end.
