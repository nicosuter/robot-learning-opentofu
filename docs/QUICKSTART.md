# Quickstart

## Prerequisites

- [OpenTofu](https://opentofu.org) `~> 1.9` (or Terraform)
- AWS CLI configured with credentials
- Sufficient account quotas: EKS, NAT Gateways, Elastic IPs, and GPU instances if needed

---

## 1. Bootstrap remote state (first time only)

The S3 backend bucket and DynamoDB lock table must exist before `tofu init`. Run the bootstrap module once with a temporary local backend:

```bash
tofu -chdir=modules/aws/bootstrap init
tofu -chdir=modules/aws/bootstrap apply \
  -var="state_bucket_name=<your-state-bucket>" \
  -var="lock_table_name=tofu-state-lock" \
  -var="region=eu-central-1"
```

Then fill in `backend.tf` with the bucket and table names you just created.

---

## 2. Configure

```bash
cp terraform.tfvars.example terraform.tfvars
```

At minimum, set:

```hcl
cluster_name        = "ethrc-rbtl-eks-cluster"
ml_data_bucket_name = "your-globally-unique-bucket-name"

cluster_access = {
  alice = {
    principal_arn = "arn:aws:iam::123456789012:user/alice"
    policy        = "AmazonEKSClusterAdminPolicy"
  }
}
```

See [VARIABLES.md](VARIABLES.md) for the full reference.

---

## 3. Deploy

```bash
tofu init
tofu plan
tofu apply   # ~15–20 min
```

---

## 4. Connect

```bash
$(tofu output -raw configure_kubectl)
kubectl get nodes -o wide
```

---

## Node tiers

Set `node_tier` in `terraform.tfvars` to control what Karpenter provisions:

| Tier | Hardware | Use case |
|---|---|---|
| `standard` | m5/m6i/t3, spot-eligible | CPU workloads |
| `gpu` | p5.xlarge (1× H100) | Single-GPU training |
| `gpux` | p5.48xlarge (8× H100) | Multi-GPU training |

The NVIDIA GPU Operator is installed automatically for `gpu` and `gpux` tiers. To target GPU nodes in a pod spec:

```yaml
nodeSelector:
  karpenter.sh/nodepool: gpu   # or gpux
resources:
  limits:
    nvidia.com/gpu: 1
```

---

## Cluster access

Each person authenticates with their own IAM identity — no shared credentials.

Add entries to `cluster_access` in `terraform.tfvars`, then re-apply:

```hcl
cluster_access = {
  alice = {
    principal_arn = "arn:aws:iam::123456789012:user/alice"
    policy        = "AmazonEKSClusterAdminPolicy"
  }
  bob = {
    principal_arn = "arn:aws:iam::123456789012:role/bob-dev-role"
    policy        = "AmazonEKSEditPolicy"
  }
}
```

Available policies: `AmazonEKSClusterAdminPolicy`, `AmazonEKSAdminPolicy`, `AmazonEKSEditPolicy`, `AmazonEKSViewPolicy`

Each user then runs:

```bash
aws eks update-kubeconfig --region eu-central-1 --name <cluster_name>
```

---

## S3 integration

An ML data bucket is created automatically (`ml_data_bucket_name`). To mount additional buckets, add their ARNs:

```hcl
s3_bucket_arns = [
  "arn:aws:s3:::my-other-bucket",
]
```

The S3 CSI driver (Mountpoint for Amazon S3) is installed when any S3 ARN is present.

---

## Sensitive outputs

Sensitive outputs are redacted in terminal output. Retrieve them explicitly when needed:

```bash
tofu output -raw cluster_certificate_authority_data
tofu output -json   # all outputs
```

---

## IPv6 / BYOIP

AWS-provided IPv6 is used by default. To bring your own prefix, see [BYOIP.md](BYOIP.md).

---

## Teardown

```bash
tofu destroy
```
