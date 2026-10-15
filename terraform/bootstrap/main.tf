provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile

  default_tags {
    tags = {
      environment = var.environment
      project     = var.project_name
      managed-by  = "terraform"
      owner       = "bishal"
      cost-center = "cloud-infrastructure"
    }
  }
}

# AWS-0089 (no access logging), accepted risk: nothing audits object reads on
# this bucket. Server access logs would record them but arrive best-effort,
# hours late; CloudTrail data events (~5 min, billed per event) are the better
# option. Single-user account, so neither is on. Enable CloudTrail data
# events here before any other principal gets access to state.
#
# AWS-0132 (no customer-managed KMS key): SSE-S3 already encrypts state at
# rest. A CMK adds a key policy as a second authorization check, but a single
# principal would hold both the S3 and KMS permissions, so it separates
# nothing. Not worth $1/month. Revisit when the CI role reads state.
#trivy:ignore:AVD-AWS-0089
#trivy:ignore:AVD-AWS-0132
resource "aws_s3_bucket" "this" {
  bucket = var.s3_bucket_name

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    id     = "keep-10-noncurrent-versions"
    status = "Enabled"

    # Apply to every object in the bucket
    filter {}

    # Keep the 10 newest old versions; delete older ones
    # once they've been noncurrent for 30 days
    noncurrent_version_expiration {
      newer_noncurrent_versions = 10
      noncurrent_days           = 30
    }

    # Clean up failed multipart uploads too
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  # Lifecycle rules that touch versions need versioning set first
  depends_on = [aws_s3_bucket_versioning.this]
}


data "aws_iam_policy_document" "deny_insecure_transport" {
  # Deny any request not made over HTTPS
  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    resources = [
      aws_s3_bucket.this.arn,
      "${aws_s3_bucket.this.arn}/*",
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "this" {
  bucket = aws_s3_bucket.this.id
  policy = data.aws_iam_policy_document.deny_insecure_transport.json
}

resource "aws_budgets_budget" "eks_platform_budget" {
  name         = "eks_platform_budget"
  budget_type  = "COST"
  limit_amount = "30"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.subscriber_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.subscriber_email]
  }

  lifecycle {
    prevent_destroy = true
  }
}

