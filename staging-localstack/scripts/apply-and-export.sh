#!/usr/bin/env bash
# Single-state apply against LocalStack, then export plan.json, graph.dot, and terraform.tfstate.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

export TF_VAR_environment="${TF_VAR_environment:-staging}"
export TF_VAR_localstack_endpoint="${TF_VAR_localstack_endpoint:-http://localhost:4566}"
export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-test}"
export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-test}"
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"
export AWS_EC2_METADATA_DISABLED="true"
unset AWS_PROFILE

echo ">>> terraform init"
terraform init -input=false

echo ">>> terraform apply"
terraform apply -auto-approve -input=false

echo ">>> terraform plan + export"
terraform plan -out=plan.bin -input=false
terraform show -json plan.bin > plan.json
terraform graph -plan=plan.bin > graph.dot
rm -f plan.bin

echo ""
echo "Done. Exported: plan.json, graph.dot, terraform.tfstate"
