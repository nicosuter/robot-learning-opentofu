output "registry_url" {
  description = "Private ECR registry URL (account.dkr.ecr.region.amazonaws.com). Pass to eks-addons so Karpenter nodes can be configured with containerd mirrors pointing at the pull-through cache prefixes."
  value       = local.registry_url
}
