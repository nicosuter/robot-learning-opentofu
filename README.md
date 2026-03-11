# Hercules

Cluster orchestration for the ETHRC organisation. OpenTofu IaC that provisions an IPv6-primary EKS cluster on AWS with GPU autoscaling and GitOps, purpose-built for ML training workloads.

## What it deploys

- **VPC** — dual-stack, IPv6-primary across 5 AZs (AWS-provided or BYOIP)
- **EKS** — Kubernetes cluster with Karpenter node autoscaling
- **Nodes** — CPU (`cpu`), entry-level GPU (`gpus`), mid GPU (`gpum`), large GPU (`gpul`), or H100 (`h100`) tiers provisioned on demand by Karpenter
- **Add-ons** — Karpenter, CoreDNS, VPC CNI, EBS CSI, NVIDIA GPU Operator (GPU tiers), S3 CSI
- **ArgoCD** — GitOps-driven workload delivery with per-project repo whitelisting
- **S3** — KMS-encrypted bucket for ML data, checkpoints, and model artefacts
- **Cost controls** — GPU node TTL (`gpu_node_max_lifetime`) and a cost killswitch script

### GPU tiers

| Tier | Node pool | Instance | GPU | VRAM | Primary workload |
|------|-----------|----------|-----|------|-----------------|
| S | `gpus` | g6.xlarge | 1× L4 | 24 GB | Code validation, EDA, script debugging |
| M | `gpum` | g6e.xlarge | 1× L40S | 48 GB | Core prototyping, LoRA fine-tuning (up to 14B params), heavy inference |
| L | `gpul` | g6e.12xlarge | 4× L40S | 192 GB | Distributed training (DDP/FSDP), continuous pre-training, large batch sizes |

## Quick start

```bash
cp terraform.tfvars.example terraform.tfvars
# fill in cluster_name, ml_data_bucket_name, and cluster_access at minimum

tofu init
tofu plan

# Fresh cluster — two-phase deploy required (see deploy.sh for details)
./deploy.sh

# Subsequent applies (updates, drift fixes)
tofu apply

$(tofu output -raw configure_kubectl)
kubectl get nodes -o wide
```

> **Fresh deploys require `./deploy.sh`** instead of a plain `tofu apply`. The Kubernetes and Helm providers authenticate before any resources exist, so a single apply will always fail for add-on resources. `deploy.sh` runs Phase 1 (VPC, EKS, S3) first and Phase 2 (Helm charts, ArgoCD, Karpenter) once the API server is ready.

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
deploy.sh                 # two-phase deploy for fresh clusters

modules/aws/
  vpc/                    # dual-stack VPC
  eks/                    # EKS cluster + IAM
  eks-addons/             # Karpenter, GPU Operator, ArgoCD, S3 CSI
  s3/                     # ML data bucket

scripts/
  cost-killswitch.py      # emergency spend brake
```

## Access

Team access is managed through the `cluster_access` variable — a map of IAM principals to EKS access policies (`ClusterAdmin`, `Admin`, `Edit`, `View`). See [VARIABLES](docs/VARIABLES.md) for details.

## State

Remote state is configured in [backend.tf](backend.tf) (S3 + DynamoDB lock, KMS-encrypted). Local state is gitignored — without the backend every apply runs from scratch.

`terraform.tfvars` and `terraform.tfstate` are gitignored. Never commit them.
