module "network" {
  source = "../modules/network"

  name_prefix                      = var.name_prefix
  vpc_cidr                         = var.vpc_cidr
  availability_zones               = var.availability_zones
  public_subnet_cidrs              = var.public_subnet_cidrs
  private_application_subnet_cidrs = var.private_application_subnet_cidrs
  private_data_subnet_cidrs        = var.private_data_subnet_cidrs
  enable_nat_gateway               = var.enable_nat_gateway
  tags                             = local.base_tags
}

module "security_groups" {
  source = "../modules/security-groups"

  name_prefix                          = var.name_prefix
  vpc_id                               = module.network.vpc_id
  alb_ingress_cidrs                    = var.alb_ingress_cidrs
  dcc_control_https_egress_cidrs       = var.dcc_control_https_egress_cidrs
  diagnostic_worker_https_egress_cidrs = var.diagnostic_worker_https_egress_cidrs
  test_worker_https_egress_cidrs       = var.test_worker_https_egress_cidrs
  diagnostic_public_http_egress_cidrs  = var.diagnostic_public_http_egress_cidrs
  tags                                 = local.base_tags
}

module "secrets_manager" {
  source = "../modules/secrets-manager"

  name_prefix = var.name_prefix
  secrets = {
    ecommerce_mongodb_atlas_uri = {
      name_suffix = "ecommerce/mongodb-atlas/uri"
      description = "MongoDB Atlas connection URI for the E-commerce backend."
      workload    = "ecommerce"
    }
    ecommerce_jwt_secret = {
      name_suffix = "ecommerce/jwt/secret"
      description = "JWT signing secret for the E-commerce backend."
      workload    = "ecommerce"
    }
  }
  recovery_window_in_days = 7
  tags                    = local.base_tags
}

module "iam" {
  source = "../modules/iam"

  name_prefix    = var.name_prefix
  aws_region     = var.aws_region
  aws_account_id = data.aws_caller_identity.current.account_id

  ecr_repository_arns = { for workload, arn in module.ecr.repository_arns : workload => [arn] }
  log_group_arns      = var.iam_log_group_arns
  secret_arns         = merge(var.iam_secret_arns, { ecommerce = concat(lookup(var.iam_secret_arns, "ecommerce", []), [module.secrets_manager.secret_arns["ecommerce_mongodb_atlas_uri"]]) })
  kms_key_arns        = var.iam_kms_key_arns

  enable_test_worker_orchestration = false
  tags                             = local.base_tags
}

module "ecr" {
  source = "../modules/ecr"

  name_prefix = var.name_prefix
  tags        = local.base_tags
}

module "ecs" {
  source = "../modules/ecs"

  name_prefix                    = var.name_prefix
  aws_region                     = var.aws_region
  aws_account_id                 = data.aws_caller_identity.current.account_id
  vpc_id                         = module.network.vpc_id
  public_subnet_ids              = module.network.public_subnet_ids
  private_application_subnet_ids = module.network.private_application_subnet_ids
  alb_security_group_id          = module.security_groups.security_group_ids["alb"]
  dcc_security_group_id          = module.security_groups.security_group_ids["dcc_control"]
  ecommerce_frontend_sg_id       = module.security_groups.security_group_ids["ecommerce_frontend"]
  ecommerce_backend_sg_id        = module.security_groups.security_group_ids["ecommerce_backend"]
  dcc_execution_role_arn         = module.iam.execution_role_arns["dcc"]
  dcc_task_role_arn              = module.iam.task_role_arns["dcc"]
  ecommerce_execution_role_arn   = module.iam.execution_role_arns["ecommerce"]
  ecommerce_task_role_arn        = module.iam.task_role_arns["ecommerce"]
  dcc_image                      = "${module.ecr.repository_urls["dcc"]}:${var.dcc_image_tag}"
  ecommerce_frontend_image       = "${module.ecr.repository_urls["ecommerce"]}:${var.ecommerce_frontend_image_tag}"
  ecommerce_backend_image        = "${module.ecr.repository_urls["ecommerce"]}:${var.ecommerce_backend_image_tag}"
  mongodb_atlas_secret_arn       = module.secrets_manager.secret_arns["ecommerce_mongodb_atlas_uri"]
  jwt_secret_arn                 = module.secrets_manager.secret_arns["ecommerce_jwt_secret"]
  tags                           = local.base_tags
}
