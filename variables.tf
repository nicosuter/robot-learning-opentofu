variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "aws_profile" {
  description = "AWS CLI named profile to use for authentication. Defaults to the AWS_PROFILE environment variable or the 'default' profile when null."
  type        = string
  default     = null
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "ethrc-prod-1"
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.35"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "Availability zones for subnets. EKS requires at least two."
  type        = list(string)
  default     = null
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (one per AZ)"
  type        = list(string)
  default     = null
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (one per AZ)"
  type        = list(string)
  default     = null
}

variable "node_tier" {
  description = "Compute tier for the node group: 'cpu', 'gpus', 'gpum', 'gpul', or 'h100'. GPU tiers auto-install the NVIDIA GPU Operator."
  type        = string
  default     = "cpu"

  validation {
    condition     = contains(["cpu", "gpus", "gpum", "gpul", "h100"], var.node_tier)
    error_message = "node_tier must be one of: cpu, gpus, gpum, gpul, h100."
  }
}

variable "gpu_operator_enabled" {
  description = "Install the NVIDIA GPU Operator. Set to true whenever GPU node pools are active."
  type        = bool
  default     = true
}

variable "gpum_instance_types" {
  description = "List of EC2 instance types to use for the 'gpum' NodePool (1× L40S). g6e.2xlarge is a fallback for regions with limited g6e.xlarge availability."
  type        = list(string)
  default     = ["g6e.xlarge", "g6e.2xlarge"]
}

variable "node_disk_size" {
  description = "Disk size in GB for worker nodes"
  type        = number
  default     = 200
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
    Project     = "ethrc-prod-1"
    Environment = "development"
    ManagedBy   = "OpenTofu"
  }
}

variable "cluster_access" {
  description = "Map of IAM principals to grant cluster access. Keys are friendly names; values specify the principal ARN, EKS access policy, and an optional list of namespaces. When namespaces is non-empty the access entry is scoped to those namespaces only; omit (or leave empty) for cluster-wide access."
  type = map(object({
    principal_arn = string
    policy        = string                     # AmazonEKSClusterAdminPolicy | AmazonEKSAdminPolicy | AmazonEKSEditPolicy | AmazonEKSViewPolicy
    namespaces    = optional(list(string), []) # [] = cluster-wide; non-empty = namespace-scoped
  }))
  default = {}
}

variable "s3_bucket_arns" {
  description = "Additional S3 bucket ARNs to expose via the CSI driver alongside the ML data bucket."
  type        = list(string)
  default     = []
}

variable "gpu_node_max_lifetime" {
  description = "Hard TTL for gpus/gpum/gpul nodes. Karpenter drains and terminates any node running longer than this duration, regardless of workload state. Go duration syntax (e.g. \"24h\", \"72h\"). Set to \"Never\" to disable."
  type        = string
  default     = "48h"
}

variable "ml_data_bucket_name" {
  description = "Name of the S3 bucket for ML training data, checkpoints, and model artefacts. Must be globally unique."
  type        = string
}


variable "argocd_enabled" {
  description = "Install ArgoCD for GitOps-driven ML workload management."
  type        = bool
  default     = true
}

variable "argocd_chart_version" {
  description = "Version of the argo-cd Helm chart to install."
  type        = string
  default     = "9.4.5"
}

variable "argocd_source_repos" {
  description = "List of git repository URLs the ml-workloads AppProject is allowed to sync from. Restrict to specific repo URLs in production to prevent syncing from untrusted sources."
  type        = list(string)
  default     = ["*"]
}

variable "workload_namespaces" {
  description = "Namespaces to create. One ArgoCD AppProject is created per namespace and each project is restricted to its own namespace as the only destination."
  type        = list(string)
  default     = ["robot-learning", "humanoid", "aeronautics", "cybersecurity"]
}

variable "argocd_team_groups" {
  description = "Map of workload namespace names to lists of SSO/OIDC group names. Members of these groups receive edit access to the corresponding team's ArgoCD AppProject and namespace only. Leave empty to configure SSO group bindings outside of Terraform."
  type        = map(list(string))
  default     = {}
}

# ── ECR variables ─────────────────────────────────────────────────────────
variable "ecr_repository_names" {
  description = "ECR repository names to create for container images."
  type        = list(string)
  default     = ["ethroboticsclub/pytorch", "ethroboticsclub/jax"]
}

variable "ecr_github_repositories" {
  description = "GitHub repositories allowed to push to ECR (format: org/repo)."
  type        = list(string)
  default     = ["ethroboticsclub/docker-images"]
}


# ── Access restriction ─────────────────────────────────────────────────────────

variable "api_server_allowed_cidrs" {
  description = "IPv4 CIDRs permitted to reach the public EKS API server (kubectl). Defaults to unrestricted when empty. AWS does not accept IPv6 here — use waf_as214770_cidrs for IPv6 coverage on application endpoints."
  type        = list(string)
  default     = []
}

variable "waf_as214770_cidrs" {
  description = "IP prefixes (IPv4 and/or IPv6) announced by AS214770. These are allowed through the WAF alongside the Switzerland geo-match rule. Fetch current prefixes from https://bgp.he.net/AS214770."
  type        = list(string)
  default     = []
}

variable "argocd_hostname" {
  description = "Public hostname for the ArgoCD UI (e.g. argocd.example.com). Set alongside argocd_certificate_arn to create an internet-facing ALB with WAF."
  type        = string
  default     = null
}

variable "route53_zone_name" {
  description = "Route 53 hosted zone name used to write DNS validation records for auto-created ACM certificates (e.g. \"ethrc.rgn.dev\"). Required when argocd_hostname is set."
  type        = string
  default     = null
}

variable "kubeflow_training_operator_enabled" {
  description = "Install Kubeflow Trainer v2 for distributed ML training with the TrainJob API. Includes JobSet and default ClusterTrainingRuntimes (torch, deepspeed, mlx, jax, torchtune)."
  type        = bool
  default     = true
}

variable "kubeflow_dashboard_enabled" {
  description = "Deploy the Kubeflow Central Dashboard. Requires kubeflow_training_operator_enabled = true."
  type        = bool
  default     = true
}

variable "kubeflow_dashboard_hostname" {
  description = "Public hostname for the Kubeflow Dashboard (e.g. kubeflow.example.com). Set alongside kubeflow_dashboard_certificate_arn to create an internet-facing ALB with WAF."
  type        = string
  default     = null
}

variable "kubeflow_dashboard_certificate_arn" {
  description = "ACM certificate ARN for the Kubeflow Dashboard HTTPS listener. Must cover kubeflow_dashboard_hostname."
  type        = string
  default     = null
}

variable "use_public_subnets_for_nodes" {
  description = "Place nodes in public subnets with auto-assigned public IPs."
  type        = bool
  default     = true
}

# ── Hybrid EKS Nodes Configuration ─────────────────────────────────────────────

variable "enable_hybrid_nodes" {
  description = "Enable support for hybrid EKS nodes (on-premises infrastructure connected to the cluster)."
  type        = bool
  default     = false
}

variable "hybrid_node_cidrs" {
  description = "IPv4 CIDR blocks for on-premises hybrid nodes that need access to the EKS cluster. Only used when enable_hybrid_nodes is true."
  type        = list(string)
  default     = []
}

variable "hybrid_node_pod_cidrs" {
  description = "IPv4 CIDR blocks for hybrid node pods (remote pod networks). AWS requires RFC1918 ranges (10/8, 172.16/12, or 192.168/16). Must not overlap with VPC CIDR or hybrid_node_cidrs. Only used when enable_hybrid_nodes is true."
  type        = list(string)
  default     = []
}

variable "hybrid_node_registration_limit" {
  description = "Maximum number of hybrid nodes that can be registered via SSM activation."
  type        = number
  default     = 10
}

# ── Tailscale Configuration ───────────────────────────────────────────────────

variable "tailscale_enabled" {
  description = "Install the Tailscale operator for mesh networking between hybrid nodes and the EKS cluster."
  type        = bool
  default     = false
}

variable "tailscale_oauth_client_id" {
  description = "Tailscale OAuth client ID for the operator. Required when tailscale_enabled is true."
  type        = string
  sensitive   = true
  default     = null
}

variable "tailscale_oauth_client_secret" {
  description = "Tailscale OAuth client secret for the operator. Required when tailscale_enabled is true."
  type        = string
  sensitive   = true
  default     = null
}

variable "tailscale_chart_version" {
  description = "Version of the Tailscale Helm chart to install."
  type        = string
  default     = "1.78.3"
}

