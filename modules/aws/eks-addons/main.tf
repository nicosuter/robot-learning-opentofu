locals {
  oidc_issuer = regex("oidc-provider/(.+)$", var.oidc_provider_arn)[0]
}

# ──────────────────────────────────────────────
# Workload namespaces — created at apply time for ArgoCD to deploy into
# ──────────────────────────────────────────────

resource "kubernetes_namespace" "workload" {
  for_each = toset(var.workload_namespaces)

  metadata {
    name = each.value

    labels = {
      "app.kubernetes.io/managed-by" = "tofu"
    }
  }
}

# ──────────────────────────────────────────────
# AWS-managed EKS add-ons
# ──────────────────────────────────────────────

# CoreDNS — requires nodes to be present
resource "aws_eks_addon" "coredns" {
  cluster_name = var.cluster_name
  addon_name   = "coredns"

  resolve_conflicts_on_update = "OVERWRITE"
  resolve_conflicts_on_create = "OVERWRITE"

  tags = var.tags
}

# kube-proxy
resource "aws_eks_addon" "kube_proxy" {
  cluster_name = var.cluster_name
  addon_name   = "kube-proxy"

  resolve_conflicts_on_update = "OVERWRITE"
  resolve_conflicts_on_create = "OVERWRITE"

  tags = var.tags
}

# EBS CSI Driver — IRSA
resource "aws_iam_role" "ebs_csi" {
  name = "${var.cluster_name}-ebs-csi"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = var.oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_issuer}:aud" = "sts.amazonaws.com"
          "${local.oidc_issuer}:sub" = "system:serviceaccount:kube-system:ebs-csi-controller-sa"
        }
      }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
  role       = aws_iam_role.ebs_csi.name
}

resource "aws_eks_addon" "ebs_csi" {
  cluster_name = var.cluster_name
  addon_name   = "aws-ebs-csi-driver"

  service_account_role_arn = aws_iam_role.ebs_csi.arn

  resolve_conflicts_on_update = "OVERWRITE"
  resolve_conflicts_on_create = "OVERWRITE"

  tags = var.tags
}
