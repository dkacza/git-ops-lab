# Flux AKS Setup

## Automated Workflow
```shell
# 1. Bootstrap Flux (done once, commits flux-system manifests to the repo)
export GITHUB_TOKEN=<PAT_WITH_REPO_SCOPE>
flux bootstrap github \
  --owner=dkacza \
  --repository=git-ops-lab \
  --branch=main \
  --path=flux/clusters/aks \
  --personal

# 2. Pull the committed Flux manifests locally
git pull

# 3. Create static public IP, then run the install script
./install-flux-aks.sh <FLUX_WEBHOOK_STATIC_IP>

# <Register the webhook in GitHub using the URL printed by the script>

# Full teardown
../../argo-cd/aks/deprovision-aks.sh
```

## Static Public IP for Flux Webhook

Required so the GitHub webhook URL stays stable across cluster stop/start cycles.
Must be created in AKS's managed node resource group, not the main resource group.

```shell
NODE_RG=$(az aks show \
  --resource-group gitops-lab-rg \
  --name gitops-lab-aks \
  --query nodeResourceGroup -o tsv)

az network public-ip create \
  --resource-group $NODE_RG \
  --name flux-webhook-public-ip \
  --sku Standard \
  --allocation-method Static

az network public-ip show \
  --resource-group $NODE_RG \
  --name flux-webhook-public-ip \
  --query ipAddress -o tsv
```

## Registering the GitHub Webhook

The install script prints all required values at the end. Use them to register the webhook in GitHub:

1. Go to the `git-ops-lab` repository → **Settings → Webhooks → Add webhook**
2. Set **Payload URL** to the URL printed by the script (`http://<ip>/hook/<hash>`)
3. Set **Content type** to `application/json`
4. Set **Secret** to the value from `flux/flux-webhook-token.txt`
5. Under events, select **Just the push event**
6. Ensure **Active** is checked and save

## Stop / Start (between sessions)

```shell
az aks stop --resource-group gitops-lab-rg --name gitops-lab-aks
az aks start --resource-group gitops-lab-rg --name gitops-lab-aks
```

After starting, verify Flux is healthy:
```shell
flux get all
```
