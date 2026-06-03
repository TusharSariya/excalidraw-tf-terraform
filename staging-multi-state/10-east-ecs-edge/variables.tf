variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "aws_profile" {
  type    = string
  default = "admin"
}

variable "terraform_deploy_role_name" {
  type    = string
  default = "TerraformDeploy"
}

variable "terraform_deploy_role_arn" {
  type    = string
  default = ""
}

variable "aws_account_id" {
  type    = string
  default = ""
}

variable "environment" {
  type    = string
  default = "staging"
}

variable "east_network_state_path" {
  type    = string
  default = "../00-east-network/terraform.tfstate"
}

variable "use_localstack" {
  type        = bool
  description = "Route AWS provider calls for this stack to LocalStack instead of AWS."
  default     = false
}

variable "localstack_endpoint" {
  type        = string
  description = "LocalStack edge endpoint used when use_localstack is true."
  default     = "http://localhost:4566"
}

