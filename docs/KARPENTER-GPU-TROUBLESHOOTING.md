# Karpenter GPU Node Provisioning Troubleshooting

When GPU pods stay pending and Karpenter isn't provisioning nodes, use these steps to diagnose.

## 1. Verify GPU Operator is installed

**Critical:** `node_tier` must be `gpus`, `gpum`, `gpul`, or `h100` for the NVIDIA GPU Operator to be installed. Without it, GPU nodes won't advertise `nvidia.com/gpu` and pods stay pending.

```bash
# Check node_tier in your terraform.tfvars
# Then verify GPU Operator is running
kubectl get pods -n gpu-operator
kubectl get daemonset -n gpu-operator
```

If `node_tier=cpu`, run `tofu apply` with `node_tier = "gpum"` (or another GPU tier: gpus, gpul, h100) to install the operator.

## 2. Check NodePool and EC2NodeClass status

```bash
kubectl get nodepools
kubectl describe nodepool gpum

kubectl get ec2nodeclasses
kubectl describe ec2nodeclass default
```

The EC2NodeClass must show `Ready` in `status.conditions`. If not, check subnets, security groups, and IAM.

## 3. Check for NodeClaims (provisioning in progress)

```bash
kubectl get nodeclaims
kubectl describe nodeclaim <name>
```

## 4. Inspect Karpenter controller logs

```bash
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter -f
```

Look for errors such as:
- `no instance type satisfied resources` — daemonset overhead or limits
- `failed to discover any AMIs` — AMI resolution failure
- `InsufficientInstanceCapacity` — EC2 capacity in the region/AZ

## 5. Verify pending pod requirements

```bash
kubectl describe pod <pending-pod> -n <namespace>
```

Ensure:
- `nodeSelector` matches NodePool template labels (`karpenter.sh/nodepool`, `node-tier`)
- `tolerations` include `nvidia.com/gpu: NoSchedule`
- `resources.limits` includes `nvidia.com/gpu: "1"` (or more)

## 6. Confirm subnet and security group tags

Karpenter discovers subnets and security groups via tags. The VPC module must set:

```text
karpenter.sh/discovery = <cluster_name>
```

```bash
# List tagged subnets
aws ec2 describe-subnets --filters "Name=tag:karpenter.sh/discovery,Values=<your-cluster-name>" --query 'Subnets[*].[SubnetId,Tags]' --output table
```

## 7. Common fixes

| Issue | Fix |
|-------|-----|
| `node_tier=cpu` | Set `node_tier = "gpum"` and re-apply Terraform |
| EC2NodeClass not Ready | Check subnet/SG tags, IAM instance profile |
| `no instance type satisfied` | Verify NodePool limits, instance types, and daemonset overhead |
| Region capacity | Try different `gpum_instance_types` or AZs |
| Stuck in single AZ | Use EFS instead of EBS, or delete zone-bound PVCs/PVs |
