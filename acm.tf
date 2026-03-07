# ─────────────────────────────────────────────────────────────────────────────
# ACM Certificates — auto-issued and DNS-validated via Route53.
# The hosted zone is discovered automatically from the hostname's apex domain.
# Override hosted_zone_id only if auto-discovery picks the wrong zone.
# argocd_certificate_arn / kubeflow_dashboard_certificate_arn are ignored when
# a hostname is set; supply them only if managing certs fully externally.
# ─────────────────────────────────────────────────────────────────────────────

locals {
  create_argocd_cert   = var.argocd_hostname != null
  create_kubeflow_cert = var.kubeflow_dashboard_hostname != null

  # Derive the apex domain from whichever hostname is set first, then look it
  # up in Route53. Strips one subdomain level: argocd.foo.com → foo.com.
  _primary_hostname = coalesce(var.argocd_hostname, var.kubeflow_dashboard_hostname)
  _apex_domain      = local._primary_hostname != null ? regex("[^.]+\\.(.+)", local._primary_hostname)[0] : null

  # Prefer an explicit override; fall back to the auto-discovered zone.
  zone_id = var.hosted_zone_id != null ? var.hosted_zone_id : try(data.aws_route53_zone.main[0].zone_id, null)
}

# Auto-discover the Route53 hosted zone from the apex domain.
data "aws_route53_zone" "main" {
  count        = local._apex_domain != null && var.hosted_zone_id == null ? 1 : 0
  name         = local._apex_domain
  private_zone = false
}

# ── ArgoCD ────────────────────────────────────────────────────────────────────

resource "aws_acm_certificate" "argocd" {
  count             = local.create_argocd_cert ? 1 : 0
  domain_name       = var.argocd_hostname
  validation_method = "DNS"
  tags              = var.tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "argocd_cert_validation" {
  for_each = {
    for dvo in try(aws_acm_certificate.argocd[0].domain_validation_options, []) : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id         = local.zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 60
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "argocd" {
  count                   = local.create_argocd_cert ? 1 : 0
  certificate_arn         = aws_acm_certificate.argocd[0].arn
  validation_record_fqdns = [for r in aws_route53_record.argocd_cert_validation : r.fqdn]
}

# ── Kubeflow Dashboard ────────────────────────────────────────────────────────

resource "aws_acm_certificate" "kubeflow" {
  count             = local.create_kubeflow_cert ? 1 : 0
  domain_name       = var.kubeflow_dashboard_hostname
  validation_method = "DNS"
  tags              = var.tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "kubeflow_cert_validation" {
  for_each = {
    for dvo in try(aws_acm_certificate.kubeflow[0].domain_validation_options, []) : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id         = local.zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 60
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "kubeflow" {
  count                   = local.create_kubeflow_cert ? 1 : 0
  certificate_arn         = aws_acm_certificate.kubeflow[0].arn
  validation_record_fqdns = [for r in aws_route53_record.kubeflow_cert_validation : r.fqdn]
}
