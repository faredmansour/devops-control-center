output "security_group_ids" {
  description = "Security Group IDs keyed by workload tier."
  value       = { for name, group in aws_security_group.this : name => group.id }
}

output "dcc_alb_security_group_id" {
  description = "Security Group ID for the DCC ALB."
  value       = aws_security_group.this["dcc_alb"].id
}

output "ecommerce_alb_security_group_id" {
  description = "Security Group ID for the E-commerce ALB."
  value       = aws_security_group.this["ecommerce_alb"].id
}

output "dcc_control_security_group_id" {
  description = "Security Group ID for the DCC control plane."
  value       = aws_security_group.this["dcc_control"].id
}

output "dcc_agent_security_group_id" {
  description = "Security Group ID for the reusable DCC Agent."
  value       = aws_security_group.this["dcc_agent"].id
}

output "diagnostic_worker_security_group_id" {
  description = "Security Group ID for temporary diagnostic workers."
  value       = aws_security_group.this["diagnostic_worker"].id
}

output "ecommerce_frontend_security_group_id" {
  description = "Security Group ID for the E-commerce frontend."
  value       = aws_security_group.this["ecommerce_frontend"].id
}

output "ecommerce_backend_security_group_id" {
  description = "Security Group ID for the E-commerce backend."
  value       = aws_security_group.this["ecommerce_backend"].id
}

output "test_worker_security_group_id" {
  description = "Security Group ID for temporary DCC test workers."
  value       = aws_security_group.this["test_worker"].id
}

output "cache_security_group_id" {
  description = "Security Group ID for the optional private cache."
  value       = aws_security_group.this["cache"].id
}
