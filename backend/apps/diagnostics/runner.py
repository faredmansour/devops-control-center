"""Short-lived, read-only ECS runtime health diagnostic runner.

The runner does not accept shell commands or arbitrary URLs. It inspects only the
ECS task selected and validated by the DCC control plane.
"""
import json
import logging
import os
import sys
from typing import Any

import boto3
from botocore.exceptions import BotoCoreError, ClientError


logger = logging.getLogger("dcc.diagnostic_runner")


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
        result_status = "failed"
        reason = f"Target ECS task is {task_status}, not RUNNING."
    elif task_health == "UNHEALTHY":
        result_status = "failed"
        reason = "ECS reports the target task as UNHEALTHY."
    elif task_health == "HEALTHY":
        result_status = "healthy"
        reason = "ECS reports the target task as HEALTHY."
    else:
        result_status = "unknown"
        reason = (
            "The target task is RUNNING, but ECS has no aggregate health signal. "
            "Configure container health checks for a definitive health result."
        )

    return {
        "status": result_status,
        "reason": reason,
        "target_task_id": target_task_id,
        "cluster_arn": cluster_arn,
        "task_last_status": task_status,
        "task_health_status": task_health,
        "containers": containers,
    }


def main() -> int:
    logging.basicConfig(
        level=os.environ.get("LOG_LEVEL", "INFO").upper(),
        format="%(message)s",
    )
    run_id = os.environ.get("DIAGNOSTIC_SESSION_ID", "").strip()
    target_task_id = os.environ.get("TARGET_TASK_ID", "").strip()
    target_cluster_arn = os.environ.get("TARGET_CLUSTER_ARN", "").strip()
    region = os.environ.get("AWS_REGION") or os.environ.get("AWS_DEFAULT_REGION")

    if not all((run_id, target_task_id, target_cluster_arn, region)):
        logger.error(json.dumps({
            "event": "diagnostic_run_failed",
            "reason": "Required runner configuration is missing.",
            "run_id": run_id or None,
        }))
        return 2

    try:
        result = inspect_target_task(
            boto3.client("ecs", region_name=region),
            cluster_arn=target_cluster_arn,
            target_task_id=target_task_id,
        )
    except (BotoCoreError, ClientError):
        logger.exception(json.dumps({
            "event": "diagnostic_run_failed",
            "reason": "AWS ECS target inspection failed.",
            "run_id": run_id,
        }))
        return 2

    logger.info(json.dumps({
        "event": "diagnostic_run_result",
        "schema_version": 1,
        "run_id": run_id,
        "test_type": "runtime_health",
        **result,
    }, default=str))

    return 0 if result["status"] in {"healthy", "unknown"} else 1


if __name__ == "__main__":
    sys.exit(main())
