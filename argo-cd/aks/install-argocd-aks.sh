#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Checking cluster connectivity..."
kubectl cluster-info --request-timeout=5s > /dev/null

echo "==> Resolving node resource group..."
NODE_RG=$(az aks show \
  --resource-group gitops-lab-rg \
  --name gitops-lab-aks \
  --query nodeResourceGroup -o tsv)

STATIC_IP=$(az network public-ip show \
  --resource-group "$NODE_RG" \
  --name gitops-tool-public-ip \
  --query ipAddress -o tsv)
echo "    Static IP: $STATIC_IP"

echo "==> Creating argocd namespace..."
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

echo "==> Installing Argo CD..."
kubectl apply -n argocd --server-side --force-conflicts \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo "==> Waiting for Argo CD pods to be ready (timeout: 120s)..."
kubectl wait --for=condition=Ready pods --all -n argocd --timeout=120s

echo "==> Exposing argocd-server via LoadBalancer (static IP: $STATIC_IP)..."
kubectl patch svc argocd-server -n argocd \
  -p "{\"spec\": {\"type\": \"LoadBalancer\", \"loadBalancerIP\": \"$STATIC_IP\"}}"

echo "==> Waiting for external IP assignment..."
EXTERNAL_IP=""
while [ -z "$EXTERNAL_IP" ]; do
  EXTERNAL_IP=$(kubectl get svc argocd-server -n argocd \
    -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
  [ -z "$EXTERNAL_IP" ] && sleep 5
done
echo "    External IP: $EXTERNAL_IP"

echo "==> Generating webhook secret..."
SECRET=$(openssl rand -hex 32)
echo "$SECRET" > "$SCRIPT_DIR/../argo-cd-webhook-secret.txt"
echo "==> Webhook secret saved to $SCRIPT_DIR/../argo-cd-webhook-secret.txt"
kubectl patch secret argocd-secret -n argocd \
  --type merge \
  -p "{\"stringData\": {\"webhook.github.secret\": \"$SECRET\"}}"

echo "==> Applying Application CRD..."
kubectl apply -f "$SCRIPT_DIR/../application.yaml"

ARGOCD_PASSWORD=$(argocd admin initial-password -n argocd | head -1)
echo "$ARGOCD_PASSWORD" > "$SCRIPT_DIR/../argo-cd-admin-password.txt"
echo "==> Password saved to $SCRIPT_DIR/../argo-cd-admin-password.txt"

echo "==> Logging in to Argo CD CLI..."
argocd login "$EXTERNAL_IP" --username admin --password "$ARGOCD_PASSWORD" --insecure

echo ""
echo "==> Argo CD is ready"
echo "    UI:           https://$EXTERNAL_IP"
echo "    Webhook URL:  https://$EXTERNAL_IP/api/webhook"
echo ""
echo "    Register the webhook in GitHub:"
echo "    Settings -> Webhooks -> Add webhook"
echo "    Payload URL:  https://$EXTERNAL_IP/api/webhook"
echo "    Content type: application/json"
echo "    Secret:       $(cat "$SCRIPT_DIR/../argo-cd-webhook-secret.txt")"
