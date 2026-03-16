# ─────────────────────────────────────────────────────────────────────────────
# EFS CSI Driver — multi-AZ persistent storage for ML workloads
#
# Unlike EBS (zone-bound), EFS works across all AZs without topology
# constraints. Pods can schedule in any AZ and access the same filesystem.
# ─────────────────────────────────────────────────────────────────────────────

locals {
  enable_efs_csi = true
}

# IRSA role for EFS CSI driver
resource "aws_iam_role" "efs_csi" {
  count = local.enable_efs_csi ? 1 : 0
  name  = "${var.cluster_name}-efs-csi"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = var.oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_issuer}:aud" = "sts.amazonaws.com"
          "${local.oidc_issuer}:sub" = "system:serviceaccount:kube-system:efs-csi-controller-sa"
        }
      }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "efs_csi" {
  count = local.enable_efs_csi ? 1 : 0
  name  = "${var.cluster_name}-efs-csi"
  role  = aws_iam_role.efs_csi[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EFSAccess"
        Effect = "Allow"
        Action = [
          "elasticfilesystem:DescribeFileSystems",
          "elasticfilesystem:DescribeMountTargets",
          "elasticfilesystem:DescribeMountTargetSecurityGroups",
          "elasticfilesystem:DescribeAccessPoints",
          "elasticfilesystem:DescribeTags",
          "elasticfilesystem:CreateAccessPoint",
          "elasticfilesystem:DeleteAccessPoint",
          "elasticfilesystem:TagResource",
        ]
        Resource = "*"
      },
    ]
  })
}

# EKS managed addon for EFS CSI driver
resource "aws_eks_addon" "efs_csi" {
  count        = local.enable_efs_csi ? 1 : 0
  cluster_name = var.cluster_name
  addon_name   = "aws-efs-csi-driver"
  addon_version = "v2.3.0-eksbuild.2"

  service_account_role_arn = aws_iam_role.efs_csi[0].arn

  resolve_conflicts_on_update = "OVERWRITE"
  resolve_conflicts_on_create = "OVERWRITE"

  tags = var.tags

  depends_on = [aws_eks_addon.coredns]
}

# Security group for EFS mount targets
resource "aws_security_group" "efs" {
  count = local.enable_efs_csi ? 1 : 0
  name  = "${var.cluster_name}-efs"
  description = "Allow NFS from EKS nodes"
  vpc_id      = var.vpc_id

  ingress {
    description = "NFS from EKS nodes"
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    security_groups = [var.node_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.cluster_name}-efs" })

  depends_on = [aws_eks_addon.efs_csi]
}

# EFS filesystem
resource "aws_efs_file_system" "ml_data" {
  count = local.enable_efs_csi ? 1 : 0

  creation_token   = "${var.cluster_name}-ml-data"
  encrypted        = true
  performance_mode = "generalPurpose"
  throughput_mode  = "elastic"

  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-ml-data"
  })

  depends_on = [aws_security_group.efs]
}

# Mount targets in all AZs
resource "aws_efs_mount_target" "ml_data" {
  count = local.enable_efs_csi ? length(var.private_subnet_ids) : 0

  file_system_id  = aws_efs_file_system.ml_data[0].id
  subnet_id       = var.private_subnet_ids[count.index]
  security_groups = [aws_security_group.efs[0].id]
}

# StorageClass for EFS dynamic provisioning
resource "kubectl_manifest" "efs_storageclass" {
  count = local.enable_efs_csi ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "storage.k8s.io/v1"
    kind       = "StorageClass"
    metadata = {
      name = "efs"
      annotations = {
        "storageclass.kubernetes.io/is-default-class" = "false"
      }
    }
    provisioner = "efs.csi.aws.com"
    parameters = {
      provisioningMode = "efs-ap"
      fileSystemId   = aws_efs_file_system.ml_data[0].id
      directoryPerms = "755"
      gidRangeStart  = "1000"
      gidRangeEnd    = "2000"
    }
    reclaimPolicy        = "Retain"
    volumeBindingMode    = "Immediate"
    allowVolumeExpansion = true
  })

  depends_on = [aws_eks_addon.efs_csi, aws_efs_mount_target.ml_data]
}

# Patch EFS CSI node daemonset for Amazon Linux 2023 compatibility.
# Adds missing /var/run/efs hostPath volume required by amazon-efs-mount-watchdog.
resource "terraform_data" "efs_csi_node_patch" {
  count = local.enable_efs_csi ? 1 : 0

  triggers_replace = [
    aws_eks_addon.efs_csi[0].id
  ]

  provisioner "local-exec" {
    command = <<-EOT
      # Check if patch is already applied (idempotent)
      if ! kubectl get daemonset efs-csi-node -n kube-system -o json | grep -q "efs-state-dir"; then
        echo "Applying EFS CSI patch for AL2023..."
        kubectl patch daemonset efs-csi-node -n kube-system --type='json' -p='[{"op": "add", "path": "/spec/template/spec/volumes/-", "value": {"name": "efs-state-dir", "hostPath": {"path": "/var/run/efs", "type": "DirectoryOrCreate"}}}]' 2>/dev/null || true
        kubectl patch daemonset efs-csi-node -n kube-system --type='json' -p='[{"op": "add", "path": "/spec/template/spec/containers/0/volumeMounts/-", "value": {"mountPath": "/var/run/efs", "name": "efs-state-dir"}}]' 2>/dev/null || true
      else
        echo "EFS CSI patch already applied, skipping."
      fi
    EOT
  }

  depends_on = [aws_eks_addon.efs_csi]
}
