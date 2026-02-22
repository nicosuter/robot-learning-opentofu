locals {
  install_gpu_operator = contains(["gpu", "gpux"], var.node_tier)
  install_s3_csi       = length(var.s3_bucket_arns) > 0
  oidc_issuer          = regex("oidc-provider/(.+)$", var.oidc_provider_arn)[0]
}

# ──────────────────────────────────────────────
# AWS-managed EKS add-ons
# ──────────────────────────────────────────────

# VPC CNI — IPv6 / prefix-delegation mode (IRSA)
resource "aws_iam_role" "vpc_cni" {
  name = "${var.cluster_name}-vpc-cni"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = var.oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_issuer}:aud" = "sts.amazonaws.com"
          "${local.oidc_issuer}:sub" = "system:serviceaccount:kube-system:aws-node"
        }
      }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "vpc_cni" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.vpc_cni.name
}

resource "aws_eks_addon" "vpc_cni" {
  cluster_name = var.cluster_name
  addon_name   = "vpc-cni"

  service_account_role_arn = aws_iam_role.vpc_cni.arn

  configuration_values = jsonencode({
    env = {
      ENABLE_IPv6              = "true"
      ENABLE_PREFIX_DELEGATION = "true"
      ENABLE_IPv4              = "false"
    }
  })

  tags = var.tags
}

# CoreDNS — requires nodes to be present
resource "aws_eks_addon" "coredns" {
  cluster_name = var.cluster_name
  addon_name   = "coredns"

  tags = var.tags

  # Implicit dependency: node group must exist before coredns can schedule
  depends_on = [aws_eks_addon.vpc_cni]
}

# kube-proxy
resource "aws_eks_addon" "kube_proxy" {
  cluster_name = var.cluster_name
  addon_name   = "kube-proxy"

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

  tags = var.tags

  depends_on = [aws_eks_addon.vpc_cni]
}

# ─────────────────────────────────────────────────────────────────────────────
# S3 CSI Driver (Mountpoint for Amazon S3)
# Conditional on s3_bucket_arns being non-empty. Creates a scoped IRSA role
# and installs the EKS managed addon.
# ─────────────────────────────────────────────────────────────────────────────

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

  tags       = var.tags
  depends_on = [aws_eks_addon.vpc_cni]
}

# ──────────────────────────────────────────────
# NVIDIA GPU Operator (gpu / gpux tiers only)
# ──────────────────────────────────────────────
# EKS GPU-optimised AMIs ship with NVIDIA drivers pre-installed, so
# driver.enabled=false tells the operator to skip driver installation and only
# manage the device plugin, DCGM exporter, and other components.

resource "helm_release" "nvidia_gpu_operator" {
  count = local.install_gpu_operator ? 1 : 0

  name             = "gpu-operator"
  repository       = "https://helm.ngc.nvidia.com/nvidia"
  chart            = "gpu-operator"
  version          = "25.10.1"
  namespace        = "gpu-operator"
  create_namespace = true

  values = [yamlencode({
    driver = { enabled = false }
  })]

  depends_on = [
    aws_eks_addon.coredns,
    helm_release.karpenter,
  ]
}

# ─────────────────────────────────────────────────────────────────────────────
# Karpenter
# ─────────────────────────────────────────────────────────────────────────────

resource "helm_release" "karpenter" {
  name             = "karpenter"
  repository       = "oci://public.ecr.aws/karpenter"
  chart            = "karpenter"
  version          = "1.9.0"
  namespace        = "karpenter"
  create_namespace = true

  values = [yamlencode({
    settings = {
      clusterName       = var.cluster_name
      interruptionQueue = var.karpenter_interruption_queue_name
    }
    serviceAccount = {
      annotations = {
        "eks.amazonaws.com/role-arn" = var.karpenter_role_arn
      }
    }
    # Pin controller to the system node group so it never self-evicts
    nodeSelector = { node-role = "system" }
    controller = {
      resources = {
        requests = { cpu = "100m", memory = "256Mi" }
      }
    }
  })]

  depends_on = [aws_eks_addon.coredns]
}

# EC2NodeClass — shared node config; subnets + SG discovered via karpenter.sh/discovery tags
resource "kubectl_manifest" "karpenter_node_class" {
  yaml_body = yamlencode({
    apiVersion = "karpenter.k8s.aws/v1"
    kind       = "EC2NodeClass"
    metadata   = { name = "default" }
    spec = {
      amiSelectorTerms           = [{ alias = "al2023@latest" }]
      role                       = var.node_iam_role_name
      subnetSelectorTerms        = [{ tags = { "karpenter.sh/discovery" = var.cluster_name } }]
      securityGroupSelectorTerms = [{ tags = { "karpenter.sh/discovery" = var.cluster_name } }]
      tags                       = merge(var.tags, { "karpenter.sh/discovery" = var.cluster_name })

      metadataOptions = {
        httpEndpoint            = "enabled"
        httpProtocolIPv6        = "enabled"
        httpPutResponseHopLimit = 1
        httpTokens              = "required"
      }

      blockDeviceMappings = [{
        deviceName = "/dev/xvda"
        ebs = {
          volumeSize          = "${var.node_disk_size}Gi"
          volumeType          = "gp3"
          encrypted           = true
          deleteOnTermination = true
        }
      }]
    }
  })

  depends_on = [helm_release.karpenter]
}

# NodePool: standard — general-purpose, spot-eligible, auto-consolidating
resource "kubectl_manifest" "nodepool_standard" {
  yaml_body = yamlencode({
    apiVersion = "karpenter.sh/v1"
    kind       = "NodePool"
    metadata   = { name = "standard" }
    spec = {
      template = {
        metadata = { labels = { "node-tier" = "standard" } }
        spec = {
          nodeClassRef = { group = "karpenter.k8s.aws", kind = "EC2NodeClass", name = "default" }
          requirements = [
            { key = "karpenter.sh/capacity-type", operator = "In", values = ["on-demand", "spot"] },
            { key = "karpenter.k8s.aws/instance-family", operator = "In", values = ["m5", "m6i", "t3"] },
            { key = "karpenter.k8s.aws/instance-cpu", operator = "In", values = ["2", "4", "8"] },
            { key = "kubernetes.io/arch", operator = "In", values = ["amd64"] },
          ]
        }
      }
      limits     = { cpu = "100" }
      disruption = { consolidationPolicy = "WhenEmptyOrUnderutilized", consolidateAfter = "1m" }
    }
  })

  depends_on = [kubectl_manifest.karpenter_node_class]
}

# NodePool: gpu — single p5 GPU node, on-demand only
resource "kubectl_manifest" "nodepool_gpu" {
  yaml_body = yamlencode({
    apiVersion = "karpenter.sh/v1"
    kind       = "NodePool"
    metadata   = { name = "gpu" }
    spec = {
      template = {
        metadata = { labels = { "node-tier" = "gpu" } }
        spec = {
          nodeClassRef = { group = "karpenter.k8s.aws", kind = "EC2NodeClass", name = "default" }
          expireAfter  = var.gpu_node_max_lifetime
          requirements = [
            { key = "karpenter.sh/capacity-type", operator = "In", values = ["on-demand"] },
            { key = "karpenter.k8s.aws/instance-family", operator = "In", values = ["p5"] },
            { key = "karpenter.k8s.aws/instance-size", operator = "In", values = ["xlarge"] },
            { key = "kubernetes.io/arch", operator = "In", values = ["amd64"] },
          ]
          taints = [{ key = "nvidia.com/gpu", value = "true", effect = "NoSchedule" }]
        }
      }
      limits     = { "nvidia.com/gpu" = "8" }
      disruption = { consolidationPolicy = "WhenEmpty", consolidateAfter = "5m" }
    }
  })

  depends_on = [kubectl_manifest.karpenter_node_class]
}

# NodePool: gpux — full NVLink p5.48xlarge, on-demand only
resource "kubectl_manifest" "nodepool_gpux" {
  yaml_body = yamlencode({
    apiVersion = "karpenter.sh/v1"
    kind       = "NodePool"
    metadata   = { name = "gpux" }
    spec = {
      template = {
        metadata = { labels = { "node-tier" = "gpux" } }
        spec = {
          nodeClassRef = { group = "karpenter.k8s.aws", kind = "EC2NodeClass", name = "default" }
          expireAfter  = var.gpu_node_max_lifetime
          requirements = [
            { key = "karpenter.sh/capacity-type", operator = "In", values = ["on-demand"] },
            { key = "karpenter.k8s.aws/instance-family", operator = "In", values = ["p5"] },
            { key = "karpenter.k8s.aws/instance-size", operator = "In", values = ["48xlarge"] },
            { key = "kubernetes.io/arch", operator = "In", values = ["amd64"] },
          ]
          taints = [{ key = "nvidia.com/gpu", value = "true", effect = "NoSchedule" }]
        }
      }
      limits     = { "nvidia.com/gpu" = "16" }
      disruption = { consolidationPolicy = "WhenEmpty", consolidateAfter = "10m" }
    }
  })

  depends_on = [kubectl_manifest.karpenter_node_class]
}
