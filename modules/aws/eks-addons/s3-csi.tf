# ─────────────────────────────────────────────────────────────────────────────
# S3 CSI Driver (Mountpoint for Amazon S3)
# Conditional on s3_bucket_arns being non-empty. Creates a scoped IRSA role
# and installs the EKS managed addon.
# ─────────────────────────────────────────────────────────────────────────────

locals {
  install_s3_csi = length(var.s3_bucket_arns) > 0
}

resource "aws_iam_role" "s3_csi" {
  count = local.install_s3_csi ? 1 : 0
  name  = "${var.cluster_name}-s3-csi"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = var.oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_issuer}:aud" = "sts.amazonaws.com"
          "${local.oidc_issuer}:sub" = "system:serviceaccount:kube-system:s3-csi-driver-sa"
        }
      }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "s3_csi" {
  count = local.install_s3_csi ? 1 : 0
  name  = "${var.cluster_name}-s3-csi"
  role  = aws_iam_role.s3_csi[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ObjectAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:AbortMultipartUpload",
          "s3:DeleteObject",
        ]
        Resource = [for arn in var.s3_bucket_arns : "${arn}/*"]
      },
      {
        Sid    = "BucketAccess"
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetBucketLocation",
        ]
        Resource = var.s3_bucket_arns
      },
    ]
  })
}

resource "aws_eks_addon" "s3_csi" {
  count        = local.install_s3_csi ? 1 : 0
  cluster_name = var.cluster_name
  addon_name   = "aws-mountpoint-s3-csi-driver"

  service_account_role_arn = aws_iam_role.s3_csi[0].arn

  resolve_conflicts_on_update = "OVERWRITE"
  resolve_conflicts_on_create = "OVERWRITE"

  tags = var.tags
}
