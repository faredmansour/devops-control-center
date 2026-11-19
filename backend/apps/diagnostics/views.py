import logging
from uuid import uuid4

from django.conf import settings
from django.core import signing
from django.core.exceptions import ImproperlyConfigured
from rest_framework.exceptions import AuthenticationFailed, NotFound, ValidationError
from rest_framework.request import Request
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.diagnostics.contracts import DiagnosticRunRequestSerializer
from apps.diagnostics.ecs_lifecycle import ECSStatelessJobLifecycle
from apps.diagnostics.models import ExecutionReference
from apps.diagnostics.providers import DiagnosticProviderError
from apps.diagnostics.serializers import (
    CreateDiagnosticSessionSerializer,
    DiagnosticSessionSerializer,
)
from apps.diagnostics.services import diagnostic_session_service, session_data


logger = logging.getLogger(__name__)
RUN_CAPABILITY_SALT = "diagnostics.stateless-run-capability.v1"


def _run_capability(run_id: str, execution: ExecutionReference, request_data: dict) -> str:
    return signing.dumps(
        {
            "run_id": run_id,
            "provider": execution.provider,
            "task_arn": execution.reference,
            "cluster": execution.cluster,
            "target_task_id": request_data["target_task_id"],
            "test_type": request_data["test_type"],
            "environment": request_data["environment"],
            "limits": request_data["limits"],
        },
        salt=RUN_CAPABILITY_SALT,
        compress=True,
    )


def _load_run_capability(request: Request, run_id: str) -> dict:
    token = request.headers.get("X-DCC-Run-Token", "").strip()
    if not token:
        raise AuthenticationFailed("A run capability token is required.")
    try:
        payload = signing.loads(
            token,
            salt=RUN_CAPABILITY_SALT,
            max_age=settings.DCC_RUN_CAPABILITY_TTL_SECONDS,
        )
    except signing.SignatureExpired:
        raise AuthenticationFailed("The run capability token has expired.") from None
    except signing.BadSignature:
        raise AuthenticationFailed("The run capability token is invalid.") from None

    if not isinstance(payload, dict) or payload.get("run_id") != run_id:
        raise AuthenticationFailed("The run capability does not match this run.")
    if payload.get("provider") != "ecs" or not payload.get("task_arn") or not payload.get("cluster"):
        raise AuthenticationFailed("The run capability is invalid.")
    return payload


def _execution_from_capability(payload: dict) -> ExecutionReference:
    return ExecutionReference(
        provider=payload["provider"],
        reference=payload["task_arn"],
        cluster=payload["cluster"],
    )


def _lifecycle() -> ECSStatelessJobLifecycle:
    try:
        return ECSStatelessJobLifecycle()
    except ImproperlyConfigured as error:
        logger.error("Stateless ECS run configuration is incomplete: %s", error)
        raise ValidationError(
            {"detail": "Stateless ECS execution is not configured."}
        ) from None


def _ecs_run_status(snapshot) -> str:
    if snapshot.last_status == "STOPPED":
        return "stopped"
    if snapshot.last_status in {"RUNNING"}:
        return "running"
    if snapshot.last_status in {"PROVISIONING", "PENDING", "ACTIVATING", "DEACTIVATING"}:
        return "queued"
    return "unknown"


class StatelessRunCollectionView(APIView):
    """Create a bounded ECS run and return its short-lived bearer capability."""

    def post(self, request: Request) -> Response:
        serializer = DiagnosticRunRequestSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        limits = data["limits"]
        run_id = str(uuid4())

        execution = _lifecycle().start(
            run_id=run_id,
            target_task_id=data["target_task_id"],
            max_duration_seconds=limits["max_duration_seconds"],
        )
        token = _run_capability(run_id, execution, data)
        return Response(
            {
                "schema_version": 1,
                "run_id": run_id,
                "test_type": data["test_type"],
                "environment": data["environment"],
                "status": "queued",
                "ecs_task_arn": execution.reference,
                "capability_token": token,
                "capability_expires_in": settings.DCC_RUN_CAPABILITY_TTL_SECONDS,
                "retention": "No run state is persisted by the DCC API.",
            },
            status=201,
        )


class StatelessRunDetailView(APIView):
    """Read ECS state using only the signed capability returned at creation."""

    def get(self, request: Request, run_id: str) -> Response:
        payload = _load_run_capability(request, run_id)
        snapshot = _lifecycle().status(run_id, _execution_from_capability(payload))
        return Response(
            {
                "schema_version": 1,
                "run_id": run_id,
                "test_type": payload["test_type"],
                "environment": payload["environment"],
                "status": _ecs_run_status(snapshot),
                "ecs": {
                    "last_status": snapshot.last_status,
                    "desired_status": snapshot.desired_status,
                    "stopped_reason": snapshot.stopped_reason,
                    "started_at": snapshot.started_at,
                    "stopped_at": snapshot.stopped_at,
                },
                "note": (
                    "ECS STOPPED indicates the task ended; it does not by itself "
                    "prove that the diagnostic test passed."
                ),
            }
        )


class StatelessRunCancelView(APIView):
    """Cancel a run using its short-lived signed capability."""

    def post(self, request: Request, run_id: str) -> Response:
        payload = _load_run_capability(request, run_id)
        _lifecycle().cancel(run_id, _execution_from_capability(payload))
        return Response(
            {
                "schema_version": 1,
                "run_id": run_id,
                "status": "cancellation_requested",
            },
            status=202,
        )


class DiagnosticSessionCollectionView(APIView):
    def get(self, request: Request) -> Response:
        data = [
            session_data(session)
            for session in diagnostic_session_service.list_sessions()
        ]
        serializer = DiagnosticSessionSerializer(data=data, many=True)
        serializer.is_valid(raise_exception=True)
        return Response(serializer.data)

    def post(self, request: Request) -> Response:
        request_serializer = CreateDiagnosticSessionSerializer(data=request.data)
        request_serializer.is_valid(raise_exception=True)
        session = diagnostic_session_service.start_session(
            request_serializer.validated_data["target_task_id"],
        )
        response_serializer = DiagnosticSessionSerializer(session_data(session))
        return Response(response_serializer.data, status=201)


class ActiveDiagnosticSessionView(APIView):
    def get(self, request: Request) -> Response:
        session = diagnostic_session_service.get_active_session()
        if session is None:
            return Response({"session": None})
        serializer = DiagnosticSessionSerializer(session_data(session))
        return Response({"session": serializer.data})


class DiagnosticSessionDetailView(APIView):
    def get(self, request: Request, session_id: str) -> Response:
        session = diagnostic_session_service.get_session(session_id)
        serializer = DiagnosticSessionSerializer(session_data(session))
        return Response(serializer.data)


class StopDiagnosticSessionView(APIView):
    def post(self, request: Request, session_id: str) -> Response:
        session = diagnostic_session_service.stop_session(session_id)
        serializer = DiagnosticSessionSerializer(session_data(session))
        return Response(serializer.data)
