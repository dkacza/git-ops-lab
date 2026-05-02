#!/usr/bin/env bash
set -euo pipefail

echo "==> This will permanently delete the resource group and all resources within it."
read -r -p "    Type 'yes' to confirm: " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
  echo "Aborted."
  exit 1
fi

echo "==> Deleting resource group gitops-lab-rg..."
az group delete --name gitops-lab-rg --yes --no-wait

echo "==> Teardown initiated (running in background)."
echo "    Monitor progress: az group show --name gitops-lab-rg --query properties.provisioningState -o tsv"
