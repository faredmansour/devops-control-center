from datetime import datetime, timezone
from unittest.mock import Mock

from botocore.exceptions import ClientError
from django.test import SimpleTestCase, override_settings

from apps.diagnostics.ecs_lifecycle import ECSStatelessJobLifecycle
from apps.diagnostics.models import ExecutionReference
from apps.diagnostics.providers import DiagnosticProviderError


@override_settings(
    AWS_REGION="us-east-1",
    DCC_ECS_CLUSTER="dcc-cluster",
    DCC_ECS_TASK_DEFINITION="dcc-diagnostic:1",
    DCC_ECS_SUBNETS=["subnet-123"],
    DCC_ECS_SECURITY_GROUPS=["sg-123"],
    DCC_ECS_CONTAINER_NAME="diagnostic-worker",
    DCC_ECS_ASSIGN_PUBLIC_IP=False,
    DCC_ECS_CLEANUP_ROLE_ARN="arn:aws:iam::123456789012:role/dcc-scheduler-stop",
    DCC_ECS_CLEANUP_SCHEDULE_GROUP="dcc-cleanup",
)
class ECSStatelessJobLifecycleTests(SimpleTestCase):
    def setUp(self):
        self.execution = ExecutionReference(
            provider="ecs",
            reference="arn:aws:ecs:us-east-1:123456789012:task/dcc/abc",
            cluster="arn:aws:ecs:us-east-1:123456789012:cluster/dcc",
        )
        self.provider = Mock()
        self.provider.start.return_value = self.execution
        self.provider.stop.return_value = None
        self.ecs = Mock()
        self.scheduler = Mock()
        self.now = datetime(2026, 11, 19, 1, 0, 0, tzinfo=timezone.utc)

        self.lifecycle = ECSStatelessJobLifecycle(
            ecs_provider=self.provider,
            ecs_client=self.ecs,
            scheduler_client=self.scheduler,
            cleanup_role_arn="arn:aws:iam::123456789012:role/dcc-scheduler-stop",
            schedule_group="dcc-cleanup",
            max_duration_seconds=300,
            clock=lambda: self.now,
        )

    def test_start_registers_independent_one_time_stop_schedule(self):
        run_id = "123e4567-e89b-42d3-a456-426614174000"

        result = self.lifecycle.start(run_id, "task-123", "cluster-arn")

        self.assertEqual(result, self.execution)
        self.provider.start.assert_called_once_with(run_id, "task-123", "cluster-arn")
        kwargs = self.scheduler.create_schedule.call_args.kwargs
        self.assertEqual(kwargs["Name"], "dcc-stop-123e4567e89b42d3a456426614174000")
        self.assertEqual(kwargs["ScheduleExpression"], "at(2026-11-19T01:05:00)")
        self.assertEqual(kwargs["ScheduleExpressionTimezone"], "UTC")
        self.assertEqual(kwargs["ActionAfterCompletion"], "DELETE")
        self.assertEqual(kwargs["Target"]["RoleArn"], "arn:aws:iam::123456789012:role/dcc-scheduler-stop")
        self.assertIn(self.execution.reference, kwargs["Target"]["Input"])

    def test_start_stops_task_if_schedule_registration_fails(self):
        self.scheduler.create_schedule.side_effect = ClientError(
            {"Error": {"Code": "AccessDeniedException", "Message": "denied"}},
            "CreateSchedule",
        )

        with self.assertRaises(DiagnosticProviderError):
            self.lifecycle.start(
                "123e4567-e89b-42d3-a456-426614174000",
                "task-123",
            )

        self.provider.stop.assert_called_once_with(self.execution)

    def test_status_uses_ecs_as_source_of_truth(self):
        self.ecs.describe_tasks.return_value = {
            "tasks": [{
                "taskArn": self.execution.reference,
                "lastStatus": "RUNNING",
                "desiredStatus": "RUNNING",
                "startedAt": self.now,
            }],
            "failures": [],
        }

        snapshot = self.lifecycle.status(
            "123e4567-e89b-42d3-a456-426614174000",
            self.execution,
        )

        self.assertEqual(snapshot.last_status, "RUNNING")
        self.assertEqual(snapshot.desired_status, "RUNNING")
        self.assertEqual(snapshot.started_at, self.now)
        self.ecs.describe_tasks.assert_called_once_with(
            cluster=self.execution.cluster,
            tasks=[self.execution.reference],
        )

    def test_status_rejects_missing_task(self):
        self.ecs.describe_tasks.return_value = {"tasks": [], "failures": [{"reason": "MISSING"}]}

        with self.assertRaises(DiagnosticProviderError):
            self.lifecycle.status(
                "123e4567-e89b-42d3-a456-426614174000",
                self.execution,
            )

    def test_cancel_stops_task_then_deletes_schedule(self):
        self.lifecycle.cancel(
            "123e4567-e89b-42d3-a456-426614174000",
            self.execution,
        )

        self.provider.stop.assert_called_once_with(self.execution)
        self.scheduler.delete_schedule.assert_called_once_with(
            Name="dcc-stop-123e4567e89b42d3a456426614174000",
            GroupName="dcc-cleanup",
        )

    def test_cancel_ignores_already_missing_schedule(self):
        self.scheduler.delete_schedule.side_effect = ClientError(
            {"Error": {"Code": "ResourceNotFoundException", "Message": "missing"}},
            "DeleteSchedule",
        )

        self.lifecycle.cancel(
            "123e4567-e89b-42d3-a456-426614174000",
            self.execution,
        )

        self.provider.stop.assert_called_once_with(self.execution)
