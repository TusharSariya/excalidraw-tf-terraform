# =============================================================================
# 02-east-datastores: All east datastores (apis 1-7)
# =============================================================================

module "api1_table" {
  source = "../modules/dynamodb_app_table"

  name = local.dynamodb_table_names["api-1"]
  tags = local.tags
}

module "api2_rds" {
  source = "../modules/rds_postgres_micro"

  identifier                 = local.rds_identifiers["api-2"]
  environment                = local.environment
  vpc_id                     = module.east_network.vpc_id
  database_subnet_ids        = module.east_network.database_subnets
  allowed_security_group_ids = []
  peer_vpc_cidr_blocks       = [local.vpc_cidrs.east]
  db_name                    = "api2"
  tags                       = local.tags
}

module "api3_aurora" {
  source = "../modules/aurora_serverless_v2_micro"

  identifier                 = local.aurora_identifiers["api-3"]
  environment                = local.environment
  vpc_id                     = module.east_network.vpc_id
  database_subnet_ids        = module.east_network.database_subnets
  allowed_security_group_ids = []
  peer_vpc_cidr_blocks       = [local.vpc_cidrs.east]
  db_name                    = "api3"
  tags                       = local.tags
}

module "api4_bucket" {
  source = "../modules/s3_app_bucket"

  bucket_name = local.s3_bucket_names["api-4"]
  tags        = local.tags
}

module "api5_table" {
  source = "../modules/dynamodb_app_table"

  name = local.dynamodb_table_names["api-5"]
  tags = local.tags
}

module "api6_rds" {
  source = "../modules/rds_postgres_micro"

  identifier                 = local.rds_identifiers["api-6"]
  environment                = local.environment
  vpc_id                     = module.east_network.vpc_id
  database_subnet_ids        = module.east_network.database_subnets
  allowed_security_group_ids = []
  peer_vpc_cidr_blocks       = [local.vpc_cidrs.east]
  db_name                    = "api6"
  tags                       = local.tags
}

module "api7_aurora" {
  source = "../modules/aurora_serverless_v2_micro"

  identifier                 = local.aurora_identifiers["api-7"]
  environment                = local.environment
  vpc_id                     = module.east_network.vpc_id
  database_subnet_ids        = module.east_network.database_subnets
  allowed_security_group_ids = []
  peer_vpc_cidr_blocks       = [local.vpc_cidrs.east]
  db_name                    = "api7"
  tags                       = local.tags
}

# =============================================================================
# 03-west-datastores: All west datastores (apis 8-11)
# =============================================================================

module "api8_west_bucket" {
  source = "../modules/s3_app_bucket"

  providers = { aws = aws.west }

  bucket_name = local.s3_bucket_names["api-8-west"]
  tags        = local.tags
}

module "api9_west_rds" {
  source = "../modules/rds_postgres_micro"

  providers = { aws = aws.west }

  identifier                 = local.rds_identifiers["api-9-west"]
  environment                = local.environment
  vpc_id                     = module.west_network.vpc_id
  database_subnet_ids        = module.west_network.database_subnets
  allowed_security_group_ids = []
  peer_vpc_cidr_blocks       = [local.vpc_cidrs.west]
  db_name                    = "api9west"
  tags                       = local.tags
}

module "api10_table" {
  source = "../modules/dynamodb_app_table"

  providers = { aws = aws.west }

  name = local.dynamodb_table_names["api-10"]
  tags = local.tags
}

module "api11_aurora" {
  source = "../modules/aurora_serverless_v2_micro"

  providers = { aws = aws.west }

  identifier                 = local.aurora_identifiers["api-11"]
  environment                = local.environment
  vpc_id                     = module.west_network.vpc_id
  database_subnet_ids        = module.west_network.database_subnets
  allowed_security_group_ids = []
  peer_vpc_cidr_blocks       = [local.vpc_cidrs.west]
  db_name                    = "api11"
  tags                       = local.tags
}

# =============================================================================
# 04-west-1-datastores: West-1 datastores (apis 12, 14)
# =============================================================================

module "api12_bucket" {
  source = "../modules/s3_app_bucket"

  providers = { aws = aws.west_1 }

  bucket_name = local.s3_bucket_names["api-12-west"]
  tags        = local.tags
}

module "api14_table" {
  source = "../modules/dynamodb_app_table"

  providers = { aws = aws.west_1 }

  name = local.dynamodb_table_names["api-14"]
  tags = local.tags
}

# =============================================================================
# 05-east-2-datastores: East-2 datastores (apis 15, 16)
# =============================================================================

module "api15_aurora" {
  source = "../modules/aurora_serverless_v2_micro"

  providers = { aws = aws.east_2 }

  identifier                 = local.aurora_identifiers["api-15"]
  environment                = local.environment
  vpc_id                     = module.east_2_network.vpc_id
  database_subnet_ids        = module.east_2_network.database_subnets
  allowed_security_group_ids = []
  peer_vpc_cidr_blocks       = concat([local.vpc_cidrs.east_2], [local.vpc_cidrs.east, local.vpc_cidrs.west, local.vpc_cidrs.west_1])
  db_name                    = "api15"
  tags                       = local.tags
}

module "api16_rds" {
  source = "../modules/rds_postgres_micro"

  providers = { aws = aws.east_2 }

  identifier                 = local.rds_identifiers["api-16"]
  environment                = local.environment
  vpc_id                     = module.east_2_network.vpc_id
  database_subnet_ids        = module.east_2_network.database_subnets
  allowed_security_group_ids = []
  peer_vpc_cidr_blocks       = concat([local.vpc_cidrs.east_2], [local.vpc_cidrs.east, local.vpc_cidrs.west, local.vpc_cidrs.west_1])
  db_name                    = "api16"
  tags                       = local.tags
}
