variable "bucket_name" {
  description = "Name of the ML data bucket."
  type        = string
}

variable "encrypt_with_kms" {
  description = "Use a customer-managed KMS key for SSE. Set to false to use SSE-S3 (AES-256, no KMS key or permissions required)."
  type        = bool
  default     = true
}

variable "kms_user_arns" {
  description = "IAM principal ARNs granted kms:Decrypt and kms:GenerateDataKey on the bucket KMS key. Only used when encrypt_with_kms = true."
  type        = list(string)
  default     = []
}

variable "checkpoint_expiry_days" {
  description = "Days before checkpoints/ objects are expired. Checkpoints are large and short-lived; default 30 days."
  type        = number
  default     = 30
}

variable "model_transition_days" {
  description = "Days before models/ objects transition to S3 Intelligent-Tiering."
  type        = number
  default     = 90
}

variable "tags" {
  description = "Common tags to apply to all resources."
  type        = map(string)
  default     = {}
}
