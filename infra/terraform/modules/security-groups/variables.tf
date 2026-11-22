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

variable "dcc_control_https_egress_cidrs" {
  description = "Approved IPv4 CIDRs that DCC Control may reach over HTTPS. Empty means no public HTTPS egress."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for cidr in var.dcc_control_https_egress_cidrs : can(cidrnetmask(cidr))])
    error_message = "Every DCC Control HTTPS egress CIDR must be a valid IPv4 CIDR."
  }
}

variable "diagnostic_worker_https_egress_cidrs" {
  description = "Approved IPv4 CIDRs that diagnostic workers may reach over HTTPS."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for cidr in var.diagnostic_worker_https_egress_cidrs : can(cidrnetmask(cidr))])
    error_message = "Every diagnostic worker HTTPS egress CIDR must be a valid IPv4 CIDR."
  }
}

variable "test_api_https_egress_cidrs" {
  description = "Approved IPv4 CIDRs that the test API may reach over HTTPS."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for cidr in var.test_api_https_egress_cidrs : can(cidrnetmask(cidr))])
    error_message = "Every test API HTTPS egress CIDR must be a valid IPv4 CIDR."
  }
}

variable "test_worker_https_egress_cidrs" {
  description = "Approved IPv4 CIDRs that test workers may reach over HTTPS."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for cidr in var.test_worker_https_egress_cidrs : can(cidrnetmask(cidr))])
    error_message = "Every test worker HTTPS egress CIDR must be a valid IPv4 CIDR."
  }
}

variable "diagnostic_public_http_egress_cidrs" {
  description = "Approved IPv4 CIDRs for diagnostic HTTP/HTTPS probes. Empty means no public probe egress."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for cidr in var.diagnostic_public_http_egress_cidrs : can(cidrnetmask(cidr))])
    error_message = "Every diagnostic public HTTP egress CIDR must be a valid IPv4 CIDR."
  }
}

variable "tags" {
  description = "Common non-sensitive tags."
  type        = map(string)
  default     = {}
}
