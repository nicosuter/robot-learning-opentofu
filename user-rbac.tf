# ─────────────────────────────────────────────────────────────────────────────
# Kubernetes RBAC extensions for namespace-scoped users
#
# AmazonEKSEditPolicy binds principals to the built-in 'edit' ClusterRole,
# which covers all core API resources (pods, deployments, jobs, services,
# configmaps, secrets, ingresses, PVCs, etc.) but not CRDs.
#
# The ClusterRoles below carry aggregate-to-edit/admin labels, causing
# Kubernetes to automatically merge their rules into every 'edit'/'admin'
# binding — no per-user RoleBinding needed, and future users with
# AmazonEKSEditPolicy inherit them automatically.
# ─────────────────────────────────────────────────────────────────────────────

resource "kubernetes_cluster_role" "ml_workload_edit" {
  metadata {
    name = "ml-workload-edit"
    labels = {
      "rbac.authorization.k8s.io/aggregate-to-edit"  = "true"
      "rbac.authorization.k8s.io/aggregate-to-admin" = "true"
    }
  }

  # ── Kubeflow Training Operator v2 ──────────────────────────────────────────
  rule {
    api_groups = ["kubeflow.org"]
    resources  = ["trainjobs", "trainjobs/status", "trainingruntimes", "trainingruntimes/status"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }
  # ClusterTrainingRuntimes are cluster-scoped; read-only is sufficient
  rule {
    api_groups = ["kubeflow.org"]
    resources  = ["clustertrainingruntimes"]
    verbs      = ["get", "list", "watch"]
  }

  # ── KServe inference ───────────────────────────────────────────────────────
  rule {
    api_groups = ["serving.kserve.io"]
    resources  = ["inferenceservices", "inferenceservices/status", "servingruntimes", "inferencegraphs"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }
  # Cluster-scoped KServe presets; read-only
  rule {
    api_groups = ["serving.kserve.io"]
    resources  = ["clusterservingruntimes", "clusterstoragecontainers"]
    verbs      = ["get", "list", "watch"]
  }

  # ── Ray (distributed training and inference) ───────────────────────────────
  rule {
    api_groups = ["ray.io"]
    resources  = ["rayclusters", "rayjobs", "rayservices"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }

  depends_on = [module.eks_addons]
}
