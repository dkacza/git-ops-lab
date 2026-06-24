#!/usr/bin/env bash
set -euo pipefail

# Step 1 of Jenkins stack setup.
# Creates the Azure VM and opens port 8080.
# Run this first, then run setup-jenkins.sh once the VM is up.

RESOURCE_GROUP="gitops-lab-rg"
LOCATION="polandcentral"
VM_NAME="jenkins-vm"
VM_SIZE="Standard_B2s"
VM_IMAGE="Ubuntu2204"
PUBLIC_IP_NAME="jenkins-vm-public-ip"
ADMIN_USERNAME="azureuser"
SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=10"

echo "==> Creating static public IP..."
az network public-ip create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$PUBLIC_IP_NAME" \
  --sku Standard \
  --allocation-method Static \
  --location "$LOCATION" \
  --output none

VM_PUBLIC_IP=$(az network public-ip show \
  --resource-group "$RESOURCE_GROUP" \
  --name "$PUBLIC_IP_NAME" \
  --query ipAddress -o tsv)
echo "    Public IP: $VM_PUBLIC_IP"

echo "==> Creating VM ($VM_SIZE)..."
az vm create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$VM_NAME" \
  --size "$VM_SIZE" \
  --image "$VM_IMAGE" \
  --admin-username "$ADMIN_USERNAME" \
  --generate-ssh-keys \
  --public-ip-address "$PUBLIC_IP_NAME" \
  --output none

echo "==> Opening port 8080..."
az vm open-port \
  --resource-group "$RESOURCE_GROUP" \
  --name "$VM_NAME" \
  --port 8080 \
  --output none

echo "==> Waiting for SSH to become available..."
DEADLINE=$(($(date +%s) + 60))
until ssh $SSH_OPTS "$ADMIN_USERNAME@$VM_PUBLIC_IP" 'exit' 2>/dev/null; do
  if [[ $(date +%s) -gt $DEADLINE ]]; then
    echo "[ERROR] SSH did not become available within 60s." >&2
    exit 1
  fi
  sleep 5
done

echo ""
echo "==> VM is ready."
echo "    SSH:  ssh $ADMIN_USERNAME@$VM_PUBLIC_IP"
echo "    Next: ./setup-jenkins.sh $VM_PUBLIC_IP"
