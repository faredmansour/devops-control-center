from django.core import signing
from django.test import SimpleTestCase, override_settings
from rest_framework.test import APIClient
from apps.diagnostics.result_store import clear_results


@override_settings(DCC_STATELESS_RUN_API_ENABLED=True, DCC_RUN_CAPABILITY_TTL_SECONDS=600,
                   DCC_RUN_RESULT_RETENTION_SECONDS=600)
class StatelessRunResultCallbackTests(SimpleTestCase):
    RUN_ID = "123e4567-e89b-42d3-a456-426614174000"

    def setUp(self):
        clear_results()
        self.client = APIClient()
        self.callback_token = signing.dumps(
            {"run_id": self.RUN_ID, "purpose": "diagnostic_result_callback"},
            salt="diagnostics.stateless-run-result-callback.v1",
        )
        self.run_token = signing.dumps({
            "run_id": self.RUN_ID, "provider": "ecs",
            "task_arn": "arn:aws:ecs:us-east-1:123456789012:task/dcc/abc",
            "cluster": "arn:aws:ecs:us-east-1:123456789012:cluster/dcc",
            "target_task_id": "target-123", "test_type": "runtime_health",
            "environment": "staging", "limits": {"max_duration_seconds": 120},
        }, salt="diagnostics.stateless-run-capability.v1")

    def tearDown(self):
        clear_results()

    def payload(self):
        return {
            "schema_version": 1, "run_id": self.RUN_ID,
            "test_type": "runtime_health", "result_status": "healthy",
            "summary": "ECS reports the target task as HEALTHY.",
            "task_last_status": "RUNNING", "task_health_status": "HEALTHY",
            "containers": [{"name": "api", "last_status": "RUNNING",
                            "health_status": "HEALTHY", "exit_code": None, "reason": ""}],
            "started_at": "2026-11-19T01:00:00Z",
            "finished_at": "2026-11-19T01:00:03Z",
        }

    def test_callback_is_accepted_and_result_is_returned_by_poll(self):
        response = self.client.post(
            f"/api/diagnostic-sessions/runs/{self.RUN_ID}/result/",
            self.payload(), format="json", HTTP_X_DCC_RESULT_TOKEN=self.callback_token,
        )
        self.assertEqual(response.status_code, 202, response.data)
        response = self.client.get(
            f"/api/diagnostic-sessions/runs/{self.RUN_ID}/",
            HTTP_X_DCC_RUN_TOKEN=self.run_token,
        )
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data["status"], "completed")
        self.assertEqual(response.data["result"]["result_status"], "healthy")

    def test_callback_rejects_payload_for_another_run(self):
        payload = self.payload()
        payload["run_id"] = "123e4567-e89b-42d3-a456-426614174001"
        response = self.client.post(
            f"/api/diagnostic-sessions/runs/{self.RUN_ID}/result/",
            payload, format="json", HTTP_X_DCC_RESULT_TOKEN=self.callback_token,
        )
        self.assertEqual(response.status_code, 403)

    def test_callback_rejects_duplicate_result(self):
        first = self.client.post(
            f"/api/diagnostic-sessions/runs/{self.RUN_ID}/result/",
            self.payload(), format="json", HTTP_X_DCC_RESULT_TOKEN=self.callback_token,
        )
        second = self.client.post(
            f"/api/diagnostic-sessions/runs/{self.RUN_ID}/result/",
            self.payload(), format="json", HTTP_X_DCC_RESULT_TOKEN=self.callback_token,
        )
        self.assertEqual(first.status_code, 202)
        self.assertEqual(second.status_code, 409)

    def test_callback_requires_signed_token(self):
        response = self.client.post(
            f"/api/diagnostic-sessions/runs/{self.RUN_ID}/result/",
            self.payload(), format="json",
        )
        self.assertEqual(response.status_code, 403)
