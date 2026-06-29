# Flux AKS Setup

## Automated Workflow
```shell
export GITHUB_TOKEN=<PAT_WITH_REPO_SCOPE>
./install-flux-aks.sh

# <Register the webhook in GitHub using the URL printed by the script>

# Switch to another stack (releases the public IP)
./uninstall-flux-aks.sh

# Full teardown
../../aks/deprovision-aks.sh
```

## Installing Flux

Run `install-flux-aks.sh` with `GITHUB_TOKEN` exported — it creates the `gitops-tool-public-ip` static IP, bootstraps Flux onto the cluster (committing the `flux-system` manifests to this repo), writes the static IP into `flux/clusters/aks/flux-system/webhook-receiver-svc-patch.yaml` and commits it so Flux manages the LoadBalancer assignment durably, configures the webhook receiver, and prints the GitHub webhook registration details.

## Uninstalling Flux

Run `uninstall-flux-aks.sh` before switching to another stack. It runs `flux uninstall`, removes the `budget-tracker` namespace, and deletes the `gitops-tool-public-ip`, freeing the public IP slot for the next stack.

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
