# =============================================================================
# East APIs (us-east-1): api-1 through api-7
# =============================================================================

# api-1: Lambda + DynamoDB (40-east-api-1)
module "api1" {
  source = "../staging-multi-state/modules/private_api_lambda"

  name                  = "api-1"
  environment           = local.environment
  aws_region            = local.regions.east
  aws_account_id        = local.aws_account_id
  vpc_id                = module.east_network.vpc_id
  vpc_cidr              = local.vpc_cidrs.east
  private_subnet_ids    = module.east_network.private_subnets
  execute_api_vpce_id   = aws_vpc_endpoint.east_execute_api.id
  artifact_bucket_id    = module.east_lambda_artifacts.s3_bucket_id
  lambda_source_file    = "${path.module}/../staging-multi-state/shared/api_handler.py"
  openapi_template_path = "${path.module}/../staging-multi-state/40-east-api-1/openapi.tftpl"
  stage_name            = local.api_stage_name
  dynamodb_table_arn    = module.api1_table.arn
  tags                  = local.tags
}

# api-2: ECS Fargate + RDS (41-east-api-2)
module "api2" {
  source = "../staging-multi-state/modules/private_api_ecs"

  name                   = "api-2"
  environment            = local.environment
  aws_region             = local.regions.east
  aws_account_id         = local.aws_account_id
  vpc_id                 = module.east_network.vpc_id
  vpc_cidr               = local.vpc_cidrs.east
  private_subnet_ids     = module.east_network.private_subnets
  execute_api_vpce_id    = aws_vpc_endpoint.east_execute_api.id
  execute_api_vpce_sg_id = module.east_network.interface_endpoint_security_group_id
  launch_type            = "FARGATE"
  db_secret_arn          = module.api2_rds.secret_arn
  stage_name             = local.api_stage_name
  tags                   = local.tags
}

# api-3: ECS EC2 + Aurora (42-east-api-3)
module "api3" {
  source = "../staging-multi-state/modules/private_api_ecs"

  name                   = "api-3"
  environment            = local.environment
  aws_region             = local.regions.east
  aws_account_id         = local.aws_account_id
  vpc_id                 = module.east_network.vpc_id
  vpc_cidr               = local.vpc_cidrs.east
  private_subnet_ids     = module.east_network.private_subnets
  execute_api_vpce_id    = aws_vpc_endpoint.east_execute_api.id
  execute_api_vpce_sg_id = module.east_network.interface_endpoint_security_group_id
  launch_type            = "FARGATE"
  db_secret_arn          = module.api3_aurora.secret_arn
  stage_name             = local.api_stage_name
  tags                   = local.tags
}

# api-6: Lambda + RDS + downstream api8/api12/api15 (45-east-api-6)
# Must be declared before api4/api5 which depend on api6/api7 (downstream URLs)
module "api6" {
  source = "../staging-multi-state/modules/private_api_lambda"

  name                  = "api-6"
  environment           = local.environment
  aws_region            = local.regions.east
  aws_account_id        = local.aws_account_id
  vpc_id                = module.east_network.vpc_id
  vpc_cidr              = local.vpc_cidrs.east
  private_subnet_ids    = module.east_network.private_subnets
  execute_api_vpce_id   = aws_vpc_endpoint.east_execute_api.id
  artifact_bucket_id    = module.east_lambda_artifacts.s3_bucket_id
  lambda_source_file    = "${path.module}/../staging-multi-state/shared/api_handler.py"
  openapi_template_path = "${path.module}/../staging-multi-state/45-east-api-6/openapi.tftpl"
  stage_name            = local.api_stage_name
  db_secret_arn         = module.api6_rds.secret_arn
  downstream_api_urls = {
    api8  = "https://${module.api8.api_id}-${aws_vpc_endpoint.west_execute_api.id}.execute-api.${local.regions.west}.amazonaws.com/${local.api_stage_name}/invoke"
    api12 = "https://${module.api12.api_id}-${aws_vpc_endpoint.west_1_execute_api.id}.execute-api.${local.regions.west_1}.amazonaws.com/${local.api_stage_name}/invoke"
    api15 = "https://${module.api15.api_id}-${aws_vpc_endpoint.east_2_execute_api.id}.execute-api.${local.regions.east_2}.amazonaws.com/${local.api_stage_name}/invoke"
  }
  tags = local.tags
}

# api-7: ECS EC2 + Aurora + downstream api9 (46-east-api-7)
module "api7" {
  source = "../staging-multi-state/modules/private_api_ecs"

  name                   = "api-7"
  environment            = local.environment
  aws_region             = local.regions.east
  aws_account_id         = local.aws_account_id
  vpc_id                 = module.east_network.vpc_id
  vpc_cidr               = local.vpc_cidrs.east
  private_subnet_ids     = module.east_network.private_subnets
  execute_api_vpce_id    = aws_vpc_endpoint.east_execute_api.id
  execute_api_vpce_sg_id = module.east_network.interface_endpoint_security_group_id
  launch_type            = "FARGATE"
  db_secret_arn          = module.api7_aurora.secret_arn
  downstream_api_urls = {
    api9 = module.api9.api_invoke_url
  }
  stage_name = local.api_stage_name
  tags       = local.tags
}

# api-4: Lambda + S3 + downstream api6 (43-east-api-4)
module "api4" {
  source = "../staging-multi-state/modules/private_api_lambda"

  name                  = "api-4"
  environment           = local.environment
  aws_region            = local.regions.east
  aws_account_id        = local.aws_account_id
  vpc_id                = module.east_network.vpc_id
  vpc_cidr              = local.vpc_cidrs.east
  private_subnet_ids    = module.east_network.private_subnets
  execute_api_vpce_id   = aws_vpc_endpoint.east_execute_api.id
  artifact_bucket_id    = module.east_lambda_artifacts.s3_bucket_id
  lambda_source_file    = "${path.module}/../staging-multi-state/shared/api_handler.py"
  openapi_template_path = "${path.module}/../staging-multi-state/43-east-api-4/openapi.tftpl"
  stage_name            = local.api_stage_name
  s3_bucket_arns        = [module.api4_bucket.bucket_arn]
  downstream_api_urls = {
    api6 = module.api6.api_invoke_url
  }
  tags = local.tags
}

# api-5: ECS Fargate + DynamoDB + downstream api7 (44-east-api-5)
module "api5" {
  source = "../staging-multi-state/modules/private_api_ecs"

  name                   = "api-5"
  environment            = local.environment
  aws_region             = local.regions.east
  aws_account_id         = local.aws_account_id
  vpc_id                 = module.east_network.vpc_id
  vpc_cidr               = local.vpc_cidrs.east
  private_subnet_ids     = module.east_network.private_subnets
  execute_api_vpce_id    = aws_vpc_endpoint.east_execute_api.id
  execute_api_vpce_sg_id = module.east_network.interface_endpoint_security_group_id
  launch_type            = "FARGATE"
  dynamodb_table_arn     = module.api5_table.arn
  downstream_api_urls = {
    api7 = module.api7.api_invoke_url
  }
  stage_name = local.api_stage_name
  tags       = local.tags
}

# =============================================================================
# West APIs (us-west-2): api-8 through api-11
# =============================================================================

# api-10: Lambda + DynamoDB (52-west-api-10) — declared before api8 (api8 → api10)
module "api10" {
  source = "../staging-multi-state/modules/private_api_lambda"

  providers = { aws = aws.west, archive = archive }

  name                  = "api-10"
  environment           = local.environment
  aws_region            = local.regions.west
  aws_account_id        = local.aws_account_id
  vpc_id                = module.west_network.vpc_id
  vpc_cidr              = local.vpc_cidrs.west
  private_subnet_ids    = module.west_network.private_subnets
  execute_api_vpce_id   = aws_vpc_endpoint.west_execute_api.id
  artifact_bucket_id    = module.west_lambda_artifacts.s3_bucket_id
  lambda_source_file    = "${path.module}/../staging-multi-state/shared/api_handler.py"
  openapi_template_path = "${path.module}/../staging-multi-state/52-west-api-10/openapi.tftpl"
  stage_name            = local.api_stage_name
  dynamodb_table_arn    = module.api10_table.arn
  tags                  = local.tags
}

# api-11: ECS Fargate + Aurora (53-west-api-11) — declared before api9 (api9 → api11)
module "api11" {
  source = "../staging-multi-state/modules/private_api_ecs"

  providers = { aws = aws.west }

  name                   = "api-11"
  environment            = local.environment
  aws_region             = local.regions.west
  aws_account_id         = local.aws_account_id
  vpc_id                 = module.west_network.vpc_id
  vpc_cidr               = local.vpc_cidrs.west
  private_subnet_ids     = module.west_network.private_subnets
  execute_api_vpce_id    = aws_vpc_endpoint.west_execute_api.id
  execute_api_vpce_sg_id = module.west_network.interface_endpoint_security_group_id
  launch_type            = "FARGATE"
  db_secret_arn          = module.api11_aurora.secret_arn
  stage_name             = local.api_stage_name
  tags                   = local.tags
}

# api-8: ECS Fargate + S3 + downstream api10 (50-west-api-8)
module "api8" {
  source = "../staging-multi-state/modules/private_api_ecs"

  providers = { aws = aws.west }

  name                   = "api-8"
  environment            = local.environment
  aws_region             = local.regions.west
  aws_account_id         = local.aws_account_id
  vpc_id                 = module.west_network.vpc_id
  vpc_cidr               = local.vpc_cidrs.west
  private_subnet_ids     = module.west_network.private_subnets
  execute_api_vpce_id    = aws_vpc_endpoint.west_execute_api.id
  execute_api_vpce_sg_id = module.west_network.interface_endpoint_security_group_id
  launch_type            = "FARGATE"
  s3_bucket_arns         = [module.api8_west_bucket.bucket_arn]
  downstream_api_urls = {
    api10 = module.api10.api_invoke_url
  }
  stage_name = local.api_stage_name
  tags       = local.tags
}

# api-9: ECS EC2 + RDS + downstream api11 (51-west-api-9)
module "api9" {
  source = "../staging-multi-state/modules/private_api_ecs"

  providers = { aws = aws.west }

  name                   = "api-9"
  environment            = local.environment
  aws_region             = local.regions.west
  aws_account_id         = local.aws_account_id
  vpc_id                 = module.west_network.vpc_id
  vpc_cidr               = local.vpc_cidrs.west
  private_subnet_ids     = module.west_network.private_subnets
  execute_api_vpce_id    = aws_vpc_endpoint.west_execute_api.id
  execute_api_vpce_sg_id = module.west_network.interface_endpoint_security_group_id
  launch_type            = "FARGATE"
  db_secret_arn          = module.api9_west_rds.secret_arn
  downstream_api_urls = {
    api11 = module.api11.api_invoke_url
  }
  stage_name = local.api_stage_name
  tags       = local.tags
}

# =============================================================================
# West-1 APIs (us-west-1): api-12, api-14
# =============================================================================

# api-14: ECS Fargate + DynamoDB (55-west-1-api-14) — declared before api12 (api12 → api14)
module "api14" {
  source = "../staging-multi-state/modules/private_api_ecs"

  providers = { aws = aws.west_1 }

  name                   = "api-14"
  environment            = local.environment
  aws_region             = local.regions.west_1
  aws_account_id         = local.aws_account_id
  vpc_id                 = module.west_1_network.vpc_id
  vpc_cidr               = local.vpc_cidrs.west_1
  private_subnet_ids     = module.west_1_network.private_subnets
  execute_api_vpce_id    = aws_vpc_endpoint.west_1_execute_api.id
  execute_api_vpce_sg_id = module.west_1_network.interface_endpoint_security_group_id
  launch_type            = "FARGATE"
  dynamodb_table_arn     = module.api14_table.arn
  stage_name             = local.api_stage_name
  tags                   = local.tags
}

# api-12: Lambda + S3 + downstream api14 (54-west-1-api-12)
module "api12" {
  source = "../staging-multi-state/modules/private_api_lambda"

  providers = { aws = aws.west_1, archive = archive }

  name                  = "api-12"
  environment           = local.environment
  aws_region            = local.regions.west_1
  aws_account_id        = local.aws_account_id
  vpc_id                = module.west_1_network.vpc_id
  vpc_cidr              = local.vpc_cidrs.west_1
  private_subnet_ids    = module.west_1_network.private_subnets
  execute_api_vpce_id   = aws_vpc_endpoint.west_1_execute_api.id
  artifact_bucket_id    = module.west_1_lambda_artifacts.s3_bucket_id
  lambda_source_file    = "${path.module}/../staging-multi-state/shared/api_handler.py"
  openapi_template_path = "${path.module}/../staging-multi-state/54-west-1-api-12/openapi.tftpl"
  stage_name            = local.api_stage_name
  s3_bucket_arns        = [module.api12_bucket.bucket_arn]
  downstream_api_urls = {
    api14 = "https://${module.api14.api_id}-${aws_vpc_endpoint.west_1_execute_api.id}.execute-api.${local.regions.west_1}.amazonaws.com/${local.api_stage_name}/invoke"
  }
  tags = local.tags
}

# =============================================================================
# East-2 APIs (us-east-2): api-15, api-16
# =============================================================================

# api-16: Lambda + RDS (57-east-2-api-16) — declared before api15 (api15 → api16)
module "api16" {
  source = "../staging-multi-state/modules/private_api_lambda"

  providers = { aws = aws.east_2, archive = archive }

  name                  = "api-16"
  environment           = local.environment
  aws_region            = local.regions.east_2
  aws_account_id        = local.aws_account_id
  vpc_id                = module.east_2_network.vpc_id
  vpc_cidr              = local.vpc_cidrs.east_2
  private_subnet_ids    = module.east_2_network.private_subnets
  execute_api_vpce_id   = aws_vpc_endpoint.east_2_execute_api.id
  artifact_bucket_id    = module.east_2_lambda_artifacts.s3_bucket_id
  lambda_source_file    = "${path.module}/../staging-multi-state/shared/api_handler.py"
  openapi_template_path = "${path.module}/../staging-multi-state/57-east-2-api-16/openapi.tftpl"
  stage_name            = local.api_stage_name
  db_secret_arn         = module.api16_rds.secret_arn
  tags                  = local.tags
}

# api-15: ECS EC2 + Aurora + downstream api16 (56-east-2-api-15)
module "api15" {
  source = "../staging-multi-state/modules/private_api_ecs"

  providers = { aws = aws.east_2 }

  name                   = "api-15"
  environment            = local.environment
  aws_region             = local.regions.east_2
  aws_account_id         = local.aws_account_id
  vpc_id                 = module.east_2_network.vpc_id
  vpc_cidr               = local.vpc_cidrs.east_2
  private_subnet_ids     = module.east_2_network.private_subnets
  execute_api_vpce_id    = aws_vpc_endpoint.east_2_execute_api.id
  execute_api_vpce_sg_id = module.east_2_network.interface_endpoint_security_group_id
  launch_type            = "FARGATE"
  db_secret_arn          = module.api15_aurora.secret_arn
  downstream_api_urls = {
    api16 = "https://${module.api16.api_id}-${aws_vpc_endpoint.east_2_execute_api.id}.execute-api.${local.regions.east_2}.amazonaws.com/${local.api_stage_name}/invoke"
  }
  stage_name = local.api_stage_name
  tags       = local.tags
}
