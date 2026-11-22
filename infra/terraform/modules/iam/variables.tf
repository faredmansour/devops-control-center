variable "name_prefix" {
  description = "Prefix used for workload IAM role names."
  type        = string

  validation {
    condition     = length(var.name_prefix) >= 3 && length(var.name_prefix) <= 48
    error_message = "name_prefix must be between 3 and 48 characters."
  }
}

variable "aws_region" {
  description = "AWS region used in the ECS task trust policy and KMS service condition."
  type        = string
}

variable "aws_account_id" {
  description = "12-digit AWS account ID used to constrain ECS task trust."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "aws_account_id must contain exactly 12 digits."
  }
}

variable "ecr_repository_arns" {
  description = "ECR repository ARNs allowed for image pulls, keyed by workload."
  type        = map(list(string))
  default     = {}
}

variable "log_group_arns" {
  description = "CloudWatch Log Group ARNs allowed for log writes, keyed by workload."
  type        = map(list(string))
  default     = {}
}

variable "secret_arns" {
  description = "Secrets Manager secret ARNs that ECS execution roles may inject, keyed by workload."
  type        = map(list(string))
  default     = {}
}

variable "kms_key_arns" {
  description = "Customer-managed KMS key ARNs for workload secrets, keyed by workload."
  type        = map(list(string))
  default     = {}
}

variable "permissions_boundary_arn" {
  description = "Optional IAM permissions boundary ARN applied to every role."
  type        = string
  default     = null
  nullable    = true
}

variable "enable_test_worker_orchestration" {
  description = "Enable scoped ECS test-worker orchestration permissions on the DCC task role."
  type        = bool
  default     = false

  validation {
    condition = !var.enable_test_worker_orchestration || (
      length(var.ecs_cluster_arn) > 0 &&
      length(var.test_worker_task_definition_arns) > 0 &&
      length(var.test_worker_task_resource_arn) > 0 &&
      length(var.test_worker_task_role_arns) > 0 &&
      length(var.test_worker_execution_role_arns) > 0
    )
    error_message = "When worker orchestration is enabled, provide the cluster ARN, task definition ARNs, task ARN pattern, and both worker role ARN lists."
  }
}

variable "ecs_cluster_arn" {
  description = "Dedicated ECS cluster ARN used by DCC to launch temporary test workers."
  type        = string
  default     = ""
}

variable "test_worker_task_definition_arns" {
  description = "Exact approved test-worker task definition ARNs DCC may run."
  type        = list(string)
  default     = []
}

variable "test_worker_task_resource_arn" {
  description = "Task ARN pattern scoped to the dedicated ECS cluster."
  type        = string
  default     = ""
}

variable "test_worker_task_role_arns" {
  description = "Exact IAM task role ARNs DCC may pass to ECS."
  type        = list(string)
  default     = []
}

variable "test_worker_execution_role_arns" {
  description = "Exact IAM execution role ARNs DCC may pass to ECS."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Common non-sensitive tags applied to IAM roles."
  type        = map(string)
  default     = {}
}