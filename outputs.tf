# VPC Outputs
output "vpc_id" {
  description = "The ID of the VPC"
  value       = module.vpc.vpc_id
}

output "vpc_cidr" {
  description = "The CIDR block of the VPC"
  value       = module.vpc.vpc_cidr
}

output "vpc_ipv6_cidr" {
  description = "The IPv6 CIDR block of the VPC (primary)"
  value       = module.vpc.vpc_ipv6_cidr_block
}

output "ipv6_source" {
  description = "IPv6 source: AWS-provided or BYOIP"
  value       = var.use_byoip_ipv6 ? "BYOIP (${var.byoip_ipv6_pool_id})" : "AWS-provided"
}

output "private_subnet_ids" {
  description = "List of private subnet IDs"
  value       = module.vpc.private_subnet_ids
}

output "public_subnet_ids" {
  description = "List of public subnet IDs"
  value       = module.vpc.public_subnet_ids
}

# EKS Cluster Outputs
output "cluster_id" {
  description = "The ID of the EKS cluster"
  value       = module.eks.cluster_id
}

output "cluster_name" {
  description = "The name of the EKS cluster"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Endpoint for EKS control plane"
  value       = module.eks.cluster_endpoint
}

output "cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster"
  value       = module.eks.cluster_security_group_id
}

output "cluster_version" {
  description = "The Kubernetes server version for the cluster"
  value       = module.eks.cluster_version
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data required to communicate with the cluster"
  value       = module.eks.cluster_certificate_authority_data
  sensitive   = true
}

# EKS Node Group Outputs
output "node_group_id" {
  description = "EKS node group ID"
  value       = module.eks.node_group_id
}

output "node_group_status" {
  description = "Status of the EKS node group"
  value       = module.eks.node_group_status
}

output "node_security_group_id" {
  description = "Security group ID attached to the EKS nodes"
  value       = module.vpc.eks_nodes_security_group_id
}

# IAM Outputs
output "cluster_iam_role_arn" {
  description = "IAM role ARN of the EKS cluster"
  value       = module.eks.cluster_iam_role_arn
}

output "node_iam_role_arn" {
  description = "IAM role ARN of the EKS node group"
  value       = module.eks.node_iam_role_arn
}
# S3 Outputs
output "ml_data_bucket_name" {
  description = "Name of the ML data S3 bucket."
  value       = module.s3_ml_data.bucket_name
}

output "ml_data_bucket_arn" {
  description = "ARN of the ML data S3 bucket."
  value       = module.s3_ml_data.bucket_arn
}

output "ml_data_kms_key_arn" {
  description = "ARN of the KMS key encrypting the ML data bucket."
  value       = module.s3_ml_data.kms_key_arn
}
# kubectl Configuration Command
output "configure_kubectl" {
  description = "Command to configure kubectl"
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}

# ArgoCD Outputs
output "argocd_installed" {
  description = "Whether ArgoCD was installed."
  value       = module.eks_addons.argocd_installed
}

output "argocd_namespace" {
  description = "Namespace where ArgoCD is deployed. Use 'kubectl port-forward svc/argocd-server -n argocd 8080:443' to access the UI."
  value       = module.eks_addons.argocd_namespace
}

output "argocd_admin_password" {
  description = "ArgoCD initial admin password. Sensitive — rotate after first login."
  value       = var.argocd_enabled ? data.kubernetes_secret.argocd_admin_password[0].data["password"] : null
  sensitive   = true
}
