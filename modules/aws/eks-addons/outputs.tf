output "gpu_operator_installed" {
  description = "Whether the NVIDIA GPU Operator was installed."
  value       = local.install_gpu_operator
}

output "argocd_installed" {
  description = "Whether ArgoCD was installed."
  value       = local.install_argocd
}

output "argocd_namespace" {
  description = "Kubernetes namespace where ArgoCD is deployed."
  value       = local.install_argocd ? "argocd" : null
}

output "training_role_arn" {
  description = "IAM role ARN for training workload pods (IRSA)."
  value       = length(var.s3_bucket_arns) > 0 ? aws_iam_role.training[0].arn : null
}
output "argocd_lb_hostname" {
  description = "ALB hostname assigned to the ArgoCD ingress by AWS LBC. Null when ArgoCD is not exposed."
  value       = local.expose_argocd ? data.kubernetes_ingress_v1.argocd[0].status[0].load_balancer[0].ingress[0].hostname : null
}
