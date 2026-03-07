variable "bucket_name" {
  description = "Name of the ML data bucket."
  type        = string
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

variable "kms_user_arns" {
  description = "IAM principal ARNs (users, roles) to grant kms:Decrypt and kms:GenerateDataKey on the bucket KMS key."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Common tags to apply to all resources."
  type        = map(string)
  default     = {}
}
