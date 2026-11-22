"""Bounded, read-only ECS inventory discovery for explicitly configured clusters."""
from typing import Any


MAX_CLUSTERS = 20
MAX_SERVICES_PER_CLUSTER = 50


def discover_ecs(ecs_client: Any, cluster_identifiers: tuple[str, ...]) -> dict[str, Any]:
    if not cluster_identifiers or len(cluster_identifiers) > MAX_CLUSTERS:
        raise ValueError("ECS discovery requires between 1 and 20 configured clusters.")

    clusters: list[dict[str, Any]] = []
    truncated = False

    resolved_identifiers: set[str] = set()
    for offset in range(0, len(cluster_identifiers), 100):
        response = ecs_client.describe_clusters(
            clusters=list(cluster_identifiers[offset:offset + 100])
        )
        for cluster in response.get("clusters", []):
            if cluster.get("clusterArn"):
                resolved_identifiers.add(cluster["clusterArn"])
            if cluster.get("clusterName"):
                resolved_identifiers.add(cluster["clusterName"])
            clusters.append({
                "arn": cluster.get("clusterArn"),
                "name": cluster.get("clusterName"),
                "status": cluster.get("status", "UNKNOWN"),
                "registered_container_instances": cluster.get("registeredContainerInstancesCount", 0),
                "running_tasks": cluster.get("runningTasksCount", 0),
                "pending_tasks": cluster.get("pendingTasksCount", 0),
                "services": [],
            })

    for cluster in clusters:
        service_arns: list[str] = []
        next_token = None
        while len(service_arns) < MAX_SERVICES_PER_CLUSTER:
            request = {
                "cluster": cluster["arn"],
                "maxResults": min(100, MAX_SERVICES_PER_CLUSTER - len(service_arns)),
            }
            if next_token:
                request["nextToken"] = next_token
            response = ecs_client.list_services(**request)
            service_arns.extend(response.get("serviceArns", []))
            next_token = response.get("nextToken")
            if not next_token:
                break
        if next_token or len(service_arns) > MAX_SERVICES_PER_CLUSTER:
            truncated = True

        for offset in range(0, min(len(service_arns), MAX_SERVICES_PER_CLUSTER), 10):
            response = ecs_client.describe_services(
                cluster=cluster["arn"],
                services=service_arns[offset:offset + 10],
            )
            for service in response.get("services", []):
                cluster["services"].append({
                    "arn": service.get("serviceArn"),
                    "name": service.get("serviceName"),
                    "status": service.get("status", "UNKNOWN"),
                    "desired_count": service.get("desiredCount", 0),
                    "running_count": service.get("runningCount", 0),
                    "pending_count": service.get("pendingCount", 0),
                    "task_definition": service.get("taskDefinition"),
                    "launch_type": service.get("launchType"),
                })

    return {
        "schema_version": 1,
        "provider": "aws",
        "discovery_scope": ["ecs.clusters", "ecs.services"],
        "truncated": truncated,
        "requested_clusters": len(cluster_identifiers),
        "unresolved_clusters": [
            item for item in cluster_identifiers if item not in resolved_identifiers
        ],
        "counts": {
            "clusters": len(clusters),
            "services": sum(len(item["services"]) for item in clusters),
        },
        "clusters": clusters,
        "limitations": [
            "Discovery is restricted to the cluster allowlist supplied at task launch.",
            "This initial agent release discovers ECS clusters and services only.",
            "It does not discover ALB, VPC, RDS, ECR, IAM, or CloudWatch resources yet.",
        ],
    }
