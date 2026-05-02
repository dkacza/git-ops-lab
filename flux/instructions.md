*Install CLI toolkit*
```shell

```

Install Flux to the cluster
```shell
export GITHUB_TOKEN=<CICD_PAT>
flux bootstrap github \
  --owner=dkacza \
  --repository=git-ops-lab \
  --branch=main \
  --path=flux/clusters/aks \
  --personal
```

