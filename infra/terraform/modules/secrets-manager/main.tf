resource "aws_secretsmanager_secret" "this" {
  for_each = var.secrets

  name                    = "${var.name_prefix}/${each.value.name_suffix}"
  description             = each.value.description
  kms_key_id              = each.value.kms_key_id
  recovery_window_in_days = var.recovery_window_in_days

  tags = merge(var.tags, {
    Name     = "${var.name_prefix}/${each.value.name_suffix}"
    Workload = each.value.workload
    Purpose  = "Runtime secret injected into ECS workloads"
  })
}
