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

# Configure the AWS Provider
provider "aws" {
  region = var.region
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.region]
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
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.region]
  }
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.region]
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

  availability_zones   = coalesce(var.availability_zones, ["${var.region}a", "${var.region}b"])
  private_subnet_cidrs = coalesce(var.private_subnet_cidrs, ["10.0.1.0/24", "10.0.2.0/24"])
  public_subnet_cidrs  = coalesce(var.public_subnet_cidrs, ["10.0.101.0/24", "10.0.102.0/24"])

  # IPv6 Configuration
  use_byoip_ipv6            = var.use_byoip_ipv6
  byoip_ipv6_pool_id        = var.byoip_ipv6_pool_id
  byoip_ipv6_cidr           = var.byoip_ipv6_cidr
  byoip_ipv6_netmask_length = var.byoip_ipv6_netmask_length

  tags = var.tags
}

# EKS Module
module "eks" {
  source = "./modules/aws/eks"

  cluster_name              = var.cluster_name
  cluster_version           = var.cluster_version
  vpc_id                    = module.vpc.vpc_id
  private_subnet_ids        = module.vpc.private_subnet_ids
  public_subnet_ids         = module.vpc.public_subnet_ids
  cluster_security_group_id = module.vpc.eks_cluster_security_group_id

  # Node Group Configuration
  node_disk_size = var.node_disk_size
  cluster_access = var.cluster_access

  tags = var.tags
}

# EKS Addons Module
module "eks_addons" {
  source = "./modules/aws/eks-addons"

  cluster_name                      = module.eks.cluster_name
  node_tier                         = var.node_tier
  node_disk_size                    = var.node_disk_size
  oidc_provider_arn                 = module.eks.oidc_provider_arn
  karpenter_role_arn                = module.eks.karpenter_role_arn
  karpenter_interruption_queue_name = module.eks.karpenter_interruption_queue_name
  node_iam_role_name                = module.eks.node_iam_role_name
  s3_bucket_arns                    = concat([module.s3_ml_data.bucket_arn], var.s3_bucket_arns)
  gpu_node_max_lifetime             = var.gpu_node_max_lifetime

  # ArgoCD
  argocd_enabled       = var.argocd_enabled
  argocd_chart_version = var.argocd_chart_version
  argocd_source_repos  = var.argocd_source_repos

  workload_namespaces = var.workload_namespaces
  argocd_team_groups  = var.argocd_team_groups

  tags = var.tags

  depends_on = [module.eks]
}

# ML Data S3 Module
module "s3_ml_data" {
  source = "./modules/aws/s3"

  bucket_name = var.ml_data_bucket_name

  tags = var.tags

  depends_on = [module.eks]
}
