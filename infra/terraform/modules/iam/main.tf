locals {
  workload_names = toset(["dcc", "ecommerce", "agent", "test_worker"])

  execution_policy_documents = {
    for workload in local.workload_names : workload => jsonencode({
      Version = "2012-10-17"
      Statement = concat(
        [{
          Sid      = "EcrAuthorizationToken"
          Effect   = "Allow"
          Action   = ["ecr:GetAuthorizationToken"]
          Resource = "*"
        }],
        length(lookup(var.ecr_repository_arns, workload, [])) > 0 ? [{
          Sid      = "PullOnlyApprovedImages"
          Effect   = "Allow"
          Action   = ["ecr:BatchCheckLayerAvailability", "ecr:GetDownloadUrlForLayer", "ecr:BatchGetImage"]
          Resource = lookup(var.ecr_repository_arns, workload, [])
        }] : [],
        length(lookup(var.log_group_arns, workload, [])) > 0 ? [{
          Sid      = "WriteOnlyApprovedContainerLogs"
          Effect   = "Allow"
          Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
          Resource = [for arn in lookup(var.log_group_arns, workload, []) : "${trimsuffix(arn, ":*")}:*"]
        }] : [],
        length(lookup(var.secret_arns, workload, [])) > 0 ? [{
          Sid      = "ReadOnlyWorkloadSecrets"
          Effect   = "Allow"
          Action   = ["secretsmanager:GetSecretValue"]
          Resource = lookup(var.secret_arns, workload, [])
        }] : [],
        length(lookup(var.kms_key_arns, workload, [])) > 0 && length(lookup(var.secret_arns, workload, [])) > 0 ? [{
          Sid      = "DecryptOnlyWorkloadSecrets"
          Effect   = "Allow"
          Action   = ["kms:Decrypt"]
          Resource = lookup(var.kms_key_arns, workload, [])
          Condition = {
            StringLike = {
              "kms:ViaService" = "secretsmanager.${var.aws_region}.amazonaws.com"
            }
          }
        }] : []
      )
    })
  }
}

data "aws_iam_policy_document" "ecs_tasks_trust" {
  for_each = local.workload_names

  statement {
    sid     = "AllowEcsTasksAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.aws_account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:ecs:${var.aws_region}:${var.aws_account_id}:*"]
    }
  }
}

resource "aws_iam_role" "execution" {
  for_each = local.workload_names

  name                 = "${var.name_prefix}-${each.key}-execution"
  assume_role_policy   = data.aws_iam_policy_document.ecs_tasks_trust[each.key].json
  permissions_boundary = var.permissions_boundary_arn

  tags = merge(var.tags, {
    Name     = "${var.name_prefix}-${each.key}-execution"
    Workload = each.key
    Purpose  = "ECS image pull, logs, and scoped secret injection"
  })
}

resource "aws_iam_role_policy" "execution" {
  for_each = local.workload_names

  name   = "${var.name_prefix}-${each.key}-execution-policy"
  role   = aws_iam_role.execution[each.key].id
  policy = local.execution_policy_documents[each.key]
}

resource "aws_iam_role" "task" {
  for_each = local.workload_names

  name                 = "${var.name_prefix}-${each.key}-task"
  assume_role_policy   = data.aws_iam_policy_document.ecs_tasks_trust[each.key].json
  permissions_boundary = var.permissions_boundary_arn

  tags = merge(var.tags, {
    Name     = "${var.name_prefix}-${each.key}-task"
    Workload = each.key
    Purpose  = "Application runtime identity; permissions added only when justified"
  })
}

data "aws_iam_policy_document" "dcc_worker_orchestration" {
  count = var.enable_test_worker_orchestration ? 1 : 0

  statement {
    sid       = "RunOnlyApprovedTestWorkerTaskDefinitions"
    effect    = "Allow"
    actions   = ["ecs:RunTask", "ecs:DescribeTaskDefinition"]
    resources = var.test_worker_task_definition_arns

    condition {
      test     = "ArnEquals"
      variable = "ecs:cluster"
      values   = [var.ecs_cluster_arn]
    }
  }

  statement {
    sid       = "InspectAndStopOnlyTasksInDedicatedCluster"
    effect    = "Allow"
    actions   = ["ecs:DescribeTasks", "ecs:StopTask"]
    resources = [var.test_worker_task_resource_arn]
  }

  statement {
    sid       = "PassOnlyTestWorkerRolesToEcsTasks"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = concat(var.test_worker_task_role_arns, var.test_worker_execution_role_arns)

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "dcc_worker_orchestration" {
  count = var.enable_test_worker_orchestration ? 1 : 0

  name   = "${var.name_prefix}-dcc-worker-orchestration"
  role   = aws_iam_role.task["dcc"].id
  policy = data.aws_iam_policy_document.dcc_worker_orchestration[0].json
}