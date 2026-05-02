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

echo "==> Resolving node resource group..."
NODE_RG=$(az aks show \
  --resource-group gitops-lab-rg \
  --name gitops-lab-aks \
  --query nodeResourceGroup -o tsv)

echo "==> Creating static public IPs..."
az network public-ip create \
  --resource-group "$NODE_RG" \
  --name argocd-public-ip \
  --sku Standard \
  --allocation-method Static

az network public-ip create \
  --resource-group "$NODE_RG" \
  --name flux-webhook-public-ip \
  --sku Standard \
  --allocation-method Static

ARGOCD_IP=$(az network public-ip show \
  --resource-group "$NODE_RG" \
  --name argocd-public-ip \
  --query ipAddress -o tsv)

FLUX_IP=$(az network public-ip show \
  --resource-group "$NODE_RG" \
  --name flux-webhook-public-ip \
  --query ipAddress -o tsv)

echo ""
echo "==> Cluster is ready"
echo "    Argo CD static IP:       $ARGOCD_IP"
echo "    Flux webhook static IP:  $FLUX_IP"
echo ""
echo "    Next steps:"
echo "    argo-cd/aks/install-argocd-aks.sh $ARGOCD_IP"
echo "    flux/aks/install-flux-aks.sh $FLUX_IP"
