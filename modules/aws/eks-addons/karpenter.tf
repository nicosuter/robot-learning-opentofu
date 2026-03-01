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
