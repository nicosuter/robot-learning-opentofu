# ─────────────────────────────────────────────────────────────────────────────
# OpenCost — open source cost monitoring for Kubernetes
#
# Tracks per-namespace, per-pod, and per-workload costs including
# GPU node spending. Useful for chargeback and cost optimization.
# See: https://opencost.io/docs/installation/install
# ─────────────────────────────────────────────────────────────────────────────

locals {
  enable_opencost = true
}

# OpenCost requires Prometheus - check if it's already installed
resource "helm_release" "opencost" {
  count = local.enable_opencost ? 1 : 0

  name             = "opencost"
  repository       = "https://opencost.github.io/opencost-helm-chart"
  chart            = "opencost"
  version          = "1.42.0"
  namespace        = "opencost"
  create_namespace = true

  values = [yamlencode({
    opencost = {
      exporter = {
        defaultClusterId = var.cluster_name
      }
      prometheus = {
        internal = {
          enabled = true
          namespace = "prometheus-system"
        }
      }
      ui = {
        enabled = true
      }
    }
    # Resource requests for cost exporter
    resources = {
      requests = {
        cpu    = "100m"
        memory = "256Mi"
      }
      limits = {
        cpu    = "500m"
        memory = "512Mi"
      }
    }
  })]

  depends_on = [aws_eks_addon.coredns]

  tags = var.tags
}
