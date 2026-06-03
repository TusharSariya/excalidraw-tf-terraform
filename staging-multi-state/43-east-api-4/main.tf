terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.5"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

locals {
  terraform_deploy_role_arn = trimspace(var.terraform_deploy_role_arn) != "" ? trimspace(var.terraform_deploy_role_arn) : "arn:aws:iam::${var.aws_account_id}:role/${var.terraform_deploy_role_name}"

  tags = {
    environment = var.environment
    stack       = "staging-multi-state"
    state       = "43-east-api-4"
    managed_by  = "terraform"
  }
}

provider "aws" {
  region  = var.aws_region
  profile = var.use_localstack ? null : var.aws_profile


  access_key                  = var.use_localstack ? "test" : null
  secret_key                  = var.use_localstack ? "test" : null
  skip_credentials_validation = var.use_localstack
  skip_metadata_api_check     = var.use_localstack
  skip_region_validation      = var.use_localstack
  s3_use_path_style           = var.use_localstack

  endpoints {
    apigateway               = var.use_localstack ? var.localstack_endpoint : null
    applicationautoscaling   = var.use_localstack ? var.localstack_endpoint : null
    autoscaling              = var.use_localstack ? var.localstack_endpoint : null
    cloudwatch               = var.use_localstack ? var.localstack_endpoint : null
    cloudwatchlogs           = var.use_localstack ? var.localstack_endpoint : null
    dynamodb                 = var.use_localstack ? var.localstack_endpoint : null
    ec2                      = var.use_localstack ? var.localstack_endpoint : null
    ecr                      = var.use_localstack ? var.localstack_endpoint : null
    ecs                      = var.use_localstack ? var.localstack_endpoint : null
    elasticloadbalancing     = var.use_localstack ? var.localstack_endpoint : null
    iam                      = var.use_localstack ? var.localstack_endpoint : null
    kms                      = var.use_localstack ? var.localstack_endpoint : null
    lambda                   = var.use_localstack ? var.localstack_endpoint : null
    rds                      = var.use_localstack ? var.localstack_endpoint : null
    resourcegroupstaggingapi = var.use_localstack ? var.localstack_endpoint : null
    s3                       = var.use_localstack ? var.localstack_endpoint : null
    secretsmanager           = var.use_localstack ? var.localstack_endpoint : null
    sqs                      = var.use_localstack ? var.localstack_endpoint : null
    ssm                      = var.use_localstack ? var.localstack_endpoint : null
    sts                      = var.use_localstack ? var.localstack_endpoint : null
  }
  assume_role {
    role_arn     = local.terraform_deploy_role_arn
    session_name = "terraform-staging-east-api-4"
  }

  default_tags {
    tags = local.tags
  }
}

check "assume_role_configured" {
  assert {
    condition     = trimspace(var.terraform_deploy_role_arn) != "" || can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "Set terraform_deploy_role_arn or a 12-digit aws_account_id."
  }
}

data "terraform_remote_state" "east_network" {
  backend = "local"
  config = {
    path = var.east_network_state_path
  }
}

data "terraform_remote_state" "east_datastores" {
  backend = "local"
  config = {
    path = var.east_datastores_state_path
  }
}

data "terraform_remote_state" "east_api6" {
  backend = "local"
  config = {
    path = var.east_api6_state_path
  }
}

module "api" {
  source = "../modules/private_api_lambda"

  name                = "api-4"
  environment         = var.environment
  aws_region          = var.aws_region
  aws_account_id      = data.terraform_remote_state.east_network.outputs.aws_account_id
  vpc_id              = data.terraform_remote_state.east_network.outputs.vpc_id
  vpc_cidr            = data.terraform_remote_state.east_network.outputs.vpc_cidr
  private_subnet_ids  = data.terraform_remote_state.east_network.outputs.private_subnet_ids
  execute_api_vpce_id = data.terraform_remote_state.east_network.outputs.execute_api_vpce_id

  artifact_bucket_id    = data.terraform_remote_state.east_network.outputs.lambda_artifacts_bucket_id
  lambda_source_file    = "${path.module}/../shared/api_handler.py"
  openapi_template_path = "${path.module}/openapi.tftpl"
  stage_name            = "v1"
  s3_bucket_arns        = [data.terraform_remote_state.east_datastores.outputs.api4_bucket_arn]
  downstream_api_urls = {
    api6 = data.terraform_remote_state.east_api6.outputs.api_invoke_url
  }
  tags = local.tags
}
