locals {
  base_tags = merge(var.common_tags, {
    Project     = var.project_name
    Environment = var.environment_name
    ManagedBy   = "Terraform"
    Purpose     = "standalone-test-laboratory"
    Region      = var.aws_region
  })
}
