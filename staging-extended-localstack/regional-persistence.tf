# =============================================================================
# Scheduled lake curation, regional writer queues/lambdas, and persistence stores
# =============================================================================

data "aws_iam_policy_document" "states_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["states.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "events_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "glue_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["glue.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "glue" {
  name               = "${local.environment}-extended-glue"
  assume_role_policy = data.aws_iam_policy_document.glue_assume.json

  tags = merge(local.extended_common_tags, { lane = "glue" })
}

resource "aws_iam_role_policy" "glue" {
  name = "${local.environment}-extended-glue"
  role = aws_iam_role.glue.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket",
          "glue:*",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_glue_catalog_database" "lake" {
  catalog_id = "000000000000"
  name       = "${local.environment}_extended_lake"
}

resource "aws_glue_crawler" "raw" {
  name          = "${local.environment}-extended-raw-crawler"
  database_name = aws_glue_catalog_database.lake.name
  role          = aws_iam_role.glue.arn

  s3_target {
    path = "s3://${aws_s3_bucket.lake["raw"].bucket}/raw/"
  }

  tags = merge(local.extended_common_tags, { lane = "glue", role = "crawler" })
}

resource "aws_glue_job" "curate" {
  name     = "${local.environment}-extended-curate"
  role_arn = aws_iam_role.glue.arn

  command {
    name            = "glueetl"
    script_location = "s3://${aws_s3_bucket.lake["spark-script"].bucket}/${aws_s3_object.flink_placeholder.key}"
    python_version  = "3"
  }

  default_arguments = {
    "--RAW_BUCKET"     = aws_s3_bucket.lake["raw"].bucket
    "--CURATED_BUCKET" = aws_s3_bucket.lake["curated"].bucket
    "--ARCHIVE_BUCKET" = aws_s3_bucket.lake["archive"].bucket
  }

  glue_version      = "4.0"
  number_of_workers = 2
  worker_type       = "G.1X"

  tags = merge(local.extended_common_tags, { lane = "glue", role = "job" })
}

resource "aws_iam_role" "state_machine" {
  name               = "${local.environment}-extended-state-machine"
  assume_role_policy = data.aws_iam_policy_document.states_assume.json

  tags = merge(local.extended_common_tags, { lane = "states" })
}

resource "aws_iam_role_policy" "state_machine" {
  name = "${local.environment}-extended-state-machine"
  role = aws_iam_role.state_machine.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["glue:StartCrawler", "glue:StartJobRun", "glue:GetJobRun", "sqs:SendMessage", "logs:*"]
        Resource = "*"
      }
    ]
  })
}

resource "aws_sfn_state_machine" "lake_curation" {
  name     = "${local.environment}-extended-lake-curation"
  role_arn = aws_iam_role.state_machine.arn

  definition = jsonencode({
    Comment = "Render-first extended lake curation workflow"
    StartAt = "StartCrawler"
    States = {
      StartCrawler = {
        Type     = "Task"
        Resource = "arn:aws:states:::aws-sdk:glue:startCrawler"
        Parameters = {
          Name = aws_glue_crawler.raw.name
        }
        Next = "RunCurator"
      }
      RunCurator = {
        Type     = "Task"
        Resource = "arn:aws:states:::glue:startJobRun.sync"
        Parameters = {
          JobName = aws_glue_job.curate.name
        }
        End = true
      }
    }
  })

  tracing_configuration {
    enabled = true
  }

  tags = merge(local.extended_common_tags, { lane = "states" })
}

resource "aws_iam_role" "eventbridge" {
  name               = "${local.environment}-extended-eventbridge"
  assume_role_policy = data.aws_iam_policy_document.events_assume.json

  tags = merge(local.extended_common_tags, { lane = "events" })
}

resource "aws_iam_role_policy" "eventbridge" {
  name = "${local.environment}-extended-eventbridge"
  role = aws_iam_role.eventbridge.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["states:StartExecution"]
        Resource = aws_sfn_state_machine.lake_curation.arn
      }
    ]
  })
}

resource "aws_cloudwatch_event_rule" "lake_curation" {
  name                = "${local.environment}-extended-lake-curation"
  description         = "Periodic extended lake curation"
  schedule_expression = "rate(15 minutes)"

  tags = merge(local.extended_common_tags, { lane = "events" })
}

resource "aws_cloudwatch_event_target" "lake_curation" {
  rule     = aws_cloudwatch_event_rule.lake_curation.name
  arn      = aws_sfn_state_machine.lake_curation.arn
  role_arn = aws_iam_role.eventbridge.arn
}

resource "aws_sqs_queue" "regional_writer_east" {
  name              = "${local.environment}-extended-writer-east"
  kms_master_key_id = aws_kms_key.lake.arn

  tags = merge(local.extended_common_tags, { lane = "regional-writer", region = local.regions.east })
}

resource "aws_sqs_queue" "regional_writer_west" {
  provider = aws.west

  name              = "${local.environment}-extended-writer-west"
  kms_master_key_id = aws_kms_key.lake.arn

  tags = merge(local.extended_common_tags, { lane = "regional-writer", region = local.regions.west })
}

resource "aws_sqs_queue" "regional_writer_west_1" {
  provider = aws.west_1

  name              = "${local.environment}-extended-writer-west-1"
  kms_master_key_id = aws_kms_key.lake.arn

  tags = merge(local.extended_common_tags, { lane = "regional-writer", region = local.regions.west_1 })
}

resource "aws_sqs_queue" "regional_writer_east_2" {
  provider = aws.east_2

  name              = "${local.environment}-extended-writer-east-2"
  kms_master_key_id = aws_kms_key.lake.arn

  tags = merge(local.extended_common_tags, { lane = "regional-writer", region = local.regions.east_2 })
}

resource "aws_dynamodb_table" "regional_events_east" {
  name         = "${local.environment}-extended-events-east"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "event_id"

  attribute {
    name = "event_id"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  replica {
    region_name = local.regions.west
  }

  replica {
    region_name = local.regions.west_1
  }

  replica {
    region_name = local.regions.east_2
  }

  tags = merge(local.extended_common_tags, { lane = "dynamodb-global" })
}

resource "aws_dynamodb_table" "regional_events_west" {
  provider = aws.west

  name         = "${local.environment}-extended-events-west-explicit"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "event_id"

  attribute {
    name = "event_id"
    type = "S"
  }

  tags = merge(local.extended_common_tags, { lane = "dynamodb-regional", region = local.regions.west })
}

module "regional_rds_east" {
  source = "../modules/rds_postgres_micro"

  identifier                 = "${local.environment}-extended-rds-east"
  environment                = local.environment
  vpc_id                     = module.east_network.vpc_id
  database_subnet_ids        = module.east_network.database_subnets
  allowed_security_group_ids = [aws_security_group.eks_to_regional_writers.id]
  peer_vpc_cidr_blocks       = [local.vpc_cidrs.east]
  db_name                    = "extendedeast"
  tags                       = merge(local.extended_common_tags, { lane = "regional-rds", region = local.regions.east })
}

module "regional_rds_west" {
  source = "../modules/rds_postgres_micro"

  providers = { aws = aws.west }

  identifier                 = "${local.environment}-extended-rds-west"
  environment                = local.environment
  vpc_id                     = module.west_network.vpc_id
  database_subnet_ids        = module.west_network.database_subnets
  allowed_security_group_ids = []
  peer_vpc_cidr_blocks       = [local.vpc_cidrs.west, local.vpc_cidrs.east]
  db_name                    = "extendedwest"
  tags                       = merge(local.extended_common_tags, { lane = "regional-rds", region = local.regions.west })
}

module "regional_aurora_east_2" {
  source = "../modules/aurora_serverless_v2_micro"

  providers = { aws = aws.east_2 }

  identifier                 = "${local.environment}-extended-aurora-east-2"
  environment                = local.environment
  vpc_id                     = module.east_2_network.vpc_id
  database_subnet_ids        = module.east_2_network.database_subnets
  allowed_security_group_ids = []
  peer_vpc_cidr_blocks       = [local.vpc_cidrs.east_2, local.vpc_cidrs.east]
  db_name                    = "extendedeast2"
  tags                       = merge(local.extended_common_tags, { lane = "regional-aurora", region = local.regions.east_2 })
}

resource "aws_lambda_function" "regional_writer_east" {
  function_name = "${local.environment}-extended-writer-east"
  role          = aws_iam_role.stream_processor_lambda.arn
  handler       = "consumer.handler"
  runtime       = "python3.12"
  filename      = data.archive_file.lake_ingestor_zip.output_path
  timeout       = 30

  environment {
    variables = {
      TARGET_TABLE = aws_dynamodb_table.regional_events_east.name
      TARGET_DB    = module.regional_rds_east.endpoint
    }
  }

  tags = merge(local.extended_common_tags, { lane = "regional-writer", region = local.regions.east })
}

resource "aws_lambda_event_source_mapping" "regional_writer_east" {
  event_source_arn = aws_sqs_queue.regional_writer_east.arn
  function_name    = aws_lambda_function.regional_writer_east.arn
  batch_size       = 10
  enabled          = true
}
