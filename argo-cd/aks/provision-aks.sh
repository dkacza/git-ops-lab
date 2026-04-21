#!/usr/bin/env bash
set -euo pipefail

echo "==> Logging in to Azure..."
az login
az account set --subscription 0ca6e150-1b48-4fed-84f7-345fb546ccc9

echo "==> Creating resource group..."
az group create --name gitops-lab-rg --location polandcentral

echo "==> Provisioning AKS cluster (~10 min)..."
az aks create \
  --resource-group gitops-lab-rg \
  --name gitops-lab-aks \
  --node-count 1 \
  --node-vm-size standard_b2as_v2 \
  --generate-ssh-keys

echo "==> Waiting for cluster to reach Running state..."
az aks wait \
  --resource-group gitops-lab-rg \
  --name gitops-lab-aks \
  --created \
  --interval 15 \
  --timeout 600

echo "==> Fetching cluster credentials..."
az aks get-credentials --resource-group gitops-lab-rg --name gitops-lab-aks

echo "==> Creating static public IP for Argo CD..."
NODE_RG=$(az aks show \
  --resource-group gitops-lab-rg \
  --name gitops-lab-aks \
  --query nodeResourceGroup -o tsv)

az network public-ip create \
  --resource-group "$NODE_RG" \
  --name argocd-public-ip \
  --sku Standard \
  --allocation-method Static

STATIC_IP=$(az network public-ip show \
  --resource-group "$NODE_RG" \
  --name argocd-public-ip \
  --query ipAddress -o tsv)

echo ""
echo "==> Cluster is ready"
echo "    Static IP:  $STATIC_IP"
echo ""
echo "    Next step — install Argo CD:"
echo "    ./install-argocd-aks.sh $STATIC_IP"
