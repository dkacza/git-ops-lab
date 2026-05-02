# AKS Cluster Setup — Argo CD

## Automated Workflow
```shell
../../aks/provision-aks.sh
./install-argocd-aks.sh

<Register or reconfigure the webhook>

# Full teardown
../../aks/deprovision-aks.sh
```

### Stop / Start (between sessions)

```shell
# Deallocates VMs — no compute charge while stopped
az aks stop --resource-group gitops-lab-rg --name gitops-lab-aks

# Resume (~2 min)
az aks start --resource-group gitops-lab-rg --name gitops-lab-aks
```

---

## Installing Argo CD

Run `install-argocd-aks.sh` — it looks up the `gitops-tool-public-ip` created by `provision-aks.sh`, installs Argo CD, configures the webhook secret, and prints the GitHub webhook registration details.

## Registering the GitHub Webhook

The install script prints all required values at the end. Use them to register the webhook in GitHub:

1. Go to the `git-ops-lab` repository → **Settings → Webhooks → Add webhook**
2. Set **Payload URL** to `https://<static-ip>/api/webhook`
3. Set **Content type** to `application/json`
4. Set **Secret** to the value from `argo-cd/argo-cd-webhook-secret.txt`
5. Under events, select **Just the push event**
6. Ensure **Active** is checked and save
