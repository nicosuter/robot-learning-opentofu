variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.29"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+$", var.cluster_version))
    error_message = "cluster_version must be in the form MAJOR.MINOR (e.g. \"1.29\")."
  }
}

variable "vpc_id" {
  description = "VPC ID where EKS cluster will be deployed"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for EKS nodes"
  type        = list(string)
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs for EKS"
  type        = list(string)
}

variable "cluster_security_group_id" {
  description = "Security group ID for EKS cluster"
  type        = string
}

variable "node_group_desired_size" {
  description = "Desired number of worker nodes"
  type        = number
  default     = 1
}

variable "node_group_min_size" {
  description = "Minimum number of worker nodes"
  type        = number
  default     = 0
}

variable "node_group_max_size" {
  description = "Maximum number of worker nodes"
  type        = number
  default     = 4
}

variable "node_instance_types" {
  description = "Instance types for the EKS node group"
  type        = list(string)
  default     = ["g5.4xlarge", "g5.8xlarge"]
}

variable "node_disk_size" {
  description = "Disk size in GB for worker nodes"
  type        = number
  default     = 200
}

variable "tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "cluster_access" {
  description = "Map of IAM principals to grant cluster access. Keys are friendly names; values specify the principal ARN and EKS access policy."
  type = map(object({
    principal_arn = string
    policy        = string # AmazonEKSClusterAdminPolicy | AmazonEKSAdminPolicy | AmazonEKSEditPolicy | AmazonEKSViewPolicy
  }))
  default = {}

  validation {
    condition = alltrue([
      for k, v in var.cluster_access :
      contains([
        "AmazonEKSClusterAdminPolicy",
        "AmazonEKSAdminPolicy",
        "AmazonEKSEditPolicy",
        "AmazonEKSViewPolicy",
      ], v.policy)
    ])
    error_message = "cluster_access policy must be one of: AmazonEKSClusterAdminPolicy, AmazonEKSAdminPolicy, AmazonEKSEditPolicy, AmazonEKSViewPolicy."
  }
}
