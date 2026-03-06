variable "region" {
  description = "AWS region for the management instance."
  type        = string
  default     = "us-east-1"
}

variable "aws_profile" {
  description = "AWS CLI profile. Set to match your main backend (e.g. ethrc)."
  type        = string
  default     = "ethrc"
}

variable "instance_type" {
  description = "EC2 instance type. t3.micro is minimum (1 vCPU, 1 GiB)."
  type        = string
  default     = "t3.micro"
}

variable "public_keys" {
  description = "List of SSH public keys (e.g. ssh-ed25519 AAAA...). First is used for the EC2 key pair; all are added to authorized_keys. Empty to skip (use SSM Session Manager)."
  type        = list(string)
  default     = []
  sensitive   = true
}

variable "ssh_allowed_cidrs" {
  description = "CIDR blocks allowed to SSH (22). Restrict to your IP in production."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "tags" {
  description = "Tags to apply to resources."
  type        = map(string)
  default = {
    Purpose = "terraform-management"
  }
}
