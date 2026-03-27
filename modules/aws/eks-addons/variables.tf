variable "cluster_name" {
  description = "Name of the EKS cluster."
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC in which the EKS cluster runs. Passed to the AWS Load Balancer Controller."
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for EFS mount targets."
  type        = list(string)
  default     = []
}

variable "node_security_group_id" {
  description = "Security group ID for EKS worker nodes (used for EFS access)."
  type        = string
  default     = null
}

variable "oidc_provider_arn" {
  description = "ARN of the EKS OIDC provider (used for IRSA)."
  type        = string
}

variable "s3_bucket_arns" {
  description = "S3 bucket ARNs accessible via the S3 CSI driver. Leave empty to skip driver installation."
  type        = list(string)
  default     = []
}

variable "node_tier" {
  description = "Compute tier inherited from the EKS module."
  type        = string

  validation {
    condition     = contains(["cpu", "gpus", "gpum", "gpul", "h100"], var.node_tier)
    error_message = "node_tier must be one of: cpu, gpus, gpum, gpul, h100."
  }
}

variable "gpu_operator_enabled" {
  description = "Install the NVIDIA GPU Operator. Enable whenever GPU node pools are active."
  type        = bool
  default     = true
}

variable "gpum_instance_types" {
  description = "List of EC2 instance types to use for the 'gpum' NodePool."
  type        = list(string)
}

variable "karpenter_role_arn" {
  description = "IAM role ARN for the Karpenter controller (IRSA)."
  type        = string
}

variable "karpenter_interruption_queue_name" {
  description = "SQS queue name for Karpenter interruption handling."
  type        = string
}

variable "node_iam_role_name" {
  description = "Node IAM role name for Karpenter EC2NodeClass instance profile."
  type        = string
}

variable "node_disk_size" {
  description = "Root volume size in GB for Karpenter-provisioned nodes."
  type        = number
  default     = 200
}

variable "gpu_node_max_lifetime" {
  description = "Hard TTL for gpus/gpum/gpul NodePool nodes. Karpenter drains and terminates any node running longer than this duration. Go duration syntax (e.g. \"24h\") or \"Never\" to disable."
  type        = string
  default     = "16h"
}

variable "tags" {
  description = "Common tags to apply to all resources."
  type        = map(string)
  default     = {}
}

variable "argocd_enabled" {
  description = "Install ArgoCD via Helm for GitOps-driven ML workload management."
  type        = bool
  default     = true
}

variable "argocd_chart_version" {
  description = "Version of the argo-cd Helm chart to install."
  type        = string
  default     = "7.8.1"
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
variable "waf_web_acl_arn" {
  description = "ARN of the WAF Web ACL to associate with the ArgoCD ALB. Required when argocd_hostname is set."
  type        = string
  default     = null
}

variable "argocd_hostname" {
  description = "Public hostname for ArgoCD (e.g. argocd.example.com). When set alongside argocd_certificate_arn, an internet-facing ALB Ingress is created."
  type        = string
  default     = null
}

variable "argocd_certificate_arn" {
  description = "ACM certificate ARN for the ArgoCD ALB HTTPS listener. Must cover argocd_hostname."
  type        = string
  default     = null
}

variable "kubeflow_training_operator_enabled" {
  description = "Install Kubeflow Trainer v2 for distributed ML training with the TrainJob API. Includes JobSet and default ClusterTrainingRuntimes (torch, deepspeed, mlx, jax, torchtune)."
  type        = bool
  default     = true
}

variable "kubeflow_dashboard_enabled" {
  description = "Deploy the Kubeflow Central Dashboard in the kubeflow namespace. Requires kubeflow_training_operator_enabled = true. Runs without Istio; WAF on the ALB enforces access control."
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

