output "vpc_id" {
  description = "ID of the dedicated VPC."
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "IPv4 CIDR allocated to the VPC."
  value       = aws_vpc.this.cidr_block
}

output "availability_zones" {
  description = "Two Availability Zone names selected for the network."
  value       = local.selected_availability_zones
}

output "public_subnet_ids" {
  description = "Public subnet IDs, ordered by Availability Zone."
  value       = [for index in range(length(local.selected_availability_zones)) : aws_subnet.public[tostring(index)].id]
}

output "private_application_subnet_ids" {
  description = "Private application subnet IDs, ordered by Availability Zone."
  value       = [for index in range(length(local.selected_availability_zones)) : aws_subnet.private_application[tostring(index)].id]
}

output "private_data_subnet_ids" {
  description = "Private data subnet IDs, ordered by Availability Zone."
  value       = [for index in range(length(local.selected_availability_zones)) : aws_subnet.private_data[tostring(index)].id]
}

output "nat_gateway_id" {
  description = "Single NAT Gateway ID, or null when NAT is disabled."
  value       = var.enable_nat_gateway ? aws_nat_gateway.this[0].id : null
}

output "route_table_ids" {
  description = "Route table IDs by subnet tier."
  value = {
    public              = aws_route_table.public.id
    private_application = aws_route_table.private_application.id
    private_data        = aws_route_table.private_data.id
  }
}

output "nat_gateway_public_ip" {
  description = "Stable public Elastic IP used by private workloads for outbound internet traffic, or null when NAT is disabled."
  value       = var.enable_nat_gateway ? aws_eip.nat[0].public_ip : null
}
