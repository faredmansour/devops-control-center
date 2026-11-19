from datetime import datetime, timezone
from uuid import uuid4

from django.test import SimpleTestCase

from apps.diagnostics.contracts import (
    DiagnosticRunRequestSerializer,
    DiagnosticRunResultSerializer,
    RUN_SCHEMA_VERSION,
)


class DiagnosticRunRequestContractTests(SimpleTestCase):
    def valid_payload(self):
        return {
            "schema_version": RUN_SCHEMA_VERSION,
            "test_type": "runtime_health",
            "environment": "production",
            "target_task_id": "task-123",
            "limits": {"max_duration_seconds": 60},
        }

    def test_accepts_valid_bounded_runtime_request(self):
        serializer = DiagnosticRunRequestSerializer(data=self.valid_payload())
        self.assertTrue(serializer.is_valid(), serializer.errors)

    def test_rejects_unknown_fields(self):
        payload = self.valid_payload()
        payload["task_definition"] = "attacker-controlled"
        serializer = DiagnosticRunRequestSerializer(data=payload)
        self.assertFalse(serializer.is_valid())
        self.assertIn("task_definition", serializer.errors)

    def test_rejects_unsupported_schema_version(self):
        payload = self.valid_payload()
        payload["schema_version"] = 99
        serializer = DiagnosticRunRequestSerializer(data=payload)
        self.assertFalse(serializer.is_valid())
        self.assertIn("schema_version", serializer.errors)

    def test_rejects_unbounded_duration(self):
        payload = self.valid_payload()
        payload["limits"]["max_duration_seconds"] = 10_000
        serializer = DiagnosticRunRequestSerializer(data=payload)
        self.assertFalse(serializer.is_valid())
        self.assertIn("limits", serializer.errors)

    def test_load_test_requires_explicit_bounded_load_limits(self):
        payload = self.valid_payload()
        payload["test_type"] = "load_test"
        payload["environment"] = "staging"
        serializer = DiagnosticRunRequestSerializer(data=payload)
        self.assertFalse(serializer.is_valid())
        self.assertIn("limits", serializer.errors)

    def test_load_test_is_rejected_for_production(self):
        payload = self.valid_payload()
        payload.update(test_type="load_test")
        payload["limits"].update({
            "max_requests": 100,
            "max_requests_per_second": 5,
            "max_virtual_users": 2,
        })
        serializer = DiagnosticRunRequestSerializer(data=payload)
        self.assertFalse(serializer.is_valid())
        self.assertIn("environment", serializer.errors)

    def test_active_security_scan_is_rejected_for_production(self):
        payload = self.valid_payload()
        payload["test_type"] = "security_scan"
        serializer = DiagnosticRunRequestSerializer(data=payload)
        self.assertFalse(serializer.is_valid())
        self.assertIn("environment", serializer.errors)


class DiagnosticRunResultContractTests(SimpleTestCase):
    def test_accepts_terminal_result_with_finish_time(self):
        now = datetime.now(timezone.utc)
        payload = {
            "schema_version": RUN_SCHEMA_VERSION,
            "run_id": str(uuid4()),
            "test_type": "runtime_health",
            "status": "completed",
            "started_at": now,
            "finished_at": now,
            "summary": "Target health checks completed.",
            "stop_reason": "",
            "limitations": [],
        }
        serializer = DiagnosticRunResultSerializer(data=payload)
        self.assertTrue(serializer.is_valid(), serializer.errors)

    def test_rejects_terminal_result_without_finish_time(self):
        payload = {
            "schema_version": RUN_SCHEMA_VERSION,
            "run_id": str(uuid4()),
            "test_type": "runtime_health",
            "status": "completed",
            "started_at": None,
            "finished_at": None,
            "summary": "",
            "stop_reason": "",
            "limitations": [],
        }
        serializer = DiagnosticRunResultSerializer(data=payload)
        self.assertFalse(serializer.is_valid())
        self.assertIn("finished_at", serializer.errors)
