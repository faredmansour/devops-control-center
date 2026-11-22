import unittest
from unittest.mock import Mock, patch

from dcc_agent.config import AgentConfig, AgentConfigurationError
from dcc_agent.discovery import discover_ecs
from dcc_agent.runtime_health import inspect_target_task


class AgentConfigTests(unittest.TestCase):
    def test_runtime_health_requires_callback_and_target(self):
        with patch.dict("os.environ", {
            "DCC_AGENT_MODE": "runtime_health",
            "AWS_REGION": "us-east-1",
        }, clear=True):
            with self.assertRaises(AgentConfigurationError):
                AgentConfig.from_env()

    def test_discovery_mode_needs_only_region(self):
        with patch.dict("os.environ", {
            "DCC_AGENT_MODE": "discover_ecs",
            "AWS_REGION": "eu-central-1",
            "DCC_DISCOVERY_CLUSTERS": "sample-cluster",
        }, clear=True):
            config = AgentConfig.from_env()
        self.assertEqual(config.mode, "discover_ecs")
        self.assertEqual(config.region, "eu-central-1")


class RuntimeHealthTests(unittest.TestCase):
    def test_healthy_task(self):
        ecs = Mock()
        ecs.describe_tasks.return_value = {
            "tasks": [{
                "lastStatus": "RUNNING",
                "healthStatus": "HEALTHY",
                "containers": [{"name": "api", "lastStatus": "RUNNING", "healthStatus": "HEALTHY"}],
            }],
            "failures": [],
        }
        result = inspect_target_task(
            ecs, cluster_arn="cluster-arn", target_task_id="task-id"
        )
        self.assertEqual(result["status"], "healthy")
        ecs.describe_tasks.assert_called_once_with(
            cluster="cluster-arn", tasks=["task-id"]
        )


class DiscoveryTests(unittest.TestCase):
    def test_discovers_clusters_and_services(self):
        ecs = Mock()
        ecs.describe_clusters.return_value = {"clusters": [{
            "clusterArn": "cluster-arn",
            "clusterName": "sample",
            "status": "ACTIVE",
            "runningTasksCount": 2,
            "tags": [{"key": "environment", "value": "staging"}],
        }]}
        ecs.list_services.return_value = {"serviceArns": ["service-arn"]}
        ecs.describe_services.return_value = {"services": [{
            "serviceArn": "service-arn",
            "serviceName": "web",
            "status": "ACTIVE",
            "desiredCount": 1,
            "runningCount": 1,
            "taskDefinition": "task-definition",
            "launchType": "FARGATE",
        }]}

        result = discover_ecs(ecs, ("sample-cluster",))
        ecs.describe_clusters.assert_called_once_with(clusters=["sample-cluster"])
        self.assertEqual(result["counts"], {"clusters": 1, "services": 1})
        self.assertEqual(result["clusters"][0]["services"][0]["name"], "web")
        ecs.describe_services.assert_called_once_with(
            cluster="cluster-arn", services=["service-arn"]
        )


if __name__ == "__main__":
    unittest.main()
