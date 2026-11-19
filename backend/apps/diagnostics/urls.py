from django.urls import path

from apps.diagnostics.views import (
    ActiveDiagnosticSessionView,
    DiagnosticSessionCollectionView,
    DiagnosticSessionDetailView,
    StatelessRunCancelView,
    StatelessRunCollectionView,
    StatelessRunDetailView,
    StopDiagnosticSessionView,
)

urlpatterns = [
    path("runs/", StatelessRunCollectionView.as_view(), name="stateless-run-list"),
    path("runs/<uuid:run_id>/", StatelessRunDetailView.as_view(), name="stateless-run-detail"),
    path("runs/<uuid:run_id>/cancel/", StatelessRunCancelView.as_view(), name="stateless-run-cancel"),
    path("", DiagnosticSessionCollectionView.as_view(), name="diagnostic-session-list"),
    path("active/", ActiveDiagnosticSessionView.as_view(), name="active-diagnostic-session"),
    path("<str:session_id>/stop/", StopDiagnosticSessionView.as_view(), name="diagnostic-session-stop"),
    path("<str:session_id>/", DiagnosticSessionDetailView.as_view(), name="diagnostic-session-detail"),
]
