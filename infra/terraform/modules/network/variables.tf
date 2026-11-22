variable "name_prefix" {
  description = "Prefix used for all network resource names and Name tags."
  type        = string

  validation {
    condition     = length(var.name_prefix) >= 3 && length(var.name_prefix) <= 32
    error_message = "name_prefix must be between 3 and 32 characters."
  }
}

variable "vpc_cidr" {
  description = "IPv4 CIDR allocated to this dedicated VPC."
  type        = string

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr))
    error_message = "vpc_cidr must be a valid IPv4 CIDR."
  }
}

variable "availability_zones" {
  description = "Exactly two AZ names. An empty list selects the first two available AZ names in the provider region."
  type        = list(string)
  default     = []

  validation {
    condition     = length(var.availability_zones) == 0 || (length(var.availability_zones) == 2 && length(distinct(var.availability_zones)) == 2)
    error_message = "availability_zones must be empty or contain exactly two distinct AZ names."
  }
}

variable "public_subnet_cidrs" {
  description = "Two public subnet CIDRs, ordered to match the selected Availability Zones."
  type        = list(string)

  validation {
    condition     = length(var.public_subnet_cidrs) == 2 && alltrue([for cidr in var.public_subnet_cidrs : can(cidrnetmask(cidr))])
    error_message = "public_subnet_cidrs must contain exactly two valid IPv4 CIDRs."
  }
}

variable "private_application_subnet_cidrs" {
  description = "Two private application subnet CIDRs, ordered to match the selected Availability Zones."
  type        = list(string)

  validation {
    condition     = length(var.private_application_subnet_cidrs) == 2 && alltrue([for cidr in var.private_application_subnet_cidrs : can(cidrnetmask(cidr))])
    error_message = "private_application_subnet_cidrs must contain exactly two valid IPv4 CIDRs."
  }
}

variable "private_data_subnet_cidrs" {
  description = "Two private data subnet CIDRs, ordered to match the selected Availability Zones."
  type        = list(string)

  validation {
    condition     = length(var.private_data_subnet_cidrs) == 2 && alltrue([for cidr in var.private_data_subnet_cidrs : can(cidrnetmask(cidr))])
    error_message = "private_data_subnet_cidrs must contain exactly two valid IPv4 CIDRs."
  }
}

variable "enable_nat_gateway" {
  description = "Whether to create one NAT Gateway for outbound internet access from private application subnets."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional tags applied to all network resources."
  type        = map(string)
  default     = {}
}
