# modules/aws/eks

EKS cluster with managed GPU node group, IAM roles, and IPv6-mode add-ons. Designed for ML training workloads.

## Usage

```hcl
module "eks" {
  source = "./modules/aws/eks"

  cluster_name              = "my-cluster"
  cluster_version           = "1.29"
  vpc_id                    = module.vpc.vpc_id
  private_subnet_ids        = module.vpc.private_subnet_ids
  public_subnet_ids         = module.vpc.public_subnet_ids
  cluster_security_group_id = module.vpc.eks_cluster_security_group_id

  node_group_desired_size = 2
  node_group_min_size     = 1
  node_group_max_size     = 10
  node_instance_types     = ["g4dn.xlarge", "g5.xlarge"]
  node_disk_size          = 200

  tags = { Project = "my-project", Environment = "production" }
}
```

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `cluster_name` | `string` | -- | EKS cluster name |
| `cluster_version` | `string` | `1.29` | Kubernetes version |
| `vpc_id` | `string` | -- | VPC ID |
| `private_subnet_ids` | `list(string)` | -- | Subnets for nodes |
| `public_subnet_ids` | `list(string)` | -- | Public subnets |
| `cluster_security_group_id` | `string` | -- | Security group for control plane |
| `node_group_desired_size` | `number` | `1` | Initial node count |
| `node_group_min_size` | `number` | `0` | Minimum node count (0 = scale-to-zero) |
| `node_group_max_size` | `number` | `2` | Maximum node count |
| `node_instance_types` | `list(string)` | `["g5.4xlarge", "g5.8xlarge"]` | Instance types |
| `node_disk_size` | `number` | `200` | Disk size (GB) |
| `cluster_access` | `map(object)` | `{}` | Map of IAM principals → EKS access policy (see below) |
| `tags` | `map(string)` | `{}` | Tags applied to all resources |

## Outputs

| Name | Description |
|------|-------------|
| `cluster_id` | EKS cluster ID |
| `cluster_name` | Cluster name |
| `cluster_endpoint` | API server endpoint |
| `cluster_security_group_id` | Control plane security group ID |
| `cluster_version` | Kubernetes server version |
| `cluster_certificate_authority_data` | CA certificate (sensitive) |
| `node_group_id` | Node group ID |
| `node_group_status` | Node group status |
| `cluster_iam_role_arn` | Cluster IAM role ARN |
| `node_iam_role_arn` | Node IAM role ARN |

## Add-ons

| Add-on | Config |
|--------|--------|
| `vpc-cni` | `ENABLE_IPv6=true`, `ENABLE_IPv4=false`, `ENABLE_PREFIX_DELEGATION=true` |
| `coredns` | Default |
| `kube-proxy` | Default |
| `aws-ebs-csi-driver` | Default |

## IAM Policies

**Cluster role**: `AmazonEKSClusterPolicy`, `AmazonEKSVPCResourceController`

**Node role**: `AmazonEKSWorkerNodePolicy`, `AmazonEKS_CNI_Policy`, `AmazonEC2ContainerRegistryReadOnly`, `AmazonEBSCSIDriverPolicy`

## RBAC / Cluster Access

Uses the EKS Access Entries API (`authentication_mode = "API"`) — no `aws-auth` ConfigMap. Each principal gets their own access entry scoped to their IAM identity.

```hcl
cluster_access = {
  alice = {
    principal_arn = "arn:aws:iam::123456789012:user/alice"
    policy        = "AmazonEKSClusterAdminPolicy"
  }
  bob = {
    principal_arn = "arn:aws:iam::123456789012:role/bob-role"
    policy        = "AmazonEKSViewPolicy"
  }
}
```

| Policy | Access |
|--------|--------|
| `AmazonEKSClusterAdminPolicy` | Full cluster-admin |
| `AmazonEKSAdminPolicy` | Admin within namespaces |
| `AmazonEKSEditPolicy` | Read/write within namespaces |
| `AmazonEKSViewPolicy` | Read-only |

## Node Labels

Nodes are pre-labeled for workload targeting:

| Label | Value |
|-------|-------|
| `Environment` | from tags |
| `Project` | from tags |
| `Workload` | `ml-training` |
| `GPU` | `enabled` |

```yaml
nodeSelector:
  Workload: ml-training
  GPU: enabled
```

## Scaling

`desired_size` is excluded from lifecycle to allow Cluster Autoscaler to manage it.

```bash
aws eks update-nodegroup-config \
  --cluster-name <name> \
  --nodegroup-name <nodegroup> \
  --scaling-config desiredSize=5
```

## Logs

Control plane logs (api, audit, authenticator, controllerManager, scheduler) are written to CloudWatch under `/aws/eks/<cluster-name>/cluster`.
