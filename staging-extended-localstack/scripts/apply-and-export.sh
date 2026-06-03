#!/usr/bin/env bash
# Single-state apply against LocalStack, then export plan.json, graph.dot, and terraform.tfstate.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ -f "$ROOT/.env.local" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$ROOT/.env.local"
  set +a
fi

export TF_VAR_environment="${TF_VAR_environment:-staging}"
export TF_VAR_localstack_endpoint="${TF_VAR_localstack_endpoint:-http://localhost:4567}"
export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-test}"
export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-test}"
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"
export AWS_EC2_METADATA_DISABLED="true"
unset AWS_PROFILE

echo ">>> seed ECS optimized AMI SSM parameter"
AMI_VALUE='{"image_id":"ami-0localstackecs2026","image_name":"localstack-ecs-optimized-al2023-arm64","release_version":"2026.05.0"}'
for region in us-east-1 us-west-2 us-west-1 us-east-2; do
  AWS_DEFAULT_REGION="$region" aws \
    --endpoint-url="$TF_VAR_localstack_endpoint" \
    ssm put-parameter \
    --name "/localstack/service/ecs/optimized-ami/amazon-linux-2023/arm64/recommended" \
    --type "String" \
    --value "$AMI_VALUE" \
    --overwrite \
    >/dev/null
done
export AWS_DEFAULT_REGION="us-east-1"

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
