# Who am I? Used to build a globally unique bucket name without hardcoding the account ID.
data "aws_caller_identity" "current" {}

locals {
  # S3 bucket names are global across all AWS accounts, so include the account ID and region.
  bucket_name = "${var.project}-tfstate-${data.aws_caller_identity.current.account_id}-${var.region}"
}

# Customer-managed KMS key: we control the key policy, rotation, and can audit every use in CloudTrail.
resource "aws_kms_key" "tfstate" {
  description             = "Encrypts Terraform state for ${var.project}"
  enable_key_rotation     = true # rotates the key material yearly
  deletion_window_in_days = 7    # lab value; production usually keeps the 30-day default
}

resource "aws_kms_alias" "tfstate" {
  name          = "alias/${var.project}-tfstate" # a friendly name instead of a key ID
  target_key_id = aws_kms_key.tfstate.key_id
}

resource "aws_s3_bucket" "tfstate" {
  bucket = local.bucket_name

  # Safety net: Terraform refuses any plan that would delete this bucket.
  lifecycle {
    prevent_destroy = true
  }
}

# Versioning: every state write keeps the previous version, so a corrupted state can be rolled back.
resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Encrypt every object with our KMS key by default.
resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.tfstate.arn
    }
    bucket_key_enabled = true # fewer KMS calls, so lower cost
  }
}

# State can contain secrets: it must never be public.
resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Deny any request that isn't over HTTPS.
data "aws_iam_policy_document" "tfstate" {
  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.tfstate.arn,
      "${aws_s3_bucket.tfstate.arn}/*",
    ]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  policy = data.aws_iam_policy_document.tfstate.json

  # Apply the public access block first, so the policy is never briefly evaluated without it.
  depends_on = [aws_s3_bucket_public_access_block.tfstate]
}
