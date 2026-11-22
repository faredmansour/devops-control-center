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

variable "enable_dcc_control_https_egress" {
  description = "Allow the DCC control plane outbound HTTPS to public IPv4 destinations."
  type        = bool
  default     = false
}

variable "enable_diagnostic_worker_https_egress" {
  description = "Allow diagnostic workers outbound HTTPS to public IPv4 destinations."
  type        = bool
  default     = false
}

variable "enable_test_api_https_egress" {
  description = "Allow the application-under-test API outbound HTTPS to public IPv4 destinations."
  type        = bool
  default     = false
}

variable "enable_test_worker_https_egress" {
  description = "Allow test workers outbound HTTPS to public IPv4 destinations."
  type        = bool
  default     = false
}

variable "enable_diagnostic_public_http_egress" {
  description = "Allow diagnostic workers public HTTP/HTTPS probes to IPv4 destinations."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Common non-sensitive tags."
  type        = map(string)
  default     = {}
}
