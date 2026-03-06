# Terraform Management Instance

Minimal EC2 instance in us-east-1 for applying Terraform/OpenTofu configs. Uses default VPC, t3.micro, Amazon Linux 2023.

## Deploy (from local)

```bash
cd management
cp terraform.tfvars.example terraform.tfvars
# Set public_key_path to your .pub file (absolute path; file() does not expand ~)
tofu init
tofu apply
```

## SSH

Terraform creates the EC2 key pair from your public key. Use the matching private key:

```bash
$(tofu -chdir=management output -raw ssh_command)
```

## Apply Hercules from the instance

```bash
# Clone repo (or scp your config)
git clone <repo> && cd ethrc-opentofu

# Backend uses profile "ethrc" — instance role has permissions, no profile needed
# If backend.tf uses profile, configure: export AWS_PROFILE=ethrc (or use instance role)

tofu init -reconfigure
tofu plan
tofu apply
```

## Restrict SSH

Set `ssh_allowed_cidrs` in `terraform.tfvars` to your IP:

```hcl
ssh_allowed_cidrs = ["YOUR_IP/32"]
```
