#!/usr/bin/env bash
set -euo pipefail

# Step 2 of Jenkins stack setup.
# Installs Jenkins on the VM and sets up AKS credentials.
# Prerequisites:
#   - VM provisioned via provision-vm.sh
#   - kubectl context points at gitops-lab-aks
#   - az CLI authenticated

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <vm-public-ip>" >&2
  exit 1
fi

VM_PUBLIC_IP="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ADMIN_USERNAME="azureuser"
JENKINS_PORT=8080
SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=10"

echo "==> Checking cluster connectivity..."
kubectl cluster-info --request-timeout=5s > /dev/null

# --- Install Java + Jenkins + kubectl on VM ---

echo "==> Copying install script to VM..."
scp $SSH_OPTS "$SCRIPT_DIR/install-jenkins.sh" "$ADMIN_USERNAME@$VM_PUBLIC_IP:/tmp/install-jenkins.sh"

echo "==> Running install script on VM..."
ssh $SSH_OPTS "$ADMIN_USERNAME@$VM_PUBLIC_IP" 'bash /tmp/install-jenkins.sh'

echo "==> Setting Jenkins root URL via init Groovy script..."
ssh $SSH_OPTS "$ADMIN_USERNAME@$VM_PUBLIC_IP" "
  sudo mkdir -p /var/lib/jenkins/init.groovy.d
  echo \"import jenkins.model.*; JenkinsLocationConfiguration.get().tap { url = 'http://$VM_PUBLIC_IP:$JENKINS_PORT'; save() }\" \
    | sudo tee /var/lib/jenkins/init.groovy.d/set-url.groovy > /dev/null
  sudo chown -R jenkins:jenkins /var/lib/jenkins/init.groovy.d
  sudo systemctl restart jenkins
"

echo "==> Waiting for Jenkins to become reachable..."
DEADLINE=$(($(date +%s) + 300))
until curl -sf "http://$VM_PUBLIC_IP:$JENKINS_PORT/login" > /dev/null 2>&1; do
  if [[ $(date +%s) -gt $DEADLINE ]]; then
    echo "[ERROR] Jenkins did not become reachable within 300s." >&2
    exit 1
  fi
  echo "    Still waiting..."
  sleep 10
done
echo "    Jenkins is up."

# --- AKS ServiceAccount + RBAC ---

echo "==> Creating AKS ServiceAccount for Jenkins..."
kubectl create namespace budget-tracker --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: jenkins-deployer
  namespace: budget-tracker
---
apiVersion: v1
kind: Secret
metadata:
  name: jenkins-deployer-token
  namespace: budget-tracker
  annotations:
    kubernetes.io/service-account.name: jenkins-deployer
type: kubernetes.io/service-account-token
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: jenkins-deployer
  namespace: budget-tracker
rules:
  - apiGroups: ["apps"]
    resources: ["deployments", "replicasets"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
  - apiGroups: [""]
    resources: ["services", "pods", "namespaces"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: jenkins-deployer
  namespace: budget-tracker
subjects:
  - kind: ServiceAccount
    name: jenkins-deployer
    namespace: budget-tracker
roleRef:
  kind: Role
  name: jenkins-deployer
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: jenkins-namespace-creator
rules:
  - apiGroups: [""]
    resources: ["namespaces"]
    verbs: ["get", "create"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: jenkins-namespace-creator
subjects:
  - kind: ServiceAccount
    name: jenkins-deployer
    namespace: budget-tracker
roleRef:
  kind: ClusterRole
  name: jenkins-namespace-creator
  apiGroup: rbac.authorization.k8s.io
EOF

echo "==> Waiting for service account token to be populated..."
sleep 5
SA_TOKEN=$(kubectl get secret jenkins-deployer-token -n budget-tracker \
  -o jsonpath='{.data.token}' | base64 --decode)
CA_CERT=$(kubectl get secret jenkins-deployer-token -n budget-tracker \
  -o jsonpath='{.data.ca\.crt}')
CLUSTER_SERVER=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')

echo "==> Saving kubeconfig to jenkins/aks-kubeconfig..."
cat > "$SCRIPT_DIR/../aks-kubeconfig" <<EOF
apiVersion: v1
kind: Config
clusters:
  - name: gitops-lab-aks
    cluster:
      server: $CLUSTER_SERVER
      certificate-authority-data: $CA_CERT
contexts:
  - name: jenkins-deployer
    context:
      cluster: gitops-lab-aks
      user: jenkins-deployer
current-context: jenkins-deployer
users:
  - name: jenkins-deployer
    user:
      token: $SA_TOKEN
EOF

INITIAL_PASSWORD=$(ssh $SSH_OPTS "$ADMIN_USERNAME@$VM_PUBLIC_IP" \
  'sudo cat /var/lib/jenkins/secrets/initialAdminPassword')

echo ""
echo "==> Automated setup complete. Manual steps follow."
echo ""
echo "    Jenkins UI:       http://$VM_PUBLIC_IP:$JENKINS_PORT"
echo "    Initial password: $INITIAL_PASSWORD"
echo ""
echo "    See jenkins/vm/instructions.md for the manual configuration steps."
