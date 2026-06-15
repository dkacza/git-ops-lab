#!/usr/bin/env bash
set -euo pipefail

# Provisions an Azure VM for Jenkins (push-based CD stack).
# Prerequisites:
#   - AKS cluster must already be running (provision-aks.sh completed)
#   - kubectl context must point at gitops-lab-aks
#   - az CLI authenticated
#
# Resource parity decision: Standard_B2s (2 vCPU, 4 GiB) matches the CPU count
# of the AKS node (Standard_B2as_v2). JVM heap is capped at 512m via JAVA_OPTS
# so Jenkins memory consumption is bounded and comparable to Argo CD / Flux pod
# metrics. See README for full rationale.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

RESOURCE_GROUP="gitops-lab-rg"
LOCATION="polandcentral"
VM_NAME="jenkins-vm"
VM_SIZE="Standard_B2s"
VM_IMAGE="Ubuntu2204"
PUBLIC_IP_NAME="jenkins-vm-public-ip"
JENKINS_PORT=8080
ADMIN_USERNAME="azureuser"
JENKINS_ADMIN_USER="admin"

echo "==> Checking cluster connectivity..."
kubectl cluster-info --request-timeout=5s > /dev/null

echo "==> Creating static public IP for Jenkins VM..."
az network public-ip create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$PUBLIC_IP_NAME" \
  --sku Standard \
  --allocation-method Static \
  --location "$LOCATION" \
  --output none

VM_PUBLIC_IP=$(az network public-ip show \
  --resource-group "$RESOURCE_GROUP" \
  --name "$PUBLIC_IP_NAME" \
  --query ipAddress -o tsv)
echo "    Public IP: $VM_PUBLIC_IP"

echo "==> Creating Jenkins VM ($VM_SIZE)..."
az vm create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$VM_NAME" \
  --size "$VM_SIZE" \
  --image "$VM_IMAGE" \
  --admin-username "$ADMIN_USERNAME" \
  --generate-ssh-keys \
  --public-ip-address "$PUBLIC_IP_NAME" \
  --output none

echo "==> Opening port $JENKINS_PORT..."
az vm open-port \
  --resource-group "$RESOURCE_GROUP" \
  --name "$VM_NAME" \
  --port "$JENKINS_PORT" \
  --output none

echo "==> Installing Java, Jenkins, and kubectl on VM..."
az vm run-command invoke \
  --resource-group "$RESOURCE_GROUP" \
  --name "$VM_NAME" \
  --command-id RunShellScript \
  --scripts '
    set -euo pipefail

    # Java 17
    apt-get update -q
    apt-get install -y -q fontconfig openjdk-17-jre

    # Jenkins
    wget -qO /usr/share/keyrings/jenkins-keyring.asc \
      https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key
    echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] \
      https://pkg.jenkins.io/debian-stable binary/" \
      > /etc/apt/sources.list.d/jenkins.list
    apt-get update -q
    apt-get install -y -q jenkins

    # Cap JVM heap — resource parity with Argo CD / Flux pod footprint
    echo "JAVA_OPTS=-Xmx512m -Xms256m" >> /etc/default/jenkins

    # kubectl
    curl -sLO "https://dl.k8s.io/release/$(curl -sL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
    rm kubectl

    systemctl enable jenkins
    systemctl start jenkins
  ' \
  --output none

echo "==> Waiting for Jenkins to start (polling http://$VM_PUBLIC_IP:$JENKINS_PORT/login)..."
DEADLINE=$(($(date +%s) + 120))
until curl -sf "http://$VM_PUBLIC_IP:$JENKINS_PORT/login" > /dev/null 2>&1; do
  if [[ $(date +%s) -gt $DEADLINE ]]; then
    echo "[ERROR] Jenkins did not become reachable within 120s." >&2
    exit 1
  fi
  sleep 5
done
echo "    Jenkins is up."

echo "==> Retrieving initial admin password..."
INITIAL_PASSWORD=$(az vm run-command invoke \
  --resource-group "$RESOURCE_GROUP" \
  --name "$VM_NAME" \
  --command-id RunShellScript \
  --scripts 'cat /var/lib/jenkins/secrets/initialAdminPassword' \
  --query 'value[0].message' -o tsv | grep -v "^$" | tail -1)

echo "==> Downloading Jenkins CLI..."
wget -q "http://$VM_PUBLIC_IP:$JENKINS_PORT/jnlpJars/jenkins-cli.jar" -O /tmp/jenkins-cli.jar

echo "==> Generating admin password..."
ADMIN_PASSWORD=$(openssl rand -hex 16)
echo "$ADMIN_PASSWORD" > "$SCRIPT_DIR/../jenkins-admin-password.txt"
echo "==> Admin password saved to jenkins/jenkins-admin-password.txt"

echo "==> Applying JCasC configuration..."
CASC_YAML=$(cat <<CASC
jenkins:
  securityRealm:
    local:
      allowsSignup: false
      users:
        - id: "$JENKINS_ADMIN_USER"
          password: "$ADMIN_PASSWORD"
  authorizationStrategy:
    loggedInUsersCanDoAnything:
      allowAnonymousRead: false
jobs:
  - script: |
      pipelineJob('budget-tracker-deploy') {
        definition {
          cps {
            script('''
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
            ''')
            sandbox(true)
          }
        }
      }
CASC
)

az vm run-command invoke \
  --resource-group "$RESOURCE_GROUP" \
  --name "$VM_NAME" \
  --command-id RunShellScript \
  --scripts "
    mkdir -p /var/lib/jenkins/casc_configs
    cat > /var/lib/jenkins/casc_configs/casc.yaml << 'HEREDOC'
$CASC_YAML
HEREDOC
    # Install Configuration as Code and Job DSL plugins, then reload
    java -jar /var/cache/jenkins/war/WEB-INF/lib/jenkins-cli.jar \
      -s http://localhost:8080 \
      -auth admin:$INITIAL_PASSWORD \
      install-plugin configuration-as-code job-dsl -restart || true
  " \
  --output none

echo "==> Waiting for Jenkins to restart after plugin install..."
sleep 30
DEADLINE=$(($(date +%s) + 120))
until curl -sf "http://$VM_PUBLIC_IP:$JENKINS_PORT/login" > /dev/null 2>&1; do
  if [[ $(date +%s) -gt $DEADLINE ]]; then
    echo "[ERROR] Jenkins did not recover after plugin install within 120s." >&2
    exit 1
  fi
  sleep 5
done

echo "==> Applying JCasC and reloading..."
az vm run-command invoke \
  --resource-group "$RESOURCE_GROUP" \
  --name "$VM_NAME" \
  --command-id RunShellScript \
  --scripts "
    echo 'CASC_JENKINS_CONFIG=/var/lib/jenkins/casc_configs' >> /etc/default/jenkins
    systemctl restart jenkins
    sleep 20
    java -jar /var/cache/jenkins/war/WEB-INF/lib/jenkins-cli.jar \
      -s http://localhost:8080 \
      -auth $JENKINS_ADMIN_USER:$ADMIN_PASSWORD \
      reload-jcasc-configuration
  " \
  --output none

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

echo "==> Building kubeconfig for Jenkins..."
KUBECONFIG_CONTENT=$(cat <<EOF
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
)

echo "==> Storing kubeconfig as Jenkins credential..."
KUBECONFIG_TMP=$(mktemp)
echo "$KUBECONFIG_CONTENT" > "$KUBECONFIG_TMP"

az vm run-command invoke \
  --resource-group "$RESOURCE_GROUP" \
  --name "$VM_NAME" \
  --command-id RunShellScript \
  --scripts "
    cat > /tmp/aks-kubeconfig << 'KCEOF'
$KUBECONFIG_CONTENT
KCEOF
    java -jar /var/cache/jenkins/war/WEB-INF/lib/jenkins-cli.jar \
      -s http://localhost:8080 \
      -auth $JENKINS_ADMIN_USER:$ADMIN_PASSWORD \
      create-credentials-by-xml system::system::jenkins _ << 'CREDEOF'
<org.jenkinsci.plugins.plaincredentials.impl.FileCredentialsImpl>
  <scope>GLOBAL</scope>
  <id>aks-kubeconfig</id>
  <description>AKS kubeconfig for jenkins-deployer service account</description>
  <fileName>kubeconfig</fileName>
  <secretBytes>\$(base64 /tmp/aks-kubeconfig)</secretBytes>
</org.jenkinsci.plugins.plaincredentials.impl.FileCredentialsImpl>
CREDEOF
    rm /tmp/aks-kubeconfig
  " \
  --output none

rm -f "$KUBECONFIG_TMP"

echo "==> Generating Jenkins API token..."
API_TOKEN=$(az vm run-command invoke \
  --resource-group "$RESOURCE_GROUP" \
  --name "$VM_NAME" \
  --command-id RunShellScript \
  --scripts "
    curl -s -X POST http://localhost:8080/user/$JENKINS_ADMIN_USER/descriptorByName/jenkins.security.ApiTokenProperty/generateNewToken \
      --user $JENKINS_ADMIN_USER:$ADMIN_PASSWORD \
      --data 'newTokenName=github-actions' \
      | python3 -c \"import sys,json; print(json.load(sys.stdin)['data']['tokenValue'])\"
  " \
  --query 'value[0].message' -o tsv | grep -v "^$" | tail -1)

echo "$API_TOKEN" > "$SCRIPT_DIR/../jenkins-api-token.txt"
echo "==> API token saved to jenkins/jenkins-api-token.txt"

echo ""
echo "==> Jenkins is ready"
echo "    UI:             http://$VM_PUBLIC_IP:$JENKINS_PORT"
echo "    Admin user:     $JENKINS_ADMIN_USER"
echo "    Admin password: $ADMIN_PASSWORD  (also in jenkins/jenkins-admin-password.txt)"
echo ""
echo "    Add these secrets to the budget-tracker GitHub repository:"
echo "    JENKINS_URL:        http://$VM_PUBLIC_IP:$JENKINS_PORT"
echo "    JENKINS_API_TOKEN:  $API_TOKEN  (also in jenkins/jenkins-api-token.txt)"
echo ""
echo "    Add this step to the budget-tracker CI workflow after the image tag commit:"
echo "    - name: Trigger Jenkins deploy"
echo "      run: |"
echo "        curl -fsS -X POST \\"
echo "          \"\${{ secrets.JENKINS_URL }}/job/budget-tracker-deploy/build\" \\"
echo "          --user \"admin:\${{ secrets.JENKINS_API_TOKEN }}\""
