# ─────────────────────────────────────────────────────────────────────────────
# Route53 DNS records — CNAME aliases pointing public hostnames to ALBs.
# Only created when hosted_zone_id is supplied alongside the relevant hostname.
#
# ALB hostnames are read from the Kubernetes Ingress status at plan time.
# On the first apply the ALB may still be provisioning (status empty), so the
# CNAME is skipped and created on the next apply once the ALB is ready.
# ─────────────────────────────────────────────────────────────────────────────

locals {
  manage_argocd_dns   = local.expose_argocd && var.hosted_zone_id != null
  manage_kubeflow_dns = local.expose_dashboard && var.hosted_zone_id != null
}

# ── ArgoCD ────────────────────────────────────────────────────────────────────

data "external" "argocd_alb_hostname" {
  count = local.manage_argocd_dns ? 1 : 0

  program = ["bash", "-c", <<-EOT
    h=$(kubectl get ingress argocd-server -n argocd \
      -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
    printf '{"hostname":"%s"}' "$h"
  EOT
  ]
}

resource "aws_route53_record" "argocd" {
  count = (
    local.manage_argocd_dns &&
    try(data.external.argocd_alb_hostname[0].result.hostname, "") != ""
  ) ? 1 : 0

  zone_id = var.hosted_zone_id
  name    = var.argocd_hostname
  type    = "CNAME"
  ttl     = 300
  records = [data.external.argocd_alb_hostname[0].result.hostname]
}

# ── Kubeflow Dashboard ────────────────────────────────────────────────────────

data "external" "kubeflow_alb_hostname" {
  count = local.manage_kubeflow_dns ? 1 : 0

  program = ["bash", "-c", <<-EOT
    h=$(kubectl get ingress centraldashboard -n kubeflow \
      -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
    printf '{"hostname":"%s"}' "$h"
  EOT
  ]
}

resource "aws_route53_record" "kubeflow" {
  count = (
    local.manage_kubeflow_dns &&
    try(data.external.kubeflow_alb_hostname[0].result.hostname, "") != ""
  ) ? 1 : 0

  zone_id = var.hosted_zone_id
  name    = var.kubeflow_dashboard_hostname
  type    = "CNAME"
  ttl     = 300
  records = [data.external.kubeflow_alb_hostname[0].result.hostname]
}
