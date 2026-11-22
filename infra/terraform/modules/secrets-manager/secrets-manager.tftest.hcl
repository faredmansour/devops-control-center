mock_provider "aws" {}

run "creates_metadata_without_secret_value" {
  command = plan

  variables {
    name_prefix = "dcc-testlab-use1"
    secrets = {
      ecommerce_mongodb_atlas_uri = {
        name_suffix = "ecommerce/mongodb-atlas/uri"
        description = "MongoDB Atlas connection URI for the E-commerce backend."
        workload    = "ecommerce"
      }
    }
  }

  assert {
    condition     = length(aws_secretsmanager_secret.this) == 1
    error_message = "Exactly the configured secret metadata resource must be planned."
  }

  assert {
    condition     = aws_secretsmanager_secret.this["ecommerce_mongodb_atlas_uri"].name == "dcc-testlab-use1/ecommerce/mongodb-atlas/uri"
    error_message = "The E-commerce Atlas secret must use the documented stable name."
  }

  assert {
    condition     = aws_secretsmanager_secret.this["ecommerce_mongodb_atlas_uri"].recovery_window_in_days == 7
    error_message = "Secrets must use the seven-day recovery window by default."
  }
}

run "rejects_short_recovery_window" {
  command = plan

  variables {
    name_prefix             = "dcc-testlab-use1"
    recovery_window_in_days = 3
    secrets = {
      ecommerce_mongodb_atlas_uri = {
        name_suffix = "ecommerce/mongodb-atlas/uri"
        description = "MongoDB Atlas connection URI."
        workload    = "ecommerce"
      }
    }
  }

  expect_failures = [var.recovery_window_in_days]
}
