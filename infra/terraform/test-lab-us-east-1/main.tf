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

  name_prefix                           = var.name_prefix
  vpc_id                                = module.network.vpc_id
  operator_ingress_cidrs                = var.operator_ingress_cidrs
  enable_dcc_control_https_egress       = var.enable_dcc_control_https_egress
  enable_diagnostic_worker_https_egress = var.enable_diagnostic_worker_https_egress
  enable_test_api_https_egress          = var.enable_test_api_https_egress
  enable_test_worker_https_egress       = var.enable_test_worker_https_egress
  enable_diagnostic_public_http_egress  = var.enable_diagnostic_public_http_egress
  tags                                  = local.base_tags
}
