output "vpc_id" {
  description = "The ID of the VPC"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "The CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

output "vpc_ipv6_cidr_block" {
  description = "The IPv6 CIDR block of the VPC"
  value       = local.vpc_ipv6_cidr_block
}

locals {
  # EKS control plane AZs are fixed at cluster creation and cannot be changed.
  # This cluster was created with us-east-1a and us-east-1b only.
  eks_control_plane_azs = ["us-east-1a", "us-east-1b"]
}

output "private_subnet_ids" {
  description = "List of private subnet IDs (all AZs)"
  value       = aws_subnet.private[*].id
}

output "public_subnet_ids" {
  description = "List of public subnet IDs (all AZs)"
  value       = aws_subnet.public[*].id
}

# EKS control plane subnets are filtered by AZ tag to match cluster creation AZs.
# Worker nodes can use all 6 AZs via Karpenter, but control plane cannot be modified.
output "eks_private_subnet_ids" {
  description = "List of private subnet IDs for EKS control plane (cluster creation AZs only)"
  value       = [for s in aws_subnet.private : s.id if contains(local.eks_control_plane_azs, s.tags["az"])]
}

output "eks_public_subnet_ids" {
  description = "List of public subnet IDs for EKS control plane (cluster creation AZs only)"
  value       = [for s in aws_subnet.public : s.id if contains(local.eks_control_plane_azs, s.tags["az"])]
}

output "eks_cluster_security_group_id" {
  description = "Security group ID for EKS cluster"
  value       = aws_security_group.eks_cluster.id
}

output "eks_nodes_security_group_id" {
  description = "Security group ID for EKS nodes"
  value       = aws_security_group.eks_nodes.id
}
