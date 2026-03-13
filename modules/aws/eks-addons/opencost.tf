# ─────────────────────────────────────────────────────────────────────────────
# OpenCost — open source cost monitoring for Kubernetes
#
# Tracks per-namespace, per-pod, and per-workload costs including
# GPU node spending. Useful for chargeback and cost optimization.
# See: https://opencost.io/docs/installation/install
# ─────────────────────────────────────────────────────────────────────────────

locals {
  enable_opencost = true
}

# Prometheus server for OpenCost metrics
resource "helm_release" "prometheus" {
  count = local.enable_opencost ? 1 : 0

  name             = "prometheus"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "prometheus"
  version          = "25.27.0"
  namespace        = "prometheus-system"
  create_namespace = true

  values = [yamlencode({
    server = {
      persistentVolume = {
        enabled = true
        size    = "10Gi"
      }
      retention = "15d"
      # Scrape OpenCost metrics
      extraScrapeConfigs = <<-EOF
        - job_name: opencost
          honor_labels: true
          scrape_interval: 1m
          scrape_timeout: 10s
          metrics_path: /metrics
          scheme: http
          dns_sd_configs:
          - names:
            - opencost.opencost
            type: 'A'
            port: 9003
      EOF
    }
    # Reduce resource usage for our setup
    alertmanager = {
      enabled = false
    }
    pushgateway = {
      enabled = false
    }
  })]

  depends_on = [aws_eks_addon.coredns]
}

# OpenCost cost monitoring
resource "helm_release" "opencost" {
  count = local.enable_opencost ? 1 : 0

  name             = "opencost"
  repository       = "https://opencost.github.io/opencost-helm-chart"
  chart            = "opencost"
  version          = "1.42.0"
  namespace        = "opencost"
  create_namespace = true

  values = [yamlencode({
    opencost = {
      exporter = {
        defaultClusterId = var.cluster_name
      }
      prometheus = {
        # Explicitly disable internal mode (defaults to true)
        internal = {
          enabled = false
        }
        # Use external mode pointing to our deployed Prometheus
        external = {
          enabled = true
          url = "http://prometheus-server.prometheus-system.svc.cluster.local:80"
        }
      }
      ui = {
        enabled = true
      }
    }
    # Resource requests for cost exporter
    resources = {
      requests = {
        cpu    = "100m"
        memory = "256Mi"
      }
      limits = {
        cpu    = "500m"
        memory = "512Mi"
      }
    }
  })]

  depends_on = [helm_release.prometheus]
}