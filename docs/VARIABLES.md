# Variables

All input variables for the root module. Set them in `terraform.tfvars` (copy from `terraform.tfvars.example`).

---

## Cluster

| Variable | Type | Default | Description |
|---|---|---|---|
| `region` | `string` | `eu-central-1` | AWS region |
| `cluster_name` | `string` | `ethrc-rbtl-eks-cluster` | EKS cluster name |
| `cluster_version` | `string` | `1.35` | Kubernetes version |

---

## Networking

| Variable | Type | Default | Description |
|---|---|---|---|
| `vpc_cidr` | `string` | `10.0.0.0/16` | VPC IPv4 CIDR |
| `use_byoip_ipv6` | `bool` | `false` | Use BYOIP instead of AWS-provided IPv6 |
| `byoip_ipv6_pool_id` | `string` | `null` | BYOIP pool ID (format: `ipv6pool-ec2-...`) |
| `byoip_ipv6_cidr` | `string` | `null` | Specific CIDR from the pool (e.g. `2001:db8::/56`) |
| `byoip_ipv6_netmask_length` | `number` | `56` | Netmask length when not specifying an exact CIDR |

See [BYOIP.md](BYOIP.md) for setup instructions.

---

## Nodes

| Variable | Type | Default | Description |
|---|---|---|---|
| `node_tier` | `string` | `cpu` | Compute tier: `cpu`, `gpum`, or `gpul` |
| `node_disk_size` | `number` | `200` | Root disk size in GB |
| `gpu_node_max_lifetime` | `string` | `16h` | Hard TTL for gpum/gpul nodes — Karpenter will drain and terminate after this duration regardless of workload state. Go duration syntax (e.g. `"72h"`). Set to `"Never"` to disable. |

`node_tier` controls Karpenter NodePool selection and whether the NVIDIA GPU Operator is installed:

| Value | Instance types | GPU Operator |
|---|---|---|
| `cpu` | m5, m6i, t3 (spot-eligible) | No |
| `gpum` | g6e.4xlarge (1× L40S) | Yes |
| `gpul` | p5.xlarge (1× H100) | Yes |

---

## Access

| Variable | Type | Default | Description |
|---|---|---|---|
| `cluster_access` | `map(object)` | `{}` | IAM principals and their cluster role |

Each entry:

```hcl
cluster_access = {
  alice = {
    principal_arn = "arn:aws:iam::123456789012:user/alice"
    policy        = "AmazonEKSClusterAdminPolicy"
  }
}
```

Available policies: `AmazonEKSClusterAdminPolicy`, `AmazonEKSAdminPolicy`, `AmazonEKSEditPolicy`, `AmazonEKSViewPolicy`

---

## S3

| Variable | Type | Default | Description |
|---|---|---|---|
| `ml_data_bucket_name` | `string` | **required** | Name for the ML data/checkpoints/artefacts bucket (must be globally unique) |
| `s3_bucket_arns` | `list(string)` | `[]` | Additional S3 bucket ARNs to mount via S3 CSI |

The S3 CSI driver is only installed when at least one bucket ARN is present (the ML data bucket is always included).

---

## Tags

| Variable | Type | Default | Description |
|---|---|---|---|
| `tags` | `map(string)` | see below | Tags applied to all resources |

Default tags:
```hcl
{
  Project     = "ethrc-rbtl"
  Environment = "development"
  ManagedBy   = "OpenTofu"
}
```
