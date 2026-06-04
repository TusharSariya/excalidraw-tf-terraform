# =============================================================================
# Ingestion account regional networks for lake, EKS, and persistence resources
# =============================================================================

module "ingestion_east_network" {
  source = "../modules/private_workload_network"

  providers = { aws = aws.ingestion }

  vpc_name              = local.ingestion_vpc_names.east
  vpc_cidr              = local.ingestion_vpc_cidrs.east
  public_subnet_cidrs   = local.ingestion_subnet_cidrs.east.public
  private_subnet_cidrs  = local.ingestion_subnet_cidrs.east.private
  intra_subnet_cidrs    = local.ingestion_subnet_cidrs.east.intra
  database_subnet_cidrs = local.ingestion_subnet_cidrs.east.database
  single_nat_gateway    = true

  interface_endpoint_security_group_name = "${local.ingestion_vpc_names.east}-vpce-sg"
  flow_logs_log_group_name               = "/aws/vpc/${local.ingestion_vpc_names.east}/flow"

  tags = merge(local.extended_common_tags, { account_lane = "ingestion" })
}

module "ingestion_west_network" {
  source = "../modules/private_workload_network"

  providers = { aws = aws.ingestion_west }

  vpc_name              = local.ingestion_vpc_names.west
  vpc_cidr              = local.ingestion_vpc_cidrs.west
  public_subnet_cidrs   = local.ingestion_subnet_cidrs.west.public
  private_subnet_cidrs  = local.ingestion_subnet_cidrs.west.private
  intra_subnet_cidrs    = local.ingestion_subnet_cidrs.west.intra
  database_subnet_cidrs = local.ingestion_subnet_cidrs.west.database
  single_nat_gateway    = true

  interface_endpoint_security_group_name = "${local.ingestion_vpc_names.west}-vpce-sg"
  flow_logs_log_group_name               = "/aws/vpc/${local.ingestion_vpc_names.west}/flow"

  tags = merge(local.extended_common_tags, { account_lane = "ingestion" })
}

module "ingestion_west_1_network" {
  source = "../modules/private_workload_network"

  providers = { aws = aws.ingestion_west_1 }

  vpc_name              = local.ingestion_vpc_names.west_1
  vpc_cidr              = local.ingestion_vpc_cidrs.west_1
  public_subnet_cidrs   = local.ingestion_subnet_cidrs.west_1.public
  private_subnet_cidrs  = local.ingestion_subnet_cidrs.west_1.private
  intra_subnet_cidrs    = local.ingestion_subnet_cidrs.west_1.intra
  database_subnet_cidrs = local.ingestion_subnet_cidrs.west_1.database
  single_nat_gateway    = true

  interface_endpoint_security_group_name = "${local.ingestion_vpc_names.west_1}-vpce-sg"
  flow_logs_log_group_name               = "/aws/vpc/${local.ingestion_vpc_names.west_1}/flow"

  tags = merge(local.extended_common_tags, { account_lane = "ingestion" })
}

module "ingestion_east_2_network" {
  source = "../modules/private_workload_network"

  providers = { aws = aws.ingestion_east_2 }

  vpc_name              = local.ingestion_vpc_names.east_2
  vpc_cidr              = local.ingestion_vpc_cidrs.east_2
  public_subnet_cidrs   = local.ingestion_subnet_cidrs.east_2.public
  private_subnet_cidrs  = local.ingestion_subnet_cidrs.east_2.private
  intra_subnet_cidrs    = local.ingestion_subnet_cidrs.east_2.intra
  database_subnet_cidrs = local.ingestion_subnet_cidrs.east_2.database
  single_nat_gateway    = true

  interface_endpoint_security_group_name = "${local.ingestion_vpc_names.east_2}-vpce-sg"
  flow_logs_log_group_name               = "/aws/vpc/${local.ingestion_vpc_names.east_2}/flow"

  tags = merge(local.extended_common_tags, { account_lane = "ingestion" })
}
