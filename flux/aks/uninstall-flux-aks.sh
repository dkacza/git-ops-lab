#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

echo "==> Uninstalling Flux..."
flux uninstall --silent

echo "==> Removing budget-tracker namespace..."
kubectl delete namespace budget-tracker --ignore-not-found

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
echo "==> Flux uninstalled and public IP released."
