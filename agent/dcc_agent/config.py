"""Validated runtime configuration for the one-shot DCC agent."""
from dataclasses import dataclass
import os
from urllib.parse import urlsplit


class AgentConfigurationError(ValueError):
    """Raised when the agent receives an invalid or incomplete job configuration."""


@dataclass(frozen=True)
class AgentConfig:
    mode: str
    region: str
    run_id: str = ""
    target_task_id: str = ""
    target_cluster_arn: str = ""
    callback_url: str = ""
    callback_token: str = ""
    discovery_clusters: tuple[str, ...] = ()

    @classmethod
    def from_env(cls) -> "AgentConfig":
        mode = os.environ.get("DCC_AGENT_MODE", "runtime_health").strip().lower()
        if mode not in {"runtime_health", "discover_ecs"}:
            raise AgentConfigurationError("DCC_AGENT_MODE is not supported.")

        region = (
            os.environ.get("AWS_REGION")
            or os.environ.get("AWS_DEFAULT_REGION")
            or ""
        ).strip()
        if not region:
            raise AgentConfigurationError("AWS_REGION is required.")

        config = cls(
            mode=mode,
            region=region,
            run_id=os.environ.get("DIAGNOSTIC_SESSION_ID", "").strip(),
            target_task_id=os.environ.get("TARGET_TASK_ID", "").strip(),
            target_cluster_arn=os.environ.get("TARGET_CLUSTER_ARN", "").strip(),
            callback_url=os.environ.get("DCC_RESULT_CALLBACK_URL", "").strip(),
            callback_token=os.environ.get("DCC_RESULT_CALLBACK_TOKEN", "").strip(),
            discovery_clusters=tuple(
                item.strip()
                for item in os.environ.get("DCC_DISCOVERY_CLUSTERS", "").split(",")
                if item.strip()
            ),
        )
        if mode == "runtime_health":
            required = (
                config.run_id,
                config.target_task_id,
                config.target_cluster_arn,
                config.callback_url,
                config.callback_token,
            )
            if not all(required):
                raise AgentConfigurationError(
                    "Runtime health mode is missing required job configuration."
                )
        if mode == "discover_ecs" and (
            not config.discovery_clusters or len(config.discovery_clusters) > 20
        ):
            raise AgentConfigurationError(
                "ECS discovery requires between 1 and 20 explicitly configured clusters."
            )
        if mode == "discover_ecs" and bool(config.callback_url) != bool(
            config.run_id and config.callback_token
        ):
            raise AgentConfigurationError(
                "ECS discovery callback configuration is incomplete."
            )
        if config.callback_url:
            parsed = urlsplit(config.callback_url)
            if (
                parsed.scheme not in {"http", "https"}
                or not parsed.netloc
                or parsed.username
                or parsed.password
                or parsed.fragment
            ):
                raise AgentConfigurationError("The result callback URL is invalid.")
        return config
