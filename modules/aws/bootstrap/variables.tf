variable "state_bucket_name" {
  description = "Name of the S3 bucket used for OpenTofu remote state."
  type        = string
}

variable "lock_table_name" {
  description = "Name of the DynamoDB table used for state locking."
  type        = string
  default     = "tofu-state-lock"
}

variable "region" {
  description = "AWS region. Must match the backend.tf region."
  type        = string
}

variable "tags" {
  description = "Common tags to apply to all resources."
  type        = map(string)
  default     = {}
}
