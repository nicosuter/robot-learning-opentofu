output "web_acl_arn" {
  description = "ARN of the WAF Web ACL. Associate with ALBs using aws_wafv2_web_acl_association."
  value       = aws_wafv2_web_acl.main.arn
}
