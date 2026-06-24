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

NIC_NAME="${VM_NAME}VMNic"

echo "==> Deleting VM $VM_NAME..."
az vm delete \
  --resource-group "$RESOURCE_GROUP" \
  --name "$VM_NAME" \
  --yes

echo "==> Deleting NIC $NIC_NAME (holds the public IP association)..."
az network nic delete \
  --resource-group "$RESOURCE_GROUP" \
  --name "$NIC_NAME"

echo "==> Deleting public IP $PUBLIC_IP_NAME..."
az network public-ip delete \
  --resource-group "$RESOURCE_GROUP" \
  --name "$PUBLIC_IP_NAME"

echo "==> Done."
