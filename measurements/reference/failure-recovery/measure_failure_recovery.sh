#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="argocd"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RESULTS_DIR="$SCRIPT_DIR/results"

RECOVERY_TIMEOUT=180

echo "[INFO] Pre-flight: checking cluster connectivity..."
kubectl cluster-info > /dev/null

# Verify all Argo CD pods are Ready before killing
TOTAL=$(kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l | tr -d ' ')
READY=$(kubectl get pods -n "$NAMESPACE" \
    -o jsonpath='{range .items[*]}{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}' 2>/dev/null \
    | grep -c True || true)

if [[ "$TOTAL" -eq 0 || "$READY" -ne "$TOTAL" ]]; then
    echo "[ERROR] Not all Argo CD pods are Ready ($READY/$TOTAL). Ensure Argo CD is healthy before measuring." >&2
    exit 1
fi

echo "[INFO] All $TOTAL Argo CD pods are Ready."

# Kill all pods
echo "[INFO] Deleting all pods in namespace $NAMESPACE..."
kubectl delete pods --all -n "$NAMESPACE"
T_START=$(date +%s)
echo "[INFO] T_start: $(date -u -r "$T_START" +%Y-%m-%dT%H:%M:%SZ)"

# Poll until all pods are back and Ready (no Terminating, same count, all Ready)
echo "[INFO] Waiting for all $TOTAL pods to recover..."
RECOVERED=false
DEADLINE=$(($(date +%s) + RECOVERY_TIMEOUT))
while [[ $(date +%s) -lt $DEADLINE ]]; do
    TERMINATING=$(kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null | grep -c Terminating || true)
    CURRENT_TOTAL=$(kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null | grep -vc Terminating || true)
    CURRENT_READY=$(kubectl get pods -n "$NAMESPACE" \
        -o jsonpath='{range .items[*]}{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}' 2>/dev/null \
        | grep -c True || true)
    if [[ "$TERMINATING" -eq 0 && "$CURRENT_TOTAL" -eq "$TOTAL" && "$CURRENT_READY" -eq "$TOTAL" ]]; then
        RECOVERED=true
        break
    fi
    sleep 0.25
done

if [[ "$RECOVERED" != "true" ]]; then
    echo "[ERROR] Recovery timeout after ${RECOVERY_TIMEOUT}s — not all pods became Ready." >&2
    exit 1
fi

T_END=$(date +%s)
RECOVERY=$((T_END - T_START))
echo "[INFO] All pods recovered. Recovery time: ${RECOVERY}s"

mkdir -p "$RESULTS_DIR"
RESULTS_FILE="$RESULTS_DIR/argocd-failure-recovery-$(date +%Y%m%d).csv"
if [[ ! -f "$RESULTS_FILE" ]]; then
    echo "run,timestamp_utc,t_start,t_end,recovery_seconds" > "$RESULTS_FILE"
fi
RUN_NUM=$(( $(wc -l < "$RESULTS_FILE") ))
echo "$RUN_NUM,$(date -u +%Y-%m-%dT%H:%M:%SZ),$T_START,$T_END,$RECOVERY" >> "$RESULTS_FILE"
echo "[INFO] Result saved to $RESULTS_FILE"
