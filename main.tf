terraform {
  required_version = "~> 1.9"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0"
    }
    kubectl = {
      source  = "alekc/kubectl"
      version = "~> 2.1"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
  }
}

locals {
  # Append --profile only when a named profile is explicitly set.
  _profile_args   = var.aws_profile != null ? ["--profile", var.aws_profile] : []
  eks_token_args  = concat(["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.region], local._profile_args)
}

# Configure the AWS Provider
provider "aws" {
  region  = var.region
  profile = var.aws_profile
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = local.eks_token_args
    }
  }
}

provider "kubectl" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  load_config_file       = false

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = local.eks_token_args
  }
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = local.eks_token_args
  }
}

# ArgoCD initial admin secret — populated by Helm after ArgoCD is installed
data "kubernetes_secret" "argocd_admin_password" {
  count = var.argocd_enabled ? 1 : 0

  metadata {
    name      = "argocd-initial-admin-secret"
    namespace = "argocd"
  }

  depends_on = [module.eks_addons]
}

# VPC Module
module "vpc" {
  source = "./modules/aws/vpc"

  cluster_name = var.cluster_name
  region       = var.region
  vpc_cidr     = var.vpc_cidr

  # 6 AZs including us-east-1e for subnet diversity. EKS control plane uses 5 AZs (excludes us-east-1e).
  availability_zones   = coalesce(var.availability_zones, ["${var.region}a", "${var.region}b", "${var.region}c", "${var.region}d", "${var.region}e", "${var.region}f"])
  private_subnet_cidrs = coalesce(var.private_subnet_cidrs, ["10.0.0.0/19", "10.0.32.0/19", "10.0.128.0/20", "10.0.144.0/20", "10.0.160.0/20", "10.0.224.0/20"])
  public_subnet_cidrs  = coalesce(var.public_subnet_cidrs, ["10.0.64.0/19", "10.0.96.0/19", "10.0.176.0/20", "10.0.192.0/20", "10.0.208.0/20", "10.0.240.0/20"])

  # IPv6 Configuration
  use_byoip_ipv6            = var.use_byoip_ipv6
  byoip_ipv6_pool_id        = var.byoip_ipv6_pool_id
  byoip_ipv6_cidr           = var.byoip_ipv6_cidr
  byoip_ipv6_netmask_length = var.byoip_ipv6_netmask_length

  tags = var.tags
}

# EKS Module
# Note: EKS control plane does not support us-east-1e. We exclude index 4 (us-east-1e) from the subnet lists.
module "eks" {
  source = "./modules/aws/eks"

  cluster_name              = var.cluster_name
  cluster_version           = var.cluster_version
  vpc_id                    = module.vpc.vpc_id
  private_subnet_ids        = [for i, id in module.vpc.private_subnet_ids : id if i != 4]
  public_subnet_ids         = [for i, id in module.vpc.public_subnet_ids : id if i != 4]
  cluster_security_group_id = module.vpc.eks_cluster_security_group_id

  # Node Group Configuration
  node_disk_size = var.node_disk_size
  cluster_access         = var.cluster_access

  api_server_allowed_cidrs = var.api_server_allowed_cidrs

  tags = var.tags
}

# WAF Module — REGIONAL Web ACL (CH geo + AS214770); attach to ALBs
module "waf" {
  source = "./modules/aws/waf"

  name_prefix    = var.cluster_name
  as214770_cidrs = var.waf_as214770_cidrs

  tags = var.tags
}

# ECR module
module "ecr" {
  source = "./modules/aws/ecr"

  name_prefix         = var.cluster_name
  repository_names    = var.ecr_repository_names
  github_repositories = var.ecr_github_repositories
  ecr_push_iam_users = ["github-cicd"]

  tags = var.tags
}

# EKS Addons Module
module "eks_addons" {
  source = "./modules/aws/eks-addons"

  cluster_name                      = module.eks.cluster_name
  vpc_id                            = module.vpc.vpc_id
  node_tier                         = var.node_tier
  gpu_operator_enabled              = var.gpu_operator_enabled
  gpum_instance_types               = var.gpum_instance_types
  node_disk_size                    = var.node_disk_size
  oidc_provider_arn                 = module.eks.oidc_provider_arn
  karpenter_role_arn                = module.eks.karpenter_role_arn
  karpenter_interruption_queue_name = module.eks.karpenter_interruption_queue_name
  node_iam_role_name                = module.eks.node_iam_role_name
  # S3 ARNs have no account/region component (arn:aws:s3:::<name>), so they
  # can be constructed from known variables — keeping for_each keys plan-time-known.
  s3_bucket_arns                    = concat(
    ["arn:aws:s3:::${var.ml_data_bucket_name}"],
    var.s3_bucket_arns,
  )
  gpu_node_max_lifetime             = var.gpu_node_max_lifetime

  # ArgoCD
  argocd_enabled         = var.argocd_enabled
  argocd_chart_version   = var.argocd_chart_version
  argocd_source_repos    = var.argocd_source_repos
  argocd_hostname        = var.argocd_hostname
  argocd_certificate_arn = var.argocd_hostname != null ? aws_acm_certificate_validation.argocd[0].certificate_arn : null

  waf_web_acl_arn = module.waf.web_acl_arn

  workload_namespaces = var.workload_namespaces
  argocd_team_groups  = var.argocd_team_groups

  # Kubeflow
  kubeflow_training_operator_enabled = var.kubeflow_training_operator_enabled
  kubeflow_dashboard_enabled         = var.kubeflow_dashboard_enabled
  kubeflow_dashboard_hostname        = var.kubeflow_dashboard_hostname
  kubeflow_dashboard_certificate_arn = var.kubeflow_dashboard_certificate_arn

  tags = var.tags

  depends_on = [module.eks]
}

# ML Data S3 Module
module "s3_ml_data" {
  source = "./modules/aws/s3"

  bucket_name   = var.ml_data_bucket_name
  kms_user_arns = [for v in var.cluster_access : v.principal_arn]

  tags = var.tags

  depends_on = [module.eks]
}