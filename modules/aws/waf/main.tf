# Split the flat CIDR list into IPv4 and IPv6 — WAF IP sets are version-specific.
locals {
  ipv4_cidrs = [for c in var.as214770_cidrs : c if !can(regex(":", c))]
  ipv6_cidrs = [for c in var.as214770_cidrs : c if can(regex(":", c))]
}

resource "aws_wafv2_ip_set" "as214770_v4" {
  count = length(local.ipv4_cidrs) > 0 ? 1 : 0

  name               = "${var.name_prefix}-as214770-v4"
  description        = "IPv4 prefixes announced by AS214770"
  scope              = "REGIONAL"
  ip_address_version = "IPV4"
  addresses          = local.ipv4_cidrs

  tags = var.tags
}

resource "aws_wafv2_ip_set" "as214770_v6" {
  count = length(local.ipv6_cidrs) > 0 ? 1 : 0

  name               = "${var.name_prefix}-as214770-v6"
  description        = "IPv6 prefixes announced by AS214770"
  scope              = "REGIONAL"
  ip_address_version = "IPV6"
  addresses          = local.ipv6_cidrs

  tags = var.tags
}

resource "aws_wafv2_web_acl" "main" {
  name        = "${var.name_prefix}-acl"
  description = "Allow CH geo + AS214770; block everything else"
  scope       = "REGIONAL"

  default_action {
    block {}
  }

  # Rule 1 — Switzerland geo-match
  rule {
    name     = "allow-ch"
    priority = 1

    action {
      allow {}
    }

    statement {
      geo_match_statement {
        country_codes = ["CH"]
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name_prefix}-allow-ch"
      sampled_requests_enabled   = true
    }
  }

  # Rule 2 — AS214770 IPv4 prefixes (only created when CIDRs are provided)
  dynamic "rule" {
    for_each = length(local.ipv4_cidrs) > 0 ? [1] : []
    content {
      name     = "allow-as214770-v4"
      priority = 2

      action {
        allow {}
      }

      statement {
        ip_set_reference_statement {
          arn = aws_wafv2_ip_set.as214770_v4[0].arn
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${var.name_prefix}-allow-as214770-v4"
        sampled_requests_enabled   = true
      }
    }
  }

  # Rule 3 — AS214770 IPv6 prefixes (only created when CIDRs are provided)
  dynamic "rule" {
    for_each = length(local.ipv6_cidrs) > 0 ? [1] : []
    content {
      name     = "allow-as214770-v6"
      priority = 3

      action {
        allow {}
      }

      statement {
        ip_set_reference_statement {
          arn = aws_wafv2_ip_set.as214770_v6[0].arn
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${var.name_prefix}-allow-as214770-v6"
        sampled_requests_enabled   = true
      }
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.name_prefix}-acl"
    sampled_requests_enabled   = true
  }

  tags = var.tags
}
