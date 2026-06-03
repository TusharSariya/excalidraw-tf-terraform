# =============================================================================
# Shared IAM policy document for API Gateway CloudWatch role (used in all 4 regions)
# =============================================================================

data "aws_iam_policy_document" "apigw_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["apigateway.amazonaws.com"]
    }
  }
}

# =============================================================================
# 00-east-network: Hub VPC (us-east-1) + TGW + VPCE + lambda artifacts
# =============================================================================

module "east_network" {
  source = "../modules/private_workload_network"

  vpc_name              = local.vpc_names.east
  vpc_cidr              = local.vpc_cidrs.east
  public_subnet_cidrs   = local.subnet_cidrs.east.public
  private_subnet_cidrs  = local.subnet_cidrs.east.private
  intra_subnet_cidrs    = local.subnet_cidrs.east.intra
  database_subnet_cidrs = local.subnet_cidrs.east.database
  single_nat_gateway    = true

  interface_endpoint_security_group_name = "${local.vpc_names.east}-vpce-sg"
  flow_logs_log_group_name               = "/aws/vpc/${local.vpc_names.east}/flow"

  tags = local.tags
}

resource "aws_vpc_endpoint" "east_execute_api" {
  vpc_id              = module.east_network.vpc_id
  service_name        = "com.amazonaws.${local.regions.east}.execute-api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.east_network.intra_subnets
  security_group_ids  = [module.east_network.interface_endpoint_security_group_id]
  private_dns_enabled = true

  tags = merge(local.tags, { Name = "${local.vpc_names.east}-execute-api-vpce" })
}

resource "aws_ec2_transit_gateway" "east" {
  description                     = "Transit Gateway for us-east-1 staging network"
  amazon_side_asn                 = local.tgw_asns.east
  auto_accept_shared_attachments  = "disable"
  default_route_table_association = "enable"
  default_route_table_propagation = "enable"
  dns_support                     = "enable"
  vpn_ecmp_support                = "enable"

  tags = merge(local.tags, { Name = local.tgw_names.east })
}

resource "aws_ec2_transit_gateway_vpc_attachment" "east_vpc" {
  subnet_ids         = module.east_network.intra_subnets
  transit_gateway_id = aws_ec2_transit_gateway.east.id
  vpc_id             = module.east_network.vpc_id

  dns_support  = "enable"
  ipv6_support = "disable"

  tags = merge(local.tags, { Name = "${local.environment}-east-vpc-attachment" })
}

module "east_lambda_artifacts" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "5.8.0"

  bucket = local.lambda_artifacts_bucket_names.east

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  versioning = { status = "Enabled" }

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = { sse_algorithm = "AES256" }
      bucket_key_enabled                      = true
    }
  }

  attach_deny_insecure_transport_policy = false

  tags = merge(local.tags, { purpose = "lambda-artifacts" })
}

resource "aws_iam_role" "east_apigw_cloudwatch" {
  name               = local.apigw_cloudwatch_role_names.east
  assume_role_policy = data.aws_iam_policy_document.apigw_assume.json
}

resource "aws_iam_role_policy_attachment" "east_apigw_cloudwatch" {
  role       = aws_iam_role.east_apigw_cloudwatch.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}

resource "aws_api_gateway_account" "east" {
  cloudwatch_role_arn = aws_iam_role.east_apigw_cloudwatch.arn
  depends_on          = [aws_iam_role_policy_attachment.east_apigw_cloudwatch]
}

# =============================================================================
# 01-west-network: West VPC (us-west-2) + TGW + VPCE + east↔west peering
# =============================================================================

module "west_network" {
  source = "../modules/private_workload_network"

  providers = { aws = aws.west }

  vpc_name              = local.vpc_names.west
  vpc_cidr              = local.vpc_cidrs.west
  public_subnet_cidrs   = local.subnet_cidrs.west.public
  private_subnet_cidrs  = local.subnet_cidrs.west.private
  intra_subnet_cidrs    = local.subnet_cidrs.west.intra
  database_subnet_cidrs = local.subnet_cidrs.west.database
  single_nat_gateway    = true

  interface_endpoint_security_group_name = "${local.vpc_names.west}-vpce-sg"
  flow_logs_log_group_name               = "/aws/vpc/${local.vpc_names.west}/flow"

  tags = local.tags
}

resource "aws_vpc_endpoint" "west_execute_api" {
  provider = aws.west

  vpc_id              = module.west_network.vpc_id
  service_name        = "com.amazonaws.${local.regions.west}.execute-api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.west_network.intra_subnets
  security_group_ids  = [module.west_network.interface_endpoint_security_group_id]
  private_dns_enabled = true

  tags = merge(local.tags, { Name = "${local.vpc_names.west}-execute-api-vpce" })
}

resource "aws_ec2_transit_gateway" "west" {
  provider = aws.west

  description                     = "Transit Gateway for us-west-2 staging network"
  amazon_side_asn                 = local.tgw_asns.west
  auto_accept_shared_attachments  = "disable"
  default_route_table_association = "enable"
  default_route_table_propagation = "enable"
  dns_support                     = "enable"
  vpn_ecmp_support                = "enable"

  tags = merge(local.tags, { Name = local.tgw_names.west })
}

resource "aws_ec2_transit_gateway_vpc_attachment" "west_vpc" {
  provider = aws.west

  subnet_ids         = module.west_network.intra_subnets
  transit_gateway_id = aws_ec2_transit_gateway.west.id
  vpc_id             = module.west_network.vpc_id

  dns_support  = "enable"
  ipv6_support = "disable"

  tags = merge(local.tags, { Name = "${local.environment}-west-vpc-attachment" })
}

module "west_lambda_artifacts" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "5.8.0"

  providers = { aws = aws.west }

  bucket = local.lambda_artifacts_bucket_names.west

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  versioning = { status = "Enabled" }

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = { sse_algorithm = "AES256" }
      bucket_key_enabled                      = true
    }
  }

  attach_deny_insecure_transport_policy = false

  tags = merge(local.tags, { purpose = "lambda-artifacts" })
}

resource "aws_iam_role" "west_apigw_cloudwatch" {
  provider = aws.west

  name               = local.apigw_cloudwatch_role_names.west
  assume_role_policy = data.aws_iam_policy_document.apigw_assume.json
}

resource "aws_iam_role_policy_attachment" "west_apigw_cloudwatch" {
  provider = aws.west

  role       = aws_iam_role.west_apigw_cloudwatch.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}

resource "aws_api_gateway_account" "west" {
  provider = aws.west

  cloudwatch_role_arn = aws_iam_role.west_apigw_cloudwatch.arn
  depends_on          = [aws_iam_role_policy_attachment.west_apigw_cloudwatch]
}

# --- west↔east TGW peering ---

resource "aws_ec2_transit_gateway_peering_attachment" "west_to_east" {
  provider = aws.west

  peer_account_id         = local.aws_account_id
  peer_region             = local.regions.east
  peer_transit_gateway_id = aws_ec2_transit_gateway.east.id
  transit_gateway_id      = aws_ec2_transit_gateway.west.id

  tags = merge(local.tags, { Name = "${local.environment}-west-east-peering" })
}

resource "aws_ec2_transit_gateway_peering_attachment_accepter" "east_accept_west" {
  transit_gateway_attachment_id = aws_ec2_transit_gateway_peering_attachment.west_to_east.id

  tags = merge(local.tags, { Name = "${local.environment}-east-west-peering-accept" })
}

resource "time_sleep" "wait_west_east_peering" {
  depends_on      = [aws_ec2_transit_gateway_peering_attachment_accepter.east_accept_west]
  create_duration = "45s"
}

resource "aws_ec2_transit_gateway_route" "west_to_east" {
  provider = aws.west

  destination_cidr_block         = local.vpc_cidrs.east
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_peering_attachment.west_to_east.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway.west.association_default_route_table_id

  depends_on = [time_sleep.wait_west_east_peering]
}

resource "aws_ec2_transit_gateway_route" "east_to_west" {
  destination_cidr_block         = local.vpc_cidrs.west
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_peering_attachment.west_to_east.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway.east.association_default_route_table_id

  depends_on = [time_sleep.wait_west_east_peering]
}

resource "aws_route" "west_private_to_east" {
  provider = aws.west

  route_table_id         = module.west_network.private_route_table_ids[0]
  destination_cidr_block = local.vpc_cidrs.east
  transit_gateway_id     = aws_ec2_transit_gateway.west.id
}

resource "aws_route" "west_intra_to_east" {
  provider = aws.west

  route_table_id         = module.west_network.intra_route_table_ids[0]
  destination_cidr_block = local.vpc_cidrs.east
  transit_gateway_id     = aws_ec2_transit_gateway.west.id
}

resource "aws_route" "west_db_to_east" {
  provider = aws.west

  route_table_id         = module.west_network.database_route_table_ids[0]
  destination_cidr_block = local.vpc_cidrs.east
  transit_gateway_id     = aws_ec2_transit_gateway.west.id
}

resource "aws_route" "east_private_to_west" {
  route_table_id         = module.east_network.private_route_table_ids[0]
  destination_cidr_block = local.vpc_cidrs.west
  transit_gateway_id     = aws_ec2_transit_gateway.east.id
}

resource "aws_route" "east_intra_to_west" {
  route_table_id         = module.east_network.intra_route_table_ids[0]
  destination_cidr_block = local.vpc_cidrs.west
  transit_gateway_id     = aws_ec2_transit_gateway.east.id
}

# =============================================================================
# 05-east-2-network: East-2 VPC (us-east-2) + TGW + VPCE + peering with east/west
# =============================================================================

module "east_2_network" {
  source = "../modules/private_workload_network"

  providers = { aws = aws.east_2 }

  vpc_name              = local.vpc_names.east_2
  vpc_cidr              = local.vpc_cidrs.east_2
  public_subnet_cidrs   = local.subnet_cidrs.east_2.public
  private_subnet_cidrs  = local.subnet_cidrs.east_2.private
  intra_subnet_cidrs    = local.subnet_cidrs.east_2.intra
  database_subnet_cidrs = local.subnet_cidrs.east_2.database
  single_nat_gateway    = true

  interface_endpoint_security_group_name = "${local.vpc_names.east_2}-vpce-sg"
  flow_logs_log_group_name               = "/aws/vpc/${local.vpc_names.east_2}/flow"

  tags = local.tags
}

resource "aws_vpc_endpoint" "east_2_execute_api" {
  provider = aws.east_2

  vpc_id              = module.east_2_network.vpc_id
  service_name        = "com.amazonaws.${local.regions.east_2}.execute-api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.east_2_network.intra_subnets
  security_group_ids  = [module.east_2_network.interface_endpoint_security_group_id]
  private_dns_enabled = true

  tags = merge(local.tags, { Name = "${local.vpc_names.east_2}-execute-api-vpce" })
}

resource "aws_ec2_transit_gateway" "east_2" {
  provider = aws.east_2

  description                     = "Transit Gateway for us-east-2 staging network"
  amazon_side_asn                 = local.tgw_asns.east_2
  auto_accept_shared_attachments  = "disable"
  default_route_table_association = "enable"
  default_route_table_propagation = "enable"
  dns_support                     = "enable"
  vpn_ecmp_support                = "enable"

  tags = merge(local.tags, { Name = local.tgw_names.east_2 })
}

resource "aws_ec2_transit_gateway_vpc_attachment" "east_2_vpc" {
  provider = aws.east_2

  subnet_ids         = module.east_2_network.intra_subnets
  transit_gateway_id = aws_ec2_transit_gateway.east_2.id
  vpc_id             = module.east_2_network.vpc_id

  dns_support  = "enable"
  ipv6_support = "disable"

  tags = merge(local.tags, { Name = "${local.environment}-east-2-vpc-attachment" })
}

module "east_2_lambda_artifacts" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "5.8.0"

  providers = { aws = aws.east_2 }

  bucket = local.lambda_artifacts_bucket_names.east_2

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  versioning = { status = "Enabled" }

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = { sse_algorithm = "AES256" }
      bucket_key_enabled                      = true
    }
  }

  attach_deny_insecure_transport_policy = false

  tags = merge(local.tags, { purpose = "lambda-artifacts" })
}

resource "aws_iam_role" "east_2_apigw_cloudwatch" {
  provider = aws.east_2

  name               = local.apigw_cloudwatch_role_names.east_2
  assume_role_policy = data.aws_iam_policy_document.apigw_assume.json
}

resource "aws_iam_role_policy_attachment" "east_2_apigw_cloudwatch" {
  provider = aws.east_2

  role       = aws_iam_role.east_2_apigw_cloudwatch.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}

resource "aws_api_gateway_account" "east_2" {
  provider = aws.east_2

  cloudwatch_role_arn = aws_iam_role.east_2_apigw_cloudwatch.arn
  depends_on          = [aws_iam_role_policy_attachment.east_2_apigw_cloudwatch]
}

# --- east-2↔east TGW peering ---

resource "aws_ec2_transit_gateway_peering_attachment" "east_2_to_east" {
  provider = aws.east_2

  peer_account_id         = local.aws_account_id
  peer_region             = local.regions.east
  peer_transit_gateway_id = aws_ec2_transit_gateway.east.id
  transit_gateway_id      = aws_ec2_transit_gateway.east_2.id

  tags = merge(local.tags, { Name = "${local.environment}-east-2-east-peering" })
}

resource "aws_ec2_transit_gateway_peering_attachment_accepter" "east_accept_east_2" {
  transit_gateway_attachment_id = aws_ec2_transit_gateway_peering_attachment.east_2_to_east.id

  tags = merge(local.tags, { Name = "${local.environment}-east-east-2-peering-accept" })
}

# --- east-2↔west TGW peering ---

resource "aws_ec2_transit_gateway_peering_attachment" "east_2_to_west" {
  provider = aws.east_2

  peer_account_id         = local.aws_account_id
  peer_region             = local.regions.west
  peer_transit_gateway_id = aws_ec2_transit_gateway.west.id
  transit_gateway_id      = aws_ec2_transit_gateway.east_2.id

  tags = merge(local.tags, { Name = "${local.environment}-east-2-west-peering" })
}

resource "aws_ec2_transit_gateway_peering_attachment_accepter" "west_accept_east_2" {
  provider = aws.west

  transit_gateway_attachment_id = aws_ec2_transit_gateway_peering_attachment.east_2_to_west.id

  tags = merge(local.tags, { Name = "${local.environment}-west-east-2-peering-accept" })
}

resource "time_sleep" "wait_east_2_peering" {
  depends_on = [
    aws_ec2_transit_gateway_peering_attachment_accepter.east_accept_east_2,
    aws_ec2_transit_gateway_peering_attachment_accepter.west_accept_east_2,
  ]
  create_duration = "45s"
}

# west default route table ID is directly accessible as an attribute — no data source needed
locals {
  west_default_rt_id = aws_ec2_transit_gateway.west.association_default_route_table_id
}

resource "aws_ec2_transit_gateway_route" "east_2_to_east" {
  provider = aws.east_2

  destination_cidr_block         = local.vpc_cidrs.east
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_peering_attachment.east_2_to_east.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway.east_2.association_default_route_table_id

  depends_on = [time_sleep.wait_east_2_peering]
}

resource "aws_ec2_transit_gateway_route" "east_2_to_west" {
  provider = aws.east_2

  destination_cidr_block         = local.vpc_cidrs.west
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_peering_attachment.east_2_to_west.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway.east_2.association_default_route_table_id

  depends_on = [time_sleep.wait_east_2_peering]
}

resource "aws_ec2_transit_gateway_route" "east_to_east_2" {
  destination_cidr_block         = local.vpc_cidrs.east_2
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_peering_attachment.east_2_to_east.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway.east.association_default_route_table_id

  depends_on = [time_sleep.wait_east_2_peering]
}

resource "aws_ec2_transit_gateway_route" "west_to_east_2" {
  provider = aws.west

  destination_cidr_block         = local.vpc_cidrs.east_2
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_peering_attachment.east_2_to_west.id
  transit_gateway_route_table_id = local.west_default_rt_id

  depends_on = [time_sleep.wait_east_2_peering]
}

resource "aws_route" "east_2_private_to_east" {
  provider = aws.east_2

  route_table_id         = module.east_2_network.private_route_table_ids[0]
  destination_cidr_block = local.vpc_cidrs.east
  transit_gateway_id     = aws_ec2_transit_gateway.east_2.id
}

resource "aws_route" "east_2_private_to_west" {
  provider = aws.east_2

  route_table_id         = module.east_2_network.private_route_table_ids[0]
  destination_cidr_block = local.vpc_cidrs.west
  transit_gateway_id     = aws_ec2_transit_gateway.east_2.id
}

resource "aws_route" "east_2_private_to_west_1" {
  provider = aws.east_2

  route_table_id         = module.east_2_network.private_route_table_ids[0]
  destination_cidr_block = local.vpc_cidrs.west_1
  transit_gateway_id     = aws_ec2_transit_gateway.east_2.id
}

resource "aws_route" "east_2_intra_to_east" {
  provider = aws.east_2

  route_table_id         = module.east_2_network.intra_route_table_ids[0]
  destination_cidr_block = local.vpc_cidrs.east
  transit_gateway_id     = aws_ec2_transit_gateway.east_2.id
}

resource "aws_route" "east_2_intra_to_west" {
  provider = aws.east_2

  route_table_id         = module.east_2_network.intra_route_table_ids[0]
  destination_cidr_block = local.vpc_cidrs.west
  transit_gateway_id     = aws_ec2_transit_gateway.east_2.id
}

resource "aws_route" "east_2_intra_to_west_1" {
  provider = aws.east_2

  route_table_id         = module.east_2_network.intra_route_table_ids[0]
  destination_cidr_block = local.vpc_cidrs.west_1
  transit_gateway_id     = aws_ec2_transit_gateway.east_2.id
}

resource "aws_route" "east_2_db_to_east" {
  provider = aws.east_2

  route_table_id         = module.east_2_network.database_route_table_ids[0]
  destination_cidr_block = local.vpc_cidrs.east
  transit_gateway_id     = aws_ec2_transit_gateway.east_2.id
}

resource "aws_route" "east_2_db_to_west" {
  provider = aws.east_2

  route_table_id         = module.east_2_network.database_route_table_ids[0]
  destination_cidr_block = local.vpc_cidrs.west
  transit_gateway_id     = aws_ec2_transit_gateway.east_2.id
}

resource "aws_route" "east_2_db_to_west_1" {
  provider = aws.east_2

  route_table_id         = module.east_2_network.database_route_table_ids[0]
  destination_cidr_block = local.vpc_cidrs.west_1
  transit_gateway_id     = aws_ec2_transit_gateway.east_2.id
}

resource "aws_route" "east_private_to_east_2" {
  route_table_id         = module.east_network.private_route_table_ids[0]
  destination_cidr_block = local.vpc_cidrs.east_2
  transit_gateway_id     = aws_ec2_transit_gateway.east.id
}

resource "aws_route" "east_intra_to_east_2" {
  route_table_id         = module.east_network.intra_route_table_ids[0]
  destination_cidr_block = local.vpc_cidrs.east_2
  transit_gateway_id     = aws_ec2_transit_gateway.east.id
}

resource "aws_route" "east_db_to_east_2" {
  route_table_id         = module.east_network.database_route_table_ids[0]
  destination_cidr_block = local.vpc_cidrs.east_2
  transit_gateway_id     = aws_ec2_transit_gateway.east.id
}

resource "aws_route" "west_hub_to_east_2" {
  provider = aws.west

  route_table_id         = module.west_network.private_route_table_ids[0]
  destination_cidr_block = local.vpc_cidrs.east_2
  transit_gateway_id     = aws_ec2_transit_gateway.west.id
}

# =============================================================================
# 04-west-1-network: West-1 VPC (us-west-1) + TGW + VPCE + full-mesh peering
# =============================================================================

module "west_1_network" {
  source = "../modules/private_workload_network"

  providers = { aws = aws.west_1 }

  vpc_name              = local.vpc_names.west_1
  vpc_cidr              = local.vpc_cidrs.west_1
  public_subnet_cidrs   = local.subnet_cidrs.west_1.public
  private_subnet_cidrs  = local.subnet_cidrs.west_1.private
  intra_subnet_cidrs    = local.subnet_cidrs.west_1.intra
  database_subnet_cidrs = local.subnet_cidrs.west_1.database
  single_nat_gateway    = true

  interface_endpoint_security_group_name = "${local.vpc_names.west_1}-vpce-sg"
  flow_logs_log_group_name               = "/aws/vpc/${local.vpc_names.west_1}/flow"

  tags = local.tags
}

resource "aws_vpc_endpoint" "west_1_execute_api" {
  provider = aws.west_1

  vpc_id              = module.west_1_network.vpc_id
  service_name        = "com.amazonaws.${local.regions.west_1}.execute-api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.west_1_network.intra_subnets
  security_group_ids  = [module.west_1_network.interface_endpoint_security_group_id]
  private_dns_enabled = true

  tags = merge(local.tags, { Name = "${local.vpc_names.west_1}-execute-api-vpce" })
}

resource "aws_ec2_transit_gateway" "west_1" {
  provider = aws.west_1

  description                     = "Transit Gateway for us-west-1 staging network"
  amazon_side_asn                 = local.tgw_asns.west_1
  auto_accept_shared_attachments  = "disable"
  default_route_table_association = "enable"
  default_route_table_propagation = "enable"
  dns_support                     = "enable"
  vpn_ecmp_support                = "enable"

  tags = merge(local.tags, { Name = local.tgw_names.west_1 })
}

resource "aws_ec2_transit_gateway_vpc_attachment" "west_1_vpc" {
  provider = aws.west_1

  subnet_ids         = module.west_1_network.intra_subnets
  transit_gateway_id = aws_ec2_transit_gateway.west_1.id
  vpc_id             = module.west_1_network.vpc_id

  dns_support  = "enable"
  ipv6_support = "disable"

  tags = merge(local.tags, { Name = "${local.environment}-west-1-vpc-attachment" })
}

module "west_1_lambda_artifacts" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "5.8.0"

  providers = { aws = aws.west_1 }

  bucket = local.lambda_artifacts_bucket_names.west_1

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  versioning = { status = "Enabled" }

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = { sse_algorithm = "AES256" }
      bucket_key_enabled                      = true
    }
  }

  attach_deny_insecure_transport_policy = false

  tags = merge(local.tags, { purpose = "lambda-artifacts" })
}

resource "aws_iam_role" "west_1_apigw_cloudwatch" {
  provider = aws.west_1

  name               = local.apigw_cloudwatch_role_names.west_1
  assume_role_policy = data.aws_iam_policy_document.apigw_assume.json
}

resource "aws_iam_role_policy_attachment" "west_1_apigw_cloudwatch" {
  provider = aws.west_1

  role       = aws_iam_role.west_1_apigw_cloudwatch.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}

resource "aws_api_gateway_account" "west_1" {
  provider = aws.west_1

  cloudwatch_role_arn = aws_iam_role.west_1_apigw_cloudwatch.arn
  depends_on          = [aws_iam_role_policy_attachment.west_1_apigw_cloudwatch]
}

# --- west-1↔east peering ---

resource "aws_ec2_transit_gateway_peering_attachment" "west_1_to_east" {
  provider = aws.west_1

  peer_account_id         = local.aws_account_id
  peer_region             = local.regions.east
  peer_transit_gateway_id = aws_ec2_transit_gateway.east.id
  transit_gateway_id      = aws_ec2_transit_gateway.west_1.id

  tags = merge(local.tags, { Name = "${local.environment}-west-1-east-peering" })
}

resource "aws_ec2_transit_gateway_peering_attachment_accepter" "east_accept_west_1" {
  transit_gateway_attachment_id = aws_ec2_transit_gateway_peering_attachment.west_1_to_east.id

  tags = merge(local.tags, { Name = "${local.environment}-east-west-1-peering-accept" })
}

# --- west-1↔west peering ---

resource "aws_ec2_transit_gateway_peering_attachment" "west_1_to_west" {
  provider = aws.west_1

  peer_account_id         = local.aws_account_id
  peer_region             = local.regions.west
  peer_transit_gateway_id = aws_ec2_transit_gateway.west.id
  transit_gateway_id      = aws_ec2_transit_gateway.west_1.id

  tags = merge(local.tags, { Name = "${local.environment}-west-1-west-peering" })
}

resource "aws_ec2_transit_gateway_peering_attachment_accepter" "west_accept_west_1" {
  provider = aws.west

  transit_gateway_attachment_id = aws_ec2_transit_gateway_peering_attachment.west_1_to_west.id

  tags = merge(local.tags, { Name = "${local.environment}-west-west-1-peering-accept" })
}

# --- west-1↔east-2 peering ---

resource "aws_ec2_transit_gateway_peering_attachment" "west_1_to_east_2" {
  provider = aws.west_1

  peer_account_id         = local.aws_account_id
  peer_region             = local.regions.east_2
  peer_transit_gateway_id = aws_ec2_transit_gateway.east_2.id
  transit_gateway_id      = aws_ec2_transit_gateway.west_1.id

  tags = merge(local.tags, { Name = "${local.environment}-west-1-east-2-peering" })
}

resource "aws_ec2_transit_gateway_peering_attachment_accepter" "east_2_accept_west_1" {
  provider = aws.east_2

  transit_gateway_attachment_id = aws_ec2_transit_gateway_peering_attachment.west_1_to_east_2.id

  tags = merge(local.tags, { Name = "${local.environment}-east-2-west-1-peering-accept" })
}

resource "time_sleep" "wait_west_1_peering" {
  depends_on = [
    aws_ec2_transit_gateway_peering_attachment_accepter.east_accept_west_1,
    aws_ec2_transit_gateway_peering_attachment_accepter.west_accept_west_1,
    aws_ec2_transit_gateway_peering_attachment_accepter.east_2_accept_west_1,
  ]
  create_duration = "45s"
}

# --- TGW routes on west-1 toward peers ---

resource "aws_ec2_transit_gateway_route" "west_1_to_east" {
  provider = aws.west_1

  destination_cidr_block         = local.vpc_cidrs.east
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_peering_attachment.west_1_to_east.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway.west_1.association_default_route_table_id

  depends_on = [time_sleep.wait_west_1_peering]
}

resource "aws_ec2_transit_gateway_route" "west_1_to_west" {
  provider = aws.west_1

  destination_cidr_block         = local.vpc_cidrs.west
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_peering_attachment.west_1_to_west.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway.west_1.association_default_route_table_id

  depends_on = [time_sleep.wait_west_1_peering]
}

resource "aws_ec2_transit_gateway_route" "west_1_to_east_2" {
  provider = aws.west_1

  destination_cidr_block         = local.vpc_cidrs.east_2
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_peering_attachment.west_1_to_east_2.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway.west_1.association_default_route_table_id

  depends_on = [time_sleep.wait_west_1_peering]
}

# --- TGW routes on peer hubs back to west-1 ---

resource "aws_ec2_transit_gateway_route" "east_to_west_1" {
  destination_cidr_block         = local.vpc_cidrs.west_1
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_peering_attachment.west_1_to_east.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway.east.association_default_route_table_id

  depends_on = [time_sleep.wait_west_1_peering]
}

resource "aws_ec2_transit_gateway_route" "west_to_west_1" {
  provider = aws.west

  destination_cidr_block         = local.vpc_cidrs.west_1
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_peering_attachment.west_1_to_west.id
  transit_gateway_route_table_id = local.west_default_rt_id

  depends_on = [time_sleep.wait_west_1_peering]
}

resource "aws_ec2_transit_gateway_route" "east_2_to_west_1" {
  provider = aws.east_2

  destination_cidr_block         = local.vpc_cidrs.west_1
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_peering_attachment.west_1_to_east_2.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway.east_2.association_default_route_table_id

  depends_on = [time_sleep.wait_west_1_peering]
}

# --- VPC routes: west-1 local tiers to peer CIDRs ---

resource "aws_route" "west_1_private_to_east" {
  provider = aws.west_1

  route_table_id         = module.west_1_network.private_route_table_ids[0]
  destination_cidr_block = local.vpc_cidrs.east
  transit_gateway_id     = aws_ec2_transit_gateway.west_1.id
}

resource "aws_route" "west_1_private_to_west" {
  provider = aws.west_1

  route_table_id         = module.west_1_network.private_route_table_ids[0]
  destination_cidr_block = local.vpc_cidrs.west
  transit_gateway_id     = aws_ec2_transit_gateway.west_1.id
}

resource "aws_route" "west_1_private_to_east_2" {
  provider = aws.west_1

  route_table_id         = module.west_1_network.private_route_table_ids[0]
  destination_cidr_block = local.vpc_cidrs.east_2
  transit_gateway_id     = aws_ec2_transit_gateway.west_1.id
}

resource "aws_route" "west_1_intra_to_east" {
  provider = aws.west_1

  route_table_id         = module.west_1_network.intra_route_table_ids[0]
  destination_cidr_block = local.vpc_cidrs.east
  transit_gateway_id     = aws_ec2_transit_gateway.west_1.id
}

resource "aws_route" "west_1_intra_to_west" {
  provider = aws.west_1

  route_table_id         = module.west_1_network.intra_route_table_ids[0]
  destination_cidr_block = local.vpc_cidrs.west
  transit_gateway_id     = aws_ec2_transit_gateway.west_1.id
}

resource "aws_route" "west_1_intra_to_east_2" {
  provider = aws.west_1

  route_table_id         = module.west_1_network.intra_route_table_ids[0]
  destination_cidr_block = local.vpc_cidrs.east_2
  transit_gateway_id     = aws_ec2_transit_gateway.west_1.id
}

resource "aws_route" "west_1_db_to_east" {
  provider = aws.west_1

  route_table_id         = module.west_1_network.database_route_table_ids[0]
  destination_cidr_block = local.vpc_cidrs.east
  transit_gateway_id     = aws_ec2_transit_gateway.west_1.id
}

resource "aws_route" "west_1_db_to_west" {
  provider = aws.west_1

  route_table_id         = module.west_1_network.database_route_table_ids[0]
  destination_cidr_block = local.vpc_cidrs.west
  transit_gateway_id     = aws_ec2_transit_gateway.west_1.id
}

resource "aws_route" "west_1_db_to_east_2" {
  provider = aws.west_1

  route_table_id         = module.west_1_network.database_route_table_ids[0]
  destination_cidr_block = local.vpc_cidrs.east_2
  transit_gateway_id     = aws_ec2_transit_gateway.west_1.id
}

resource "aws_route" "east_private_to_west_1" {
  route_table_id         = module.east_network.private_route_table_ids[0]
  destination_cidr_block = local.vpc_cidrs.west_1
  transit_gateway_id     = aws_ec2_transit_gateway.east.id
}

resource "aws_route" "east_intra_to_west_1" {
  route_table_id         = module.east_network.intra_route_table_ids[0]
  destination_cidr_block = local.vpc_cidrs.west_1
  transit_gateway_id     = aws_ec2_transit_gateway.east.id
}

resource "aws_route" "east_db_to_west_1" {
  route_table_id         = module.east_network.database_route_table_ids[0]
  destination_cidr_block = local.vpc_cidrs.west_1
  transit_gateway_id     = aws_ec2_transit_gateway.east.id
}

resource "aws_route" "west_hub_to_west_1" {
  provider = aws.west

  route_table_id         = module.west_network.private_route_table_ids[0]
  destination_cidr_block = local.vpc_cidrs.west_1
  transit_gateway_id     = aws_ec2_transit_gateway.west.id
}

resource "aws_route" "east_2_private_to_west_1_from_west_1" {
  provider = aws.east_2

  route_table_id         = module.east_2_network.private_route_table_ids[0]
  destination_cidr_block = local.vpc_cidrs.west_1
  transit_gateway_id     = aws_ec2_transit_gateway.east_2.id
}

resource "aws_route" "east_2_intra_to_west_1_from_west_1" {
  provider = aws.east_2

  route_table_id         = module.east_2_network.intra_route_table_ids[0]
  destination_cidr_block = local.vpc_cidrs.west_1
  transit_gateway_id     = aws_ec2_transit_gateway.east_2.id
}

resource "aws_route" "east_2_db_to_west_1_from_west_1" {
  provider = aws.east_2

  route_table_id         = module.east_2_network.database_route_table_ids[0]
  destination_cidr_block = local.vpc_cidrs.west_1
  transit_gateway_id     = aws_ec2_transit_gateway.east_2.id
}
