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
