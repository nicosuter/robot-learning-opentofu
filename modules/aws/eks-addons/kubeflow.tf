# ─────────────────────────────────────────────────────────────────────────────
# Kubeflow Trainer v2 — TrainJob controller for distributed ML training
# Replaces legacy Training Operator (PyTorchJob/TFJob/MPIJob). Uses TrainJob API.
# ─────────────────────────────────────────────────────────────────────────────

locals {
  install_training_operator = var.kubeflow_training_operator_enabled
}

resource "helm_release" "kubeflow_trainer" {
  count = local.install_training_operator ? 1 : 0

  name             = "kubeflow-trainer"
  chart            = "oci://ghcr.io/kubeflow/charts/kubeflow-trainer"
  version          = "2.1.0"
  namespace        = "kubeflow-system"
  create_namespace = true

  values = [yamlencode({
    manager = {
      nodeSelector = { "node-role" = "system" }
      resources = {
        requests = { cpu = "100m", memory = "128Mi" }
        limits   = { cpu = "500m", memory = "512Mi" }
      }
    }
    runtimes = {
      defaultEnabled = true
    }
  })]

  depends_on = [
    aws_eks_addon.coredns,
    helm_release.karpenter,
  ]
}
