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
  description = "Availability zones to deploy into. Single entry = single-AZ (default, no redundancy)."
  type        = list(string)
  default     = ["eu-central-1a"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (one per AZ)"
  type        = list(string)
  default     = ["10.0.1.0/24"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (one per AZ)"
  type        = list(string)
  default     = ["10.0.101.0/24"]
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
