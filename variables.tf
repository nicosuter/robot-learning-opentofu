variable "region" {
  description = "AWS region"
  type        = string
  default     = "eu-central-1"
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "ethrc-rbtl-eks-cluster"
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.29"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
  default     = ["eu-central-1a", "eu-central-1b", "eu-central-1c"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
}

variable "node_group_desired_size" {
  description = "Desired number of worker nodes"
  type        = number
  default     = 1
}

variable "node_group_min_size" {
  description = "Minimum number of worker nodes (0 enables scale-to-zero via Cluster Autoscaler)"
  type        = number
  default     = 0
}

variable "node_group_max_size" {
  description = "Maximum number of worker nodes"
  type        = number
  default     = 2
}

variable "node_instance_types" {
  description = "Instance types for the EKS node group (GPU instances for ML workloads)"
  type        = list(string)
  default     = ["g5.4xlarge", "g5.8xlarge"]
}

variable "node_disk_size" {
  description = "Disk size in GB for worker nodes (larger for ML models)"
  type        = number
  default     = 200
}

variable "enable_ipv6" {
  description = "Enable IPv6 for VPC and subnets"
  type        = bool
  default     = true
}

variable "use_byoip_ipv6" {
  description = "Use Bring Your Own IP (BYOIP) for IPv6 instead of AWS-provided addresses"
  type        = bool
  default     = false
}

variable "byoip_ipv6_pool_id" {
  description = "AWS IPv6 BYOIP pool ID (required if use_byoip_ipv6 is true). Format: ipv6pool-ec2-xxxxxxxxxxxxxxxxx"
  type        = string
  default     = null
}

variable "byoip_ipv6_cidr" {
  description = "BYOIP IPv6 CIDR block to use (e.g., 2001:db8:1234::/56). If not specified with use_byoip_ipv6, will use netmask length"
  type        = string
  default     = null
}

variable "byoip_ipv6_netmask_length" {
  description = "Netmask length for BYOIP IPv6 CIDR (typically 56 for VPC from a /48 allocation)"
  type        = number
  default     = 56
}

variable "tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default = {
    Project     = "ethrc-rbtl"
    Environment = "development"
    ManagedBy   = "OpenTofu"
  }
}

variable "cluster_access" {
  description = "Map of IAM principals to grant cluster access. Keys are friendly names."
  type = map(object({
    principal_arn = string
    policy        = string # AmazonEKSClusterAdminPolicy | AmazonEKSAdminPolicy | AmazonEKSEditPolicy | AmazonEKSViewPolicy
  }))
  default = {}
}
