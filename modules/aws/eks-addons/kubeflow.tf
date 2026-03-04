# ─────────────────────────────────────────────────────────────────────────────
# Kubeflow Trainer v2 — TrainJob controller for distributed ML training
# Replaces legacy Training Operator (PyTorchJob/TFJob/MPIJob). Uses TrainJob API.
# ─────────────────────────────────────────────────────────────────────────────

locals {
  install_training_operator = var.kubeflow_training_operator_enabled
  install_dashboard = (
    local.install_training_operator &&
    var.kubeflow_dashboard_enabled
  )
  expose_dashboard = (
    local.install_dashboard &&
    var.kubeflow_dashboard_hostname != null &&
    var.kubeflow_dashboard_certificate_arn != null
  )
}

resource "helm_release" "kubeflow_trainer" {
  count = local.install_training_operator ? 1 : 0

  name             = "kubeflow-trainer"
  chart            = "oci://ghcr.io/kubeflow/charts/kubeflow-trainer"
  version          = "2.1.0"
  namespace        = "kubeflow-system"
  create_namespace = true

  values = [yamlencode({
    manager = {
      nodeSelector = { "node-role" = "system" }
      resources = {
        requests = { cpu = "100m", memory = "128Mi" }
        limits   = { cpu = "500m", memory = "512Mi" }
      }
    }
    runtimes = {
      # Installs ClusterTrainingRuntimes for: torch, deepspeed, mlx, jax, torchtune
      defaultEnabled = true
    }
  })]

  depends_on = [
    aws_eks_addon.coredns,
    helm_release.karpenter,
  ]
}

# ─────────────────────────────────────────────────────────────────────────────
# Kubeflow Central Dashboard — web UI for the Kubeflow platform
# Deployed without Istio; WAF on the ALB handles access control.
# Profiles/KFAM and namespace isolation are intentionally omitted since this
# cluster is single-tenant. The dashboard still provides a training hub with
# links to Trainer v2 documentation and cluster overview.
# ─────────────────────────────────────────────────────────────────────────────

resource "kubernetes_namespace" "kubeflow" {
  count = local.install_dashboard ? 1 : 0

  metadata {
    name = "kubeflow"
    labels = {
      "app.kubernetes.io/managed-by" = "tofu"
    }
  }
}

resource "kubectl_manifest" "centraldashboard_sa" {
  count = local.install_dashboard ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "ServiceAccount"
    metadata = {
      name      = "centraldashboard"
      namespace = "kubeflow"
      labels = {
        app                            = "centraldashboard"
        "app.kubernetes.io/component"  = "centraldashboard"
        "app.kubernetes.io/managed-by" = "tofu"
      }
    }
  })

  depends_on = [kubernetes_namespace.kubeflow]
}

resource "kubectl_manifest" "centraldashboard_clusterrole" {
  count = local.install_dashboard ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "rbac.authorization.k8s.io/v1"
    kind       = "ClusterRole"
    metadata = {
      name = "centraldashboard"
      labels = {
        app                            = "centraldashboard"
        "app.kubernetes.io/component"  = "centraldashboard"
        "app.kubernetes.io/managed-by" = "tofu"
      }
    }
    rules = [
      {
        apiGroups = [""]
        resources = ["events", "namespaces", "nodes"]
        verbs     = ["get", "list", "watch"]
      }
    ]
  })
}

resource "kubectl_manifest" "centraldashboard_clusterrolebinding" {
  count = local.install_dashboard ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "rbac.authorization.k8s.io/v1"
    kind       = "ClusterRoleBinding"
    metadata = {
      name = "centraldashboard"
      labels = {
        app                            = "centraldashboard"
        "app.kubernetes.io/component"  = "centraldashboard"
        "app.kubernetes.io/managed-by" = "tofu"
      }
    }
    roleRef = {
      apiGroup = "rbac.authorization.k8s.io"
      kind     = "ClusterRole"
      name     = "centraldashboard"
    }
    subjects = [
      {
        kind      = "ServiceAccount"
        name      = "centraldashboard"
        namespace = "kubeflow"
      }
    ]
  })

  depends_on = [
    kubectl_manifest.centraldashboard_sa,
    kubectl_manifest.centraldashboard_clusterrole,
  ]
}

resource "kubectl_manifest" "centraldashboard_role" {
  count = local.install_dashboard ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "rbac.authorization.k8s.io/v1"
    kind       = "Role"
    metadata = {
      name      = "centraldashboard"
      namespace = "kubeflow"
      labels = {
        app                            = "centraldashboard"
        "app.kubernetes.io/component"  = "centraldashboard"
        "app.kubernetes.io/managed-by" = "tofu"
      }
    }
    rules = [
      {
        apiGroups = ["", "app.k8s.io"]
        resources = ["applications", "pods", "pods/exec", "pods/log"]
        verbs     = ["get", "list", "watch"]
      },
      {
        apiGroups = [""]
        resources = ["secrets", "configmaps"]
        verbs     = ["get"]
      }
    ]
  })

  depends_on = [kubernetes_namespace.kubeflow]
}

resource "kubectl_manifest" "centraldashboard_rolebinding" {
  count = local.install_dashboard ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "rbac.authorization.k8s.io/v1"
    kind       = "RoleBinding"
    metadata = {
      name      = "centraldashboard"
      namespace = "kubeflow"
      labels = {
        app                            = "centraldashboard"
        "app.kubernetes.io/component"  = "centraldashboard"
        "app.kubernetes.io/managed-by" = "tofu"
      }
    }
    roleRef = {
      apiGroup = "rbac.authorization.k8s.io"
      kind     = "Role"
      name     = "centraldashboard"
    }
    subjects = [
      {
        kind      = "ServiceAccount"
        name      = "centraldashboard"
        namespace = "kubeflow"
      }
    ]
  })

  depends_on = [
    kubectl_manifest.centraldashboard_sa,
    kubectl_manifest.centraldashboard_role,
  ]
}

resource "kubectl_manifest" "centraldashboard_config" {
  count = local.install_dashboard ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "ConfigMap"
    metadata = {
      name      = "centraldashboard-config"
      namespace = "kubeflow"
      labels = {
        app                            = "centraldashboard"
        "app.kubernetes.io/component"  = "centraldashboard"
        "app.kubernetes.io/managed-by" = "tofu"
      }
    }
    data = {
      settings = jsonencode({ DASHBOARD_FORCE_IFRAME = true })
      links = jsonencode({
        menuLinks = []
        externalLinks = []
        documentationItems = [
          {
            desc = "Distributed training with the TrainJob API"
            link = "https://www.kubeflow.org/docs/components/trainer/"
            text = "Kubeflow Trainer v2"
          },
          {
            desc = "Pre-built ClusterTrainingRuntimes for PyTorch, JAX, DeepSpeed, MLX, TorchTune"
            link = "https://www.kubeflow.org/docs/components/trainer/operator-guides/runtime/"
            text = "Training Runtimes"
          },
          {
            desc = "API reference for TrainJob and ClusterTrainingRuntime"
            link = "https://www.kubeflow.org/docs/components/trainer/reference/api/"
            text = "Trainer API Reference"
          }
        ]
        quickLinks = []
      })
    }
  })

  depends_on = [kubernetes_namespace.kubeflow]
}

resource "kubectl_manifest" "centraldashboard_deployment" {
  count = local.install_dashboard ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "apps/v1"
    kind       = "Deployment"
    metadata = {
      name      = "centraldashboard"
      namespace = "kubeflow"
      labels = {
        app                            = "centraldashboard"
        "app.kubernetes.io/component"  = "centraldashboard"
        "app.kubernetes.io/managed-by" = "tofu"
      }
    }
    spec = {
      replicas = 1
      selector = {
        matchLabels = { app = "centraldashboard" }
      }
      template = {
        metadata = {
          labels = { app = "centraldashboard" }
        }
        spec = {
          serviceAccountName = "centraldashboard"
          nodeSelector       = { "node-role" = "system" }
          securityContext = {
            seccompProfile = { type = "RuntimeDefault" }
          }
          containers = [
            {
              name            = "centraldashboard"
              image           = "ghcr.io/kubeflow/kubeflow/central-dashboard:v1.10.0"
              imagePullPolicy = "IfNotPresent"
              ports = [
                { containerPort = 8082, protocol = "TCP" }
              ]
              livenessProbe = {
                httpGet = { path = "/healthz", port = 8082 }
                initialDelaySeconds = 30
                periodSeconds       = 30
              }
              env = [
                # No Istio/oauth2-proxy: identity headers are not injected.
                # The dashboard runs in anonymous mode; WAF on the ALB enforces access.
                { name = "USERID_HEADER", value = "" },
                { name = "USERID_PREFIX", value = "" },
                # Profiles/KFAM not deployed — namespace selector will show an empty list.
                { name = "PROFILES_KFAM_SERVICE_HOST", value = "" },
                { name = "REGISTRATION_FLOW", value = "false" },
                { name = "DASHBOARD_CONFIGMAP", value = "centraldashboard-config" },
                { name = "LOGOUT_URL", value = "" },
                { name = "COLLECT_METRICS", value = "false" },
                {
                  name = "POD_NAMESPACE"
                  valueFrom = {
                    fieldRef = { fieldPath = "metadata.namespace" }
                  }
                }
              ]
              resources = {
                requests = { cpu = "50m", memory = "128Mi" }
                limits   = { cpu = "500m", memory = "512Mi" }
              }
              securityContext = {
                runAsNonRoot             = true
                runAsUser                = 1000
                allowPrivilegeEscalation = false
                capabilities             = { drop = ["ALL"] }
              }
            }
          ]
        }
      }
    }
  })

  depends_on = [
    kubernetes_namespace.kubeflow,
    kubectl_manifest.centraldashboard_sa,
    kubectl_manifest.centraldashboard_config,
    helm_release.kubeflow_trainer,
  ]
}

resource "kubectl_manifest" "centraldashboard_service" {
  count = local.install_dashboard ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Service"
    metadata = {
      name      = "centraldashboard"
      namespace = "kubeflow"
      labels = {
        app                            = "centraldashboard"
        "app.kubernetes.io/component"  = "centraldashboard"
        "app.kubernetes.io/managed-by" = "tofu"
      }
    }
    spec = {
      type            = "ClusterIP"
      sessionAffinity = "None"
      selector        = { app = "centraldashboard" }
      ports = [
        {
          port       = 80
          targetPort = 8082
          protocol   = "TCP"
        }
      ]
    }
  })

  depends_on = [kubernetes_namespace.kubeflow]
}

# ─────────────────────────────────────────────────────────────────────────────
# Central Dashboard Ingress — internet-facing ALB with WAF; created only when
# kubeflow_dashboard_hostname and kubeflow_dashboard_certificate_arn are set.
# ─────────────────────────────────────────────────────────────────────────────

resource "kubectl_manifest" "centraldashboard_ingress" {
  count = local.expose_dashboard ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "networking.k8s.io/v1"
    kind       = "Ingress"
    metadata = {
      name      = "centraldashboard"
      namespace = "kubeflow"
      annotations = {
        "kubernetes.io/ingress.class"                        = "alb"
        "alb.ingress.kubernetes.io/scheme"                   = "internet-facing"
        "alb.ingress.kubernetes.io/target-type"              = "ip"
        "alb.ingress.kubernetes.io/ip-address-type"          = "dualstack"
        "alb.ingress.kubernetes.io/backend-protocol"         = "HTTP"
        "alb.ingress.kubernetes.io/listen-ports"             = jsonencode([{ HTTPS = 443 }])
        "alb.ingress.kubernetes.io/ssl-redirect"             = "443"
        "alb.ingress.kubernetes.io/ssl-policy"               = "ELBSecurityPolicy-TLS13-1-2-2021-06"
        "alb.ingress.kubernetes.io/certificate-arn"          = var.kubeflow_dashboard_certificate_arn
        "alb.ingress.kubernetes.io/wafv2-acl-arn"            = var.waf_web_acl_arn
        "alb.ingress.kubernetes.io/healthcheck-path"         = "/healthz"
        "alb.ingress.kubernetes.io/healthcheck-protocol"     = "HTTP"
        "alb.ingress.kubernetes.io/success-codes"            = "200"
      }
    }
    spec = {
      rules = [
        {
          host = var.kubeflow_dashboard_hostname
          http = {
            paths = [
              {
                path     = "/"
                pathType = "Prefix"
                backend = {
                  service = {
                    name = "centraldashboard"
                    port = { number = 80 }
                  }
                }
              }
            ]
          }
        }
      ]
    }
  })

  depends_on = [
    kubectl_manifest.centraldashboard_service,
    helm_release.aws_lbc,
  ]
}
