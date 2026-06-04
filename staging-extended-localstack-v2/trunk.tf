# =============================================================================
# 10-east-ecs-edge: Public ALB, producer ECS service, egress ECS service
# =============================================================================

resource "aws_s3_object" "egress_worker_script" {
  bucket = module.east_lambda_artifacts.s3_bucket_id
  key    = "egress/egress_worker.py"
  source = "${path.module}/../staging-multi-state/10-east-ecs-edge/src/egress_worker.py"
  etag   = filemd5("${path.module}/../staging-multi-state/10-east-ecs-edge/src/egress_worker.py")

  server_side_encryption = "AES256"
}

resource "aws_security_group" "ecs_service" {
  name        = "${local.environment}-ecs-service-sg"
  description = "Security group for ECS tasks"
  vpc_id      = module.east_network.vpc_id

  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "alb" {
  name        = "${local.environment}-ecs-alb-sg"
  description = "Security group for public ALB"
  vpc_id      = module.east_network.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_service.id]
  }
}

resource "aws_security_group_rule" "ecs_ingress_from_alb" {
  type                     = "ingress"
  from_port                = 8080
  to_port                  = 8080
  protocol                 = "tcp"
  security_group_id        = aws_security_group.ecs_service.id
  source_security_group_id = aws_security_group.alb.id
}

resource "aws_cloudwatch_log_group" "ecs_producer" {
  name              = "/aws/ecs/${local.environment}/producer"
  retention_in_days = 30
}

resource "aws_cloudwatch_log_group" "ecs_egress" {
  name              = "/aws/ecs/${local.environment}/egress"
  retention_in_days = 30
}

data "aws_iam_policy_document" "ecs_task_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_task_execution" {
  name               = "${local.environment}-ecs-task-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume.json
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_managed" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "ecs_task" {
  name               = "${local.environment}-ecs-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume.json
}

data "aws_iam_policy_document" "egress_task" {
  statement {
    effect = "Allow"
    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
      "sqs:ChangeMessageVisibility",
    ]
    resources = [module.egress_queue.queue_arn]
  }

  statement {
    effect    = "Allow"
    actions   = ["kms:Decrypt", "kms:DescribeKey", "kms:GenerateDataKey"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["sqs.${local.regions.east}.amazonaws.com"]
    }
  }

  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
    ]
    resources = ["${module.east_lambda_artifacts.s3_bucket_arn}/egress/egress_worker.py"]
  }
}

resource "aws_iam_role_policy" "egress_task" {
  name   = "${local.environment}-ecs-egress-sqs"
  role   = aws_iam_role.ecs_task.id
  policy = data.aws_iam_policy_document.egress_task.json
}

resource "aws_ecs_cluster" "this" {
  name = "${local.environment}-ecs-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_dynamodb_table" "ecs_config" {
  name         = "${local.environment}-ecs-config"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "config_key"

  attribute {
    name = "config_key"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }
}

resource "aws_lb" "ecs" {
  name               = "${local.environment}-ecs-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = module.east_network.public_subnets
}

resource "aws_lb_target_group" "ecs" {
  name        = "${local.environment}-ecs-tg"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = module.east_network.vpc_id
  target_type = "ip"

  health_check {
    path                = "/health"
    matcher             = "200-399"
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.ecs.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ecs.arn
  }
}

resource "aws_ecs_task_definition" "producer" {
  family                   = "${local.environment}-producer"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name      = "producer"
      image     = "public.ecr.aws/docker/library/busybox:1.36"
      essential = true
      command   = ["sh", "-c", "while true; do sleep 300; done"]
      portMappings = [{
        containerPort = 8080
        hostPort      = 8080
        protocol      = "tcp"
      }]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.ecs_producer.name
          awslogs-region        = local.regions.east
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])
}

resource "aws_ecs_task_definition" "egress" {
  family                   = "${local.environment}-egress"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name      = "egress"
      image     = "public.ecr.aws/docker/library/python:3.12-slim"
      essential = true
      command = [
        "sh",
        "-c",
        "pip install -q boto3 && python -c \"import boto3; s3=boto3.client('s3'); s3.download_file('${module.east_lambda_artifacts.s3_bucket_id}', '${aws_s3_object.egress_worker_script.key}', '/tmp/egress_worker.py')\" && EGRESS_QUEUE_URL=${module.egress_queue.queue_url} python /tmp/egress_worker.py",
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.ecs_egress.name
          awslogs-region        = local.regions.east
          awslogs-stream-prefix = "egress"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "producer" {
  name            = local.producer_ecs_name
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.producer.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    assign_public_ip = false
    security_groups  = [aws_security_group.ecs_service.id]
    subnets          = module.east_network.private_subnets
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.ecs.arn
    container_name   = "producer"
    container_port   = 8080
  }

  depends_on = [aws_lb_listener.http]
}

resource "aws_ecs_service" "egress" {
  name            = local.egress_ecs_name
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.egress.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    assign_public_ip = false
    security_groups  = [aws_security_group.ecs_service.id]
    subnets          = module.east_network.private_subnets
  }
}

# =============================================================================
# 20-east-messaging: Ingress/egress SQS queues + consumer Lambda
# =============================================================================

data "archive_file" "consumer_zip" {
  type        = "zip"
  source_file = "${path.module}/../staging-multi-state/20-east-messaging/src/consumer.py"
  output_path = "${path.module}/build/consumer.zip"
}

resource "aws_s3_object" "consumer_package" {
  bucket = module.east_lambda_artifacts.s3_bucket_id
  key    = "consumer/${data.archive_file.consumer_zip.output_md5}.zip"
  source = data.archive_file.consumer_zip.output_path
  etag   = data.archive_file.consumer_zip.output_md5

  server_side_encryption = "AES256"
}

module "ingress_queue" {
  source = "../modules/encrypted_sqs_queue"

  queue_name = local.ingress_queue_name
  dlq_name   = local.ingress_dlq_name
  create_dlq = true

  dlq_messages_alarm_name     = local.ingress_dlq_messages_alarm_name
  visible_messages_alarm_name = "${local.environment}-events-visible-messages"

  redrive_policy = { maxReceiveCount = 5 }

  tags = merge(local.tags, { component = "messaging-ingress" })
}

module "egress_queue" {
  source = "../modules/encrypted_sqs_queue"

  queue_name = local.egress_queue_name
  dlq_name   = local.egress_dlq_name
  create_dlq = true

  dlq_messages_alarm_name     = local.egress_dlq_messages_alarm_name
  visible_messages_alarm_name = "${local.environment}-egress-visible-messages"

  redrive_policy = { maxReceiveCount = 5 }

  tags = merge(local.tags, { component = "messaging-egress" })
}

module "consumer_lambda" {
  source = "../modules/lambda_service"

  function_name = local.sqs_consumer_lambda_name
  lambda_role   = local.sqs_consumer_lambda_name
  handler       = "consumer.handler"
  runtime       = "python3.12"

  enable_vpc = true

  s3_existing_package = {
    bucket = module.east_lambda_artifacts.s3_bucket_id
    key    = aws_s3_object.consumer_package.key
  }

  vpc_id                         = module.east_network.vpc_id
  vpc_subnet_ids                 = module.east_network.private_subnets
  security_group_name            = "${local.environment}-sqs-consumer-sg"
  vpc_cidr_for_restricted_egress = local.vpc_cidrs.east

  environment_variables = {
    API_1_URL        = module.api1.api_invoke_url
    API_2_URL        = module.api2.api_invoke_url
    API_3_URL        = module.api3.api_invoke_url
    API_4_URL        = module.api4.api_invoke_url
    API_5_URL        = module.api5.api_invoke_url
    EGRESS_QUEUE_URL = module.egress_queue.queue_url
  }

  create_errors_alarm    = true
  errors_alarm_name      = "${local.environment}-sqs-consumer-errors"
  errors_alarm_threshold = 0

  attach_policy_statements = true
  policy_statements = {
    sqs_consume = {
      effect    = "Allow"
      actions   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes", "sqs:ChangeMessageVisibility"]
      resources = [module.ingress_queue.queue_arn]
    }
    sqs_egress_send = {
      effect    = "Allow"
      actions   = ["sqs:SendMessage"]
      resources = [module.egress_queue.queue_arn]
    }
    kms_sqs = {
      effect    = "Allow"
      actions   = ["kms:Decrypt", "kms:DescribeKey", "kms:GenerateDataKey"]
      resources = [module.ingress_queue.kms_key_arn, module.egress_queue.kms_key_arn]
    }
    execute_api = {
      effect  = "Allow"
      actions = ["execute-api:Invoke"]
      resources = [
        "${module.api1.api_execution_arn}/*",
        "${module.api2.api_execution_arn}/*",
        "${module.api3.api_execution_arn}/*",
        "${module.api4.api_execution_arn}/*",
        "${module.api5.api_execution_arn}/*",
      ]
    }
  }
}

resource "aws_lambda_event_source_mapping" "queue_consumer" {
  event_source_arn = module.ingress_queue.queue_arn
  function_name    = module.consumer_lambda.lambda_function_arn
  batch_size       = 1
  enabled          = true

  function_response_types = ["ReportBatchItemFailures"]
}

data "aws_iam_policy_document" "ecs_send_message" {
  statement {
    effect    = "Allow"
    actions   = ["sqs:SendMessage"]
    resources = [module.ingress_queue.queue_arn]
  }

  statement {
    effect    = "Allow"
    actions   = ["kms:Decrypt", "kms:DescribeKey", "kms:GenerateDataKey"]
    resources = [module.ingress_queue.kms_key_arn]
  }
}

resource "aws_iam_policy" "ecs_send_message" {
  name   = "${local.environment}-ecs-send-sqs"
  policy = data.aws_iam_policy_document.ecs_send_message.json
}

resource "aws_iam_role_policy_attachment" "ecs_send_message" {
  role       = aws_iam_role.ecs_task.name
  policy_arn = aws_iam_policy.ecs_send_message.arn
}
