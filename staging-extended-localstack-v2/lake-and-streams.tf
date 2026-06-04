# =============================================================================
# Extended ingestion, Kinesis variants, lake buckets, and fanout queues
# =============================================================================

resource "aws_kms_key" "lake" {
  provider = aws.ingestion

  description             = "${local.environment} multi-region lake key"
  deletion_window_in_days = 7
  enable_key_rotation     = true
  multi_region            = true

  tags = merge(local.extended_common_tags, { lane = "lake" })
}

resource "aws_kms_alias" "lake" {
  provider = aws.ingestion

  name          = "alias/${local.environment}-extended-lake"
  target_key_id = aws_kms_key.lake.key_id
}

resource "aws_s3_bucket" "lake" {
  provider = aws.ingestion

  for_each = local.lake_bucket_families

  bucket = "${local.environment}-${local.accounts.ingestion}-extended-${each.key}"

  tags = merge(local.extended_common_tags, {
    lane   = "lake"
    family = each.key
  })
}

resource "aws_s3_bucket_versioning" "lake" {
  provider = aws.ingestion

  for_each = aws_s3_bucket.lake

  bucket = each.value.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "lake" {
  provider = aws.ingestion

  for_each = aws_s3_bucket.lake

  bucket = each.value.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.lake.arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "lake" {
  provider = aws.ingestion

  for_each = aws_s3_bucket.lake

  bucket                  = each.value.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "lake" {
  provider = aws.ingestion

  for_each = aws_s3_bucket.lake

  bucket = each.value.id

  rule {
    id     = "tier-${each.key}-objects"
    status = "Enabled"

    filter {
      prefix = ""
    }

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 90
      storage_class = "GLACIER"
    }
  }
}

resource "aws_s3_bucket" "lake_replica_west" {
  provider = aws.ingestion_west
  for_each = toset(["raw", "curated", "archive"])

  bucket = "${local.environment}-${local.accounts.ingestion}-extended-${each.key}-replica-west"

  tags = merge(local.extended_common_tags, { lane = "replica", source = each.key })
}

resource "aws_s3_bucket" "lake_replica_west_1" {
  provider = aws.ingestion_west_1
  for_each = toset(["raw", "curated", "archive"])

  bucket = "${local.environment}-${local.accounts.ingestion}-extended-${each.key}-replica-west-1"

  tags = merge(local.extended_common_tags, { lane = "replica", source = each.key })
}

resource "aws_s3_bucket" "lake_replica_east_2" {
  provider = aws.ingestion_east_2
  for_each = toset(["raw", "curated", "archive"])

  bucket = "${local.environment}-${local.accounts.ingestion}-extended-${each.key}-replica-east-2"

  tags = merge(local.extended_common_tags, { lane = "replica", source = each.key })
}

resource "aws_sqs_queue" "ingest_fifo_dlq" {
  provider = aws.ingestion

  name                        = "${local.environment}-extended-ingest-dlq.fifo"
  fifo_queue                  = true
  content_based_deduplication = true
  kms_master_key_id           = aws_kms_key.lake.arn

  tags = merge(local.extended_common_tags, { lane = "sqs", role = "dlq" })
}

resource "aws_sqs_queue" "ingest_fifo" {
  provider = aws.ingestion

  name                        = "${local.environment}-extended-ingest.fifo"
  fifo_queue                  = true
  content_based_deduplication = true
  visibility_timeout_seconds  = 60
  message_retention_seconds   = 1209600
  kms_master_key_id           = aws_kms_key.lake.arn

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.ingest_fifo_dlq.arn
    maxReceiveCount     = 4
  })

  tags = merge(local.extended_common_tags, { lane = "sqs", role = "ingest" })
}

resource "aws_sqs_queue" "priority_standard" {
  provider = aws.ingestion

  name                       = "${local.environment}-extended-priority"
  delay_seconds              = 5
  visibility_timeout_seconds = 90
  kms_master_key_id          = aws_kms_key.lake.arn

  tags = merge(local.extended_common_tags, { lane = "sqs", role = "priority" })
}

resource "aws_sqs_queue" "replay_fifo" {
  provider = aws.ingestion

  name                        = "${local.environment}-extended-replay.fifo"
  fifo_queue                  = true
  content_based_deduplication = true
  visibility_timeout_seconds  = 120
  kms_master_key_id           = aws_kms_key.lake.arn

  tags = merge(local.extended_common_tags, { lane = "sqs", role = "replay" })
}

resource "aws_sqs_queue" "quarantine" {
  provider = aws.ingestion

  name                      = "${local.environment}-extended-quarantine"
  message_retention_seconds = 1209600
  kms_master_key_id         = aws_kms_key.audit.arn

  tags = merge(local.extended_common_tags, { lane = "sqs", role = "quarantine" })
}

resource "aws_sns_topic" "event_bus" {
  provider = aws.ingestion

  name              = "${local.environment}-extended-event-bus"
  kms_master_key_id = aws_kms_key.lake.arn

  tags = merge(local.extended_common_tags, { lane = "sns" })
}

resource "aws_sns_topic" "replay_bus" {
  provider = aws.ingestion

  name                        = "${local.environment}-extended-replay.fifo"
  fifo_topic                  = true
  content_based_deduplication = true
  kms_master_key_id           = aws_kms_key.lake.arn

  tags = merge(local.extended_common_tags, { lane = "sns", role = "replay" })
}

resource "aws_sns_topic_subscription" "priority_queue" {
  provider = aws.ingestion

  topic_arn = aws_sns_topic.event_bus.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.priority_standard.arn
}

resource "aws_sns_topic_subscription" "replay_queue" {
  provider = aws.ingestion

  topic_arn = aws_sns_topic.replay_bus.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.replay_fifo.arn
}

resource "aws_kinesis_stream" "provisioned" {
  provider = aws.ingestion

  name             = "${local.environment}-extended-provisioned"
  shard_count      = 4
  retention_period = 48

  shard_level_metrics = [
    "IncomingBytes",
    "IncomingRecords",
    "IteratorAgeMilliseconds",
    "OutgoingBytes",
    "OutgoingRecords",
  ]

  stream_mode_details {
    stream_mode = "PROVISIONED"
  }

  tags = merge(local.extended_common_tags, { lane = "kinesis", mode = "provisioned" })
}

resource "aws_kinesis_stream" "burst_on_demand" {
  provider = aws.ingestion

  name = "${local.environment}-extended-burst"

  stream_mode_details {
    stream_mode = "ON_DEMAND"
  }

  tags = merge(local.extended_common_tags, { lane = "kinesis", mode = "on-demand" })
}

resource "aws_cloudwatch_log_group" "enhanced_consumer" {
  provider = aws.ingestion

  name              = "/aws/kinesis/${local.environment}-extended-enhanced-consumer"
  retention_in_days = 30
  tags              = merge(local.extended_common_tags, { lane = "kinesis", role = "enhanced-consumer" })
}

data "aws_iam_policy_document" "lambda_extended_assume" {
  provider = aws.ingestion

  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lake_ingestor_lambda" {
  provider = aws.ingestion

  name               = "${local.environment}-extended-lake-ingestor"
  assume_role_policy = data.aws_iam_policy_document.lambda_extended_assume.json

  tags = merge(local.extended_common_tags, { lane = "lambda" })
}

resource "aws_iam_role_policy" "lake_ingestor_lambda" {
  provider = aws.ingestion

  name = "${local.environment}-extended-lake-ingestor"
  role = aws_iam_role.lake_ingestor_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:ChangeMessageVisibility",
          "kinesis:PutRecord",
          "kinesis:PutRecords",
          "sns:Publish",
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

data "archive_file" "lake_ingestor_zip" {
  type        = "zip"
  source_file = "${path.module}/../staging-multi-state/20-east-messaging/src/consumer.py"
  output_path = "${path.module}/build/lake_ingestor.zip"
}

resource "aws_lambda_function" "lake_ingestor" {
  provider = aws.ingestion

  function_name = "${local.environment}-extended-lake-ingestor"
  role          = aws_iam_role.lake_ingestor_lambda.arn
  handler       = "consumer.handler"
  runtime       = "python3.12"
  filename      = data.archive_file.lake_ingestor_zip.output_path
  timeout       = 30

  environment {
    variables = {
      STREAM_NAME    = aws_kinesis_stream.provisioned.name
      TOPIC_ARN      = aws_sns_topic.event_bus.arn
      QUARANTINE_URL = aws_sqs_queue.quarantine.url
    }
  }

  tracing_config {
    mode = "Active"
  }

  tags = merge(local.extended_common_tags, { lane = "lambda", role = "lake-ingestor" })
}

resource "aws_lambda_event_source_mapping" "lake_ingestor" {
  provider = aws.ingestion

  event_source_arn = aws_sqs_queue.ingest_fifo.arn
  function_name    = aws_lambda_function.lake_ingestor.arn
  batch_size       = 1
  enabled          = true
}

resource "aws_iam_role" "stream_processor_lambda" {
  provider = aws.ingestion

  name               = "${local.environment}-extended-stream-processor"
  assume_role_policy = data.aws_iam_policy_document.lambda_extended_assume.json

  tags = merge(local.extended_common_tags, { lane = "lambda" })
}

resource "aws_iam_role_policy" "stream_processor_lambda" {
  provider = aws.ingestion

  name = "${local.environment}-extended-stream-processor"
  role = aws_iam_role.stream_processor_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kinesis:DescribeStream",
          "kinesis:DescribeStreamConsumer",
          "kinesis:GetRecords",
          "kinesis:GetShardIterator",
          "kinesis:SubscribeToShard",
          "s3:PutObject",
          "sqs:SendMessage",
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_lambda_function" "stream_processor" {
  provider = aws.ingestion

  function_name = "${local.environment}-extended-stream-processor"
  role          = aws_iam_role.stream_processor_lambda.arn
  handler       = "consumer.handler"
  runtime       = "python3.12"
  filename      = data.archive_file.lake_ingestor_zip.output_path
  timeout       = 60

  environment {
    variables = {
      CURATED_BUCKET = aws_s3_bucket.lake["curated"].bucket
      PRIORITY_URL   = aws_sqs_queue.priority_standard.url
    }
  }

  tracing_config {
    mode = "Active"
  }

  tags = merge(local.extended_common_tags, { lane = "lambda", role = "stream-processor" })
}

resource "aws_lambda_event_source_mapping" "stream_processor" {
  provider = aws.ingestion

  event_source_arn  = aws_kinesis_stream.provisioned.arn
  function_name     = aws_lambda_function.stream_processor.arn
  starting_position = "LATEST"
  batch_size        = 100
  enabled           = true
}

data "aws_iam_policy_document" "firehose_assume" {
  provider = aws.ingestion

  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["firehose.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "firehose" {
  provider = aws.ingestion

  name               = "${local.environment}-extended-firehose"
  assume_role_policy = data.aws_iam_policy_document.firehose_assume.json

  tags = merge(local.extended_common_tags, { lane = "firehose" })
}

resource "aws_iam_role_policy" "firehose" {
  provider = aws.ingestion

  name = "${local.environment}-extended-firehose"
  role = aws_iam_role.firehose.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:AbortMultipartUpload",
          "s3:GetBucketLocation",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:ListBucketMultipartUploads",
          "s3:PutObject",
          "kinesis:DescribeStream",
          "kinesis:GetRecords",
          "kinesis:GetShardIterator",
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_kinesis_firehose_delivery_stream" "raw_delivery" {
  provider = aws.ingestion

  name        = "${local.environment}-extended-raw"
  destination = "extended_s3"

  kinesis_source_configuration {
    kinesis_stream_arn = aws_kinesis_stream.provisioned.arn
    role_arn           = aws_iam_role.firehose.arn
  }

  extended_s3_configuration {
    bucket_arn          = aws_s3_bucket.lake["raw"].arn
    role_arn            = aws_iam_role.firehose.arn
    prefix              = "raw/region=!{partitionKeyFromQuery:region}/dt=!{timestamp:yyyy-MM-dd}/"
    error_output_prefix = "errors/!{firehose:error-output-type}/dt=!{timestamp:yyyy-MM-dd}/"
    buffering_size      = 64
    buffering_interval  = 300
    compression_format  = "GZIP"

    dynamic_partitioning_configuration {
      enabled = true
    }

    processing_configuration {
      enabled = true
      processors {
        type = "MetadataExtraction"
        parameters {
          parameter_name  = "MetadataExtractionQuery"
          parameter_value = "{region:.region}"
        }
        parameters {
          parameter_name  = "JsonParsingEngine"
          parameter_value = "JQ-1.6"
        }
      }
    }
  }

  tags = merge(local.extended_common_tags, { lane = "firehose" })
}

data "aws_iam_policy_document" "kinesis_analytics_assume" {
  provider = aws.ingestion

  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["kinesisanalytics.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "kinesis_analytics" {
  provider = aws.ingestion

  name               = "${local.environment}-extended-flink"
  assume_role_policy = data.aws_iam_policy_document.kinesis_analytics_assume.json

  tags = merge(local.extended_common_tags, { lane = "flink" })
}

resource "aws_iam_role_policy" "kinesis_analytics" {
  provider = aws.ingestion

  name = "${local.environment}-extended-flink"
  role = aws_iam_role.kinesis_analytics.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kinesis:*",
          "s3:GetObject",
          "s3:PutObject",
          "logs:PutLogEvents",
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_s3_object" "flink_placeholder" {
  provider = aws.ingestion

  bucket  = aws_s3_bucket.lake["spark-script"].id
  key     = "flink/curator.py"
  content = "print('localstack render fixture')\n"

  server_side_encryption = "aws:kms"
  kms_key_id             = aws_kms_key.lake.arn
}

resource "aws_cloudwatch_log_group" "flink_curator" {
  provider = aws.ingestion

  name              = "/aws/kinesis-analytics/${local.environment}-extended-curator"
  retention_in_days = 30
  tags              = merge(local.extended_common_tags, { lane = "flink" })
}
