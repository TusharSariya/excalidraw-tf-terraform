# =============================================================================
# Management account organization model for LocalStack multi-account diagrams
# =============================================================================

resource "aws_organizations_organization" "this" {
  provider = aws.management

  aws_service_access_principals = [
    "cloudtrail.amazonaws.com",
    "config.amazonaws.com",
    "guardduty.amazonaws.com",
    "securityhub.amazonaws.com",
  ]
  enabled_policy_types = ["SERVICE_CONTROL_POLICY"]
  feature_set          = "ALL"
}

resource "aws_organizations_organizational_unit" "workloads" {
  provider = aws.management

  name      = "Workloads"
  parent_id = aws_organizations_organization.this.roots[0].id
}

resource "aws_organizations_organizational_unit" "data_platform" {
  provider = aws.management

  name      = "DataPlatform"
  parent_id = aws_organizations_organization.this.roots[0].id
}

resource "aws_organizations_organizational_unit" "security" {
  provider = aws.management

  name      = "Security"
  parent_id = aws_organizations_organization.this.roots[0].id
}

resource "aws_organizations_account" "workload" {
  provider = aws.management

  name      = "staging-workload"
  email     = "localstack-workload@example.com"
  parent_id = aws_organizations_organizational_unit.workloads.id
}

resource "aws_organizations_account" "ingestion" {
  provider = aws.management

  name      = "staging-ingestion"
  email     = "localstack-ingestion@example.com"
  parent_id = aws_organizations_organizational_unit.data_platform.id
}

resource "aws_organizations_account" "security" {
  provider = aws.management

  name      = "staging-security"
  email     = "localstack-security@example.com"
  parent_id = aws_organizations_organizational_unit.security.id
}

resource "aws_organizations_delegated_administrator" "securityhub" {
  provider = aws.management

  account_id        = aws_organizations_account.security.id
  service_principal = "securityhub.amazonaws.com"

  depends_on = [aws_organizations_account.security]
}

resource "aws_organizations_delegated_administrator" "guardduty" {
  provider = aws.management

  account_id        = aws_organizations_account.security.id
  service_principal = "guardduty.amazonaws.com"

  depends_on = [aws_organizations_account.security]
}

resource "aws_organizations_policy" "deny_outside_local_regions" {
  provider = aws.management

  name        = "${local.environment}-extended-v2-deny-outside-local-regions"
  description = "Diagram-only SCP: document allowed LocalStack fixture regions."
  type        = "SERVICE_CONTROL_POLICY"
  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "DenyOutsideFixtureRegions"
        Effect   = "Deny"
        Action   = "*"
        Resource = "*"
        Condition = {
          StringNotEquals = {
            "aws:RequestedRegion" = values(local.regions)
          }
        }
      }
    ]
  })

  depends_on = [aws_organizations_organization.this]
}

resource "aws_organizations_policy" "deny_public_s3" {
  provider = aws.management

  name        = "${local.environment}-extended-v2-deny-public-s3"
  description = "Diagram-only SCP: document public S3 guardrail without relying on LocalStack enforcement."
  type        = "SERVICE_CONTROL_POLICY"
  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "DenyPublicBucketPolicy"
        Effect   = "Deny"
        Action   = ["s3:PutBucketPublicAccessBlock", "s3:PutBucketPolicy"]
        Resource = "*"
      }
    ]
  })

  depends_on = [aws_organizations_organization.this]
}

resource "aws_organizations_policy_attachment" "workloads_regions" {
  provider = aws.management

  policy_id = aws_organizations_policy.deny_outside_local_regions.id
  target_id = aws_organizations_organizational_unit.workloads.id
}

resource "aws_organizations_policy_attachment" "data_platform_regions" {
  provider = aws.management

  policy_id = aws_organizations_policy.deny_outside_local_regions.id
  target_id = aws_organizations_organizational_unit.data_platform.id
}

resource "aws_organizations_policy_attachment" "security_s3" {
  provider = aws.management

  policy_id = aws_organizations_policy.deny_public_s3.id
  target_id = aws_organizations_organizational_unit.security.id
}
