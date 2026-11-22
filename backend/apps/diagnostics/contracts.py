"""Versioned, bounded request/result contracts for on-demand diagnostic runs.

This module deliberately defines validation only. It does not launch jobs or imply
that every catalog entry already has an execution adapter.
"""
from rest_framework import serializers


RUN_SCHEMA_VERSION = 1
RUN_TYPES = (
    "runtime_health",
    "ecs_discovery",
    "api_smoke",
    "database_readonly",
    "security_scan",
    "load_test",
)
ENVIRONMENTS = ("staging", "production")


class StrictSerializer(serializers.Serializer):
    """Reject unknown keys instead of silently accepting unsafe caller input."""

    def to_internal_value(self, data):
        if isinstance(data, dict):
            unexpected = set(data).difference(self.fields)
            if unexpected:
                raise serializers.ValidationError({
                    field: "This field is not supported."
                    for field in sorted(unexpected)
                })
        return super().to_internal_value(data)


class DiagnosticRunLimitsSerializer(StrictSerializer):
    max_duration_seconds = serializers.IntegerField(min_value=1, max_value=900)
    max_requests = serializers.IntegerField(min_value=1, max_value=100_000, required=False)
    max_requests_per_second = serializers.IntegerField(
        min_value=1, max_value=100, required=False
    )
    max_virtual_users = serializers.IntegerField(
        min_value=1, max_value=50, required=False
    )


class DiagnosticRunRequestSerializer(StrictSerializer):
    schema_version = serializers.IntegerField()
    test_type = serializers.ChoiceField(choices=RUN_TYPES)
    environment = serializers.ChoiceField(choices=ENVIRONMENTS)
    target_task_id = serializers.RegexField(
        regex=r"\A[A-Za-z0-9][A-Za-z0-9._:-]{0,127}\Z",
        max_length=128,
    )
    limits = DiagnosticRunLimitsSerializer()

    def validate_schema_version(self, value):
        if value != RUN_SCHEMA_VERSION:
            raise serializers.ValidationError(
                f"Unsupported schema version. Expected {RUN_SCHEMA_VERSION}."
            )
        return value

    def validate(self, attrs):
        test_type = attrs["test_type"]
        environment = attrs["environment"]
        if test_type == "runtime_health" and not attrs.get("target_task_id"):
            raise serializers.ValidationError({"target_task_id": "This field is required for runtime health."})
        if test_type == "ecs_discovery" and any(key in limits for key in ("max_requests", "max_requests_per_second", "max_virtual_users")):
            raise serializers.ValidationError({"limits": "Load-generation limits are not valid for ECS discovery."})
        limits = attrs["limits"]

        if test_type == "load_test":
            required = {"max_requests", "max_requests_per_second", "max_virtual_users"}
            missing = required.difference(limits)
            if missing:
                raise serializers.ValidationError({
                    "limits": {
                        key: "This limit is required for load tests."
                        for key in sorted(missing)
                    }
                })
            if environment == "production":
                raise serializers.ValidationError({
                    "environment": "Load tests are not enabled for production targets."
                })

        if test_type == "security_scan" and environment == "production":
            raise serializers.ValidationError({
                "environment": "Active security scans are not enabled for production targets."
            })

        return attrs


class DiagnosticRunResultSerializer(StrictSerializer):
    schema_version = serializers.IntegerField()
    run_id = serializers.UUIDField()
    test_type = serializers.ChoiceField(choices=RUN_TYPES)
    status = serializers.ChoiceField(choices=(
        "queued",
        "running",
        "completed",
        "failed",
        "cancelled",
        "timed_out",
        "stopped_by_safety",
    ))
    started_at = serializers.DateTimeField(allow_null=True)
    finished_at = serializers.DateTimeField(allow_null=True)
    summary = serializers.CharField(max_length=2000, allow_blank=True)
    stop_reason = serializers.CharField(max_length=500, allow_blank=True, required=False)
    limitations = serializers.ListField(
        child=serializers.CharField(max_length=500), max_length=50
    )

    def validate_schema_version(self, value):
        if value != RUN_SCHEMA_VERSION:
            raise serializers.ValidationError(
                f"Unsupported schema version. Expected {RUN_SCHEMA_VERSION}."
            )
        return value

    def validate(self, attrs):
        if attrs["status"] in {
            "completed", "failed", "cancelled", "timed_out", "stopped_by_safety"
        } and attrs["finished_at"] is None:
            raise serializers.ValidationError({
                "finished_at": "A terminal run must include its finish timestamp."
            })
        return attrs


class DiagnosticRunContainerResultSerializer(StrictSerializer):
    name = serializers.CharField(max_length=128)
    last_status = serializers.CharField(max_length=32)
    health_status = serializers.CharField(max_length=32)
    exit_code = serializers.IntegerField(allow_null=True)
    reason = serializers.CharField(max_length=500, allow_blank=True)


class DiagnosticRunCallbackSerializer(StrictSerializer):
    """Bounded payload accepted from a short-lived diagnostic runner."""
    schema_version = serializers.IntegerField()
    run_id = serializers.UUIDField()
    test_type = serializers.ChoiceField(choices=("runtime_health", "ecs_discovery"))
    result_status = serializers.ChoiceField(choices=("healthy", "failed", "unknown"))
    summary = serializers.CharField(max_length=2000)
    task_last_status = serializers.CharField(max_length=32, required=False, default="UNKNOWN")
    task_health_status = serializers.CharField(max_length=32, required=False, default="UNKNOWN")
    containers = DiagnosticRunContainerResultSerializer(many=True, max_length=50, required=False, default=list)
    discovery = serializers.JSONField(required=False)
    started_at = serializers.DateTimeField()
    finished_at = serializers.DateTimeField()

    def validate_schema_version(self, value):
        if value != RUN_SCHEMA_VERSION:
            raise serializers.ValidationError(
                f"Unsupported schema version. Expected {RUN_SCHEMA_VERSION}."
            )
        return value

    def validate(self, attrs):
        if attrs["test_type"] == "ecs_discovery" and "discovery" not in attrs:
            raise serializers.ValidationError({"discovery": "ECS discovery result is required."})
        if attrs["test_type"] == "runtime_health" and "discovery" in attrs:
            raise serializers.ValidationError({"discovery": "Discovery data is not valid for runtime health."})
        if attrs["finished_at"] < attrs["started_at"]:
            raise serializers.ValidationError({
                "finished_at": "Finish time cannot be earlier than start time."
            })
        return attrs
