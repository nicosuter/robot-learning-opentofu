#!/usr/bin/env bash
# Two-phase deploy — required on fresh clusters.
#
# The Kubernetes and Helm providers authenticate at the very start of apply
# (before any resources exist), so a single `tofu apply` on a fresh cluster
# will always fail for eks_addons resources. Phase 1 brings the cluster and
# nodes up first; phase 2 applies everything else once the API server is ready.
#
# Subsequent applies (updates, drift fixes) can use plain `tofu apply`.

set -euo pipefail

# Phase 1: AWS-only resources — VPC, EKS cluster + node group, WAF
echo "==> Phase 1: cluster infrastructure"
tofu apply \
  -target=module.vpc \
  -target=module.eks \
  -target=module.waf \
  -target=module.s3_ml_data \
  "$@"

# Phase 2: everything else — Helm charts, k8s manifests, ArgoCD, Karpenter
echo "==> Phase 2: cluster addons"
tofu apply "$@"
