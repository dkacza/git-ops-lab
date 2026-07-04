#!/usr/bin/env bash
set -euo pipefail

echo "==> Uninstalling kube-prometheus-stack..."
helm uninstall monitoring --namespace monitoring

echo "==> Deleting monitoring namespace..."
kubectl delete namespace monitoring --ignore-not-found

echo ""
echo "==> Monitoring stack uninstalled."
