mock_provider "aws" {}

run "creates_separate_least_privilege_execution_and_task_roles" {
  command = plan
  variables {
    name_prefix = "dcc-iam-test"
    aws_region = "us-east-1"
    aws_account_id = "123456789012"
    ecr_repository_arns = { dcc = ["arn:aws:ecr:us-east-1:123456789012:repository/dcc-control"], ecommerce = ["arn:aws:ecr:us-east-1:123456789012:repository/ecommerce-api"] }
    log_group_arns = { dcc = ["arn:aws:logs:us-east-1:123456789012:log-group:/ecs/dcc"] }
    secret_arns = { ecommerce = ["arn:aws:secretsmanager:us-east-1:123456789012:secret:ecommerce/runtime-AbCd"] }
  }
  assert { condition = length(aws_iam_role.execution) == 4 && length(aws_iam_role.task) == 4, error_message = "Each workload must have its own execution and task role." }
  assert { condition = aws_iam_role.execution["dcc"].name != aws_iam_role.execution["ecommerce"].name && aws_iam_role.task["dcc"].name != aws_iam_role.task["ecommerce"].name, error_message = "DCC and E-commerce must never share roles." }
  assert { condition = length(aws_iam_role_policy.dcc_worker_orchestration) == 0, error_message = "Worker orchestration must remain disabled unless explicitly configured." }
}

run "enables_scoped_worker_orchestration_only_when_complete" {
  command = plan
  variables {
    name_prefix = "dcc-iam-test"
    aws_region = "us-east-1"
    aws_account_id = "123456789012"
    enable_test_worker_orchestration = true
    ecs_cluster_arn = "arn:aws:ecs:us-east-1:123456789012:cluster/dcc-testlab"
    test_worker_task_definition_arns = ["arn:aws:ecs:us-east-1:123456789012:task-definition/dcc-test-worker:1"]
    test_worker_task_resource_arn = "arn:aws:ecs:us-east-1:123456789012:task/dcc-testlab/*"
    test_worker_task_role_arns = ["arn:aws:iam::123456789012:role/dcc-testlab-test_worker-task"]
    test_worker_execution_role_arns = ["arn:aws:iam::123456789012:role/dcc-testlab-test_worker-execution"]
  }
  assert { condition = length(aws_iam_role_policy.dcc_worker_orchestration) == 1, error_message = "The orchestration policy should be created only when explicitly enabled." }
}

run "rejects_invalid_account_id" {
  command = plan
  variables { name_prefix = "dcc-iam-test", aws_region = "us-east-1", aws_account_id = "not-an-account" }
  expect_failures = [var.aws_account_id]
}

run "rejects_incomplete_worker_orchestration_configuration" {
  command = plan
  variables { name_prefix = "dcc-iam-test", aws_region = "us-east-1", aws_account_id = "123456789012", enable_test_worker_orchestration = true }
  expect_failures = [var.enable_test_worker_orchestration]
}