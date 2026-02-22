# ETHRC, Robot Learning Division - IaC

OpenTofu configuration for an IPv6-primary EKS cluster on AWS, optimized for ML training workloads.

## Features

- **IPv6-primary** — dual-stack VPC, IPv6 pod/service networking, BYOIP or AWS-provided
- **GPU nodes** — g5.4xlarge (1× A10G, 24 GB VRAM), scale-to-zero via Cluster Autoscaler
- **Modular** — `modules/aws/{vpc,eks}` are independently usable; add other clouds as siblings

## Structure

```
.
├── main.tf
├── variables.tf
├── outputs.tf
├── backend.tf
├── terraform.tfvars.example
├── modules/
│   └── aws/
│       ├── vpc/
│       └── eks/
└── docs/
    └── IPv6 BYOIP.md
```

## Architecture

```
modules/aws/vpc
├── Public subnets x 3 AZs  → Internet Gateway
├── Private subnets x 3 AZs → NAT Gateways (IPv4) + Egress-Only IGW (IPv6)
└── Security groups (cluster + nodes)

modules/aws/eks
├── IAM roles (cluster + nodes)
├── EKS cluster (ip_family = ipv6)
├── Managed node group (GPU, on-demand)
└── Add-ons: vpc-cni (IPv6), coredns, kube-proxy, aws-ebs-csi-driver
```

## Prerequisites

- OpenTofu or Terraform
- AWS CLI with credentials configured
- Account quotas for GPU instances, NAT Gateways, and Elastic IPs

## Quick Start

```bash
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars

tofu init
tofu plan
tofu apply  # ~15-20 min

aws eks update-kubeconfig --region eu-central-1 --name ethrc-rbtl-eks-cluster
kubectl get nodes -o wide
```

## Secrets & State

### What is and isn't committed

| Path | Committed | Reason |
|------|-----------|--------|
| `terraform.tfvars` | No — gitignored | Contains IAM ARNs, BYOIP pool IDs |
| `terraform.tfstate` | No — gitignored | Contains **all output values in plaintext**, including the CA cert |
| `backend.tf` | Yes | Just points to the S3 bucket — no credentials |
| `.terraform.lock.hcl` | Yes | Provider version lock — ensures everyone uses the same provider build |
| `*.tfvars.example` | Yes | Placeholders only, no real values |

### Remote state (required for shared use)

Local state is gitignored, so without a remote backend each person has their own state — meaning `tofu apply` from a second machine will try to recreate everything.

Configure the S3 backend in `backend.tf` (already present), create the bucket and lock table once, then:

```bash
tofu init  # prompts to migrate any existing local state
```

State is stored encrypted at rest (KMS) with versioning enabled. Access is controlled by S3 bucket policy — only team members with the right IAM permissions can read or write it.

### Accessing sensitive outputs

Sensitive outputs (e.g. `cluster_certificate_authority_data`) are redacted in terminal output but retrievable when needed:

```bash
tofu output -raw cluster_certificate_authority_data
tofu output -json  # all outputs including sensitive
```

These values live in state — keep the S3 bucket access-controlled and do **not** print them in CI logs.

## Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `cluster_name` | `ethrc-rbtl-eks-cluster` | EKS cluster name |
| `region` | `eu-central-1` | AWS region |
| `cluster_version` | `1.29` | Kubernetes version |
| `vpc_cidr` | `10.0.0.0/16` | VPC IPv4 CIDR |
| `availability_zones` | `[eu-central-1a/b/c]` | AZs to deploy into |
| `use_byoip_ipv6` | `false` | Use BYOIP pool instead of AWS-provided IPv6 |
| `byoip_ipv6_pool_id` | `null` | AWS BYOIP pool ID |
| `byoip_ipv6_cidr` | `null` | BYOIP CIDR (e.g. `2001:db8:1234::/56`) |
| `node_instance_types` | `["g5.4xlarge", "g5.8xlarge"]` | Node instance types |
| `node_disk_size` | `200` | Node disk size (GB) |
| `node_group_desired_size` | `1` | Initial node count |
| `node_group_min_size` | `0` | Minimum node count (0 = scale-to-zero) |
| `node_group_max_size` | `2` | Maximum node count |

For BYOIP setup, see [docs/IPv6 BYOIP.md](docs/IPv6%20BYOIP.md).

## RBAC / Cluster Access

Each user authenticates with their own AWS IAM identity. Add entries to `cluster_access` in `terraform.tfvars`:

```hcl
cluster_access = {
  alice = {
    principal_arn = "arn:aws:iam::123456789012:user/alice"
    policy        = "AmazonEKSClusterAdminPolicy"
  }
  bob = {
    principal_arn = "arn:aws:iam::123456789012:role/bob-dev-role"
    policy        = "AmazonEKSViewPolicy"
  }
}
```

Available policies:

| Policy | Access |
|--------|--------|
| `AmazonEKSClusterAdminPolicy` | Full cluster-admin |
| `AmazonEKSAdminPolicy` | Admin within namespaces |
| `AmazonEKSEditPolicy` | Read/write within namespaces |
| `AmazonEKSViewPolicy` | Read-only |

Users generate a kubeconfig scoped to their own identity:

```bash
aws eks update-kubeconfig --region eu-central-1 --name ethrc-rbtl-eks-cluster
```

## Outputs

| Output | Description |
|--------|-------------|
| `cluster_endpoint` | EKS API server endpoint |
| `cluster_name` | Cluster name |
| `configure_kubectl` | kubectl config command |
| `vpc_id` | VPC ID |
| `vpc_ipv6_cidr` | IPv6 CIDR block |
| `cluster_certificate_authority_data` | CA certificate (sensitive) |

## Cluster Autoscaler

The node group is tagged for auto-discovery. Install the Cluster Autoscaler to enable scale-to-zero when no workloads are running:

```bash
helm repo add autoscaler https://kubernetes.github.io/autoscaler
helm install cluster-autoscaler autoscaler/cluster-autoscaler \
  --namespace kube-system \
  --set autoDiscovery.clusterName=ethrc-rbtl-eks-cluster \
  --set awsRegion=eu-central-1 \
  --set extraArgs.scale-down-unneeded-time=10m \
  --set extraArgs.scale-down-delay-after-add=10m
```

## GPU Workloads

```bash
kubectl apply -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.14.0/nvidia-device-plugin.yml
```

Target GPU nodes in pod specs:

```yaml
nodeSelector:
  Workload: ml-training
  GPU: enabled
resources:
  limits:
    nvidia.com/gpu: 1
```

## Troubleshooting

**IPv6 pods not starting**
```bash
kubectl describe daemonset aws-node -n kube-system
```

**GPUs not available**
```bash
kubectl get pods -n kube-system | grep nvidia
```

**Insufficient capacity** — try a different AZ, different instance type, or request a quota increase.

## Cleanup

```bash
tofu destroy
```
