variable "name_prefix" {
  description = "Prefix for IAM resource names (e.g. cluster name)."
  type        = string
}

variable "repository_names" {
  description = "List of ECR repository names to create."
  type        = list(string)
}

variable "github_repositories" {
  description = "GitHub repositories allowed to assume the ECR push role."
  type        = list(string)
}

variable "tags" {
  description = "Tags to apply to all resources."
  type        = map(string)
  default     = {}
}

variable "ecr_push_iam_users" {
  descriptions  = "IAM user names to grant ECR push/pull access."
  type          = list(string)
  default       = []
}