#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "==> Checking cluster connectivity..."
kubectl cluster-info --request-timeout=5s > /dev/null

if [ -z "${GITHUB_TOKEN:-}" ]; then
  echo "[ERROR] GITHUB_TOKEN is not set. Export a PAT with repo scope before running this script." >&2
  exit 1
fi

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

echo "==> Bootstrapping Flux..."
flux bootstrap github \
  --owner=dkacza \
  --repository=git-ops-lab \
  --branch=main \
  --path=flux/clusters/aks \
  --personal

echo "==> Pulling Flux manifests committed by bootstrap..."
git -C "$REPO_ROOT" pull

echo "==> Waiting for Flux pods to be ready (timeout: 120s)..."
kubectl wait --for=condition=Ready pods --all -n flux-system --timeout=120s

echo "==> Exposing webhook-receiver via LoadBalancer (static IP: $STATIC_IP)..."
kubectl patch svc webhook-receiver -n flux-system \
  -p "{\"spec\": {\"type\": \"LoadBalancer\", \"loadBalancerIP\": \"$STATIC_IP\"}}"

echo "==> Waiting for external IP assignment..."
EXTERNAL_IP=""
while [ -z "$EXTERNAL_IP" ]; do
  EXTERNAL_IP=$(kubectl get svc webhook-receiver -n flux-system \
    -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
  [ -z "$EXTERNAL_IP" ] && sleep 5
done
echo "    External IP: $EXTERNAL_IP"

echo "==> Generating webhook token..."
TOKEN=$(openssl rand -hex 32)
echo "$TOKEN" > "$SCRIPT_DIR/../flux-webhook-token.txt"
echo "==> Webhook token saved to flux/flux-webhook-token.txt"

echo "==> Creating webhook-token secret in cluster..."
kubectl create secret generic webhook-token \
  -n flux-system \
  --from-literal=token="$TOKEN" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "==> Applying webhook Receiver..."
kubectl apply -f "$REPO_ROOT/flux/clusters/aks/webhook-receiver.yaml"

echo "==> Waiting for Receiver to be ready..."
kubectl wait --for=condition=Ready receiver/github-receiver -n flux-system --timeout=60s

WEBHOOK_PATH=$(kubectl get receiver github-receiver -n flux-system \
  -o jsonpath='{.status.webhookPath}')

echo ""
echo "==> Flux webhook receiver is ready"
echo "    Webhook URL:  http://$EXTERNAL_IP$WEBHOOK_PATH"
echo ""
echo "    Register the webhook in GitHub (git-ops-lab repository):"
echo "    Settings -> Webhooks -> Add webhook"
echo "    Payload URL:  http://$EXTERNAL_IP$WEBHOOK_PATH"
echo "    Content type: application/json"
echo "    Secret:       $TOKEN"
echo "    Events:       Just the push event"
