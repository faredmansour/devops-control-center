variable "name_prefix" {
  description = "Prefix used for Security Group names."
  type        = string
}

variable "vpc_id" {
  description = "VPC ID in which the Security Groups are created."
  type        = string
}

variable "operator_ingress_cidrs" {
  description = "Approved IPv4 CIDRs allowed to reach the ALB over HTTPS. Empty means no public ingress."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for cidr in var.operator_ingress_cidrs : can(cidrnetmask(cidr))])
    error_message = "Every operator_ingress_cidrs entry must be a valid IPv4 CIDR."
  }
}

variable "enable_application_https_egress" {
  description = "Allow application tasks to make outbound HTTPS requests to any IPv4 destination."
  type        = bool
  default     = false
}

variable "enable_worker_https_egress" {
  description = "Allow worker tasks to make outbound HTTPS requests to any IPv4 destination."
  type        = bool
  default     = false
}

variable "enable_diagnostics_http_egress" {
  description = "Allow diagnostic tasks to probe public HTTP and HTTPS endpoints."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Common non-sensitive tags."
  type        = map(string)
  default     = {}
}
