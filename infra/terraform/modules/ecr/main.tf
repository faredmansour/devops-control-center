locals {
  repositories = toset(["dcc", "ecommerce", "agent", "test_worker"])

  lifecycle_policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Retain only the 10 most recent images in each workload repository."
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = {
        type = "expire"
      }
    }]
  })
}

resource "aws_ecr_repository" "this" {
  for_each = local.repositories

  name                 = "${var.name_prefix}-${each.key}"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = false

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = merge(var.tags, {
    Name     = "${var.name_prefix}-${each.key}"
    Workload = each.key
    Purpose  = "DCC Test Lab container image repository"
  })
}

resource "aws_ecr_lifecycle_policy" "this" {
  for_each = aws_ecr_repository.this

  repository = each.value.name
  policy     = local.lifecycle_policy
}
