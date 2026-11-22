variable "name_prefix" { type = string }
variable "aws_region" { type = string }
variable "aws_account_id" { type = string }
variable "vpc_id" { type = string }
variable "public_subnet_ids" { type = list(string) }
variable "private_application_subnet_ids" { type = list(string) }
variable "alb_security_group_id" { type = string }
variable "dcc_security_group_id" { type = string }
variable "ecommerce_frontend_sg_id" { type = string }
variable "ecommerce_backend_sg_id" { type = string }
variable "dcc_execution_role_arn" { type = string }
variable "dcc_task_role_arn" { type = string }
variable "ecommerce_execution_role_arn" { type = string }
variable "ecommerce_task_role_arn" { type = string }
variable "dcc_image" { type = string }
variable "ecommerce_frontend_image" { type = string }
variable "ecommerce_backend_image" { type = string }
variable "mongodb_atlas_secret_arn" { type = string }
variable "jwt_secret_arn" { type = string }
variable "tags" {
  type    = map(string)
  default = {}
}
