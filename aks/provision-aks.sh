#!/usr/bin/env bash
set -euo pipefail
K8S_VERSION="1.31"

echo "==> Logging in to Azure..."
az login
az account set --subscription 0ca6e150-1b48-4fed-84f7-345fb546ccc9

echo "==> Creating resource group..."
az group create --name gitops-lab-rg --location polandcentral

echo "==> Provisioning AKS cluster (~10 min, Kubernetes $K8S_VERSION)..."
az aks create \
  --resource-group gitops-lab-rg \
  --name gitops-lab-aks \
  --kubernetes-version "$K8S_VERSION" \
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

echo ""
echo "==> Cluster is ready"
echo ""
echo "    Next: run the tool-specific install script."
echo "    argo-cd/aks/install-argocd-aks.sh"
echo "    flux/aks/install-flux-aks.sh"
echo "    jenkins/vm/provision-vm.sh  (then setup-jenkins.sh)"
