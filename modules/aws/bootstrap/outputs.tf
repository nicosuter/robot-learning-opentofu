output "state_bucket_name" {
  description = "Name of the S3 state bucket."
  value       = aws_s3_bucket.state.id
}

output "state_bucket_arn" {
  description = "ARN of the S3 state bucket."
  value       = aws_s3_bucket.state.arn
}

output "lock_table_name" {
  description = "Name of the DynamoDB lock table."
  value       = aws_dynamodb_table.lock.id
}

output "kms_key_arn" {
  description = "ARN of the KMS key used to encrypt state."
  value       = aws_kms_key.state.arn
}

output "backend_config_snippet" {
  description = "Paste this into backend.tf."
  value       = <<-EOT
    terraform {
      backend "s3" {
        bucket         = "${aws_s3_bucket.state.id}"
        key            = "ethrc-rbtl/eks/terraform.tfstate"
        region         = "${var.region}"
        encrypt        = true
        dynamodb_table = "${aws_dynamodb_table.lock.id}"
      }
    }
  EOT
}
