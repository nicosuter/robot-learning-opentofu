output "instance_id" {
  description = "EC2 instance ID."
  value       = aws_instance.management.id
}

output "public_ip" {
  description = "Elastic IP for SSH (stable across stop/start)."
  value       = aws_eip.management.public_ip
}

output "ssh_command" {
  description = "SSH command. Use the private key that matches your first public key."
  value       = length(var.public_keys) > 0 ? "ssh -i ~/.ssh/your-private-key ec2-user@${aws_eip.management.public_ip}" : "No key pair — use SSM Session Manager to connect"
  sensitive   = true
}
