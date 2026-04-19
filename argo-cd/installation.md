Create ArgoCD namespace:
```shell
kubectl create namespace argocd
```


Instalation of ArgoCD:
```shell
kubectl apply -n argocd --server-side --force-conflicts -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

Port forward (no LB):
```shell
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

Retrieve the credentials:
User: admin
Password: `argocd admin initial-password -n argocd`

Install CLI toolkit:
```shell
brew install argocd
```

Login via CLI:
```shell
argocd login localhost:8080 --username admin --password <password> --insecure
```

---

## Connecting the CD pipeline

### 1. Apply the Application manifest

The Application CRD tells Argo CD what to watch and where to deploy.

```shell
kubectl apply -f argo-cd/application.yaml
```

Key fields in `application.yaml`:
- `source.repoURL` — the git-ops-lab config repo
- `source.path` — Argo CD watches only `argo-cd/manifests/`
- `destination.namespace` — deploys into `budget-tracker`
- `syncPolicy.automated.selfHeal: true` — reverts any manual cluster changes
- `syncPolicy.automated.prune: true` — removes resources deleted from Git
- `syncOptions: CreateNamespace=true` — creates `budget-tracker` namespace if missing

### 2. Verify the Application is synced

```shell
kubectl get application budget-tracker -n argocd
```

Expected output:
```
NAME             SYNC STATUS   HEALTH STATUS
budget-tracker   Synced        Healthy
```

### 3. Check deployed pods

```shell
kubectl get pods -n budget-tracker
```

Both `backend` and `frontend` pods should reach `Running` status and pass readiness probes.

---
## Continuous Integration
On commit to main branch GitHub Actions pipeline is triggered. It consists of the following steps:
1. Build images and push them to the GHCR
2. Update the image tag in this repository through Access Token.

Argo CD should pick up the changes automatically.