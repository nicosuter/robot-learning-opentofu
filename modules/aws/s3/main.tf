# KMS key for ML data encryption
resource "aws_kms_key" "ml_data" {
  description             = "KMS key for ML data bucket: ${var.bucket_name}"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  tags                    = merge(var.tags, { Name = "${var.bucket_name}-kms" })
}

resource "aws_kms_alias" "ml_data" {
  name          = "alias/${var.bucket_name}"
  target_key_id = aws_kms_key.ml_data.id
}

# ML data bucket — single bucket, prefix-separated:
#   training-data/   raw and preprocessed datasets
#   checkpoints/     ephemeral training checkpoints
#   models/          finalised model artefacts
resource "aws_s3_bucket" "ml_data" {
  bucket        = var.bucket_name
  force_destroy = false
  tags          = merge(var.tags, { Name = var.bucket_name })
}

resource "aws_s3_bucket_versioning" "ml_data" {
  bucket = aws_s3_bucket.ml_data.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "ml_data" {
  bucket = aws_s3_bucket.ml_data.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.ml_data.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "ml_data" {
  bucket                  = aws_s3_bucket.ml_data.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle rules — expire checkpoints quickly; tier old models to save cost
resource "aws_s3_bucket_lifecycle_configuration" "ml_data" {
  bucket = aws_s3_bucket.ml_data.id

  rule {
    id     = "expire-checkpoints"
    status = "Enabled"
    filter { prefix = "checkpoints/" }
    expiration {
      days = var.checkpoint_expiry_days
    }
    noncurrent_version_expiration {
      noncurrent_days = 7
    }
  }

  rule {
    id     = "tier-models"
    status = "Enabled"
    filter { prefix = "models/" }
    transition {
      days          = var.model_transition_days
      storage_class = "INTELLIGENT_TIERING"
    }
  }

  rule {
    id     = "expire-old-data-versions"
    status = "Enabled"
    filter { prefix = "" }
    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

resource "aws_s3_bucket_policy" "ml_data" {
  bucket = aws_s3_bucket.ml_data.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource = [
        aws_s3_bucket.ml_data.arn,
        "${aws_s3_bucket.ml_data.arn}/*",
      ]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })

  depends_on = [aws_s3_bucket_public_access_block.ml_data]
}
