#!/bin/sh

set -euo pipefail

apt-get update
apt-get install -y curl ca-certificates git

# Docker
apt-get install -y docker.io

systemctl enable --now docker
usermod -aG docker "${SUDO_USER:-$USER}"

# Kubectl
KUBECTL_VERSION="v1.35.5"
curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"

curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl.sha256"
echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check

install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

rm -f kubectl kubectl.sha256

# K3d
curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash

# Check
curl --version | grep curl
git --version
docker --version
kubectl version --client
k3d --version