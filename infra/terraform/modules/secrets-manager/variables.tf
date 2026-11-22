variable "name_prefix" {
  description = "Prefix for Secrets Manager secret names."
  type        = string

  validation {
    condition     = length(var.name_prefix) >= 3 && length(var.name_prefix) <= 48
    error_message = "name_prefix must be between 3 and 48 characters."
  }
}

variable "secrets" {
  description = "Secret metadata keyed by a stable logical identifier. Values are deliberately not managed by Terraform."
  type = map(object({
    name_suffix = string
    description = string
    workload    = string
    kms_key_id  = optional(string)
  }))

  validation {
    condition     = length(var.secrets) > 0 && alltrue([for secret in values(var.secrets) : length(secret.name_suffix) > 0 && !startswith(secret.name_suffix, "/") && !endswith(secret.name_suffix, "/") && length(secret.description) > 0 && length(secret.workload) > 0])
    error_message = "Provide at least one secret with a non-empty relative name suffix, description, and workload."
  }
}

variable "recovery_window_in_days" {
  description = "Days before a deleted secret is permanently removed. Use 7-30 days."
  type        = number
  default     = 7

  validation {
    condition     = var.recovery_window_in_days >= 7 && var.recovery_window_in_days <= 30
    error_message = "recovery_window_in_days must be between 7 and 30."
  }
}

variable "tags" {
  description = "Common non-sensitive tags applied to secrets."
  type        = map(string)
  default     = {}
}
