variable "aws_region" {
  description = "AWS region dedicated to this independent Test Lab."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project tag value applied to managed resources."
  type        = string
  default     = "DCC-TestLab"
}

variable "environment_name" {
  description = "Environment tag value."
  type        = string
  default     = "lab"
}

variable "name_prefix" {
  description = "Unique resource naming prefix for the us-east-1 environment."
  type        = string
  default     = "dcc-testlab-use1"

  validation {
    condition     = length(var.name_prefix) >= 3 && length(var.name_prefix) <= 32
    error_message = "name_prefix must be between 3 and 32 characters."
  }
}

variable "vpc_cidr" {
  description = "Dedicated VPC CIDR; verify it against all connected networks before apply."
  type        = string
  default     = "10.81.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr))
    error_message = "vpc_cidr must be a valid IPv4 CIDR."
  }
}

variable "availability_zones" {
  description = "Exactly two AZ names, or empty to select the first two available in us-east-1."
  type        = list(string)
  default     = []

  validation {
    condition     = length(var.availability_zones) == 0 || (length(var.availability_zones) == 2 && length(distinct(var.availability_zones)) == 2)
    error_message = "availability_zones must be empty or contain exactly two distinct AZ names."
  }
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDRs ordered by AZ."
  type        = list(string)
  default     = ["10.81.0.0/24", "10.81.1.0/24"]
}

variable "private_application_subnet_cidrs" {
  description = "Private application subnet CIDRs ordered by AZ."
  type        = list(string)
  default     = ["10.81.16.0/20", "10.81.32.0/20"]
}

variable "private_data_subnet_cidrs" {
  description = "Private data subnet CIDRs ordered by AZ."
  type        = list(string)
  default     = ["10.81.48.0/24", "10.81.49.0/24"]
}

variable "enable_nat_gateway" {
  description = "Create one NAT Gateway for private application egress; incurs recurring cost."
  type        = bool
  default     = true
}

variable "common_tags" {
  description = "Additional non-sensitive tags applied to all resources."
  type        = map(string)
  default     = {}
}

variable "operator_ingress_cidrs" {
  description = "Approved IPv4 CIDRs allowed to reach the ALB over HTTPS. Empty means no public ingress."
  type        = list(string)
  default     = []
}

variable "ecommerce_ingress_cidrs" {
  description = "Approved IPv4 CIDRs allowed to reach the E-commerce ALB over HTTPS. Empty means no public ingress."
  type        = list(string)
  default     = []
}

variable "dcc_control_https_egress_cidrs" {
  description = "Approved IPv4 CIDRs that DCC Control may reach over HTTPS."
  type        = list(string)
  default     = []
}

variable "diagnostic_worker_https_egress_cidrs" {
  description = "Approved IPv4 CIDRs that diagnostic workers may reach over HTTPS."
  type        = list(string)
  default     = []
}

variable "test_worker_https_egress_cidrs" {
  description = "Approved IPv4 CIDRs that test workers may reach over HTTPS."
  type        = list(string)
  default     = []
}

variable "diagnostic_public_http_egress_cidrs" {
  description = "Approved IPv4 CIDRs for diagnostic HTTP/HTTPS probes."
  type        = list(string)
  default     = []
}

variable "iam_ecr_repository_arns" {
  description = "ECR repository ARNs allowed for each workload execution role."
  type        = map(list(string))
  default     = {}
}

variable "iam_log_group_arns" {
  description = "CloudWatch log group ARNs allowed for each workload execution role."
  type        = map(list(string))
  default     = {}
}

variable "iam_secret_arns" {
  description = "Secrets Manager secret ARNs injected into each workload by ECS."
  type        = map(list(string))
  default     = {}
}

variable "iam_kms_key_arns" {
  description = "Customer-managed KMS key ARNs used to decrypt each workload secret."
  type        = map(list(string))
  default     = {}
}