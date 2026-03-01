# ─────────────────────────────────────────────────────────────────────────────
# ArgoCD — GitOps controller for ML workload lifecycle management
# Pinned to system nodes; ApplicationSet + notifications controllers enabled.
# ─────────────────────────────────────────────────────────────────────────────

locals {
  install_argocd = var.argocd_enabled
  expose_argocd  = (
    local.install_argocd &&
    var.argocd_hostname != null &&
    var.argocd_certificate_arn != null
  )
}

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
  wait          = true
  wait_for_jobs = true
  timeout       = 600

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

# ─────────────────────────────────────────────────────────────────────────────
# ArgoCD AppProjects — one per team namespace.
# Each project is locked to a single destination namespace so that a team can
# only deploy into their own namespace via ArgoCD.
# ClusterRole / ClusterRoleBinding are intentionally excluded from
# clusterResourceWhitelist to prevent privilege escalation from any trusted repo.
# ─────────────────────────────────────────────────────────────────────────────

resource "kubectl_manifest" "argocd_team_project" {
  for_each = local.install_argocd ? toset(var.workload_namespaces) : toset([])

  yaml_body = yamlencode({
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "AppProject"
    metadata = {
      name      = each.value
      namespace = "argocd"
    }
    spec = {
      description = "Workloads for the ${each.value} team — scoped exclusively to the ${each.value} namespace."

      sourceRepos = var.argocd_source_repos

      # Only this team's namespace is an allowed destination.
      destinations = [
        { server = "https://kubernetes.default.svc", namespace = each.value }
      ]

      # Teams may not manage cluster-scoped resources through ArgoCD.
      clusterResourceWhitelist = []

      namespaceResourceWhitelist = [
        { group = "*", kind = "*" },
      ]

      orphanedResources = { warn = true }
    }
  })

  depends_on = [helm_release.argocd]
}

# ─────────────────────────────────────────────────────────────────────────────
# ArgoCD RBAC — per-team roles.
# Each team gets a role that can fully manage applications inside their own
# AppProject/namespace and nothing else. SSO/OIDC group-to-role mappings are
# supplied via var.argocd_team_groups; leave empty to configure SSO separately.
# ─────────────────────────────────────────────────────────────────────────────

resource "kubectl_manifest" "argocd_rbac_cm" {
  count = local.install_argocd ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "ConfigMap"
    metadata = {
      name      = "argocd-rbac-cm"
      namespace = "argocd"
    }
    data = {
      # Unauthenticated / unmatched users get read-only access cluster-wide.
      "policy.default" = "role:readonly"

      "policy.csv" = join("\n", flatten([
        # Per-team roles: full control over apps inside the team's own project only.
        [for ns in var.workload_namespaces : [
          "p, role:${ns}-team, applications, *, ${ns}/*, allow",
          "p, role:${ns}-team, repositories, get, *, allow",
          "p, role:${ns}-team, logs, get, ${ns}/*, allow",
          "p, role:${ns}-team, exec, create, ${ns}/*, allow",
        ]],

        # SSO/OIDC group → team role bindings (populated from argocd_team_groups).
        [for ns, groups in var.argocd_team_groups : [
          for group in groups : "g, ${group}, role:${ns}-team"
        ]],
      ]))
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
