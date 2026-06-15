# Jenkins stack — AKS setup guide

## Prerequisites

- AKS cluster provisioned and kubectl context set (`aks/provision-aks.sh` completed)
- Azure CLI authenticated (`az login`)

## Automated setup

```bash
./provision-jenkins-vm.sh
```

The script:
1. Creates a static public IP and an Azure VM (`Standard_B2s`, Ubuntu 22.04)
2. Installs Java 17, Jenkins (LTS), and kubectl on the VM
3. Caps JVM heap at 512m (`JAVA_OPTS=-Xmx512m -Xms256m`) — resource parity decision, see README
4. Installs the Configuration as Code and Job DSL plugins
5. Creates the `budget-tracker-deploy` pipeline job via JCasC (no manual UI steps)
6. Creates an AKS ServiceAccount `jenkins-deployer` with RBAC scoped to `budget-tracker` namespace
7. Stores the resulting kubeconfig as the `aks-kubeconfig` Jenkins credential
8. Generates an API token and prints GitHub Actions secret values

## GitHub Actions wiring

Add these secrets to the `budget-tracker` repository:

| Secret | Value |
|---|---|
| `JENKINS_URL` | `http://<vm-ip>:8080` (printed by script) |
| `JENKINS_API_TOKEN` | printed by script, also in `jenkins/jenkins-api-token.txt` |

Add this step to the budget-tracker CI workflow **after** the image tag commit step:

```yaml
- name: Trigger Jenkins deploy
  run: |
    curl -fsS -X POST \
      "${{ secrets.JENKINS_URL }}/job/budget-tracker-deploy/build" \
      --user "admin:${{ secrets.JENKINS_API_TOKEN }}"
```

## Cluster and VM lifecycle

Stop VM between sessions to save cost:
```bash
az vm stop  --resource-group gitops-lab-rg --name jenkins-vm
az vm start --resource-group gitops-lab-rg --name jenkins-vm
```

Stop AKS cluster:
```bash
az aks stop  --resource-group gitops-lab-rg --name gitops-lab-aks
az aks start --resource-group gitops-lab-rg --name gitops-lab-aks
```

Tear down VM only (keep AKS):
```bash
./deprovision-jenkins-vm.sh
```
