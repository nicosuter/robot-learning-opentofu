data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ─────────────────────────────────────────────────────────────────────────────
# ECR Repositories
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_ecr_repository" "this" {
  for_each = toset(var.repository_names)

  name                 = each.value
  image_tag_mutability = "MUTABLE"
  force_delete         = false

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = merge(var.tags, { Name = each.value })
}

resource "aws_ecr_lifecycle_policy" "this" {
  for_each   = aws_ecr_repository.this
  repository = each.value.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 20 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 20
      }
      action = { type = "expire" }
    }]
  })
}

# ─────────────────────────────────────────────────────────────────────────────
# GitHub Actions OIDC Provider
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_iam_openid_connect_provider" "github_actions" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["1c58a3a8518e8759bf075b76b750d4f2df264fcd"]
  tags            = var.tags
}


# ─────────────────────────────────────────────────────────────────────────────
# IAM Role for GitHub Actions → ECR push
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_iam_role" "github_actions_ecr" {
  name = "${var.name_prefix}-github-actions-ecr"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.github_actions.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          "token.actions.githubusercontent.com:sub" = [
            for repo in var.github_repositories : "repo:${repo}:*"
          ]
        }
      }
    }]
  })

  tags = var.tags
}

resource "aws_iam_policy" "ecr_push" {
  name = "${var.name_prefix}-ecr-push"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AllowAuth"
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Sid    = "AllowPushPull"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
        ]
        Resource = [
          for name in var.repository_names :
          "arn:aws:ecr:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:repository/${name}"
        ]
      },
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "github_actions_ecr" {
  role       = aws_iam_role.github_actions_ecr.name
  policy_arn = aws_iam_policy.ecr_push.arn
}

resource "aws_iam_user_policy_attachment" "ecr_push" {
  for_each   = toset(var.ecr_push_iam_users)
  user       = each.value
  policy_arn = aws_iam_policy.ecr_push.arn
}