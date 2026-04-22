#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="budget-tracker"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RESULTS_DIR="$SCRIPT_DIR/results"

REVERT_TIMEOUT=120
ROLLOUT_TIMEOUT=120

echo "[INFO] Pre-flight: checking cluster connectivity..."
kubectl cluster-info > /dev/null

# Verify backend is healthy before introducing drift
READY=$(kubectl get deployment backend -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}')
if [[ "${READY:-0}" -lt 1 ]]; then
    echo "[ERROR] Backend deployment is not healthy. Ensure the pod is ready before measuring." >&2
    exit 1
fi

# Record generation before our patch
PRE_GEN=$(kubectl get deployment backend -n "$NAMESPACE" -o jsonpath='{.metadata.generation}')
echo "[INFO] Pre-drift generation: $PRE_GEN"

# Introduce drift: scale backend to 0 replicas
echo "[INFO] Introducing drift: scaling backend to 0 replicas..."
kubectl patch deployment backend -n "$NAMESPACE" \
    --type='json' \
    -p='[{"op":"replace","path":"/spec/replicas","value":0}]'

T_START=$(date +%s)
echo "[INFO] T_start: $(date -u -r "$T_START" +%Y-%m-%dT%H:%M:%SZ)"

# Wait for Argo CD to revert the drift.
# Our patch:      PRE_GEN → PRE_GEN+1
# Argo CD revert: PRE_GEN+1 → PRE_GEN+2
echo "[INFO] Waiting for Argo CD to self-heal..."
REVERTED=false
DEADLINE=$(($(date +%s) + REVERT_TIMEOUT))
while [[ $(date +%s) -lt $DEADLINE ]]; do
    GEN=$(kubectl get deployment backend -n "$NAMESPACE" -o jsonpath='{.metadata.generation}')
    if [[ "$GEN" -gt $((PRE_GEN + 1)) ]]; then
        REVERTED=true
        break
    fi
    sleep 0.25
done

if [[ "$REVERTED" != "true" ]]; then
    echo "[ERROR] Revert timeout after ${REVERT_TIMEOUT}s — Argo CD did not self-heal. Is selfHeal enabled?" >&2
    exit 1
fi

T_REVERT=$(date +%s)
REACTION=$((T_REVERT - T_START))
echo "[INFO] Drift reverted by Argo CD. Reaction time: ${REACTION}s"

# Wait for the pod to be ready again
echo "[INFO] Waiting for pod to be ready..."
kubectl rollout status deployment/backend -n "$NAMESPACE" --timeout="${ROLLOUT_TIMEOUT}s"

T_END=$(date +%s)
RECOVERY=$((T_END - T_START))
echo "[INFO] Done. Reaction: ${REACTION}s, Full recovery: ${RECOVERY}s"

# Append result to CSV
mkdir -p "$RESULTS_DIR"
RESULTS_FILE="$RESULTS_DIR/argocd-self-healing-$(date +%Y%m%d).csv"
if [[ ! -f "$RESULTS_FILE" ]]; then
    echo "run,timestamp_utc,t_start,t_revert,t_end,reaction_seconds,recovery_seconds" > "$RESULTS_FILE"
fi
RUN_NUM=$(( $(wc -l < "$RESULTS_FILE") ))
echo "$RUN_NUM,$(date -u +%Y-%m-%dT%H:%M:%SZ),$T_START,$T_REVERT,$T_END,$REACTION,$RECOVERY" >> "$RESULTS_FILE"
echo "[INFO] Result saved to $RESULTS_FILE"
