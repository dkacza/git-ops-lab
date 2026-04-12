#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

BACKEND_IMAGE="budget-tracker-backend"
FRONTEND_IMAGE="budget-tracker-frontend"
VERSION="${1:-$(git -C "$SCRIPT_DIR" rev-parse --short HEAD 2>/dev/null || echo 'dev')}"
BUILD_TIME="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

echo "==> Building images (version: $VERSION)"

docker build \
  --build-arg VERSION="$VERSION" \
  --build-arg BUILD_TIME="$BUILD_TIME" \
  -t "$BACKEND_IMAGE:$VERSION" \
  -t "$BACKEND_IMAGE:latest" \
  "$SCRIPT_DIR/backend"

docker build \
  -t "$FRONTEND_IMAGE:$VERSION" \
  -t "$FRONTEND_IMAGE:latest" \
  "$SCRIPT_DIR/frontend"

echo "==> Applying manifests"
kubectl apply -f "$SCRIPT_DIR/k8s.yaml"

echo "==> Waiting for rollout"
kubectl rollout status deployment/backend -n budget-tracker --timeout=60s
kubectl rollout status deployment/frontend -n budget-tracker --timeout=60s

echo ""
echo "==> Done. Application rolled out"
