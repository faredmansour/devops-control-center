output "security_group_ids" {
  description = "Security Group IDs keyed by workload tier."
  value       = { for name, group in aws_security_group.this : name => group.id }
}

output "alb_security_group_id" {
  description = "Security Group ID for the Application Load Balancer."
  value       = aws_security_group.this["alb"].id
}

output "application_security_group_id" {
  description = "Security Group ID for application tasks."
  value       = aws_security_group.this["application"].id
}

output "worker_security_group_id" {
  description = "Security Group ID for background worker tasks."
  value       = aws_security_group.this["worker"].id
}

output "database_security_group_id" {
  description = "Security Group ID for the database tier."
  value       = aws_security_group.this["database"].id
}

output "cache_security_group_id" {
  description = "Security Group ID for the cache tier."
  value       = aws_security_group.this["cache"].id
}

output "diagnostics_security_group_id" {
  description = "Security Group ID for on-demand diagnostic tasks."
  value       = aws_security_group.this["diagnostics"].id
}
