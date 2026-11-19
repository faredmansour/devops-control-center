"""Short-lived, read-only ECS runtime health diagnostic runner.

The runner does not accept shell commands or arbitrary URLs. It inspects only the
ECS task selected and validated by the DCC control plane.
"""
import json
import logging
import os
import sys
import urllib.error
import urllib.request
from datetime import datetime, timezone
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
    callback_url = os.environ.get("DCC_RESULT_CALLBACK_URL", "").strip()
    callback_token = os.environ.get("DCC_RESULT_CALLBACK_TOKEN", "").strip()
    started_at = datetime.now(timezone.utc)

    if not all((run_id, target_task_id, target_cluster_arn, region, callback_url, callback_token)):
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
        # Report an explicit failed result rather than leaving the run pending
        # until the ECS cleanup timer fires.
        logger.error(json.dumps({
            "event": "diagnostic_run_failed",
            "reason": "AWS ECS target inspection failed.",
            "run_id": run_id,
        }))
        result = {
            "status": "failed",
            "reason": "AWS ECS target inspection failed.",
            "task_last_status": "UNKNOWN",
            "task_health_status": "UNKNOWN",
            "containers": [],
        }

    finished_at = datetime.now(timezone.utc)
    callback_payload = {
        "schema_version": 1, "run_id": run_id, "test_type": "runtime_health",
        "result_status": result["status"], "summary": result["reason"],
        "task_last_status": result.get("task_last_status", "UNKNOWN"),
        "task_health_status": result.get("task_health_status", "UNKNOWN"),
        "containers": [{
            "name": item.get("name", "unknown"),
            "last_status": item.get("last_status", "UNKNOWN"),
            "health_status": item.get("health_status", "UNKNOWN"),
            "exit_code": item.get("exit_code"),
            "reason": item.get("reason") or "",
        } for item in result.get("containers", [])],
        "started_at": started_at.isoformat(), "finished_at": finished_at.isoformat(),
    }
    callback_request = urllib.request.Request(
        callback_url, data=json.dumps(callback_payload).encode("utf-8"),
        headers={"Content-Type": "application/json", "X-DCC-Result-Token": callback_token},
        method="POST",
    )
    try:
        with urllib.request.urlopen(callback_request, timeout=10) as response:
            if response.status not in {200, 202}:
                raise RuntimeError("Unexpected callback response.")
    except (urllib.error.URLError, TimeoutError, RuntimeError, ValueError):
        logger.error(json.dumps({"event": "diagnostic_result_callback_failed", "run_id": run_id}))
        return 2

    logger.info(json.dumps({
        "event": "diagnostic_run_finished", "run_id": run_id,
        "test_type": "runtime_health", "result_status": result["status"],
    }))

    return 0 if result["status"] in {"healthy", "unknown"} else 1


if __name__ == "__main__":
    sys.exit(main())
