#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="budget-tracker"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MANIFESTS_DIR="$REPO_ROOT/argo-cd/manifests"
RESULTS_DIR="$SCRIPT_DIR/results"

BAD_TAG="sha-badbeef000"

SYNC_TIMEOUT=120
DETECTION_TIMEOUT=120
CLEANUP_TIMEOUT=180

echo "[INFO] Pre-flight: checking cluster connectivity..."
kubectl cluster-info > /dev/null

# Verify backend is healthy before introducing a bad deployment
READY=$(kubectl get deployment backend -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}')
if [[ "${READY:-0}" -lt 1 ]]; then
    echo "[ERROR] Backend deployment is not healthy. Ensure the pod is ready before measuring." >&2
    exit 1
fi

# Save current good tag so we can restore it after measurement
ORIGINAL_TAG=$(grep -oE 'budget-tracker-backend:sha-[a-f0-9]+' "$MANIFESTS_DIR/backend-deployment.yaml" | cut -d: -f2)
echo "[INFO] Current (good) tag: $ORIGINAL_TAG"

# Record pre-deploy generation
PRE_GEN=$(kubectl get deployment backend -n "$NAMESPACE" -o jsonpath='{.metadata.generation}')
echo "[INFO] Pre-deploy generation: $PRE_GEN"

# Deploy bad image tag
echo "[INFO] Deploying bad image tag ($BAD_TAG)..."
sed -i '' "s|budget-tracker-backend:$ORIGINAL_TAG|budget-tracker-backend:$BAD_TAG|g" "$MANIFESTS_DIR/backend-deployment.yaml"
git -C "$REPO_ROOT" add "$MANIFESTS_DIR/backend-deployment.yaml"
git -C "$REPO_ROOT" commit -m "measurement: deploy bad image tag $BAD_TAG"
git -C "$REPO_ROOT" push

T_START=$(git -C "$REPO_ROOT" log -1 --format="%ct")
echo "[INFO] T_start: $(date -u -r "$T_START" +%Y-%m-%dT%H:%M:%SZ)"

# Wait for Argo CD to apply the bad manifest
echo "[INFO] Waiting for Argo CD to sync bad manifest..."
SYNCED=false
DEADLINE=$(($(date +%s) + SYNC_TIMEOUT))
while [[ $(date +%s) -lt $DEADLINE ]]; do
    GEN=$(kubectl get deployment backend -n "$NAMESPACE" -o jsonpath='{.metadata.generation}')
    if [[ "$GEN" -gt "$PRE_GEN" ]]; then
        SYNCED=true
        break
    fi
    sleep 0.25
done

if [[ "$SYNCED" != "true" ]]; then
    echo "[ERROR] Sync timeout after ${SYNC_TIMEOUT}s — Argo CD did not apply the manifest. Check webhook configuration." >&2
    exit 1
fi

# Poll pod status until the bad image enters a failing pull state
echo "[INFO] Bad manifest applied. Waiting for ImagePullBackOff on bad pod..."
DETECTED=false
DEADLINE=$(($(date +%s) + DETECTION_TIMEOUT))
while [[ $(date +%s) -lt $DEADLINE ]]; do
    REASONS=$(kubectl get pods -n "$NAMESPACE" -l app=backend \
        -o jsonpath='{range .items[*]}{range .status.containerStatuses[*]}{.state.waiting.reason}{" "}{end}{end}')
    if echo "$REASONS" | grep -qE 'ImagePullBackOff|ErrImagePull'; then
        DETECTED=true
        break
    fi
    sleep 0.25
done

if [[ "$DETECTED" != "true" ]]; then
    echo "[ERROR] Detection timeout after ${DETECTION_TIMEOUT}s — pod did not enter ImagePullBackOff." >&2
    exit 1
fi

T_END=$(date +%s)
DETECTION=$((T_END - T_START))
echo "[INFO] Failure detected. Detection time: ${DETECTION}s"

# Append result to CSV
mkdir -p "$RESULTS_DIR"
RESULTS_FILE="$RESULTS_DIR/argocd-failed-detection-$(date +%Y%m%d).csv"
if [[ ! -f "$RESULTS_FILE" ]]; then
    echo "run,timestamp_utc,bad_tag,t_start,t_end,detection_seconds" > "$RESULTS_FILE"
fi
RUN_NUM=$(( $(wc -l < "$RESULTS_FILE") ))
echo "$RUN_NUM,$(date -u +%Y-%m-%dT%H:%M:%SZ),$BAD_TAG,$T_START,$T_END,$DETECTION" >> "$RESULTS_FILE"
echo "[INFO] Result saved to $RESULTS_FILE"

# Cleanup: restore original good tag
echo "[INFO] Restoring image tag to $ORIGINAL_TAG..."
CLEANUP_PRE_GEN=$(kubectl get deployment backend -n "$NAMESPACE" -o jsonpath='{.metadata.generation}')
sed -i '' "s|budget-tracker-backend:$BAD_TAG|budget-tracker-backend:$ORIGINAL_TAG|g" "$MANIFESTS_DIR/backend-deployment.yaml"
git -C "$REPO_ROOT" add "$MANIFESTS_DIR/backend-deployment.yaml"
git -C "$REPO_ROOT" commit -m "measurement: restore image tag to $ORIGINAL_TAG"
git -C "$REPO_ROOT" push

RESTORED=false
DEADLINE=$(($(date +%s) + CLEANUP_TIMEOUT))
while [[ $(date +%s) -lt $DEADLINE ]]; do
    GEN=$(kubectl get deployment backend -n "$NAMESPACE" -o jsonpath='{.metadata.generation}')
    if [[ "$GEN" -gt "$CLEANUP_PRE_GEN" ]]; then
        RESTORED=true
        break
    fi
    sleep 0.25
done

if [[ "$RESTORED" != "true" ]]; then
    echo "[ERROR] Cleanup sync timeout — restore may have failed. Check cluster state manually." >&2
    exit 1
fi

kubectl rollout status deployment/backend -n "$NAMESPACE" --timeout="${CLEANUP_TIMEOUT}s"
echo "[INFO] Cluster restored. Backend is healthy."
