data "aws_iam_policy_document" "ecs_tasks_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_execution" {
  name               = "${var.name_prefix}-execution-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_trust.json

  tags = {
    Name = "${var.name_prefix}-execution-role"
  }
}

data "aws_iam_policy_document" "ecs_execution" {
  statement {
    sid       = "ECRAuthorization"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid    = "PullTestLabImage"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
    ]
    resources = [aws_ecr_repository.test_lab.arn]
  }

  statement {
    sid    = "PullDCCImage"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
    ]
    resources = [aws_ecr_repository.dcc_app.arn]
  }

  statement {
    sid    = "WriteTestLabLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:${var.log_group_prefix}/*:log-stream:*"
    ]
  }

  statement {
    sid       = "ReadDCCApplicationSecret"
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.dcc_django_key.arn]
  }
}

resource "aws_iam_role_policy" "ecs_execution" {
  name   = "${var.name_prefix}-execution-policy"
  role   = aws_iam_role.ecs_execution.id
  policy = data.aws_iam_policy_document.ecs_execution.json
}

data "aws_iam_policy_document" "ecs_database_secret" {
  statement {
    sid       = "ReadManagedDatabaseCredentials"
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_db_instance.test_lab.master_user_secret[0].secret_arn]
  }
}

resource "aws_iam_role_policy" "ecs_database_secret" {
  name   = "${var.name_prefix}-database-secret-policy"
  role   = aws_iam_role.ecs_execution.id
  policy = data.aws_iam_policy_document.ecs_database_secret.json
}

resource "aws_iam_role" "test_api_task" {
  name               = "${var.name_prefix}-api-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_trust.json

  tags = {
    Name = "${var.name_prefix}-api-task-role"
  }
}

resource "aws_iam_role" "test_worker_task" {
  name               = "${var.name_prefix}-worker-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_trust.json

  tags = {
    Name = "${var.name_prefix}-worker-task-role"
  }
}

resource "aws_iam_role" "diagnostic_task" {
  name               = "${var.name_prefix}-diagnostic-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_trust.json

  tags = {
    Name = "${var.name_prefix}-diagnostic-task-role"
  }
}

data "aws_iam_policy_document" "dcc_ecs_discovery" {
  statement {
    sid       = "DiscoverConfiguredCluster"
    effect    = "Allow"
    actions   = ["ecs:DescribeClusters"]
    resources = [aws_ecs_cluster.test_lab.arn]
  }

  statement {
    sid       = "ListConfiguredServices"
    effect    = "Allow"
    actions   = ["ecs:ListServices"]
    resources = [aws_ecs_cluster.test_lab.arn, "arn:${data.aws_partition.current.partition}:ecs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:service/${aws_ecs_cluster.test_lab.name}/*"]
  }

  statement {
    sid     = "ListConfiguredTasks"
    effect  = "Allow"
    actions = ["ecs:ListTasks"]
    resources = [
      aws_ecs_cluster.test_lab.arn,
      "arn:${data.aws_partition.current.partition}:ecs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:container-instance/${aws_ecs_cluster.test_lab.name}/*",
    ]
  }

  statement {
    sid    = "DescribeConfiguredServicesAndTasks"
    effect = "Allow"
    actions = [
      "ecs:DescribeServices",
      "ecs:DescribeTasks",
    ]
    resources = [
      aws_ecs_cluster.test_lab.arn,
      "arn:${data.aws_partition.current.partition}:ecs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:service/${aws_ecs_cluster.test_lab.name}/*",
      "arn:${data.aws_partition.current.partition}:ecs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:task/${aws_ecs_cluster.test_lab.name}/*",
    ]
  }

  statement {
    sid       = "DescribeConfiguredTaskDefinitions"
    effect    = "Allow"
    actions   = ["ecs:DescribeTaskDefinition"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "dcc_ecs_discovery" {
  name   = "${var.name_prefix}-dcc-ecs-discovery-policy"
  role   = aws_iam_role.diagnostic_task.id
  policy = data.aws_iam_policy_document.dcc_ecs_discovery.json
}

# A one-time EventBridge Scheduler role stops diagnostic Fargate tasks even if
# the Django control-plane process restarts or becomes unavailable.
resource "aws_scheduler_schedule_group" "dcc_cleanup" {
  name = "${var.name_prefix}-dcc-cleanup"

  tags = {
    Name    = "${var.name_prefix}-dcc-cleanup"
    Project = var.project_name
  }
}

data "aws_iam_policy_document" "scheduler_cleanup_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["scheduler.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = [aws_scheduler_schedule_group.dcc_cleanup.arn]
    }
  }
}

resource "aws_iam_role" "scheduler_cleanup" {
  name               = "${var.name_prefix}-scheduler-cleanup-role"
  assume_role_policy = data.aws_iam_policy_document.scheduler_cleanup_trust.json

  tags = {
    Name    = "${var.name_prefix}-scheduler-cleanup-role"
    Project = var.project_name
  }
}

data "aws_iam_policy_document" "scheduler_cleanup" {
  statement {
    sid       = "StopOnlyDCCDiagnosticTasks"
    effect    = "Allow"
    actions   = ["ecs:StopTask"]
    resources = [
      "arn:${data.aws_partition.current.partition}:ecs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:task/${aws_ecs_cluster.test_lab.name}/*"
    ]

    condition {
      test     = "ArnEquals"
      variable = "ecs:cluster"
      values   = [aws_ecs_cluster.test_lab.arn]
    }
  }
}

resource "aws_iam_role_policy" "scheduler_cleanup" {
  name   = "${var.name_prefix}-scheduler-cleanup-policy"
  role   = aws_iam_role.scheduler_cleanup.id
  policy = data.aws_iam_policy_document.scheduler_cleanup.json
}

data "aws_iam_policy_document" "dcc_scheduler_control" {
  statement {
    sid    = "ManageOnlyDCCCleanupSchedules"
    effect = "Allow"
    actions = [
      "scheduler:CreateSchedule",
      "scheduler:DeleteSchedule",
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:scheduler:${var.aws_region}:${data.aws_caller_identity.current.account_id}:schedule/${aws_scheduler_schedule_group.dcc_cleanup.name}/*"
    ]
  }

  statement {
    sid       = "PassOnlySchedulerCleanupRole"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = [aws_iam_role.scheduler_cleanup.arn]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["scheduler.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "dcc_scheduler_control" {
  name   = "${var.name_prefix}-dcc-scheduler-control-policy"
  role   = aws_iam_role.diagnostic_task.id
  policy = data.aws_iam_policy_document.dcc_scheduler_control.json
}


# A dedicated runner role can only inspect tasks in the configured Test Lab cluster.
resource "aws_iam_role" "diagnostic_runner_task" {
  name               = "${var.name_prefix}-diagnostic-runner-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_trust.json

  tags = {
    Name    = "${var.name_prefix}-diagnostic-runner-role"
    Project = var.project_name
  }
}

data "aws_iam_policy_document" "diagnostic_runner_task" {
  statement {
    sid       = "DescribeTasksInTestLab"
    effect    = "Allow"
    actions   = ["ecs:DescribeTasks"]
    resources = [
      aws_ecs_cluster.test_lab.arn,
      "arn:${data.aws_partition.current.partition}:ecs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:task/${aws_ecs_cluster.test_lab.name}/*"
    ]
  }
}

resource "aws_iam_role_policy" "diagnostic_runner_task" {
  name   = "${var.name_prefix}-diagnostic-runner-policy"
  role   = aws_iam_role.diagnostic_runner_task.id
  policy = data.aws_iam_policy_document.diagnostic_runner_task.json
}

# Only the DCC control task may launch the fixed runner task definition.
data "aws_iam_policy_document" "dcc_run_diagnostic_task" {
  statement {
    sid       = "RunFixedDiagnosticRunner"
    effect    = "Allow"
    actions   = ["ecs:RunTask"]
    resources = [aws_ecs_task_definition.diagnostic_runner.arn]

    condition {
      test     = "ArnEquals"
      variable = "ecs:cluster"
      values   = [aws_ecs_cluster.test_lab.arn]
    }
  }

  statement {
    sid       = "PassOnlyRunnerRoles"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = [
      aws_iam_role.ecs_execution.arn,
      aws_iam_role.diagnostic_runner_task.arn,
    ]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "dcc_run_diagnostic_task" {
  name   = "${var.name_prefix}-dcc-run-diagnostic-task-policy"
  role   = aws_iam_role.diagnostic_task.id
  policy = data.aws_iam_policy_document.dcc_run_diagnostic_task.json
}
