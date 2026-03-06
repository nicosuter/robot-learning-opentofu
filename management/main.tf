# ─────────────────────────────────────────────────────────────────────────────
# EC2 Management Instance — minimal instance for applying Terraform/OpenTofu
# Deploy from local: tofu -chdir=management init && tofu -chdir=management apply
# ─────────────────────────────────────────────────────────────────────────────

provider "aws" {
  region  = var.region
  profile = var.aws_profile
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# IAM role — broad permissions for Terraform (S3, DynamoDB, EC2, EKS, IAM, VPC, etc.)
resource "aws_iam_role" "management" {
  name = "terraform-management-instance"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = "sts:AssumeRole"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })

  tags = var.tags
}

# PowerUserAccess covers most Terraform needs; add S3/DynamoDB explicitly for state
resource "aws_iam_role_policy_attachment" "power_user" {
  role       = aws_iam_role.management.name
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}

resource "aws_iam_role_policy" "state_access" {
  name = "state-bucket-access"
  role = aws_iam_role.management.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject", "s3:PutObject", "s3:DeleteObject",
          "s3:ListBucket", "s3:GetBucketLocation"
        ]
        Resource = [
          "arn:aws:s3:::ethrc-tf",
          "arn:aws:s3:::ethrc-tf/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem",
          "dynamodb:ConditionCheckItem", "dynamodb:Query", "dynamodb:Scan",
          "dynamodb:BatchGetItem", "dynamodb:BatchWriteItem",
          "dynamodb:DescribeTable", "dynamodb:ListTables"
        ]
        Resource = "arn:aws:dynamodb:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:table/tofu-state-lock"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "management" {
  name = "terraform-management-instance"
  role = aws_iam_role.management.name

  tags = var.tags
}

# Security group
resource "aws_security_group" "management" {
  name        = "terraform-management"
  description = "SSH and outbound for Terraform management instance"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.ssh_allowed_cidrs
    description = "SSH"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound"
  }

  tags = merge(var.tags, { Name = "terraform-management" })
}

# EC2 key pair — created from first public key
resource "aws_key_pair" "management" {
  count = length(var.public_keys) > 0 ? 1 : 0

  key_name   = "terraform-management-${data.aws_caller_identity.current.account_id}"
  public_key = var.public_keys[0]

  tags = merge(var.tags, { Name = "terraform-management" })
}

# User data — install OpenTofu, AWS CLI v2, git, optional extra SSH keys
locals {
  extra_keys_b64   = length(var.public_keys) > 1 ? base64encode(join("\n", slice(var.public_keys, 1, length(var.public_keys)))) : ""
  extra_keys_script = length(var.public_keys) > 1 ? join("\n", [
    "mkdir -p /home/ec2-user/.ssh",
    "chmod 700 /home/ec2-user/.ssh",
    "echo '${local.extra_keys_b64}' | base64 -d | while read -r line; do [ -n \"$${line}\" ] && echo \"$${line}\" >> /home/ec2-user/.ssh/authorized_keys; done",
    "chmod 600 /home/ec2-user/.ssh/authorized_keys",
    "chown -R ec2-user:ec2-user /home/ec2-user/.ssh",
  ]) : ""
  user_data = <<-EOT
#!/bin/bash
set -e
dnf update -y
dnf install -y git

${local.extra_keys_script}

# AWS CLI v2
curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
dnf install -y unzip
unzip -q /tmp/awscliv2.zip -d /tmp
/tmp/aws/install -b /usr/local/bin -i /usr/local/aws-cli
rm -rf /tmp/awscliv2.zip /tmp/aws

# OpenTofu
TOFU_VER="1.9.5"
curl -sL "https://github.com/opentofu/opentofu/releases/download/v$${TOFU_VER}/tofu_$${TOFU_VER}_linux_amd64.zip" -o /tmp/tofu.zip
unzip -q /tmp/tofu.zip -d /usr/local/bin
rm /tmp/tofu.zip
chmod +x /usr/local/bin/tofu

# Ready
echo "Management instance ready. Clone repo and run: tofu init -reconfigure && tofu plan"
  EOT
}

# EC2 instance
resource "aws_instance" "management" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = var.instance_type
  key_name               = length(var.public_keys) > 0 ? aws_key_pair.management[0].key_name : null
  subnet_id              = tolist(data.aws_subnets.default.ids)[0]
  vpc_security_group_ids  = [aws_security_group.management.id]
  iam_instance_profile   = aws_iam_instance_profile.management.name
  user_data              = local.user_data
  user_data_replace_on_change = true

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_size = 8
    volume_type = "gp3"
  }

  tags = merge(var.tags, {
    Name = "terraform-management"
  })
}

resource "aws_eip" "management" {
  instance = aws_instance.management.id
  domain   = "vpc"

  tags = merge(var.tags, { Name = "terraform-management" })
}

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}
