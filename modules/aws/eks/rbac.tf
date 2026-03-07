# ─────────────────────────────────────────────────────────────────────────────
# EKS Access Entries — per-user/role IAM RBAC (no shared kubeconfig)
# ─────────────────────────────────────────────────────────────────────────────

data "aws_iam_policy" "local_dev_access" {
  name = "SignInLocalDevelopmentAccess"
}

locals {
  # Principals that are scoped to specific namespaces (team members, not admins).
  namespace_scoped = {
    for k, v in var.cluster_access : k => v
    if length(v.namespaces) > 0
  }

  # Split by principal type so we can use the correct attachment resource.
  ns_iam_users = {
    for k, v in local.namespace_scoped : k => v
    if can(regex(":user/", v.principal_arn))
  }
  ns_iam_roles = {
    for k, v in local.namespace_scoped : k => v
    if can(regex(":role/", v.principal_arn))
  }
}


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

resource "aws_iam_user_policy_attachment" "local_dev_access" {
  for_each = local.ns_iam_users

  user       = regex(":user/(.+)$", each.value.principal_arn)[0]
  policy_arn = data.aws_iam_policy.local_dev_access.arn
}

# ── IAM: allow namespace-scoped users to describe the cluster and generate kubeconfigs ──

resource "aws_iam_policy" "cluster_connect" {
  name        = "${var.cluster_name}-dev-cluster-connect"
  description = "Allows namespace-scoped developers to describe and connect to the EKS cluster"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["eks:DescribeCluster", "eks:ListClusters"]
      Resource = "*"
    }]
  })

  tags = var.tags
}

resource "aws_iam_user_policy_attachment" "cluster_connect" {
  for_each = local.ns_iam_users

  user       = regex(":user/(.+)$", each.value.principal_arn)[0]
  policy_arn = aws_iam_policy.cluster_connect.arn
}
