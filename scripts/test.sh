#!/bin/sh

set -euo pipefail

#################### CLUSTER K3D
echo
echo "=== CLUSTER K3D ==="
echo

# verif cluster
echo "=== CLUSTER ==="
k3d cluster list
kubectl get nodes -o wide

# verif namespaces
echo "===NAMESPACES==="
kubectl get namespaces

# verif pods
echo "===PODS==="
kubectl get pods -n argocd
kubectl get pods -n dev

# verif deployment
echo "===DEPLOYMENT==="
kubectl get deployment -n dev

# verif service
echo "===SERVICE==="
kubectl get service -n dev

# verif ingress
echo "===INGRESS==="
kubectl get ingress -n dev


################## ARGO CD
echo
echo "=== ARGOCD ==="
echo

# verif pods argocd
echo "===PODS==="
kubectl get nodes -n argocd

# verif application
echo "===APPLICATION==="
kubectl get application -n argocd
kubectl describe application playground -n argocd


################## RESULT
echo
echo "=== RESULT ==="
echo

curl http://localhost:8888/