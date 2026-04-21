# AKS Cluster Setup

## Automated Workflow
```shell
./provision.aks.sh
./install-argcd-aks.sh <ARGO_CD_STATIC_IP>

# Full teardown
./deprovision-aks.sh
```


## Manual Steps
### AKS provisioning
```shell
az login
az account set --subscription 0ca6e150-1b48-4fed-84f7-345fb546ccc9

az group create --name gitops-lab-rg --location westeurope

az aks create \
  --resource-group gitops-lab-rg \
  --name gitops-lab-aks \
  --node-count 1 \
  --node-vm-size standard_b2as_v2 \
  --generate-ssh-keys

az aks get-credentials --resource-group gitops-lab-rg --name gitops-lab-aks
```

### Stop / Start (between sessions)

```shell
# Deallocates VMs — no compute charge while stopped
az aks stop --resource-group gitops-lab-rg --name gitops-lab-aks

# Resume (~2 min)
az aks start --resource-group gitops-lab-rg --name gitops-lab-aks
```

### Teardown

```shell
# Deletes cluster, nodes, load balancers, public IPs — everything
az group delete --name gitops-lab-rg --yes --no-wait
```

---

## Static Public IP for Argo CD

Required so the GitHub webhook URL stays stable across cluster stop/start cycles.
Must be created in AKS's managed node resource group, not the main resource group.

```shell
NODE_RG=$(az aks show \
  --resource-group gitops-lab-rg \
  --name gitops-lab-aks \
  --query nodeResourceGroup -o tsv)

az network public-ip create \
  --resource-group $NODE_RG \
  --name argocd-public-ip \
  --sku Standard \
  --allocation-method Static

az network public-ip show \
  --resource-group $NODE_RG \
  --name argocd-public-ip \
  --query ipAddress -o tsv
```

## Installing Argo CD
For installing Argo CD use the `install-argocd-aks.sh` script. It uses the same commands as the `install-argo-local.sh` as it is based on the kubectl interface which is set to azure.

The only difference is that the static IP needs to be provided as a parameter.

