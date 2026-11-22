"""AWS-backed lifecycle operations for short-lived diagnostic ECS tasks.

ECS is the source of truth for task state. EventBridge Scheduler provides an
independent stop deadline so a Django process restart cannot leave a task running
indefinitely. This module is additive; legacy session APIs remain unchanged until
the stateless run API is wired in a later step.
"""
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
import json
import logging
import re
from typing import Any
from uuid import UUID

import boto3
from botocore.exceptions import BotoCoreError, ClientError
from django.conf import settings
from django.core.exceptions import ImproperlyConfigured

from apps.diagnostics.ecs_provider import ECSExecutionConfig
from apps.diagnostics.models import ExecutionReference
from apps.diagnostics.providers import DiagnosticProviderError
from apps.diagnostics.ecs_provider import ECSDiagnosticExecutionProvider


logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class ECSJobSnapshot:
    run_id: str
    task_arn: str
    cluster: str
    last_status: str
    desired_status: str
    stopped_reason: str | None
    started_at: datetime | None
    stopped_at: datetime | None


class ECSStatelessJobLifecycle:
    """Launch, inspect, cancel, and independently expire one ECS diagnostic task."""

    def __init__(
        self,
        *,
        ecs_provider: ECSDiagnosticExecutionProvider | None = None,
        ecs_client: Any | None = None,
        scheduler_client: Any | None = None,
        cleanup_role_arn: str | None = None,
        schedule_group: str | None = None,
        max_duration_seconds: int | None = None,
        clock: Any | None = None,
    ) -> None:
        self._provider = ecs_provider or ECSDiagnosticExecutionProvider.from_settings()
        config = ECSExecutionConfig.from_settings()
        self._ecs = ecs_client
        self._scheduler = scheduler_client
        self._region = config.region
        self._cluster = config.cluster
        self._cleanup_role_arn = (
            cleanup_role_arn
            if cleanup_role_arn is not None
            else settings.DCC_ECS_CLEANUP_ROLE_ARN
        )
        self._schedule_group = (
            schedule_group
            if schedule_group is not None
            else settings.DCC_ECS_CLEANUP_SCHEDULE_GROUP
        )
        self._max_duration = (
            max_duration_seconds
            if max_duration_seconds is not None
            else settings.DCC_DIAGNOSTIC_MAX_DURATION_SECONDS
        )
        self._clock = clock or (lambda: datetime.now(timezone.utc))

        if not self._cleanup_role_arn:
            raise ImproperlyConfigured(
                "DCC_ECS_CLEANUP_ROLE_ARN is required for ECS diagnostic execution."
            )
        if not re.fullmatch(r"[A-Za-z0-9_-]{1,64}", self._schedule_group):
            raise ImproperlyConfigured("DCC_ECS_CLEANUP_SCHEDULE_GROUP is invalid.")
        if not 1 <= self._max_duration <= 900:
            raise ImproperlyConfigured(
                "DCC_DIAGNOSTIC_MAX_DURATION_SECONDS must be between 1 and 900."
            )

    def _ecs_client(self) -> Any:
        if self._ecs is None:
            self._ecs = boto3.client("ecs", region_name=self._region)
        return self._ecs

    def _scheduler_client(self) -> Any:
        if self._scheduler is None:
            self._scheduler = boto3.client("scheduler", region_name=self._region)
        return self._scheduler

    @staticmethod
    def _validate_run_id(run_id: str) -> str:
        try:
            return str(UUID(run_id))
        except (TypeError, ValueError, AttributeError):
            raise DiagnosticProviderError("The diagnostic run ID is invalid.") from None

    @staticmethod
    def _schedule_name(run_id: str) -> str:
        return "dcc-stop-" + run_id.replace("-", "")

    def start(
        self,
        run_id: str,
        target_task_id: str | None,
        target_cluster_arn: str | None = None,
        max_duration_seconds: int | None = None,
        runner_environment: dict[str, str] | None = None,
    ) -> ExecutionReference:
        """Launch a task and register an independent, one-time stop deadline."""
        run_id = self._validate_run_id(run_id)
        duration = max_duration_seconds or self._max_duration
        if not 1 <= duration <= self._max_duration:
            raise DiagnosticProviderError(
                "The requested run duration exceeds the configured maximum."
            )
        if runner_environment:
            execution = self._provider.start(
                run_id, target_task_id, target_cluster_arn,
                extra_environment=runner_environment,
            )
        else:
            execution = self._provider.start(run_id, target_task_id, target_cluster_arn)
        try:
            self._schedule_cleanup(run_id, execution, duration)
        except Exception:
            # Never leave a task running when its independent cleanup timer failed.
            try:
                self._provider.stop(execution)
            except Exception as stop_error:
                logger.error(
                    "ECS task cleanup failed after scheduler registration failure "
                    "(run_id=%s error_type=%s).",
                    run_id,
                    type(stop_error).__name__,
                )
            raise
        return execution

    def _schedule_cleanup(
        self,
        run_id: str,
        execution: ExecutionReference,
        duration_seconds: int,
    ) -> None:
        if execution.provider != "ecs" or not execution.cluster:
            raise DiagnosticProviderError("The ECS execution reference is invalid.")

        deadline = self._clock() + timedelta(seconds=duration_seconds)
        schedule_expression = deadline.astimezone(timezone.utc).strftime(
            "at(%Y-%m-%dT%H:%M:%S)"
        )
        try:
            self._scheduler_client().create_schedule(
                Name=self._schedule_name(run_id),
                GroupName=self._schedule_group,
                ScheduleExpression=schedule_expression,
                ScheduleExpressionTimezone="UTC",
                FlexibleTimeWindow={"Mode": "OFF"},
                ActionAfterCompletion="DELETE",
                Target={
                    "Arn": (
                        "arn:aws:scheduler:::aws-sdk:ecs:stopTask"
                    ),
                    "RoleArn": self._cleanup_role_arn,
                    "Input": json.dumps({
                        "cluster": execution.cluster,
                        "task": execution.reference,
                        "reason": "DCC diagnostic maximum duration reached",
                    }),
                },
            )
        except (BotoCoreError, ClientError):
            logger.warning(
                "ECS automatic cleanup schedule could not be created (run_id=%s).",
                run_id,
            )
            raise DiagnosticProviderError(
                "Automatic diagnostic task cleanup could not be configured."
            ) from None

    def status(self, run_id: str, execution: ExecutionReference) -> ECSJobSnapshot:
        run_id = self._validate_run_id(run_id)
        if execution.provider != "ecs" or not execution.cluster:
            raise DiagnosticProviderError("The ECS execution reference is invalid.")
        try:
            response = self._ecs_client().describe_tasks(
                cluster=execution.cluster,
                tasks=[execution.reference],
            )
        except (BotoCoreError, ClientError):
            logger.warning("ECS task status lookup failed (run_id=%s).", run_id)
            raise DiagnosticProviderError(
                "The diagnostic task status could not be retrieved."
            ) from None

        tasks = response.get("tasks", [])
        if response.get("failures") or not tasks:
            raise DiagnosticProviderError("The diagnostic task was not found in ECS.")
        task = tasks[0]
        return ECSJobSnapshot(
            run_id=run_id,
            task_arn=task.get("taskArn", execution.reference),
            cluster=execution.cluster,
            last_status=task.get("lastStatus", "UNKNOWN"),
            desired_status=task.get("desiredStatus", "UNKNOWN"),
            stopped_reason=task.get("stoppedReason"),
            started_at=task.get("startedAt"),
            stopped_at=task.get("stoppedAt"),
        )

    def cancel(self, run_id: str, execution: ExecutionReference) -> None:
        """Cancel the ECS task and remove its pending one-time deadline."""
        run_id = self._validate_run_id(run_id)
        if execution.provider != "ecs" or not execution.cluster:
            raise DiagnosticProviderError("The ECS execution reference is invalid.")

        # Stop first: deleting the timer first could remove the only cleanup path
        # if the ECS stop request fails.
        self._provider.stop(execution)
        try:
            self._scheduler_client().delete_schedule(
                Name=self._schedule_name(run_id),
                GroupName=self._schedule_group,
            )
        except ClientError as error:
            code = error.response.get("Error", {}).get("Code")
            if code != "ResourceNotFoundException":
                logger.warning(
                    "ECS cleanup schedule deletion failed (run_id=%s code=%s).",
                    run_id,
                    code or "unknown",
                )
                raise DiagnosticProviderError(
                    "The diagnostic task was stopped but its cleanup schedule "
                    "could not be removed."
                ) from None
        except BotoCoreError:
            raise DiagnosticProviderError(
                "The diagnostic task was stopped but its cleanup schedule "
                "could not be removed."
            ) from None
