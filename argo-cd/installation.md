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