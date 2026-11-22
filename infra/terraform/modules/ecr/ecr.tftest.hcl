mock_provider "aws" {}

run "creates_four_private_immutable_scanned_repositories" {
  command = plan

  variables {
    name_prefix = "dcc-testlab-use1"
    tags = {
      Environment = "test"
    }
  }

  assert {
    condition     = length(aws_ecr_repository.this) == 4
    error_message = "Exactly four workload repositories must be created."
  }

  assert {
    condition     = alltrue([for repository in values(aws_ecr_repository.this) : repository.image_tag_mutability == "IMMUTABLE" && repository.image_scanning_configuration[0].scan_on_push])
    error_message = "Every repository must use immutable tags and scan images on push."
  }

  assert {
    condition     = alltrue([for repository in values(aws_ecr_repository.this) : repository.force_delete == false && repository.encryption_configuration[0].encryption_type == "AES256"])
    error_message = "Repositories must not force-delete images and must use AES256 encryption."
  }

  assert {
    condition     = length(aws_ecr_lifecycle_policy.this) == 4
    error_message = "Every repository must have a lifecycle retention policy."
  }
}

run "rejects_invalid_repository_prefix" {
  command = plan

  variables {
    name_prefix = "INVALID PREFIX"
  }

  expect_failures = [var.name_prefix]
}
