locals {
  install_gpu_operator      = contains(["gpum", "gpul"], var.node_tier)
  install_s3_csi            = length(var.s3_bucket_arns) > 0
  install_argocd            = var.argocd_enabled
  install_training_operator = var.kubeflow_training_operator_enabled
  oidc_issuer               = regex("oidc-provider/(.+)$", var.oidc_provider_arn)[0]

  expose_argocd = (
    local.install_argocd &&
    var.argocd_hostname != null &&
    var.argocd_certificate_arn != null
  )
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

  resolve_conflicts_on_update = "OVERWRITE"
  resolve_conflicts_on_create = "OVERWRITE"

  tags       = var.tags
}

# ──────────────────────────────────────────────
# Kubeflow Training Operator
# Manages PyTorchJob, TFJob, MPIJob CRDs for distributed training.
# ──────────────────────────────────────────────

resource "helm_release" "training_operator" {
  count = local.install_training_operator ? 1 : 0

  name             = "training-operator"
  repository       = "https://kubeflow.github.io/training-operator"
  chart            = "training-operator"
  version          = "1.8.1"
  namespace        = "kubeflow"
  create_namespace = true

  values = [yamlencode({
    nodeSelector = { "node-role" = "system" }
    resources = {
      requests = { cpu = "100m", memory = "128Mi" }
      limits   = { cpu = "500m", memory = "512Mi" }
    }
  })]

  depends_on = [
    aws_eks_addon.coredns,
    helm_release.karpenter,
  ]
}

# ─────────────────────────────────────────────────────────────────────────────
# AWS Load Balancer Controller — provisions ALBs from Ingress resources
# Required to expose services (e.g. ArgoCD) via an ALB with WAF attached.
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_iam_role" "aws_lbc" {
  name = "${var.cluster_name}-aws-lbc"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = var.oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_issuer}:aud" = "sts.amazonaws.com"
          "${local.oidc_issuer}:sub" = "system:serviceaccount:kube-system:aws-load-balancer-controller"
        }
      }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "aws_lbc" {
  name = "${var.cluster_name}-aws-lbc"
  role = aws_iam_role.aws_lbc.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["iam:CreateServiceLinkedRole"]
        Resource = "*"
        Condition = {
          StringEquals = { "iam:AWSServiceName" = "elasticloadbalancing.amazonaws.com" }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeAccountAttributes", "ec2:DescribeAddresses",
          "ec2:DescribeAvailabilityZones", "ec2:DescribeInternetGateways",
          "ec2:DescribeVpcs", "ec2:DescribeVpcPeeringConnections",
          "ec2:DescribeSubnets", "ec2:DescribeSecurityGroups",
          "ec2:DescribeInstances", "ec2:DescribeNetworkInterfaces",
          "ec2:DescribeTags", "ec2:GetCoipPoolUsage",
          "ec2:DescribeCoipPools", "ec2:GetSecurityGroupsForVpc",
          "elasticloadbalancing:DescribeLoadBalancers",
          "elasticloadbalancing:DescribeLoadBalancerAttributes",
          "elasticloadbalancing:DescribeListeners",
          "elasticloadbalancing:DescribeListenerCertificates",
          "elasticloadbalancing:DescribeSSLPolicies",
          "elasticloadbalancing:DescribeRules",
          "elasticloadbalancing:DescribeTargetGroups",
          "elasticloadbalancing:DescribeTargetGroupAttributes",
          "elasticloadbalancing:DescribeTargetHealth",
          "elasticloadbalancing:DescribeTags",
          "elasticloadbalancing:DescribeTrustStores",
          "elasticloadbalancing:DescribeListenerAttributes",
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "cognito-idp:DescribeUserPoolClient",
          "acm:ListCertificates", "acm:DescribeCertificate",
          "iam:ListServerCertificates", "iam:GetServerCertificate",
          "waf-regional:GetWebACL", "waf-regional:GetWebACLForResource",
          "waf-regional:AssociateWebACL", "waf-regional:DisassociateWebACL",
          "wafv2:GetWebACL", "wafv2:GetWebACLForResource",
          "wafv2:AssociateWebACL", "wafv2:DisassociateWebACL",
          "shield:GetSubscriptionState", "shield:DescribeProtection",
          "shield:CreateProtection", "shield:DeleteProtection",
        ]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["ec2:AuthorizeSecurityGroupIngress", "ec2:RevokeSecurityGroupIngress"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["ec2:CreateSecurityGroup"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["ec2:CreateTags"]
        Resource = "arn:aws:ec2:*:*:security-group/*"
        Condition = {
          StringEquals = { "ec2:CreateAction" = "CreateSecurityGroup" }
          Null         = { "aws:RequestTag/elbv2.k8s.aws/cluster" = "false" }
        }
      },
      {
        Effect   = "Allow"
        Action   = ["ec2:CreateTags", "ec2:DeleteTags"]
        Resource = "arn:aws:ec2:*:*:security-group/*"
        Condition = {
          Null = {
            "aws:RequestTag/elbv2.k8s.aws/cluster"  = "true"
            "aws:ResourceTag/elbv2.k8s.aws/cluster" = "false"
          }
        }
      },
      {
        Effect   = "Allow"
        Action   = ["ec2:AuthorizeSecurityGroupIngress", "ec2:RevokeSecurityGroupIngress", "ec2:DeleteSecurityGroup"]
        Resource = "*"
        Condition = {
          Null = { "aws:ResourceTag/elbv2.k8s.aws/cluster" = "false" }
        }
      },
      {
        Effect   = "Allow"
        Action   = ["elasticloadbalancing:CreateLoadBalancer", "elasticloadbalancing:CreateTargetGroup"]
        Resource = "*"
        Condition = {
          Null = { "aws:RequestTag/elbv2.k8s.aws/cluster" = "false" }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:CreateListener", "elasticloadbalancing:DeleteListener",
          "elasticloadbalancing:CreateRule", "elasticloadbalancing:DeleteRule",
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = ["elasticloadbalancing:AddTags", "elasticloadbalancing:RemoveTags"]
        Resource = [
          "arn:aws:elasticloadbalancing:*:*:targetgroup/*/*",
          "arn:aws:elasticloadbalancing:*:*:loadbalancer/net/*/*",
          "arn:aws:elasticloadbalancing:*:*:loadbalancer/app/*/*",
        ]
        Condition = {
          Null = {
            "aws:RequestTag/elbv2.k8s.aws/cluster"  = "true"
            "aws:ResourceTag/elbv2.k8s.aws/cluster" = "false"
          }
        }
      },
      {
        Effect = "Allow"
        Action = ["elasticloadbalancing:AddTags", "elasticloadbalancing:RemoveTags"]
        Resource = [
          "arn:aws:elasticloadbalancing:*:*:listener/net/*/*/*",
          "arn:aws:elasticloadbalancing:*:*:listener/app/*/*/*",
          "arn:aws:elasticloadbalancing:*:*:listener-rule/net/*/*/*",
          "arn:aws:elasticloadbalancing:*:*:listener-rule/app/*/*/*",
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:ModifyLoadBalancerAttributes",
          "elasticloadbalancing:SetIpAddressType", "elasticloadbalancing:SetSecurityGroups",
          "elasticloadbalancing:SetSubnets", "elasticloadbalancing:DeleteLoadBalancer",
          "elasticloadbalancing:ModifyTargetGroup", "elasticloadbalancing:ModifyTargetGroupAttributes",
          "elasticloadbalancing:DeleteTargetGroup", "elasticloadbalancing:ModifyListenerAttributes",
        ]
        Resource = "*"
        Condition = {
          Null = { "aws:ResourceTag/elbv2.k8s.aws/cluster" = "false" }
        }
      },
      {
        Effect = "Allow"
        Action = ["elasticloadbalancing:AddTags"]
        Resource = [
          "arn:aws:elasticloadbalancing:*:*:targetgroup/*/*",
          "arn:aws:elasticloadbalancing:*:*:loadbalancer/net/*/*",
          "arn:aws:elasticloadbalancing:*:*:loadbalancer/app/*/*",
        ]
        Condition = {
          StringEquals = { "elasticloadbalancing:CreateAction" = ["CreateTargetGroup", "CreateLoadBalancer"] }
          Null         = { "aws:RequestTag/elbv2.k8s.aws/cluster" = "false" }
        }
      },
      {
        Effect   = "Allow"
        Action   = ["elasticloadbalancing:RegisterTargets", "elasticloadbalancing:DeregisterTargets"]
        Resource = "arn:aws:elasticloadbalancing:*:*:targetgroup/*/*"
      },
      {
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:SetWebAcl", "elasticloadbalancing:ModifyListener",
          "elasticloadbalancing:AddListenerCertificates", "elasticloadbalancing:RemoveListenerCertificates",
          "elasticloadbalancing:ModifyRule",
        ]
        Resource = "*"
      },
    ]
  })
}

resource "helm_release" "aws_lbc" {
  name             = "aws-load-balancer-controller"
  repository       = "https://aws.github.io/eks-charts"
  chart            = "aws-load-balancer-controller"
  version          = "1.8.1"
  namespace        = "kube-system"

  values = [yamlencode({
    clusterName = var.cluster_name
    serviceAccount = {
      annotations = {
        "eks.amazonaws.com/role-arn" = aws_iam_role.aws_lbc.arn
      }
    }
    nodeSelector = { "node-role" = "system" }
    resources = {
      requests = { cpu = "50m", memory = "128Mi" }
    }
  })]

  depends_on = [aws_eks_addon.coredns]
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
        rootVolume = true
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
      # When exposed via ALB, TLS is terminated at the load balancer and the
      # server runs in HTTP mode. extraArgs is empty when no ingress is configured.
      extraArgs = local.expose_argocd ? ["--insecure"] : []
      service   = { type = "ClusterIP" }

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

# ─────────────────────────────────────────────────────────────────────────────
# ArgoCD Ingress — internet-facing ALB with WAF (CH + AS214770) and HTTPS
# Created only when argocd_hostname and argocd_certificate_arn are provided.
# The AWS LBC reads the annotations and provisions the ALB + WAF association.
# ─────────────────────────────────────────────────────────────────────────────

resource "kubectl_manifest" "argocd_ingress" {
  count = local.expose_argocd ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "networking.k8s.io/v1"
    kind       = "Ingress"
    metadata = {
      name      = "argocd-server"
      namespace = "argocd"
      annotations = {
        "kubernetes.io/ingress.class"                        = "alb"
        "alb.ingress.kubernetes.io/scheme"                   = "internet-facing"
        "alb.ingress.kubernetes.io/target-type"              = "ip"
        "alb.ingress.kubernetes.io/ip-address-type"          = "dualstack"
        "alb.ingress.kubernetes.io/backend-protocol"         = "HTTP"
        "alb.ingress.kubernetes.io/listen-ports"             = jsonencode([{ HTTPS = 443 }])
        "alb.ingress.kubernetes.io/ssl-redirect"             = "443"
        "alb.ingress.kubernetes.io/ssl-policy"               = "ELBSecurityPolicy-TLS13-1-2-2021-06"
        "alb.ingress.kubernetes.io/certificate-arn"          = var.argocd_certificate_arn
        "alb.ingress.kubernetes.io/wafv2-acl-arn"            = var.waf_web_acl_arn
        "alb.ingress.kubernetes.io/healthcheck-path"         = "/healthz"
        "alb.ingress.kubernetes.io/healthcheck-protocol"     = "HTTP"
        "alb.ingress.kubernetes.io/success-codes"            = "200"
      }
    }
    spec = {
      rules = [{
        host = var.argocd_hostname
        http = {
          paths = [{
            path     = "/"
            pathType = "Prefix"
            backend = {
              service = {
                name = "argocd-server"
                port = { number = 80 }
              }
            }
          }]
        }
      }]
    }
  })

  depends_on = [
    helm_release.argocd,
    helm_release.aws_lbc,
  ]
}
