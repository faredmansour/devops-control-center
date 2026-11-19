from unittest import TestCase
from unittest.mock import Mock

from apps.diagnostics.runner import inspect_target_task


class RuntimeHealthRunnerTests(TestCase):
    def setUp(self):
        self.ecs = Mock()

    def test_reports_healthy_task(self):
        self.ecs.describe_tasks.return_value = {
            "tasks": [{
                "lastStatus": "RUNNING",
                "healthStatus": "HEALTHY",
                "containers": [{
                    "name": "api",
                    "lastStatus": "RUNNING",
                    "healthStatus": "HEALTHY",
                }],
            }],
            "failures": [],
        }

        result = inspect_target_task(
            self.ecs,
            cluster_arn="arn:aws:ecs:eu-north-1:123456789012:cluster/lab",
            target_task_id="target-123",
        )

        self.assertEqual(result["status"], "healthy")
        self.assertEqual(result["task_health_status"], "HEALTHY")
        self.ecs.describe_tasks.assert_called_once()

    def test_reports_unknown_when_target_has_no_health_signal(self):
        self.ecs.describe_tasks.return_value = {
            "tasks": [{
                "lastStatus": "RUNNING",
                "healthStatus": "UNKNOWN",
                "containers": [{
                    "name": "api",
                    "lastStatus": "RUNNING",
                }],
            }],
            "failures": [],
        }

        result = inspect_target_task(
            self.ecs,
            cluster_arn="cluster-arn",
            target_task_id="target-123",
        )

        self.assertEqual(result["status"], "unknown")
        self.assertIn("health checks", result["reason"])

    def test_reports_failed_for_unhealthy_target(self):
        self.ecs.describe_tasks.return_value = {
            "tasks": [{
                "lastStatus": "RUNNING",
                "healthStatus": "UNHEALTHY",
                "containers": [],
            }],
            "failures": [],
        }

        result = inspect_target_task(
            self.ecs,
            cluster_arn="cluster-arn",
            target_task_id="target-123",
        )

        self.assertEqual(result["status"], "failed")

    def test_reports_failed_when_target_is_not_running(self):
        self.ecs.describe_tasks.return_value = {
            "tasks": [{
                "lastStatus": "STOPPED",
                "healthStatus": "UNKNOWN",
                "containers": [],
            }],
            "failures": [],
        }

        result = inspect_target_task(
            self.ecs,
            cluster_arn="cluster-arn",
            target_task_id="target-123",
        )

        self.assertEqual(result["status"], "failed")

    def test_reports_failed_when_target_is_missing(self):
        self.ecs.describe_tasks.return_value = {
            "tasks": [],
            "failures": [{"reason": "MISSING"}],
        }

        result = inspect_target_task(
            self.ecs,
            cluster_arn="cluster-arn",
            target_task_id="target-123",
        )

        self.assertEqual(result["status"], "failed")
