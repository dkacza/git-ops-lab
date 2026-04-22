#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="budget-tracker"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MANIFESTS_DIR="$REPO_ROOT/argo-cd/manifests"
RESULTS_DIR="$SCRIPT_DIR/results"

TAG_A="sha-00c452c"
TAG_B="sha-ee9dff6"

SYNC_TIMEOUT=120
ROLLOUT_TIMEOUT=180

echo "[INFO] Pre-flight: checking cluster connectivity..."
kubectl cluster-info > /dev/null

# Detect current tag and determine the next one
CURRENT_TAG=$(grep -oE 'budget-tracker-backend:sha-[a-f0-9]+' "$MANIFESTS_DIR/backend-deployment.yaml" | cut -d: -f2)
if [[ -z "$CURRENT_TAG" ]]; then
    echo "[ERROR] Could not detect current image tag" >&2
    exit 1
fi
NEW_TAG=$([[ "$CURRENT_TAG" == "$TAG_A" ]] && echo "$TAG_B" || echo "$TAG_A")
echo "[INFO] Switching $CURRENT_TAG → $NEW_TAG"

# Record pre-change deployment generations
PRE_GEN_BACKEND=$(kubectl get deployment backend  -n "$NAMESPACE" -o jsonpath='{.metadata.generation}')
PRE_GEN_FRONTEND=$(kubectl get deployment frontend -n "$NAMESPACE" -o jsonpath='{.metadata.generation}')
echo "[INFO] Pre-sync generations — backend: $PRE_GEN_BACKEND, frontend: $PRE_GEN_FRONTEND"

# Update both manifests
sed -i '' "s|budget-tracker-backend:$CURRENT_TAG|budget-tracker-backend:$NEW_TAG|g"   "$MANIFESTS_DIR/backend-deployment.yaml"
sed -i '' "s|budget-tracker-frontend:$CURRENT_TAG|budget-tracker-frontend:$NEW_TAG|g" "$MANIFESTS_DIR/frontend-deployment.yaml"

# Commit and push
git -C "$REPO_ROOT" add \
    "$MANIFESTS_DIR/backend-deployment.yaml" \
    "$MANIFESTS_DIR/frontend-deployment.yaml"
git -C "$REPO_ROOT" commit -m "measurement: switch image tags to $NEW_TAG"
git -C "$REPO_ROOT" push

# T_start = Unix timestamp of the commit
T_START=$(git -C "$REPO_ROOT" log -1 --format="%ct")
echo "[INFO] T_start: $(date -u -r "$T_START" +%Y-%m-%dT%H:%M:%SZ)"

# Wait for Argo CD to apply the new manifests (generation must increase)
echo "[INFO] Waiting for Argo CD to sync..."
ELAPSED=0
while true; do
    GEN_B=$(kubectl get deployment backend  -n "$NAMESPACE" -o jsonpath='{.metadata.generation}')
    GEN_F=$(kubectl get deployment frontend -n "$NAMESPACE" -o jsonpath='{.metadata.generation}')
    if [[ "$GEN_B" -gt "$PRE_GEN_BACKEND" ]] && [[ "$GEN_F" -gt "$PRE_GEN_FRONTEND" ]]; then
        break
    fi
    sleep 2
    ELAPSED=$((ELAPSED + 2))
    if [[ $ELAPSED -ge $SYNC_TIMEOUT ]]; then
        echo "[ERROR] Sync timeout after ${SYNC_TIMEOUT}s — Argo CD may not have synced. Check webhook configuration." >&2
        exit 1
    fi
done

# Wait for both rollouts to complete
echo "[INFO] Sync detected. Waiting for rollout to complete..."
kubectl rollout status deployment/backend  -n "$NAMESPACE" --timeout="${ROLLOUT_TIMEOUT}s"
kubectl rollout status deployment/frontend -n "$NAMESPACE" --timeout="${ROLLOUT_TIMEOUT}s"

T_END=$(date +%s)
DURATION=$((T_END - T_START))
echo "[INFO] Done. Duration: ${DURATION}s"

# Append result to CSV
mkdir -p "$RESULTS_DIR"
RESULTS_FILE="$RESULTS_DIR/argocd-cd-$(date +%Y%m%d).csv"
if [[ ! -f "$RESULTS_FILE" ]]; then
    echo "run,timestamp_utc,from_tag,to_tag,duration_seconds" > "$RESULTS_FILE"
fi
RUN_NUM=$(( $(wc -l < "$RESULTS_FILE") ))
echo "$RUN_NUM,$(date -u +%Y-%m-%dT%H:%M:%SZ),$CURRENT_TAG,$NEW_TAG,$DURATION" >> "$RESULTS_FILE"
echo "[INFO] Result saved to $RESULTS_FILE"
