# modules/aws/eks

EKS cluster with IPv6 ip_family, a permanent single-node system node group (`t3.small`), Karpenter IAM/IRSA, and RBAC via Access Entries. Workload nodes are provisioned on-demand by Karpenter (configured in `modules/aws/eks-addons`).

## Usage

```hcl
module "eks" {
  source = "./modules/aws/eks"

  cluster_name              = "my-cluster"
  cluster_version           = "1.35"
  vpc_id                    = module.vpc.vpc_id
  private_subnet_ids        = module.vpc.private_subnet_ids
  public_subnet_ids         = module.vpc.public_subnet_ids
  cluster_security_group_id = module.vpc.eks_cluster_security_group_id

  node_disk_size        = 200 # Karpenter-provisioned workload nodes
  system_node_disk_size = 20  # system node group (default)

  tags = { Project = "my-project", Environment = "production" }
}
```

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `cluster_name` | `string` | -- | EKS cluster name |
| `cluster_version` | `string` | `"1.35"` | Kubernetes version |
| `vpc_id` | `string` | -- | VPC ID |
| `private_subnet_ids` | `list(string)` | -- | Subnets for nodes |
| `public_subnet_ids` | `list(string)` | -- | Public subnets |
| `cluster_security_group_id` | `string` | -- | Security group for control plane |
| `node_disk_size` | `number` | `200` | Disk size (GB) for Karpenter-provisioned workload nodes |
| `system_node_disk_size` | `number` | `20` | Disk size (GB) for the permanent system node |
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
| `vpc-cni` | `ENABLE_PREFIX_DELEGATION=true`, `enableNetworkPolicy=true` |
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

## System Node Group

One permanent `t3.small` node (ON_DEMAND) runs 24/7, labelled `node-role=system`. It hosts Karpenter, CoreDNS, and kube-proxy. Karpenter must be running before it can provision workload nodes, so this node group has a fixed size of `min=1 / desired=1 / max=1` with no lifecycle `ignore_changes`.

## Logs

Control plane logs (api, audit, authenticator, controllerManager, scheduler) are written to CloudWatch under `/aws/eks/<cluster-name>/cluster`.
