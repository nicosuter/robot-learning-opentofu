variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.35"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+$", var.cluster_version))
    error_message = "cluster_version must be in the form MAJOR.MINOR (e.g. \"1.35\")."
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


variable "karpenter_namespace" {
  description = "Kubernetes namespace where Karpenter is installed."
  type        = string
  default     = "karpenter"
}

variable "node_disk_size" {
  description = "Disk size in GB for Karpenter-provisioned workload nodes"
  type        = number
  default     = 200
}

variable "system_node_disk_size" {
  description = "Disk size in GB for the system node group (Karpenter + CoreDNS)"
  type        = number
  default     = 20
}

variable "tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "api_server_allowed_cidrs" {
  description = "IPv4 CIDRs allowed to reach the public EKS API endpoint. Defaults to unrestricted (0.0.0.0/0) when empty. Note: AWS does not support IPv6 CIDRs here — use the WAF Web ACL for IPv6 restriction on application endpoints."
  type        = list(string)
  default     = []
}


variable "cluster_access" {
  description = "Map of IAM principals to grant cluster access. Keys are friendly names; values specify the principal ARN, EKS access policy, and an optional list of namespaces. When namespaces is non-empty the access entry is scoped to those namespaces only; omit (or leave empty) for cluster-wide access."
  type = map(object({
    principal_arn = string
    policy        = string                     # AmazonEKSClusterAdminPolicy | AmazonEKSAdminPolicy | AmazonEKSEditPolicy | AmazonEKSViewPolicy
    namespaces    = optional(list(string), []) # [] = cluster-wide; non-empty = namespace-scoped
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

variable "use_public_subnets_for_nodes" {
  description = "Place nodes in public subnets with auto-assigned public IPs."
  type        = bool
  default     = false
}

# ── Hybrid EKS Nodes Configuration ─────────────────────────────────────────────

variable "enable_hybrid_nodes" {
  description = "Enable support for hybrid EKS nodes (on-premises infrastructure connected to the cluster)."
  type        = bool
  default     = false
}

variable "hybrid_node_registration_limit" {
  description = "Maximum number of hybrid nodes that can be registered via SSM activation."
  type        = number
  default     = 10
}

variable "hybrid_node_cidrs" {
  description = "IPv4 CIDR blocks for on-premises hybrid nodes (for remote network config)."
  type        = list(string)
  default     = []
}

variable "hybrid_node_pod_cidrs" {
  description = "IPv4 CIDR blocks for hybrid node pods (remote pod networks). AWS requires RFC1918 ranges (10/8, 172.16/12, or 192.168/16)."
  type        = list(string)
  default     = []
}
