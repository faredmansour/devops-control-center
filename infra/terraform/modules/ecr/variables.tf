variable "name_prefix" {
  description = "Prefix used for ECR repository names."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9_-]{1,30}[a-z0-9]$", var.name_prefix))
    error_message = "name_prefix must be 3-32 lowercase letters, digits, underscores, or hyphens, and start/end with a letter or digit."
  }
}

variable "tags" {
  description = "Common non-sensitive tags applied to ECR repositories."
  type        = map(string)
  default     = {}
}
