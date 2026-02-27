# Robot Learning OpenTofu

OpenTofu IaC for an IPv6-primary EKS cluster on AWS, built for ML training workloads.

## What it deploys

- **VPC** — dual-stack, IPv6-primary across 3 AZs (AWS-provided or BYOIP)
- **EKS** — Kubernetes cluster with Karpenter node autoscaling
- **Nodes** — CPU (cpu), mid-GPU (gpum), or single-GPU (gpul) tiers
- **Add-ons** — Karpenter, CoreDNS, VPC CNI, EBS CSI, NVIDIA GPU Operator (gpum/gpul only), S3 CSI
- **S3** — KMS-encrypted bucket for ML data, checkpoints, and model artefacts

## Quick start

```bash
cp terraform.tfvars.example terraform.tfvars
# fill in cluster_name, ml_data_bucket_name, and cluster_access at minimum

tofu init
tofu plan
tofu apply  # ~15–20 min

$(tofu output -raw configure_kubectl)
kubectl get nodes -o wide
```

## Docs

| | |
|---|---|
| [QUICKSTART](docs/QUICKSTART.md) | Prerequisites, step-by-step deploy, teardown |
| [VARIABLES](docs/VARIABLES.md) | All input variables with types and defaults |
| [BYOIP](docs/BYOIP.md) | Bring-your-own IPv6 prefix setup |

## Structure

```
main.tf                   # root module wiring
variables.tf              # input variables
outputs.tf                # outputs
backend.tf                # S3 remote state
terraform.tfvars.example  # copy → terraform.tfvars

modules/aws/
  vpc/                    # dual-stack VPC
  eks/                    # EKS cluster + IAM
  eks-addons/             # Karpenter, GPU Operator, S3 CSI
  s3/                     # ML data bucket
```

## State

Remote state is configured in [backend.tf](backend.tf) (S3 + DynamoDB lock, KMS-encrypted). Local state is gitignored — without the backend every apply runs from scratch.

`terraform.tfvars` and `terraform.tfstate` are gitignored. Never commit them.
