# ─────────────────────────────────────────────────────────────────────────────
# EKS Access Entries — per-user/role IAM RBAC (no shared kubeconfig)
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_eks_access_entry" "users" {
  for_each = var.cluster_access

  cluster_name  = aws_eks_cluster.main.name
  principal_arn = each.value.principal_arn
  type          = "STANDARD"

  tags = var.tags
}

resource "aws_eks_access_policy_association" "users" {
  for_each = var.cluster_access

  cluster_name  = aws_eks_cluster.main.name
  principal_arn = each.value.principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/${each.value.policy}"

  # Namespace-scoped when the caller specifies namespaces; cluster-wide otherwise.
  access_scope {
    type       = length(each.value.namespaces) > 0 ? "namespace" : "cluster"
    namespaces = length(each.value.namespaces) > 0 ? each.value.namespaces : null
  }

  depends_on = [aws_eks_access_entry.users]
}
