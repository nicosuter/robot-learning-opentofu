variable "tags" {
  description = "Common tags to apply to all resources."
  type        = map(string)
  default     = {}
}

variable "dockerhub_credentials_secret_arn" {
  description = "ARN of the AWS Secrets Manager secret containing DockerHub credentials for authenticated pull-through cache. The secret value must be JSON: {\"username\":\"...\",\"accessToken\":\"...\"}. When null, unauthenticated pulls are used (subject to DockerHub anonymous rate limits)."
  type        = string
  default     = null
}
