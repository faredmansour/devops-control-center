"""Bounded, read-only ECS runtime health inspection."""
from typing import Any


def inspect_target_task(
    ecs_client: Any,
    *,
    cluster_arn: str,
    target_task_id: str,
) -> dict[str, Any]:
    response = ecs_client.describe_tasks(
        cluster=cluster_arn,
        tasks=[target_task_id],
    )
    if response.get("failures") or len(response.get("tasks", [])) != 1:
        return {
            "status": "failed",
            "reason": "The selected ECS task could not be described.",
            "target_task_id": target_task_id,
            "cluster_arn": cluster_arn,
            "containers": [],
        }

    task = response["tasks"][0]
    containers = [
        {
            "name": container.get("name", "unknown"),
            "last_status": container.get("lastStatus", "UNKNOWN"),
            "health_status": container.get("healthStatus", "UNKNOWN"),
            "exit_code": container.get("exitCode"),
            "reason": container.get("reason"),
        }
        for container in task.get("containers", [])
    ]
    task_status = task.get("lastStatus", "UNKNOWN")
    task_health = task.get("healthStatus", "UNKNOWN")

    if task_status != "RUNNING":
        status = "failed"
        reason = f"Target ECS task is {task_status}, not RUNNING."
    elif task_health == "UNHEALTHY":
        status = "failed"
        reason = "ECS reports the target task as UNHEALTHY."
    elif task_health == "HEALTHY":
        status = "healthy"
        reason = "ECS reports the target task as HEALTHY."
    else:
        status = "unknown"
        reason = (
            "The target task is RUNNING, but ECS has no aggregate health signal. "
            "Configure container health checks for a definitive health result."
        )

    return {
        "status": status,
        "reason": reason,
        "target_task_id": target_task_id,
        "cluster_arn": cluster_arn,
        "task_last_status": task_status,
        "task_health_status": task_health,
        "containers": containers,
    }
