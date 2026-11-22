"""One-shot entry point for the reusable DCC agent image."""
import json
import logging
import sys
from datetime import datetime, timezone

import boto3
from botocore.config import Config
from botocore.exceptions import BotoCoreError, ClientError

from dcc_agent.callback import post_result
from dcc_agent.config import AgentConfig, AgentConfigurationError
from dcc_agent.discovery import discover_ecs
from dcc_agent.runtime_health import inspect_target_task


logger = logging.getLogger("dcc_agent")


def _aws_client(service: str, region: str):
    return boto3.client(
        service,
        region_name=region,
        config=Config(connect_timeout=3, read_timeout=10, retries={"max_attempts": 2}),
    )


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    try:
        config = AgentConfig.from_env()
    except AgentConfigurationError as error:
        logger.error(json.dumps({"event": "agent_configuration_error", "reason": str(error)}))
        return 2

    try:
        ecs = _aws_client("ecs", config.region)
        if config.mode == "discover_ecs":
            print(json.dumps(discover_ecs(ecs), separators=(",", ":")))
            return 0

        started_at = datetime.now(timezone.utc)
        result = inspect_target_task(
            ecs,
            cluster_arn=config.target_cluster_arn,
            target_task_id=config.target_task_id,
        )
        finished_at = datetime.now(timezone.utc)
        payload = {
            "schema_version": 1,
            "run_id": config.run_id,
            "test_type": "runtime_health",
            "result_status": result["status"],
            "summary": result["reason"],
            "task_last_status": result.get("task_last_status", "UNKNOWN"),
            "task_health_status": result.get("task_health_status", "UNKNOWN"),
            "containers": [{
                "name": item.get("name", "unknown"),
                "last_status": item.get("last_status", "UNKNOWN"),
                "health_status": item.get("health_status", "UNKNOWN"),
                "exit_code": item.get("exit_code"),
                "reason": item.get("reason") or "",
            } for item in result.get("containers", [])],
            "started_at": started_at.isoformat(),
            "finished_at": finished_at.isoformat(),
        }
        post_result(config.callback_url, config.callback_token, payload)
        logger.info(json.dumps({
            "event": "agent_run_finished",
            "run_id": config.run_id,
            "test_type": config.mode,
            "result_status": result["status"],
        }))
        return 0 if result["status"] in {"healthy", "unknown"} else 1
    except (BotoCoreError, ClientError):
        logger.error(json.dumps({
            "event": "agent_execution_failed",
            "reason": "The AWS operation failed.",
        }))
        return 2
    except RuntimeError as error:
        logger.error(json.dumps({
            "event": "agent_execution_failed",
            "reason": str(error),
        }))
        return 2


if __name__ == "__main__":
    sys.exit(main())
