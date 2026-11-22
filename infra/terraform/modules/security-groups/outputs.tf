output "security_group_ids" {
  description = "Security Group IDs keyed by workload tier."
  value       = { for name, group in aws_security_group.this : name => group.id }
}

output "alb_security_group_id" {
  description = "Security Group ID for the Application Load Balancer."
  value       = aws_security_group.this["alb"].id
}

output "dcc_control_security_group_id" {
  description = "Security Group ID for the DCC control plane."
  value       = aws_security_group.this["dcc_control"].id
}

output "diagnostic_worker_security_group_id" {
  description = "Security Group ID for on-demand diagnostic workers."
  value       = aws_security_group.this["diagnostic_worker"].id
}

output "test_api_security_group_id" {
  description = "Security Group ID for the application-under-test API."
  value       = aws_security_group.this["test_api"].id
}

output "test_worker_security_group_id" {
  description = "Security Group ID for background test workers."
  value       = aws_security_group.this["test_worker"].id
}

output "database_security_group_id" {
  description = "Security Group ID for the database tier."
  value       = aws_security_group.this["database"].id
}

output "cache_security_group_id" {
  description = "Security Group ID for the cache tier."
  value       = aws_security_group.this["cache"].id
}
