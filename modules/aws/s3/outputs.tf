output "bucket_name" {
  description = "Name of the ML data bucket."
  value       = aws_s3_bucket.ml_data.id
}

output "bucket_arn" {
  description = "ARN of the ML data bucket."
  value       = aws_s3_bucket.ml_data.arn
}

output "kms_key_arn" {
  description = "ARN of the KMS key used to encrypt the ML data bucket."
  value       = aws_kms_key.ml_data.arn
}
