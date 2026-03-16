# ETHRC Hackathon Kubernetes Guide

A survival guide for running ML workloads on our shared EKS cluster. Each team gets an isolated namespace.

---

## Before You Start

**You need:** AWS CLI, kubectl, and a team namespace from the organizers.

```bash
# macOS
brew install awscli kubectl

# Or grab binaries directly:
# https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html
# https://kubernetes.io/docs/tasks/tools/
```

**Optional but recommended:** [k9s](https://k9scli.io/) — terminal UI for browsing pods, logs, and resources without typing a thousand kubectl commands.

---

## Connect to the Cluster

```bash
# Configure credentials (organizers will provide these)
aws configure
# Region: us-east-1

# Connect kubectl
aws eks update-kubeconfig --region us-east-1 --name ethrc-prod-1

# Verify
kubectl get nodes

# Set your team's namespace
export NAMESPACE=your-team-name  # e.g., team-alpha, team-beta
```

---

## What's Available

### Pre-built Images

| Framework | Image | Location |
|-----------|-------|----------|
| PyTorch | `ethroboticsclub/pytorch:latest` | ECR |
| JAX | `ethroboticsclub/jax:latest` | ECR |

These are built from the [docker-images](https://github.com/ethroboticsclub/docker-images) repo and kept up to date. Use them directly or build your own.

### Hardware Tiers

| Tier | Instance | GPU | VRAM | Use For |
|------|----------|-----|------|---------|
| `cpu` | m6i/t3 | — | — | Data prep, web apps |
| `gpus` | g6.xlarge | 1× L4 | 24 GB | **Start here** — testing, small models |
| `gpum` | g6e.xlarge | 1× L40S | 48 GB | If you hit 24GB VRAM limit |
| `gpul` | g6e.12xlarge | 4× L40S | 192 GB | Distributed training only |

**Default: `gpus`**. The L4 handles most hackathon workloads. More VRAM ≠ more performance unless you've implemented data parallelism (you probably haven't).

Nodes spin up on-demand via Karpenter. First node takes 60-90 seconds.

### Your Namespace

Each hackathon team is isolated. You can only see resources in your namespace:

| Team | Namespace |
|------|-----------|
| Team Alpha | `team-alpha` |
| Team Beta | `team-beta` |
| Team Gamma | `team-gamma` |
| Team Delta | `team-delta` |

---

## First Deployment

Create `hello.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hello
  namespace: YOUR-NAMESPACE-HERE
spec:
  replicas: 1
  selector:
    matchLabels:
      app: hello
  template:
    metadata:
      labels:
        app: hello
    spec:
      containers:
      - name: hello
        image: python:3.11-slim
        command: ["sleep", "3600"]
        resources:
          requests:
            memory: "256Mi"
            cpu: "250m"
          limits:
            memory: "512Mi"
            cpu: "500m"
```

Deploy and verify:

```bash
kubectl apply -f hello.yaml
kubectl get pods -n $NAMESPACE
```

Get a shell inside:

```bash
kubectl exec -it deploy/hello -n $NAMESPACE -- /bin/bash
python --version
exit
```

View logs:

```bash
kubectl logs deploy/hello -n $NAMESPACE
kubectl logs -f deploy/hello -n $NAMESPACE  # follow
```

Clean up:

```bash
kubectl delete -f hello.yaml
```

---

## Training Jobs with GPUs

Use **TrainJob** (Kubeflow Trainer v2), not raw pods.

Create `train.yaml`:

```yaml
apiVersion: trainer.kubeflow.org/v1alpha1
kind: TrainJob
metadata:
  name: my-training
  namespace: YOUR-NAMESPACE-HERE
spec:
  runtimeRef:
    name: torch-distributed
  numNodes: 1
  trainer:
    image: ethroboticsclub/pytorch:latest
    command:
      - python
      - train.py
    resources:
      limits:
        nvidia.com/gpu: 1
        ephemeral-storage: "200Gi"
      requests:
        memory: "8Gi"
        cpu: "4"
        nvidia.com/gpu: 1
```

Deploy and monitor:

```bash
kubectl apply -f train.yaml
kubectl get trainjobs -n $NAMESPACE
kubectl get trainjobs -n $NAMESPACE -w  # watch

# Logs
kubectl logs -l trainer.kubeflow.org/trainjob-name=my-training -n $NAMESPACE

# Check GPU allocation
kubectl get pods -l trainer.kubeflow.org/trainjob-name=my-training -n $NAMESPACE \
  -o json | grep nvidia.com/gpu
```

Clean up:

```bash
kubectl delete trainjob my-training -n $NAMESPACE
```

### GPU Node TTL

**GPU nodes terminate after 16 hours.** Design your training to:
- Save checkpoints regularly
- Resume from checkpoints
- Use shorter runs or distributed training for large jobs

---

## Storage

### Local NVMe (Ephemeral)

Fast scratch space that disappears when the node terminates:

```yaml
resources:
  limits:
    ephemeral-storage: "200Gi"
```

Data in `/tmp` uses local NVMe.

Downloads from HuggingFace, pip, apt, etc. work normally — nodes have public internet access.

---

## Quick Reference

```bash
# Pods
kubectl get pods -n $NAMESPACE
kubectl logs <pod> -n $NAMESPACE
kubectl exec -it <pod> -n $NAMESPACE -- /bin/bash
kubectl describe pod <pod> -n $NAMESPACE

# TrainJobs
kubectl get trainjobs -n $NAMESPACE
kubectl describe trainjob <name> -n $NAMESPACE
kubectl logs -l trainer.kubeflow.org/trainjob-name=<name> -n $NAMESPACE

# Check GPU
kubectl get pods -n $NAMESPACE -o json | grep nvidia.com/gpu
kubectl exec <pod> -n $NAMESPACE -- nvidia-smi

# Verify access
kubectl auth can-i get pods -n $NAMESPACE

# Debug
kubectl get events -n $NAMESPACE --sort-by='.lastTimestamp'
```

---

## Troubleshooting

### Pod stuck Pending

```bash
kubectl describe pod <pod> -n $NAMESPACE
```

| Symptom | Cause | Fix |
|---------|-------|-----|
| `0/3 nodes available` | Karpenter provisioning | Wait 1-8 minutes |
| `Insufficient nvidia.com/gpu` | GPUs in use | Wait or try different tier |
| `OutOfMemory` | Memory limit too low | Increase memory in spec |
| `ImagePullBackOff` | Bad image name or no permissions | Check if image exists |

### Container crashing

```bash
kubectl logs <pod> -n $NAMESPACE --previous
kubectl describe pod <pod> -n $NAMESPACE
```

### Can't connect

```bash
aws sts get-caller-identity  # verify creds
aws eks update-kubeconfig --region us-east-1 --name ethrc-prod-1
```

### GPU not visible

```bash
# Check GPU operator
kubectl get pods -n gpu-operator

# Test inside container
kubectl exec <pod> -n $NAMESPACE -- nvidia-smi
```

### OOMKilled

```bash
kubectl describe pod <pod> -n $NAMESPACE | grep -A5 "State:"
```

Your process exceeded available node memory. Try:
- Reduce batch size or model memory footprint
- Move to a larger GPU tier with more RAM
- Check for memory leaks

---

## Example: Training from a Git Repo

Put your code in a repo, then clone and run it:

```yaml
apiVersion: trainer.kubeflow.org/v1alpha1
kind: TrainJob
metadata:
  name: training-run
  namespace: YOUR-NAMESPACE-HERE
spec:
  runtimeRef:
    name: torch-distributed
  numNodes: 1
  trainer:
    image: ethroboticsclub/pytorch:latest
    command:
      - bash
      - -c
      - |
        git clone https://github.com/YOUR_ORG/YOUR_REPO.git /workspace
        cd /workspace
        python train.py
    resources:
      limits:
        nvidia.com/gpu: 1
        ephemeral-storage: "200Gi"
      requests:
        memory: "8Gi"
        cpu: "4"
        nvidia.com/gpu: 1
```

Or use an init container to clone, keeping the trainer command clean:

```yaml
apiVersion: trainer.kubeflow.org/v1alpha1
kind: TrainJob
metadata:
  name: training-run
  namespace: YOUR-NAMESPACE-HERE
spec:
  runtimeRef:
    name: torch-distributed
  numNodes: 1
  trainer:
    image: ethroboticsclub/pytorch:latest
    command: ["python", "/workspace/train.py"]
    resources:
      limits:
        nvidia.com/gpu: 1
        ephemeral-storage: "200Gi"
      requests:
        memory: "8Gi"
        cpu: "4"
        nvidia.com/gpu: 1
    volumeMounts:
      - name: code
        mountPath: /workspace
  volumes:
    - name: code
      emptyDir: {}
  initContainers:
    - name: clone
      image: alpine/git
      command: ["git", "clone", "https://github.com/YOUR_ORG/YOUR_REPO.git", "/workspace"]
      volumeMounts:
        - name: code
          mountPath: /workspace
```

Deploy and watch:

```bash
kubectl apply -f training.yaml
kubectl get trainjobs -n $NAMESPACE -w
kubectl logs -l trainer.kubeflow.org/trainjob-name=training-run -n $NAMESPACE -f
kubectl delete trainjob training-run -n $NAMESPACE
```

---

## Rules of the Road

1. **Always use your namespace** — resources without one go to `default`, which you probably can't access
2. **Start with `gpus` tier** — upgrade only if you hit the 24GB limit
3. **Set resource requests/limits** — helps Karpenter schedule efficiently
4. **Use TrainJob, not raw pods** — Kubeflow Trainer is installed for a reason
5. **Save checkpoints** — nodes die after 16 hours
6. **Clean up when done** — delete finished jobs to free GPUs
7. **Name clearly** — include team name: `team-alpha-exp-v1`

---

## Getting Help

Stuck? Gather diagnostics:

```bash
kubectl describe trainjob <name> -n $NAMESPACE
kubectl logs -l trainer.kubeflow.org/trainjob-name=<name> -n $NAMESPACE
kubectl get events -n $NAMESPACE --sort-by='.lastTimestamp'
```

Share that output with the ETHRC team.

---

Happy hacking.
