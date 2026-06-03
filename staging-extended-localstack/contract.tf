locals {
  environment    = var.environment
  aws_account_id = "000000000000"

  regions = {
    east   = "us-east-1"
    west   = "us-west-2"
    west_1 = "us-west-1"
    east_2 = "us-east-2"
  }

  vpc_names = {
    east   = "staging-east"
    west   = "staging-west"
    west_1 = "staging-west-1"
    east_2 = "staging-east-2"
  }

  vpc_cidrs = {
    east   = "10.60.0.0/16"
    west   = "10.70.0.0/16"
    west_1 = "10.80.0.0/16"
    east_2 = "10.65.0.0/16"
  }

  all_peer_cidrs = [
    "10.60.0.0/16",
    "10.70.0.0/16",
    "10.80.0.0/16",
    "10.65.0.0/16",
  ]

  subnet_cidrs = {
    east = {
      public   = ["10.60.0.0/24", "10.60.1.0/24"]
      private  = ["10.60.10.0/24", "10.60.11.0/24"]
      intra    = ["10.60.20.0/24", "10.60.21.0/24"]
      database = ["10.60.30.0/24", "10.60.31.0/24"]
    }
    west = {
      public   = ["10.70.0.0/24", "10.70.1.0/24"]
      private  = ["10.70.10.0/24", "10.70.11.0/24"]
      intra    = ["10.70.20.0/24", "10.70.21.0/24"]
      database = ["10.70.30.0/24", "10.70.31.0/24"]
    }
    west_1 = {
      public   = ["10.80.0.0/24", "10.80.1.0/24"]
      private  = ["10.80.10.0/24", "10.80.11.0/24"]
      intra    = ["10.80.20.0/24", "10.80.21.0/24"]
      database = ["10.80.30.0/24", "10.80.31.0/24"]
    }
    east_2 = {
      public   = ["10.65.0.0/24", "10.65.1.0/24"]
      private  = ["10.65.10.0/24", "10.65.11.0/24"]
      intra    = ["10.65.20.0/24", "10.65.21.0/24"]
      database = ["10.65.30.0/24", "10.65.31.0/24"]
    }
  }

  tgw_asns = {
    east   = 64512
    west   = 64513
    west_1 = 64514
    east_2 = 64515
  }

  api_gateway_names = {
    for i in range(1, 17) : "api-${i}" => "${local.environment}-api-${i}"
  }

  ingress_queue_name = "${local.environment}-events.fifo"
  ingress_dlq_name   = "${local.environment}-events-dlq.fifo"
  egress_queue_name  = "${local.environment}-egress"
  egress_dlq_name    = "${local.environment}-egress-dlq"

  ingress_dlq_messages_alarm_name = "${local.environment}-events-dlq-messages"
  egress_dlq_messages_alarm_name  = "${local.environment}-egress-dlq-messages"

  sqs_consumer_lambda_name = "${local.environment}-sqs-consumer"
  producer_ecs_name        = "${local.environment}-producer"
  egress_ecs_name          = "${local.environment}-egress"

  dynamodb_table_names = {
    "api-1"  = "${local.environment}-api-1"
    "api-5"  = "${local.environment}-api-5"
    "api-10" = "${local.environment}-api-10"
    "api-14" = "${local.environment}-api-14"
  }

  rds_identifiers = {
    "api-2"      = "${local.environment}-api-2"
    "api-6"      = "${local.environment}-api-6"
    "api-9-west" = "${local.environment}-api-9-west"
    "api-16"     = "${local.environment}-api-16"
  }

  aurora_identifiers = {
    "api-3"  = "${local.environment}-api-3"
    "api-7"  = "${local.environment}-api-7"
    "api-11" = "${local.environment}-api-11"
    "api-15" = "${local.environment}-api-15"
  }

  s3_bucket_names = {
    "api-4"       = "${local.environment}-${local.aws_account_id}-api-4"
    "api-8-west"  = "${local.environment}-${local.aws_account_id}-api-8-west"
    "api-12-west" = "${local.environment}-${local.aws_account_id}-api-12-west"
  }

  lambda_artifacts_bucket_names = {
    east   = "${local.environment}-${local.aws_account_id}-east-lambda-artifacts"
    west   = "${local.environment}-${local.aws_account_id}-west-lambda-artifacts"
    west_1 = "${local.environment}-${local.aws_account_id}-west-1-lambda-artifacts"
    east_2 = "${local.environment}-${local.aws_account_id}-east-2-lambda-artifacts"
  }

  apigw_cloudwatch_role_names = {
    east   = "${local.environment}-apigw-cloudwatch-role"
    west   = "${local.environment}-west-apigw-cloudwatch-role"
    west_1 = "${local.environment}-west-1-apigw-cloudwatch-role"
    east_2 = "${local.environment}-east-2-apigw-cloudwatch-role"
  }

  tgw_names = {
    east   = "${local.environment}-east-tgw"
    west   = "${local.environment}-west-tgw"
    west_1 = "${local.environment}-west-1-tgw"
    east_2 = "${local.environment}-east-2-tgw"
  }

  api_stage_name = "v1"

  tags = {
    environment = local.environment
    stack       = "staging-extended-localstack"
    managed_by  = "terraform"
  }
}
