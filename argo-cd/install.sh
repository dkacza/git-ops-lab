#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Checking cluster connectivity..."
kubectl cluster-info --request-timeout=5s > /dev/null

echo "==> Creating argocd namespace..."
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

echo "==> Installing Argo CD..."
kubectl apply -n argocd --server-side --force-conflicts \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo "==> Waiting for Argo CD pods to be ready (timeout: 120s)..."
kubectl wait --for=condition=Ready pods --all -n argocd --timeout=120s

echo "==> Applying Application CRD..."
kubectl apply -f "$SCRIPT_DIR/application.yaml"

ARGOCD_PASSWORD=$(argocd admin initial-password -n argocd | head -1)
echo "$ARGOCD_PASSWORD" > "$SCRIPT_DIR/argo-cd-admin-password.txt"
echo "==> Password saved to $SCRIPT_DIR/argo-cd-admin-password.txt"

echo "==> Starting port-forward in background (localhost:8080 -> argocd-server:443)..."
kubectl port-forward svc/argocd-server -n argocd 8080:443 >/dev/null 2>&1 &
PORT_FORWARD_PID=$!
sleep 1

echo "==> Logging in to Argo CD CLI..."
argocd login localhost:8080 --username admin --password "$ARGOCD_PASSWORD" --insecure

echo ""
echo "==> Argo CD is ready"
echo "    UI:                https://localhost:8080"
echo "    Port-forward PID:  $PORT_FORWARD_PID"
