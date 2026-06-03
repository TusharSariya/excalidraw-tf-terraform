terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.5"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.13"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

locals {
  localstack_ep = var.localstack_endpoint
}

provider "aws" {
  region = "us-east-1"

  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_region_validation      = true
  s3_use_path_style           = true

  endpoints {
    apigateway               = local.localstack_ep
    applicationautoscaling   = local.localstack_ep
    autoscaling              = local.localstack_ep
    cloudwatch               = local.localstack_ep
    cloudwatchlogs           = local.localstack_ep
    dynamodb                 = local.localstack_ep
    ec2                      = local.localstack_ep
    ecr                      = local.localstack_ep
    ecs                      = local.localstack_ep
    elasticloadbalancing     = local.localstack_ep
    iam                      = local.localstack_ep
    kms                      = local.localstack_ep
    lambda                   = local.localstack_ep
    rds                      = local.localstack_ep
    resourcegroupstaggingapi = local.localstack_ep
    s3                       = local.localstack_ep
    s3control                = local.localstack_ep
    secretsmanager           = local.localstack_ep
    sqs                      = local.localstack_ep
    ssm                      = local.localstack_ep
    sts                      = local.localstack_ep
  }

  default_tags {
    tags = {
      environment = var.environment
      stack       = "staging-localstack"
      managed_by  = "terraform"
    }
  }
}

provider "aws" {
  alias  = "west"
  region = "us-west-2"

  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_region_validation      = true
  s3_use_path_style           = true

  endpoints {
    apigateway               = local.localstack_ep
    applicationautoscaling   = local.localstack_ep
    autoscaling              = local.localstack_ep
    cloudwatch               = local.localstack_ep
    cloudwatchlogs           = local.localstack_ep
    dynamodb                 = local.localstack_ep
    ec2                      = local.localstack_ep
    ecr                      = local.localstack_ep
    ecs                      = local.localstack_ep
    elasticloadbalancing     = local.localstack_ep
    iam                      = local.localstack_ep
    kms                      = local.localstack_ep
    lambda                   = local.localstack_ep
    rds                      = local.localstack_ep
    resourcegroupstaggingapi = local.localstack_ep
    s3                       = local.localstack_ep
    s3control                = local.localstack_ep
    secretsmanager           = local.localstack_ep
    sqs                      = local.localstack_ep
    ssm                      = local.localstack_ep
    sts                      = local.localstack_ep
  }

  default_tags {
    tags = {
      environment = var.environment
      stack       = "staging-localstack"
      managed_by  = "terraform"
    }
  }
}

provider "aws" {
  alias  = "west_1"
  region = "us-west-1"

  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_region_validation      = true
  s3_use_path_style           = true

  endpoints {
    apigateway               = local.localstack_ep
    applicationautoscaling   = local.localstack_ep
    autoscaling              = local.localstack_ep
    cloudwatch               = local.localstack_ep
    cloudwatchlogs           = local.localstack_ep
    dynamodb                 = local.localstack_ep
    ec2                      = local.localstack_ep
    ecr                      = local.localstack_ep
    ecs                      = local.localstack_ep
    elasticloadbalancing     = local.localstack_ep
    iam                      = local.localstack_ep
    kms                      = local.localstack_ep
    lambda                   = local.localstack_ep
    rds                      = local.localstack_ep
    resourcegroupstaggingapi = local.localstack_ep
    s3                       = local.localstack_ep
    s3control                = local.localstack_ep
    secretsmanager           = local.localstack_ep
    sqs                      = local.localstack_ep
    ssm                      = local.localstack_ep
    sts                      = local.localstack_ep
  }

  default_tags {
    tags = {
      environment = var.environment
      stack       = "staging-localstack"
      managed_by  = "terraform"
    }
  }
}

provider "aws" {
  alias  = "east_2"
  region = "us-east-2"

  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_region_validation      = true
  s3_use_path_style           = true

  endpoints {
    apigateway               = local.localstack_ep
    applicationautoscaling   = local.localstack_ep
    autoscaling              = local.localstack_ep
    cloudwatch               = local.localstack_ep
    cloudwatchlogs           = local.localstack_ep
    dynamodb                 = local.localstack_ep
    ec2                      = local.localstack_ep
    ecr                      = local.localstack_ep
    ecs                      = local.localstack_ep
    elasticloadbalancing     = local.localstack_ep
    iam                      = local.localstack_ep
    kms                      = local.localstack_ep
    lambda                   = local.localstack_ep
    rds                      = local.localstack_ep
    resourcegroupstaggingapi = local.localstack_ep
    s3                       = local.localstack_ep
    s3control                = local.localstack_ep
    secretsmanager           = local.localstack_ep
    sqs                      = local.localstack_ep
    ssm                      = local.localstack_ep
    sts                      = local.localstack_ep
  }

  default_tags {
    tags = {
      environment = var.environment
      stack       = "staging-localstack"
      managed_by  = "terraform"
    }
  }
}
