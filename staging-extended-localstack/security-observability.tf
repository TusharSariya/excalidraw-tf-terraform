# =============================================================================
# Security, audit, VPC endpoints, and observability
# =============================================================================

data "aws_iam_policy_document" "cloudtrail_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "config_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }
  }
}

resource "aws_cloudtrail" "organization" {
  name                          = "${local.environment}-extended-org-trail"
  s3_bucket_name                = aws_s3_bucket.lake["audit"].bucket
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true
  kms_key_id                    = aws_kms_key.audit.arn

  event_selector {
    read_write_type           = "All"
    include_management_events = true

    data_resource {
      type   = "AWS::S3::Object"
      values = ["${aws_s3_bucket.lake["raw"].arn}/", "${aws_s3_bucket.lake["curated"].arn}/"]
    }
  }

  tags = merge(local.extended_common_tags, { lane = "cloudtrail" })
}

resource "aws_iam_role" "config" {
  name               = "${local.environment}-extended-config"
  assume_role_policy = data.aws_iam_policy_document.config_assume.json

  tags = merge(local.extended_common_tags, { lane = "config" })
}

resource "aws_iam_role_policy_attachment" "config" {
  role       = aws_iam_role.config.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWS_ConfigRole"
}

resource "aws_config_configuration_recorder" "this" {
  name     = "${local.environment}-extended-recorder"
  role_arn = aws_iam_role.config.arn

  recording_group {
    all_supported                 = true
    include_global_resource_types = true
  }
}

resource "aws_config_delivery_channel" "this" {
  name           = "${local.environment}-extended-delivery"
  s3_bucket_name = aws_s3_bucket.lake["audit"].bucket

  snapshot_delivery_properties {
    delivery_frequency = "Six_Hours"
  }

  depends_on = [aws_config_configuration_recorder.this]
}

resource "aws_config_config_rule" "s3_encrypted" {
  name = "${local.environment}-extended-s3-encrypted"

  source {
    owner             = "AWS"
    source_identifier = "S3_BUCKET_SERVER_SIDE_ENCRYPTION_ENABLED"
  }

  depends_on = [aws_config_configuration_recorder.this]
}

resource "aws_cloudwatch_log_group" "security_hub_findings" {
  name              = "/aws/securityhub/${local.environment}-extended-findings"
  retention_in_days = 90
  tags              = merge(local.extended_common_tags, { lane = "securityhub" })
}

resource "aws_cloudwatch_log_group" "guardduty_findings" {
  name              = "/aws/guardduty/${local.environment}-extended-findings"
  retention_in_days = 90
  tags              = merge(local.extended_common_tags, { lane = "guardduty" })
}

resource "aws_wafv2_web_acl" "api" {
  name  = "${local.environment}-extended-api"
  scope = "REGIONAL"

  default_action {
    allow {}
  }

  rule {
    name     = "rate-limit"
    priority = 1

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = 2000
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.environment}-extended-rate-limit"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${local.environment}-extended-api"
    sampled_requests_enabled   = true
  }

  tags = merge(local.extended_common_tags, { lane = "waf" })
}

resource "aws_wafv2_web_acl_association" "ecs_alb" {
  resource_arn = aws_lb.ecs.arn
  web_acl_arn  = aws_wafv2_web_acl.api.arn
}

resource "aws_vpc_endpoint" "east_extended_interface" {
  for_each = toset([
    "sqs",
    "sns",
    "kinesis-streams",
    "firehose",
    "glue",
    "logs",
    "sts",
    "ecr.api",
    "ecr.dkr",
    "secretsmanager",
  ])

  vpc_id              = module.east_network.vpc_id
  service_name        = "com.amazonaws.${local.regions.east}.${each.key}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.east_network.intra_subnets
  security_group_ids  = [module.east_network.interface_endpoint_security_group_id]
  private_dns_enabled = true

  tags = merge(local.extended_common_tags, { lane = "vpce", service = each.key })
}

resource "aws_vpc_endpoint" "east_s3_gateway" {
  vpc_id            = module.east_network.vpc_id
  service_name      = "com.amazonaws.${local.regions.east}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = module.east_network.private_route_table_ids

  tags = merge(local.extended_common_tags, { lane = "vpce", service = "s3" })
}

resource "aws_sns_topic" "ops" {
  name              = "${local.environment}-extended-ops"
  kms_master_key_id = aws_kms_key.audit.arn

  tags = merge(local.extended_common_tags, { lane = "ops" })
}

resource "aws_cloudwatch_metric_alarm" "ingest_dlq_depth" {
  alarm_name          = "${local.environment}-extended-ingest-dlq-depth"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Maximum"
  threshold           = 0
  alarm_actions       = [aws_sns_topic.ops.arn]

  dimensions = {
    QueueName = aws_sqs_queue.ingest_fifo_dlq.name
  }

  tags = merge(local.extended_common_tags, { lane = "alarm", target = "ingest-dlq" })
}

resource "aws_cloudwatch_metric_alarm" "kinesis_iterator_age" {
  alarm_name          = "${local.environment}-extended-kinesis-iterator-age"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "GetRecords.IteratorAgeMilliseconds"
  namespace           = "AWS/Kinesis"
  period              = 60
  statistic           = "Maximum"
  threshold           = 300000
  alarm_actions       = [aws_sns_topic.ops.arn]

  dimensions = {
    StreamName = aws_kinesis_stream.provisioned.name
  }

  tags = merge(local.extended_common_tags, { lane = "alarm", target = "kinesis" })
}

resource "aws_cloudwatch_metric_alarm" "firehose_failures" {
  alarm_name          = "${local.environment}-extended-firehose-failures"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "DeliveryToS3.DataFreshness"
  namespace           = "AWS/Firehose"
  period              = 300
  statistic           = "Maximum"
  threshold           = 900
  alarm_actions       = [aws_sns_topic.ops.arn]

  dimensions = {
    DeliveryStreamName = aws_kinesis_firehose_delivery_stream.raw_delivery.name
  }

  tags = merge(local.extended_common_tags, { lane = "alarm", target = "firehose" })
}

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${local.environment}-extended-lambda-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  alarm_actions       = [aws_sns_topic.ops.arn]

  dimensions = {
    FunctionName = aws_lambda_function.stream_processor.function_name
  }

  tags = merge(local.extended_common_tags, { lane = "alarm", target = "lambda" })
}

resource "aws_cloudwatch_metric_alarm" "states_failures" {
  alarm_name          = "${local.environment}-extended-states-failures"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ExecutionsFailed"
  namespace           = "AWS/States"
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  alarm_actions       = [aws_sns_topic.ops.arn]

  dimensions = {
    StateMachineArn = aws_sfn_state_machine.lake_curation.arn
  }

  tags = merge(local.extended_common_tags, { lane = "alarm", target = "states" })
}

resource "aws_cloudwatch_metric_alarm" "glue_failures" {
  alarm_name          = "${local.environment}-extended-glue-failures"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "glue.driver.aggregate.numFailedTasks"
  namespace           = "Glue"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_actions       = [aws_sns_topic.ops.arn]

  dimensions = {
    JobName = aws_glue_job.curate.name
  }

  tags = merge(local.extended_common_tags, { lane = "alarm", target = "glue" })
}

resource "aws_cloudwatch_metric_alarm" "eks_node_health" {
  alarm_name          = "${local.environment}-extended-eks-node-health"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "cluster_node_count"
  namespace           = "ContainerInsights"
  period              = 60
  statistic           = "Average"
  threshold           = 1
  alarm_actions       = [aws_sns_topic.ops.arn]

  dimensions = {
    ClusterName = aws_eks_cluster.stream_processors.name
  }

  tags = merge(local.extended_common_tags, { lane = "alarm", target = "eks" })
}

resource "aws_cloudwatch_dashboard" "extended" {
  dashboard_name = "${local.environment}-extended-platform"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 8
        height = 6
        properties = {
          title   = "Ingestion queues"
          region  = local.regions.east
          metrics = [["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", aws_sqs_queue.ingest_fifo.name]]
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 0
        width  = 8
        height = 6
        properties = {
          title   = "Kinesis iterator age"
          region  = local.regions.east
          metrics = [["AWS/Kinesis", "GetRecords.IteratorAgeMilliseconds", "StreamName", aws_kinesis_stream.provisioned.name]]
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 0
        width  = 8
        height = 6
        properties = {
          title   = "Regional writers"
          region  = local.regions.east
          metrics = [["AWS/Lambda", "Errors", "FunctionName", aws_lambda_function.regional_writer_east.function_name]]
        }
      }
    ]
  })
}
