# ─────────────────────────────────────────────────────────────────────────────
# ECR Pull-Through Cache
#
# Routes image pulls for docker.io, ghcr.io, quay.io, registry.k8s.io, and
# public.ecr.aws through private ECR repositories.  Containerd on every
# Karpenter node is configured to use these as mirrors, so image traffic never
# touches the NAT Gateway after the first pull per tag.
#
# Cost model (us-east-1 example):
#   NAT Gateway processing  $0.045/GB  → $0 for cached pulls
#   ECR storage             $0.10/GB·month (first 500 GB free)
#   ECR data transfer       free within the same region
# ─────────────────────────────────────────────────────────────────────────────

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  registry_url = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.name}.amazonaws.com"
}

# ── Pull-through cache rules ──────────────────────────────────────────────────
#
# Each rule maps an upstream registry to a prefix inside your private ECR.
# Pull: docker pull <registry_url>/dockerhub/library/ubuntu:22.04
#        → ECR checks cache → on miss, fetches from registry-1.docker.io

resource "aws_ecr_pull_through_cache_rule" "dockerhub" {
  ecr_repository_prefix = "dockerhub"
  upstream_registry_url = "registry-1.docker.io"
  # Optional: authenticated pulls avoid DockerHub anonymous rate limits (100 req/6 h/IP).
  # Store {"username":"...","accessToken":"..."} in Secrets Manager and pass the ARN.
  credential_arn = var.dockerhub_credentials_secret_arn
}

resource "aws_ecr_pull_through_cache_rule" "ghcr" {
  ecr_repository_prefix = "ghcr"
  upstream_registry_url = "ghcr.io"
}

resource "aws_ecr_pull_through_cache_rule" "quay" {
  ecr_repository_prefix = "quay"
  upstream_registry_url = "quay.io"
}

resource "aws_ecr_pull_through_cache_rule" "k8s" {
  ecr_repository_prefix = "k8s"
  upstream_registry_url = "registry.k8s.io"
}

resource "aws_ecr_pull_through_cache_rule" "ecr_public" {
  ecr_repository_prefix = "ecr-public"
  upstream_registry_url = "public.ecr.aws"
}
