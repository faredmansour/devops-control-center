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
  operator_ingress_cidrs               = var.operator_ingress_cidrs
  ecommerce_ingress_cidrs              = var.ecommerce_ingress_cidrs
  dcc_control_https_egress_cidrs       = var.dcc_control_https_egress_cidrs
  diagnostic_worker_https_egress_cidrs = var.diagnostic_worker_https_egress_cidrs
  test_worker_https_egress_cidrs       = var.test_worker_https_egress_cidrs
  diagnostic_public_http_egress_cidrs  = var.diagnostic_public_http_egress_cidrs
  tags                                 = local.base_tags
}
