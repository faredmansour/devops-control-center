output "execution_role_arns" { description = "ECS execution role ARNs keyed by workload." value = { for workload, role in aws_iam_role.execution : workload => role.arn } }

output "task_role_arns" { description = "ECS application task role ARNs keyed by workload." value = { for workload, role in aws_iam_role.task : workload => role.arn } }

output "execution_role_names" { description = "ECS execution role names keyed by workload." value = { for workload, role in aws_iam_role.execution : workload => role.name } }

output "task_role_names" { description = "ECS application task role names keyed by workload." value = { for workload, role in aws_iam_role.task : workload => role.name } }