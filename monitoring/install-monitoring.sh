#!/usr/bin/env bash
set -euo pipefail

echo "==> Checking cluster connectivity..."
kubectl cluster-info --request-timeout=5s > /dev/null

echo "==> Adding prometheus-community Helm repo..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update prometheus-community

echo "==> Creating monitoring namespace..."
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

echo "==> Installing kube-prometheus-stack..."
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --set prometheus.prometheusSpec.scrapeInterval=15s \
  --set prometheus.prometheusSpec.resources.requests.cpu=50m \
  --set prometheus.prometheusSpec.resources.requests.memory=256Mi \
  --set prometheus.prometheusSpec.resources.limits.cpu=300m \
  --set prometheus.prometheusSpec.resources.limits.memory=512Mi \
  --set grafana.resources.requests.cpu=25m \
  --set grafana.resources.requests.memory=128Mi \
  --set grafana.resources.limits.cpu=100m \
  --set grafana.resources.limits.memory=256Mi \
  --wait --timeout=300s

echo "==> Waiting for monitoring pods to be ready..."
kubectl wait --for=condition=Ready pods --all -n monitoring --timeout=300s

GRAFANA_PASSWORD=$(kubectl get secret --namespace monitoring monitoring-grafana \
  -o jsonpath="{.data.admin-password}" | base64 --decode)
echo "$GRAFANA_PASSWORD" > "$(dirname "${BASH_SOURCE[0]}")/grafana-admin-password.txt"

echo ""
echo "==> Monitoring stack is ready"
echo "    Grafana password saved to monitoring/grafana-admin-password.txt"
echo ""
echo "    To access Grafana locally:"
echo "    kubectl port-forward -n monitoring svc/monitoring-grafana 3000:80"
echo "    http://localhost:3000  (admin / <see grafana-admin-password.txt>)"
