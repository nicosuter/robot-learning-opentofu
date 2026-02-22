# modules/aws

AWS-specific infrastructure modules.

| Module | Description |
|--------|-------------|
| [vpc](./vpc) | Dual-stack VPC with public/private subnets, NAT, IGW, EIGW, and EKS security groups |
| [eks](./eks) | EKS cluster with managed GPU node group, IAM roles, and IPv6-mode add-ons |

## Usage

```hcl
module "vpc" {
  source = "./modules/aws/vpc"

  cluster_name         = "my-cluster"
  vpc_cidr             = "10.0.0.0/16"
  availability_zones   = ["eu-central-1a", "eu-central-1b", "eu-central-1c"]
  private_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnet_cidrs  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
  tags                 = { Project = "my-project" }
}

module "eks" {
  source = "./modules/aws/eks"

  cluster_name              = "my-cluster"
  cluster_version           = "1.29"
  vpc_id                    = module.vpc.vpc_id
  private_subnet_ids        = module.vpc.private_subnet_ids
  public_subnet_ids         = module.vpc.public_subnet_ids
  cluster_security_group_id = module.vpc.eks_cluster_security_group_id
  node_instance_types       = ["g5.xlarge"]
  node_disk_size            = 200
  tags                      = { Project = "my-project" }
}
```

## Multi-Cloud Layout

Other providers slot in as siblings to `aws/`, e.g.:

```
modules/
├── aws/            # vpc/, eks/
├── azure/          # vnet/, aks/
├── gcp/            # vpc/, gke/
└── cloudflare/     # zero-trust/, workers/
```
