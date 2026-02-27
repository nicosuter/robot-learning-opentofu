locals {
  install_gpu_operator = contains(["gpum", "gpul"], var.node_tier)
  install_s3_csi       = length(var.s3_bucket_arns) > 0
  install_argocd       = var.argocd_enabled
  oidc_issuer          = regex("oidc-provider/(.+)$", var.oidc_provider_arn)[0]
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
# NVIDIA GPU Operator (gpum / gpul tiers only)
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

# NodePool: cpu — general-purpose, spot-eligible, auto-consolidating
resource "kubectl_manifest" "nodepool_cpu" {
  yaml_body = yamlencode({
    apiVersion = "karpenter.sh/v1"
    kind       = "NodePool"
    metadata   = { name = "cpu" }
    spec = {
      template = {
        metadata = { labels = { "node-tier" = "cpu" } }
        spec = {
          nodeClassRef = { group = "karpenter.k8s.aws", kind = "EC2NodeClass", name = "default" }
          requirements = [
            { key = "karpenter.sh/capacity-type", operator = "In", values = ["on-demand", "spot"] },
            { key = "karpenter.k8s.aws/instance-family", operator = "In", values = ["m5", "m6i", "t3"] },
            { key = "karpenter.k8s.aws/instance-cpu", operator = "In", values = ["2", "4"] },
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

# NodePool: gpum — mid-tier g6e.4xlarge GPU node (1× L40S), on-demand only
resource "kubectl_manifest" "nodepool_gpum" {
  yaml_body = yamlencode({
    apiVersion = "karpenter.sh/v1"
    kind       = "NodePool"
    metadata   = { name = "gpum" }
    spec = {
      template = {
        metadata = { labels = { "node-tier" = "gpum" } }
        spec = {
          nodeClassRef = { group = "karpenter.k8s.aws", kind = "EC2NodeClass", name = "default" }
          expireAfter  = var.gpu_node_max_lifetime
          requirements = [
            { key = "karpenter.sh/capacity-type", operator = "In", values = ["on-demand"] },
            { key = "karpenter.k8s.aws/instance-family", operator = "In", values = ["g6e"] },
            { key = "karpenter.k8s.aws/instance-size", operator = "In", values = ["4xlarge"] },
            { key = "kubernetes.io/arch", operator = "In", values = ["amd64"] },
          ]
          taints = [{ key = "nvidia.com/gpu", value = "true", effect = "NoSchedule" }]
        }
      }
      limits     = { "nvidia.com/gpu" = "1" }
      disruption = { consolidationPolicy = "WhenEmpty", consolidateAfter = "5m" }
    }
  })

  depends_on = [kubectl_manifest.karpenter_node_class]
}

# NodePool: gpul — single p5.xlarge GPU node (1× H100), on-demand only
resource "kubectl_manifest" "nodepool_gpul" {
  yaml_body = yamlencode({
    apiVersion = "karpenter.sh/v1"
    kind       = "NodePool"
    metadata   = { name = "gpul" }
    spec = {
      template = {
        metadata = { labels = { "node-tier" = "gpul" } }
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


# ─────────────────────────────────────────────────────────────────────────────
# ArgoCD — GitOps controller for ML workload lifecycle management
# Pinned to system nodes; ApplicationSet + notifications controllers enabled.
# ─────────────────────────────────────────────────────────────────────────────

resource "helm_release" "argocd" {
  count = local.install_argocd ? 1 : 0

  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.argocd_chart_version
  namespace        = "argocd"
  create_namespace = true

  # wait=true blocks until all Deployments are Available and CRDs are established,
  # which prevents the AppProject kubectl_manifest below from racing the CRD registration.
  wait         = true
  wait_for_jobs = true
  timeout      = 600

  values = [yamlencode({
    global = {
      # Pin all ArgoCD pods to dedicated system nodes so they are never
      # evicted when GPU / spot nodes are reclaimed.
      nodeSelector = { "node-role" = "system" }
    }

    server = {
      # Expose over in-cluster service only; add an Ingress separately if needed.
      service = { type = "ClusterIP" }

      resources = {
        requests = { cpu = "100m", memory = "128Mi" }
        limits   = { cpu = "500m", memory = "512Mi" }
      }
    }

    controller = {
      resources = {
        requests = { cpu = "250m", memory = "512Mi" }
        limits   = { cpu = "1000m", memory = "1Gi" }
      }
    }

    repoServer = {
      resources = {
        requests = { cpu = "100m", memory = "256Mi" }
        limits   = { cpu = "500m", memory = "512Mi" }
      }
    }

    # ApplicationSet controller — required for fleet-style ML workload management
    applicationSet = {
      enabled = true
      resources = {
        requests = { cpu = "50m", memory = "64Mi" }
        limits   = { cpu = "200m", memory = "128Mi" }
      }
    }

    # Notifications controller — Slack / PagerDuty alerts for training job events
    notifications = {
      enabled = true
      resources = {
        requests = { cpu = "50m", memory = "64Mi" }
        limits   = { cpu = "200m", memory = "128Mi" }
      }
    }

    # Redis — internal cache; keep it lightweight
    redis = {
      resources = {
        requests = { cpu = "50m", memory = "64Mi" }
        limits   = { cpu = "200m", memory = "128Mi" }
      }
    }
  })]

  depends_on = [
    aws_eks_addon.coredns,
    helm_release.karpenter,
  ]
}

# ArgoCD AppProject: ml-workloads
# Scopes ML training jobs, experiment trackers, and model servers to a
# dedicated project with its own RBAC boundary.
resource "kubectl_manifest" "argocd_ml_project" {
  count = local.install_argocd ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "AppProject"
    metadata = {
      name      = "ml-workloads"
      namespace = "argocd"
    }
    spec = {
      description = "ML training, experiment tracking, and model serving workloads"

      # Restrict to explicit source repos. Wildcard left as default but callers
      # should override argocd_source_repos to a specific list in production.
      sourceRepos = var.argocd_source_repos

      destinations = concat(
        [
          { server = "https://kubernetes.default.svc", namespace = "ml-workloads" },
          { server = "https://kubernetes.default.svc", namespace = "kubeflow" },
        ],
        [for ns in var.workload_namespaces : { server = "https://kubernetes.default.svc", namespace = ns }]
      )

      # Cluster-scoped resources the project may manage.
      # ClusterRole / ClusterRoleBinding are intentionally excluded: granting
      # GitOps control over RBAC primitives allows privilege escalation from
      # any repo that the project trusts.
      clusterResourceWhitelist = [
        { group = "", kind = "Namespace" },
        { group = "storage.k8s.io", kind = "StorageClass" },
        # Karpenter NodePool expansion triggered by ML workload demand
        { group = "karpenter.sh", kind = "NodePool" },
        { group = "karpenter.k8s.aws", kind = "EC2NodeClass" },
      ]

      namespaceResourceWhitelist = [
        { group = "*", kind = "*" },
      ]

      orphanedResources = { warn = true }
    }
  })

  depends_on = [helm_release.argocd]
}
