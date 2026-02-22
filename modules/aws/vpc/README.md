# modules/aws/vpc

Dual-stack (IPv4 + IPv6) VPC for EKS. IPv6 is primary; IPv4 is fallback. Supports BYOIP or AWS-provided IPv6 prefixes.

## Usage

```hcl
module "vpc" {
  source = "./modules/aws/vpc"

  cluster_name         = "my-cluster"
  vpc_cidr             = "10.0.0.0/16"
  availability_zones   = ["eu-central-1a", "eu-central-1b", "eu-central-1c"]
  private_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnet_cidrs  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  # BYOIP (optional - defaults to AWS-provided)
  use_byoip_ipv6     = true
  byoip_ipv6_pool_id = "ipv6pool-ec2-xxxxxxxxxxxx"
  byoip_ipv6_cidr    = "2001:db8:1234::/56"

  tags = { Project = "my-project", Environment = "production" }
}
```

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `cluster_name` | `string` | -- | Resource naming and EKS subnet tags |
| `vpc_cidr` | `string` | `10.0.0.0/16` | VPC IPv4 CIDR |
| `availability_zones` | `list(string)` | -- | One subnet per AZ |
| `private_subnet_cidrs` | `list(string)` | -- | One CIDR per AZ |
| `public_subnet_cidrs` | `list(string)` | -- | One CIDR per AZ |
| `use_byoip_ipv6` | `bool` | `false` | Use BYOIP instead of AWS-provided IPv6 |
| `byoip_ipv6_pool_id` | `string` | `null` | AWS BYOIP pool ID |
| `byoip_ipv6_cidr` | `string` | `null` | BYOIP CIDR block |
| `byoip_ipv6_netmask_length` | `number` | `56` | Netmask length for BYOIP |
| `tags` | `map(string)` | `{}` | Tags applied to all resources |

## Outputs

| Name | Description |
|------|-------------|
| `vpc_id` | VPC ID |
| `vpc_cidr` | VPC IPv4 CIDR |
| `vpc_ipv6_cidr_block` | VPC IPv6 CIDR block |
| `private_subnet_ids` | Private subnet IDs |
| `public_subnet_ids` | Public subnet IDs |
| `eks_cluster_security_group_id` | Security group for EKS control plane |
| `eks_nodes_security_group_id` | Security group for EKS nodes |
| `nat_gateway_ids` | NAT Gateway IDs |

## Subnet IPv6 Layout

Private and public subnets get /64 blocks carved from the VPC /56:

| Tier | Index offsets |
|------|--------------|
| Private | 0, 1, 2, ... |
| Public | 100, 101, 102, ... |

## Security Groups

**Cluster** - ingress: 443 from nodes; egress: all

**Nodes** - ingress: all from nodes, 1025-65535 from cluster; egress: all
