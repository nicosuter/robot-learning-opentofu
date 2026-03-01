# ─────────────────────────────────────────────────────────────────────────────
# NVIDIA GPU Operator (gpum / gpul tiers only)
# ─────────────────────────────────────────────────────────────────────────────
# EKS GPU-optimised AMIs ship with NVIDIA drivers pre-installed, so
# driver.enabled=false tells the operator to skip driver installation and only
# manage the device plugin, DCGM exporter, and other components.

locals {
  install_gpu_operator = contains(["gpum", "gpul"], var.node_tier)
}

resource "helm_release" "nvidia_gpu_operator" {
  count = local.install_gpu_operator ? 1 : 0

  name             = "gpu-operator"
  repository       = "https://helm.ngc.nvidia.com/nvidia"
  chart            = "gpu-operator"
  version          = "25.10.1"
  namespace        = "gpu-operator"
  create_namespace = true

  values = [yamlencode({
    driver = { enabled = false }
  })]

  depends_on = [
    aws_eks_addon.coredns,
    helm_release.karpenter,
  ]
}
