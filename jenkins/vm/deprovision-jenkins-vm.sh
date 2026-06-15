#!/usr/bin/env bash
set -euo pipefail

RESOURCE_GROUP="gitops-lab-rg"
VM_NAME="jenkins-vm"
PUBLIC_IP_NAME="jenkins-vm-public-ip"

read -rp "This will delete $VM_NAME and its public IP from $RESOURCE_GROUP. Type 'yes' to confirm: " CONFIRM
if [[ "$CONFIRM" != "yes" ]]; then
  echo "Aborted."
  exit 0
fi

echo "==> Deleting VM $VM_NAME..."
az vm delete \
  --resource-group "$RESOURCE_GROUP" \
  --name "$VM_NAME" \
  --yes \
  --no-wait

echo "==> Deleting public IP $PUBLIC_IP_NAME..."
az network public-ip delete \
  --resource-group "$RESOURCE_GROUP" \
  --name "$PUBLIC_IP_NAME" \
  --no-wait

echo "==> Deletion triggered (running in background)."
echo "    Monitor progress: az vm show --resource-group $RESOURCE_GROUP --name $VM_NAME"
