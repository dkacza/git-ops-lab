#!/usr/bin/env bash
set -euo pipefail

echo "==> Removing Argo CD Application and namespace..."
kubectl delete -f "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../application.yaml" --ignore-not-found
kubectl delete namespace argocd --ignore-not-found

echo "==> Resolving node resource group..."
NODE_RG=$(az aks show \
  --resource-group gitops-lab-rg \
  --name gitops-lab-aks \
  --query nodeResourceGroup -o tsv)

echo "==> Deleting static public IP..."
az network public-ip delete \
  --resource-group "$NODE_RG" \
  --name gitops-tool-public-ip

echo ""
echo "==> Argo CD uninstalled and public IP released."
