output "cluster_id" {
  description = "The ID of the EKS cluster"
  value       = aws_eks_cluster.main.id
}

output "cluster_name" {
  description = "The name of the EKS cluster"
  value       = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  description = "Endpoint for EKS control plane"
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster"
  value       = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
}

output "cluster_version" {
  description = "The Kubernetes server version for the cluster"
  value       = aws_eks_cluster.main.version
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data required to communicate with the cluster"
  value       = aws_eks_cluster.main.certificate_authority[0].data
  sensitive   = true
}

output "node_group_id" {
  description = "EKS system node group ID"
  value       = aws_eks_node_group.system.id
}

output "node_group_status" {
  description = "Status of the EKS system node group"
  value       = aws_eks_node_group.system.status
}

output "cluster_iam_role_arn" {
  description = "IAM role ARN of the EKS cluster"
  value       = aws_iam_role.eks_cluster.arn
}

output "node_iam_role_arn" {
  description = "IAM role ARN of the EKS node group"
  value       = aws_iam_role.eks_nodes.arn
}

output "node_iam_role_name" {
  description = "IAM role name of the EKS node group (used by Karpenter EC2NodeClass)."
  value       = aws_iam_role.eks_nodes.name
}

output "oidc_provider_arn" {
  description = "ARN of the EKS OIDC provider."
  value       = aws_iam_openid_connect_provider.eks.arn
}

output "karpenter_role_arn" {
  description = "IAM role ARN for the Karpenter controller (IRSA)."
  value       = aws_iam_role.karpenter.arn
}

output "karpenter_interruption_queue_name" {
  description = "SQS queue name for Karpenter interruption handling."
  value       = aws_sqs_queue.karpenter_interruption.name
}
