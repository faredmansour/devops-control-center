output "aws_region" {
  description = "AWS region for this independent Test Lab."
  value       = var.aws_region
}

output "aws_account_id" {
  description = "AWS account ID selected by the active credential chain."
  value       = data.aws_caller_identity.current.account_id
}

output "vpc_id" {
  description = "Dedicated VPC ID."
  value       = module.network.vpc_id
}

output "vpc_cidr" {
  description = "Dedicated VPC IPv4 CIDR."
  value       = module.network.vpc_cidr
}

output "availability_zones" {
  description = "Availability Zones selected for this network."
  value       = module.network.availability_zones
}

output "public_subnet_ids" {
  description = "Public subnet IDs."
  value       = module.network.public_subnet_ids
}

output "private_application_subnet_ids" {
  description = "Private application subnet IDs for ECS workloads."
  value       = module.network.private_application_subnet_ids
}

output "private_data_subnet_ids" {
  description = "Private data subnet IDs for database/cache subnet groups."
  value       = module.network.private_data_subnet_ids
}

output "nat_gateway_id" {
  description = "NAT Gateway ID, or null when NAT is disabled."
  value       = module.network.nat_gateway_id
}

output "route_table_ids" {
  description = "Route table IDs by network tier."
  value       = module.network.route_table_ids
}

output "security_group_ids" {
  description = "Security Group IDs keyed by workload tier."
  value       = module.security_groups.security_group_ids
}

output "nat_gateway_public_ip" {
  description = "Stable outbound public IP to allowlist in MongoDB Atlas, or null when NAT is disabled."
  value       = module.network.nat_gateway_public_ip
}

output "iam_execution_role_arns" {
  description = "ECS execution role ARNs keyed by workload."
  value       = module.iam.execution_role_arns
}

output "iam_task_role_arns" {
  description = "ECS task role ARNs keyed by workload."
  value       = module.iam.task_role_arns
}

output "ecr_repository_arns" {
  description = "Private ECR repository ARNs keyed by workload."
  value       = module.ecr.repository_arns
}

output "ecr_repository_urls" {
  description = "Private ECR repository URLs keyed by workload."
  value       = module.ecr.repository_urls
}


output "ecommerce_mongodb_atlas_secret_arn" {
  description = "Secrets Manager ARN for the E-commerce MongoDB Atlas URI; the secret value is managed outside Terraform."
  value       = module.secrets_manager.secret_arns["ecommerce_mongodb_atlas_uri"]
}

output "ecs_cluster_name" {
  description = "ECS cluster hosting the DCC and E-commerce test services."
  value       = module.ecs.cluster_name
}

output "test_lab_alb_dns_name" {
  description = "Shared HTTP ALB DNS name. E-commerce uses port 80; DCC uses port 8080."
  value       = module.ecs.load_balancer_dns_name
}

output "ecs_service_names" {
  description = "ECS service names for the three test application components."
  value       = module.ecs.service_names
}

output "ecs_task_definition_arns" {
  description = "ECS task definition ARNs for the three test application components."
  value       = module.ecs.task_definition_arns
}
