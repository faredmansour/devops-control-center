output "secret_arns" {
  description = "Secrets Manager ARNs keyed by logical secret identifier."
  value       = { for key, secret in aws_secretsmanager_secret.this : key => secret.arn }
}

output "secret_names" {
  description = "Secrets Manager names keyed by logical secret identifier."
  value       = { for key, secret in aws_secretsmanager_secret.this : key => secret.name }
}
