output "repository_arns" {
  description = "ECR repository ARNs keyed by workload."
  value       = { for workload, repository in aws_ecr_repository.this : workload => repository.arn }
}

output "repository_urls" {
  description = "ECR repository URLs keyed by workload."
  value       = { for workload, repository in aws_ecr_repository.this : workload => repository.repository_url }
}

output "repository_names" {
  description = "ECR repository names keyed by workload."
  value       = { for workload, repository in aws_ecr_repository.this : workload => repository.name }
}

output "repository_registry_ids" {
  description = "AWS registry IDs keyed by workload."
  value       = { for workload, repository in aws_ecr_repository.this : workload => repository.registry_id }
}
