variable "cluster_name" {
  description = "Name of the EKS cluster (used for resource naming)"
  type        = string
}

variable "region" {
  description = "AWS region (used for VPC endpoint service names)"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "Availability zones to deploy into. EKS requires at least two AZs."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b", "us-east-1c", "us-east-1d", "us-east-1e", "us-east-1f"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (one per AZ)"
  type        = list(string)
  default     = ["10.0.0.0/19", "10.0.32.0/19", "10.0.128.0/20", "10.0.144.0/20", "10.0.160.0/20", "10.0.224.0/20"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (one per AZ)"
  type        = list(string)
  default     = ["10.0.64.0/19", "10.0.96.0/19", "10.0.176.0/20", "10.0.192.0/20", "10.0.208.0/20", "10.0.240.0/20"]
}

variable "use_byoip_ipv6" {
  description = "Use Bring Your Own IP (BYOIP) for IPv6 instead of AWS-provided addresses"
  type        = bool
  default     = false
}

variable "byoip_ipv6_pool_id" {
  description = "AWS IPv6 BYOIP pool ID (required if use_byoip_ipv6 is true)"
  type        = string
  default     = null
}

variable "byoip_ipv6_cidr" {
  description = "BYOIP IPv6 CIDR block to use"
  type        = string
  default     = null
}

variable "byoip_ipv6_netmask_length" {
  description = "Netmask length for BYOIP IPv6 CIDR"
  type        = number
  default     = 56
}

variable "tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}
