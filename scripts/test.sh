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
echo

# verif namespaces
echo "===NAMESPACES==="
kubectl get namespaces
echo

# verif pods
echo "===PODS==="
kubectl get pods -n dev
echo

# verif deployment
echo "===DEPLOYMENT==="
kubectl get deployment -n dev
echo

# verif service
echo "===SERVICE==="
kubectl get service -n dev
echo

# verif ingress
echo "===INGRESS==="
kubectl get ingress -n dev
echo


################## ARGO CD
echo
echo "=== ARGOCD ==="
echo

# verif pods argocd
echo "===PODS==="
kubectl get pods -n argocd
echo

# verif application
echo "===APPLICATION==="
kubectl get application -n argocd
echo


################## RESULT
echo
echo "=== RESULT ==="
echo

# Pour accelerer le rafraichissement par agrocd :

#kubectl annotate application playground -n argocd \
#  argocd.argoproj.io/refresh=hard --overwrite

curl http://localhost:8888/
echo