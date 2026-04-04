# ─────────────────────────────────────────────────────────────────────────────
# Training workload IRSA — provides S3 credentials to pods via a shared
# ServiceAccount in each workload namespace. Pods using `aws s3 cp` or the
# AWS SDK get credentials automatically through the projected OIDC token.
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_iam_role" "training" {
  count = length(var.s3_bucket_arns) > 0 ? 1 : 0
  name  = "${var.cluster_name}-training"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = var.oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_issuer}:aud" = "sts.amazonaws.com"
          "${local.oidc_issuer}:sub" = [
            for ns in var.workload_namespaces :
            "system:serviceaccount:${ns}:training-sa"
          ]
        }
      }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "training_s3" {
  count = length(var.s3_bucket_arns) > 0 ? 1 : 0
  name  = "${var.cluster_name}-training-s3"
  role  = aws_iam_role.training[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
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
      ],
      length(var.s3_bucket_kms_key_arns) > 0 ? [{
        Sid    = "KmsAccess"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:GenerateDataKeyWithoutPlaintext",
          "kms:DescribeKey",
        ]
        Resource = var.s3_bucket_kms_key_arns
      }] : []
    )
  })
}

resource "kubernetes_service_account" "training" {
  for_each = length(var.s3_bucket_arns) > 0 ? toset(var.workload_namespaces) : toset([])

  metadata {
    name      = "training-sa"
    namespace = each.value

    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.training[0].arn
    }

    labels = {
      "app.kubernetes.io/managed-by" = "tofu"
    }
  }

  depends_on = [kubernetes_namespace.workload]
}