terraform {
  required_version = "~> 1.8"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = var.region
}

# VPC Module
module "vpc" {
  source = "./modules/aws/vpc"

  cluster_name         = var.cluster_name
  vpc_cidr             = var.vpc_cidr
  availability_zones   = var.availability_zones
  private_subnet_cidrs = var.private_subnet_cidrs
  public_subnet_cidrs  = var.public_subnet_cidrs

  # IPv6 Configuration
  use_byoip_ipv6           = var.use_byoip_ipv6
  byoip_ipv6_pool_id       = var.byoip_ipv6_pool_id
  byoip_ipv6_cidr          = var.byoip_ipv6_cidr
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
  node_group_desired_size = var.node_group_desired_size
  node_group_min_size     = var.node_group_min_size
  node_group_max_size     = var.node_group_max_size
  node_instance_types     = var.node_instance_types
  node_disk_size          = var.node_disk_size
  cluster_access          = var.cluster_access

  tags = var.tags
}
