# ─────────────────────────────────────────────────────────────────────────────
# Kubernetes RBAC extensions for namespace-scoped users
#
# AmazonEKSEditPolicy binds principals to the built-in 'edit' ClusterRole,
# which covers all core API resources (pods, deployments, jobs, services,
# configmaps, secrets, ingresses, PVCs, etc.) but not CRDs.
#
# ml-workload-edit carries aggregate-to-edit/admin labels as a best-effort
# aggregation hint, but EKS access entry bindings don't reliably trigger the
# aggregation controller. Explicit RoleBindings per user × namespace are the
# reliable path and are generated automatically from var.cluster_access.
# ─────────────────────────────────────────────────────────────────────────────

locals {
  # Flatten namespace-scoped IAM users into user × namespace pairs so we can
  # create one RoleBinding per combination.
  user_namespace_pairs = merge([
    for k, v in var.cluster_access : {
      for ns in v.namespaces : "${k}--${ns}" => {
        username  = v.principal_arn
        namespace = ns
      }
    }
    if length(v.namespaces) > 0 && can(regex(":user/", v.principal_arn))
  ]...)
}

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
    api_groups = ["trainer.kubeflow.org"]
    resources  = ["trainjobs", "trainjobs/status", "trainingruntimes", "trainingruntimes/status"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }
  # ClusterTrainingRuntimes are cluster-scoped; read-only is sufficient
  rule {
    api_groups = ["trainer.kubeflow.org"]
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

# Explicit RoleBindings — one per user × namespace. More reliable than
# relying on ClusterRole aggregation with EKS-managed access entry bindings.
resource "kubernetes_role_binding" "ml_workload_edit" {
  for_each = local.user_namespace_pairs

  metadata {
    name      = "ml-workload-edit--${each.key}"
    namespace = each.value.namespace
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.ml_workload_edit.metadata[0].name
  }

  subject {
    api_group = "rbac.authorization.k8s.io"
    kind      = "User"
    name      = each.value.username
  }

  depends_on = [module.eks_addons]
}
