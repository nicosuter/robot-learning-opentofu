MIME-Version: 1.0
Content-Type: multipart/mixed; boundary="==BOUNDARY=="

--==BOUNDARY==
Content-Type: text/x-shellscript; charset="us-ascii"

#!/bin/bash
set -euo pipefail

# Redirect image pulls for public registries through ECR pull-through cache.
# Containerd reads per-registry host config from /etc/containerd/certs.d/.
# On AL2023 the EKS AMI already sets config_path to that directory, so
# creating a hosts.toml per registry is all that is needed.
#
# ECR registry URL is substituted by Terraform at plan time.
ECR="${ecr_registry_url}"

register_mirror() {
  local registry=$1 prefix=$2 server=$3
  mkdir -p "/etc/containerd/certs.d/$registry"
  printf 'server = "%s"\n\n[host."https://%s/%s"]\n  capabilities = ["pull", "resolve"]\n' \
    "$server" "$ECR" "$prefix" > "/etc/containerd/certs.d/$registry/hosts.toml"
}

register_mirror docker.io        dockerhub  https://registry-1.docker.io
register_mirror ghcr.io          ghcr       https://ghcr.io
register_mirror quay.io          quay       https://quay.io
register_mirror registry.k8s.io  k8s        https://registry.k8s.io
register_mirror public.ecr.aws   ecr-public https://public.ecr.aws

--==BOUNDARY==--
