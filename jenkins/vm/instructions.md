# Jenkins stack — AKS setup guide

## Prerequisites

- AKS cluster provisioned and kubectl context set (`aks/provision-aks.sh` completed)
- Azure CLI authenticated (`az login`)

## Step 1 — provision the VM (~3 min)

```bash
./provision-vm.sh
```

Prints the VM public IP at the end.

## Step 2 — install Jenkins and create AKS credentials (~10 min)

```bash
./setup-jenkins.sh <vm-public-ip>
```

This script:
- Installs Java 21, Jenkins LTS, and kubectl on the VM
- Sets the Jenkins root URL (required for SECURITY-3674 fix)
- Creates the `jenkins-deployer` ServiceAccount + RBAC in AKS
- Saves the kubeconfig to `jenkins/aks-kubeconfig`
- Prints the Jenkins URL and initial admin password

## Step 3 — manual Jenkins configuration (~5 min)

Open `http://<vm-ip>:8080` in a browser.

**3a. Unlock Jenkins**
- Enter the initial admin password printed by `setup-jenkins.sh`
- Click "Install suggested plugins", wait for it to finish
- Create the admin user (username: `admin`, choose a password)
- Save the password to `jenkins/jenkins-admin-password.txt`

**3b. Add the AKS kubeconfig credential**
- Go to **Manage Jenkins → Credentials → System → Global credentials → Add Credentials**
- Kind: `Secret file`
- ID: `aks-kubeconfig`
- File: upload `jenkins/aks-kubeconfig`
- Click Save

**3c. Create the deploy pipeline**
- Go to **New Item**, name it `budget-tracker-deploy`, type: `Pipeline`
- Paste the following into the Pipeline script box:

```groovy
pipeline {
  agent any
  stages {
    stage('Deploy') {
      steps {
        withCredentials([file(credentialsId: 'aks-kubeconfig', variable: 'KUBECONFIG')]) {
          sh 'rm -rf /tmp/git-ops-lab && git clone https://github.com/dkacza/git-ops-lab /tmp/git-ops-lab'
          sh 'kubectl apply -f /tmp/git-ops-lab/jenkins/manifests/'
        }
      }
    }
    stage('Wait for rollout') {
      steps {
        withCredentials([file(credentialsId: 'aks-kubeconfig', variable: 'KUBECONFIG')]) {
          sh 'kubectl rollout status deployment/backend -n budget-tracker --timeout=180s'
          sh 'kubectl rollout status deployment/frontend -n budget-tracker --timeout=180s'
        }
      }
    }
  }
}
```

**3d. Generate an API token**
- Go to **Account → Security → API Token → Add new Token**
- Name it `github-actions`, click Generate
- Save the token to `jenkins/jenkins-api-token.txt`

## Step 4 — wire GitHub Actions

Add these secrets to the `budget-tracker` repository:

| Secret | Value |
|---|---|
| `JENKINS_URL` | `http://<vm-ip>:8080` |
| `JENKINS_API_TOKEN` | token from step 3e |

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
