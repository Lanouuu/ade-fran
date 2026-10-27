#!/bin/sh

set -euo pipefail

CLUSTER_NAME="iot"
CONF_DIR="$(cd "$(dirname "$0")/../confs" && pwd)"

k3d cluster create "$CLUSTER_NAME" -p "8888:80@loadbalancer"

kubectl wait --for=condition=Ready node --all --timeout=120s

# Crée les deux namespaces demandés :
# argocd (pour l’outil) et dev (pour l’application déployée).

kubectl create namespace argocd
kubectl create namespace dev

# install argocd
kubectl apply -n argocd --server-side --force-conflicts \
    -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=300s
kubectl rollout status statefulset/argocd-application-controller -n argocd --timeout=300s

# application
kubectl apply -f "$CONF_DIR/application.yaml"

# port forward
kubectl port-forward svc/argocd-server -n argocd 8080:443 &

# mdp
echo "Interface Argo CD : https://localhost:8080 (utilisateur : admin)"
echo "Mot de passe admin :"
kubectl -n argocd get secret argocd-initial-admin-secret \
    -o jsonpath="{.data.password}" | base64 -d
echo