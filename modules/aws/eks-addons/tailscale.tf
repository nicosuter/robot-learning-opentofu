# ─────────────────────────────────────────────────────────────────────────────
# Tailscale Operator — Mesh networking for hybrid EKS nodes
#
# Provides secure, encrypted mesh networking between the EKS cluster and
# on-premises hybrid nodes without requiring VPN or Direct Connect.
#
# The operator can also function as a subnet router to advertise the cluster
# and VPC CIDRs to the Tailscale network.
# ─────────────────────────────────────────────────────────────────────────────

locals {
  tailscale_namespace = "tailscale"
}

resource "kubernetes_namespace" "tailscale" {
  count = var.tailscale_enabled ? 1 : 0

  metadata {
    name = local.tailscale_namespace

    labels = {
      "app.kubernetes.io/managed-by" = "tofu"
    }
  }
}

resource "helm_release" "tailscale_operator" {
  count = var.tailscale_enabled ? 1 : 0

  name       = "tailscale-operator"
  namespace  = local.tailscale_namespace
  repository = "https://pkgs.tailscale.com/helmcharts"
  chart      = "tailscale-operator"
  version    = var.tailscale_chart_version

  set_sensitive {
    name  = "oauth.clientId"
    value = var.tailscale_oauth_client_id
  }

  set_sensitive {
    name  = "oauth.clientSecret"
    value = var.tailscale_oauth_client_secret
  }

  # Enable proxy mode for pod-to-pod mesh networking
  set {
    name  = "proxy"
    value = "true"
  }

  # Configure as subnet router to advertise VPC CIDRs
  set {
    name  = "subnetRouter"
    value = "true"
  }

  # Advertise routes for the VPC CIDR (auto-detected if not specified)
  set {
    name  = "subnetRouterAdvertiseRoutes"
    value = ""  # Leave empty to auto-detect from node routes
  }

  # Accept DNS from Tailscale
  set {
    name  = "dns"
    value = "true"
  }

  # Enable metrics for monitoring
  set {
    name  = "metrics.enabled"
    value = "true"
  }

  # Configure resource limits
  set {
    name  = "resources.limits.cpu"
    value = "500m"
  }

  set {
    name  = "resources.limits.memory"
    value = "512Mi"
  }

  set {
    name  = "resources.requests.cpu"
    value = "100m"
  }

  set {
    name  = "resources.requests.memory"
    value = "128Mi"
  }

  depends_on = [kubernetes_namespace.tailscale]
}

# Create a ProxyClass for GPU workloads that need Tailscale connectivity
resource "kubectl_manifest" "tailscale_proxyclass_gpu" {
  count = var.tailscale_enabled && var.gpu_operator_enabled ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "tailscale.com/v1alpha1"
    kind       = "ProxyClass"
    metadata = {
      name      = "gpu-workloads"
      namespace = local.tailscale_namespace
    }
    spec = {
      # Allow GPU workloads to use Tailscale sidecars
      statefulSet = {
        pod = {
          tailscaleContainer = {
            resources = {
              limits = {
                cpu    = "500m"
                memory = "256Mi"
              }
              requests = {
                cpu    = "100m"
                memory = "128Mi"
              }
            }
          }
        }
      }
    }
  })

  depends_on = [helm_release.tailscale_operator]
}
