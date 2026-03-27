# IAM Role for EKS Cluster
resource "aws_iam_role" "eks_cluster" {
  name = "${var.cluster_name}-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_name}-cluster-role"
    }
  )
}

# Attach required policies to EKS Cluster Role
resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster.name
}

resource "aws_iam_role_policy_attachment" "eks_vpc_resource_controller" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  role       = aws_iam_role.eks_cluster.name
}

# IAM Role for EKS Node Group
resource "aws_iam_role" "eks_nodes" {
  name = "${var.cluster_name}-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_name}-node-role"
    }
  )
}

# Attach required policies to EKS Node Role
resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_nodes.name
}

resource "aws_iam_role_policy_attachment" "eks_container_registry_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_nodes.name
}

resource "aws_iam_role_policy_attachment" "eks_nodes_cni" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_nodes.name
}


resource "aws_iam_role_policy" "eks_nodes_ipv6" {
  name = "${var.cluster_name}-nodes-ipv6"
  role = aws_iam_role.eks_nodes.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:AssignIpv6Addresses",
          "ec2:UnassignIpv6Addresses",
          "ec2:AssignIpv6Prefixes",
          "ec2:UnassignIpv6Prefixes",
        ]
        Resource = "*"
      },
    ]
  })
}

# EKS Cluster
resource "aws_eks_cluster" "main" {
  name     = var.cluster_name
  role_arn = aws_iam_role.eks_cluster.arn
  version  = var.cluster_version

  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = true
  }

  upgrade_policy {
    support_type = "STANDARD"
  }

  vpc_config {
    subnet_ids              = concat(var.private_subnet_ids, var.public_subnet_ids)
    security_group_ids      = [var.cluster_security_group_id]
    endpoint_private_access = true
    endpoint_public_access  = true
    # Restrict public API server access by CIDR. Defaults to 0.0.0.0/0 when
    # empty; set api_server_allowed_cidrs in the root module to lock this down.
    public_access_cidrs = length(var.api_server_allowed_cidrs) > 0 ? var.api_server_allowed_cidrs : ["0.0.0.0/0"]
  }

  kubernetes_network_config {
    # IPv6 primary for pod and service networking
    ip_family = "ipv6"
  }

  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  tags = merge(
    var.tags,
    {
      Name = var.cluster_name
    }
  )

  lifecycle {
    prevent_destroy = true
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
    aws_iam_role_policy_attachment.eks_vpc_resource_controller,
  ]
}

# Launch template for the system node group — sets the EC2 instance Name tag and
# owns disk configuration (required when a launch template is used).
resource "aws_launch_template" "system" {
  name_prefix = "${var.cluster_name}-system-"

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = var.system_node_disk_size
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags = merge(var.tags, {
      Name = "${var.cluster_name}-system-1"
    })
  }

  tags = var.tags
}

# System node group — runs cluster-critical workloads (CoreDNS, kube-proxy, Karpenter controller).
# All workload nodes are provisioned on-demand by Karpenter.
resource "aws_eks_node_group" "system" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.cluster_name}-system"
  node_role_arn   = aws_iam_role.eks_nodes.arn
  subnet_ids      = var.use_public_subnets_for_nodes ? var.public_subnet_ids : var.private_subnet_ids
  instance_types  = ["t3.xlarge"]

  launch_template {
    id      = aws_launch_template.system.id
    version = aws_launch_template.system.latest_version
  }

  scaling_config {
    desired_size = 1
    min_size     = 1
    max_size     = 1
  }

  update_config {
    max_unavailable = 1
  }

  labels = {
    "node-role" = "system"
  }

  capacity_type = "ON_DEMAND"

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-system"
  })

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_container_registry_policy,
    aws_iam_role_policy_attachment.eks_nodes_cni,
    aws_iam_role_policy.eks_nodes_ipv6,
    aws_eks_addon.vpc_cni,
  ]

  lifecycle {
    create_before_destroy = true
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# VPC CNI Addon — IPv6 / prefix-delegation mode (IRSA)
# Must be initialized BEFORE nodes join to avoid "cni not initialized" errors.
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_iam_role" "vpc_cni" {
  name = "${var.cluster_name}-vpc-cni"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.eks.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_provider_id}:aud" = "sts.amazonaws.com"
          "${local.oidc_provider_id}:sub" = "system:serviceaccount:kube-system:aws-node"
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

resource "aws_iam_role_policy" "vpc_cni_ipv6" {
  name = "${var.cluster_name}-vpc-cni-ipv6"
  role = aws_iam_role.vpc_cni.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:AssignIpv6Addresses",
          "ec2:UnassignIpv6Addresses",
          "ec2:AssignIpv6Prefixes",
          "ec2:UnassignIpv6Prefixes",
        ]
        Resource = "*"
      },
    ]
  })
}

resource "aws_eks_addon" "vpc_cni" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "vpc-cni"

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  service_account_role_arn    = aws_iam_role.vpc_cni.arn
  configuration_values = jsonencode({
    enableNetworkPolicy = "true"
  })

  tags = var.tags
}

# ─────────────────────────────────────────────────────────────────────────────
# Cluster access IAM policy — grants the AWS-side permissions required to
# run `aws eks update-kubeconfig` and call the Kubernetes API.
# Attach this policy to any IAM user/role that needs kubectl access.
# Kubernetes RBAC is handled separately via the access entries below.
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_iam_policy" "cluster_access" {
  name        = "${var.cluster_name}-cluster-access"
  description = "Allows aws eks update-kubeconfig and signed API calls to ${var.cluster_name}"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DescribeCluster"
        Effect = "Allow"
        Action = ["eks:DescribeCluster"]
        Resource = "arn:aws:eks:*:*:cluster/${var.cluster_name}"
      },
    ]
  })

  tags = var.tags
}

# ─────────────────────────────────────────────────────────────────────────────
# OIDC Provider — enables IRSA (IAM Roles for Service Accounts)
# ─────────────────────────────────────────────────────────────────────────────

data "aws_region" "current" {}

data "tls_certificate" "eks_oidc" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks_oidc.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer
  tags            = var.tags
}

# ─────────────────────────────────────────────────────────────────────────────
# Karpenter — IAM role (IRSA), SQS interruption queue, EventBridge rules,
#             and discovery tags on subnets / cluster SG
# ─────────────────────────────────────────────────────────────────────────────

locals {
  oidc_provider_id = trimprefix(aws_eks_cluster.main.identity[0].oidc[0].issuer, "https://")
}

resource "aws_iam_role" "karpenter" {
  name = "${var.cluster_name}-karpenter"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = "sts:AssumeRoleWithWebIdentity"
      Principal = {
        Federated = aws_iam_openid_connect_provider.eks.arn
      }
      Condition = {
        StringEquals = {
          "${local.oidc_provider_id}:sub" = "system:serviceaccount:${var.karpenter_namespace}:karpenter"
          "${local.oidc_provider_id}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "karpenter" {
  name = "${var.cluster_name}-karpenter"
  role = aws_iam_role.karpenter.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowScopedEC2InstanceAccessActions"
        Effect = "Allow"
        Resource = [
          "arn:aws:ec2:*:*:image/*",
          "arn:aws:ec2:*:*:snapshot/*",
          "arn:aws:ec2:*:*:spot-instances-request/*",
          "arn:aws:ec2:*:*:security-group/*",
          "arn:aws:ec2:*:*:subnet/*",
          "arn:aws:ec2:*:*:launch-template/*",
        ]
        Action = ["ec2:RunInstances", "ec2:CreateFleet"]
      },
      {
        Sid    = "AllowScopedEC2InstanceActionsWithTags"
        Effect = "Allow"
        Resource = [
          "arn:aws:ec2:*:*:fleet/*",
          "arn:aws:ec2:*:*:instance/*",
          "arn:aws:ec2:*:*:volume/*",
          "arn:aws:ec2:*:*:network-interface/*",
          "arn:aws:ec2:*:*:launch-template/*",
          "arn:aws:ec2:*:*:spot-instances-request/*",
        ]
        Action = ["ec2:RunInstances", "ec2:CreateFleet", "ec2:CreateLaunchTemplate"]
        Condition = {
          StringEquals = { "aws:RequestTag/kubernetes.io/cluster/${var.cluster_name}" = "owned" }
          StringLike   = { "aws:RequestTag/karpenter.sh/nodepool" = "*" }
        }
      },
      {
        Sid    = "AllowScopedResourceCreationTagging"
        Effect = "Allow"
        Resource = [
          "arn:aws:ec2:*:*:fleet/*",
          "arn:aws:ec2:*:*:instance/*",
          "arn:aws:ec2:*:*:volume/*",
          "arn:aws:ec2:*:*:network-interface/*",
          "arn:aws:ec2:*:*:launch-template/*",
          "arn:aws:ec2:*:*:spot-instances-request/*",
        ]
        Action = ["ec2:CreateTags"]
        Condition = {
          StringEquals = {
            "aws:RequestTag/kubernetes.io/cluster/${var.cluster_name}" = "owned"
            "ec2:CreateAction"                                         = ["RunInstances", "CreateFleet", "CreateLaunchTemplate"]
          }
          StringLike = { "aws:RequestTag/karpenter.sh/nodepool" = "*" }
        }
      },
      {
        Sid      = "AllowScopedResourceTagging"
        Effect   = "Allow"
        Resource = ["arn:aws:ec2:*:*:instance/*"]
        Action   = ["ec2:CreateTags"]
        Condition = {
          StringEquals              = { "aws:ResourceTag/kubernetes.io/cluster/${var.cluster_name}" = "owned" }
          StringLike                = { "aws:ResourceTag/karpenter.sh/nodepool" = "*" }
          "ForAllValues:StringEquals" = { "aws:TagKeys" = ["karpenter.sh/nodeclaim", "Name"] }
        }
      },
      {
        Sid    = "AllowScopedDeletion"
        Effect = "Allow"
        Resource = [
          "arn:aws:ec2:*:*:instance/*",
          "arn:aws:ec2:*:*:launch-template/*",
        ]
        Action = ["ec2:TerminateInstances", "ec2:DeleteLaunchTemplate"]
        Condition = {
          StringEquals = { "aws:ResourceTag/kubernetes.io/cluster/${var.cluster_name}" = "owned" }
          StringLike   = { "aws:ResourceTag/karpenter.sh/nodepool" = "*" }
        }
      },
      {
        Sid      = "AllowRegionalReadActions"
        Effect   = "Allow"
        Resource = ["*"]
        Action = [
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeImages",
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceTypeOfferings",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeLaunchTemplates",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSpotPriceHistory",
          "ec2:DescribeSubnets",
        ]
        Condition = { StringEquals = { "aws:RequestedRegion" = data.aws_region.current.region } }
      },
      {
        Sid      = "AllowSSMReadActions"
        Effect   = "Allow"
        Resource = ["arn:aws:ssm:*::parameter/aws/service/*"]
        Action   = ["ssm:GetParameter"]
      },
      {
        Sid      = "AllowPricingReadActions"
        Effect   = "Allow"
        Resource = ["*"]
        Action   = ["pricing:GetProducts"]
      },
      {
        Sid      = "AllowInterruptionQueueActions"
        Effect   = "Allow"
        Resource = [aws_sqs_queue.karpenter_interruption.arn]
        Action   = ["sqs:DeleteMessage", "sqs:GetQueueAttributes", "sqs:GetQueueUrl", "sqs:ReceiveMessage"]
      },
      {
        Sid       = "AllowPassingInstanceRole"
        Effect    = "Allow"
        Resource  = [aws_iam_role.eks_nodes.arn]
        Action    = ["iam:PassRole"]
        Condition = { StringEquals = { "iam:PassedToService" = "ec2.amazonaws.com" } }
      },
      {
        Sid      = "AllowScopedInstanceProfileCreationActions"
        Effect   = "Allow"
        Resource = ["*"]
        Action   = ["iam:CreateInstanceProfile"]
        Condition = {
          StringEquals = { "aws:RequestTag/kubernetes.io/cluster/${var.cluster_name}" = "owned" }
          StringLike   = { "aws:RequestTag/karpenter.k8s.aws/ec2nodeclass" = "*" }
        }
      },
      {
        Sid      = "AllowScopedInstanceProfileTagActions"
        Effect   = "Allow"
        Resource = ["*"]
        Action   = ["iam:TagInstanceProfile"]
        Condition = {
          StringEquals = {
            "aws:ResourceTag/kubernetes.io/cluster/${var.cluster_name}" = "owned"
            "aws:RequestTag/kubernetes.io/cluster/${var.cluster_name}"  = "owned"
          }
          StringLike = {
            "aws:ResourceTag/karpenter.k8s.aws/ec2nodeclass" = "*"
            "aws:RequestTag/karpenter.k8s.aws/ec2nodeclass"  = "*"
          }
        }
      },
      {
        Sid      = "AllowScopedInstanceProfileActions"
        Effect   = "Allow"
        Resource = ["*"]
        Action   = ["iam:AddRoleToInstanceProfile", "iam:RemoveRoleFromInstanceProfile", "iam:DeleteInstanceProfile"]
        Condition = {
          StringEquals = { "aws:ResourceTag/kubernetes.io/cluster/${var.cluster_name}" = "owned" }
          StringLike   = { "aws:ResourceTag/karpenter.k8s.aws/ec2nodeclass" = "*" }
        }
      },
      {
        Sid      = "AllowInstanceProfileReadActions"
        Effect   = "Allow"
        Resource = ["*"]
        Action   = ["iam:GetInstanceProfile", "iam:ListInstanceProfiles"]
      },
      {
        Sid      = "AllowAPIServerEndpointDiscovery"
        Effect   = "Allow"
        Resource = ["arn:aws:eks:*:*:cluster/${var.cluster_name}"]
        Action   = ["eks:DescribeCluster"]
      },
    ]
  })
}

# SQS queue — receives spot interruption / rebalance / state-change events
resource "aws_sqs_queue" "karpenter_interruption" {
  name                      = "${var.cluster_name}-karpenter-interruption"
  message_retention_seconds = 300
  sqs_managed_sse_enabled   = true
  tags                      = var.tags
}

resource "aws_sqs_queue_policy" "karpenter_interruption" {
  queue_url = aws_sqs_queue.karpenter_interruption.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = ["events.amazonaws.com", "sqs.amazonaws.com"] }
      Action    = "sqs:SendMessage"
      Resource  = aws_sqs_queue.karpenter_interruption.arn
    }]
  })
}

resource "aws_cloudwatch_event_rule" "karpenter_spot_interruption" {
  name          = "${var.cluster_name}-karpenter-spot-interruption"
  event_pattern = jsonencode({ source = ["aws.ec2"], "detail-type" = ["EC2 Spot Instance Interruption Warning"] })
  tags          = var.tags
}

resource "aws_cloudwatch_event_rule" "karpenter_rebalance" {
  name          = "${var.cluster_name}-karpenter-rebalance"
  event_pattern = jsonencode({ source = ["aws.ec2"], "detail-type" = ["EC2 Instance Rebalance Recommendation"] })
  tags          = var.tags
}

resource "aws_cloudwatch_event_rule" "karpenter_instance_state" {
  name          = "${var.cluster_name}-karpenter-instance-state"
  event_pattern = jsonencode({ source = ["aws.ec2"], "detail-type" = ["EC2 Instance State-change Notification"] })
  tags          = var.tags
}

resource "aws_cloudwatch_event_target" "karpenter_spot_interruption" {
  rule = aws_cloudwatch_event_rule.karpenter_spot_interruption.name
  arn  = aws_sqs_queue.karpenter_interruption.arn
}

resource "aws_cloudwatch_event_target" "karpenter_rebalance" {
  rule = aws_cloudwatch_event_rule.karpenter_rebalance.name
  arn  = aws_sqs_queue.karpenter_interruption.arn
}

resource "aws_cloudwatch_event_target" "karpenter_instance_state" {
  rule = aws_cloudwatch_event_rule.karpenter_instance_state.name
  arn  = aws_sqs_queue.karpenter_interruption.arn
}

# Tag ALL subnets for Karpenter discovery; worker nodes use public subnets to avoid NAT costs
resource "aws_ec2_tag" "karpenter_public_subnet" {
  for_each    = { for i, id in var.public_subnet_ids : tostring(i) => id }
  resource_id = each.value
  key         = "karpenter.sh/discovery"
  value       = var.cluster_name
}

resource "aws_ec2_tag" "karpenter_private_subnet" {
  for_each    = { for i, id in var.private_subnet_ids : tostring(i) => id }
  resource_id = each.value
  key         = "karpenter.sh/discovery"
  value       = var.cluster_name
}

resource "aws_ec2_tag" "karpenter_cluster_sg" {
  resource_id = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
  key         = "karpenter.sh/discovery"
  value       = var.cluster_name
}

# ─────────────────────────────────────────────────────────────────────────────
# Hybrid EKS Nodes — IAM role and SSM activation for on-premises infrastructure
# ─────────────────────────────────────────────────────────────────────────────

# IAM Role for Hybrid EKS Nodes (SSM trust policy for activation)
resource "aws_iam_role" "hybrid_nodes" {
  count = var.enable_hybrid_nodes ? 1 : 0
  name  = "${var.cluster_name}-hybrid-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ssm.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_name}-hybrid-node-role"
    }
  )
}

# Attach required policies to Hybrid Node Role
resource "aws_iam_role_policy_attachment" "hybrid_eks_worker" {
  count      = var.enable_hybrid_nodes ? 1 : 0
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.hybrid_nodes[0].name
}

resource "aws_iam_role_policy_attachment" "hybrid_eks_cni" {
  count      = var.enable_hybrid_nodes ? 1 : 0
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.hybrid_nodes[0].name
}

resource "aws_iam_role_policy_attachment" "hybrid_ecr_readonly" {
  count      = var.enable_hybrid_nodes ? 1 : 0
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.hybrid_nodes[0].name
}

# SSM policy for hybrid node activation and management
resource "aws_iam_role_policy_attachment" "hybrid_ssm" {
  count      = var.enable_hybrid_nodes ? 1 : 0
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = aws_iam_role.hybrid_nodes[0].name
}

# IPv6 policy for hybrid nodes (matches EC2 node configuration)
resource "aws_iam_role_policy" "hybrid_nodes_ipv6" {
  count = var.enable_hybrid_nodes ? 1 : 0
  name  = "${var.cluster_name}-hybrid-nodes-ipv6"
  role  = aws_iam_role.hybrid_nodes[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:AssignIpv6Addresses",
          "ec2:UnassignIpv6Addresses",
          "ec2:AssignIpv6Prefixes",
          "ec2:UnassignIpv6Prefixes",
        ]
        Resource = "*"
      },
    ]
  })
}

# SSM Activation for hybrid node registration
resource "aws_ssm_activation" "hybrid_nodes" {
  count              = var.enable_hybrid_nodes ? 1 : 0
  name               = "${var.cluster_name}-hybrid-nodes"
  iam_role           = aws_iam_role.hybrid_nodes[0].id
  registration_limit = var.hybrid_node_registration_limit
  description        = "SSM activation for hybrid EKS nodes in ${var.cluster_name}"

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_name}-hybrid-nodes"
    }
  )

  depends_on = [
    aws_iam_role_policy_attachment.hybrid_eks_worker,
    aws_iam_role_policy_attachment.hybrid_eks_cni,
    aws_iam_role_policy_attachment.hybrid_ecr_readonly,
    aws_iam_role_policy_attachment.hybrid_ssm,
    aws_iam_role_policy.hybrid_nodes_ipv6,
  ]
}
