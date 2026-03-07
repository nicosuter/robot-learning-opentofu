# ─────────────────────────────────────────────────────────────────────────────
# ACM — auto-created, DNS-validated certificates
# Created only when a hostname is configured (e.g. argocd_hostname).
# Validation records are written directly into the Route 53 zone so no manual
# steps are required; tofu apply blocks until the cert reaches ISSUED status.
# ─────────────────────────────────────────────────────────────────────────────

data "aws_route53_zone" "main" {
  count        = var.argocd_hostname != null ? 1 : 0
  name         = var.route53_zone_name
  private_zone = false
}

resource "aws_acm_certificate" "argocd" {
  count             = var.argocd_hostname != null ? 1 : 0
  domain_name       = var.argocd_hostname
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = var.tags
}

resource "aws_route53_record" "argocd_cert_validation" {
  for_each = var.argocd_hostname != null ? {
    for dvo in aws_acm_certificate.argocd[0].domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  } : {}

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.main[0].zone_id
}

resource "aws_acm_certificate_validation" "argocd" {
  count                   = var.argocd_hostname != null ? 1 : 0
  certificate_arn         = aws_acm_certificate.argocd[0].arn
  validation_record_fqdns = [for r in aws_route53_record.argocd_cert_validation : r.fqdn]
}

# Route 53 record — points the ArgoCD hostname at the ALB created by AWS LBC.
# The ALB hostname is read back from the ingress status after LBC reconciles.
resource "aws_route53_record" "argocd" {
  count   = var.argocd_hostname != null ? 1 : 0
  zone_id = data.aws_route53_zone.main[0].zone_id
  name    = var.argocd_hostname
  type    = "CNAME"
  ttl     = 60
  records = [module.eks_addons.argocd_lb_hostname]
}
