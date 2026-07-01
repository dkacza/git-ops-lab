#!/usr/bin/env bash
set -euo pipefail

# Measures failure recovery time for a pull-based CD tool by deleting all pods
# in its namespace and timing the return to a fully-Ready state. Jenkins uses a
# separate script (measure_failure_recovery_jenkins.sh) because it runs as a
# systemd service on an external VM, not as a Kubernetes workload.

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <argocd|flux> [-n <count>]" >&2
    exit 1
fi

TOOL="$1"
case "$TOOL" in
    argocd) NAMESPACE="argocd" ;;
    flux)   NAMESPACE="flux-system" ;;
    *)
        echo "[ERROR] Unknown tool '$TOOL'. Use 'argocd' or 'flux'." >&2
        exit 1
        ;;
esac
shift 1

COUNT=1
while [[ $# -gt 0 ]]; do
    case "$1" in
        -n) COUNT="$2"; shift 2 ;;
        *) echo "[ERROR] Unknown argument: $1" >&2; exit 1 ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RESULTS_DIR="$SCRIPT_DIR/results"

RECOVERY_TIMEOUT=180
SETTLE_SECONDS=30

echo "[INFO] Pre-flight: checking cluster connectivity..."
kubectl cluster-info > /dev/null

mkdir -p "$RESULTS_DIR"
RESULTS_FILE="$RESULTS_DIR/${TOOL}-failure-recovery-$(date +%Y%m%d).csv"
if [[ ! -f "$RESULTS_FILE" ]]; then
    echo "run,timestamp_utc,t_start,t_end,recovery_seconds" > "$RESULTS_FILE"
fi

for i in $(seq 1 "$COUNT"); do
    echo ""
    echo "[INFO] === Run $i/$COUNT ==="

    # Verify all pods are Ready before killing
    TOTAL=$(kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l | tr -d ' ')
    READY=$(kubectl get pods -n "$NAMESPACE" \
        -o jsonpath='{range .items[*]}{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}' 2>/dev/null \
        | grep -c True || true)

    if [[ "$TOTAL" -eq 0 || "$READY" -ne "$TOTAL" ]]; then
        echo "[ERROR] Not all $TOOL pods are Ready ($READY/$TOTAL). Ensure $TOOL is healthy before measuring." >&2
        exit 1
    fi

    echo "[INFO] All $TOTAL $TOOL pods are Ready."

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

    RUN_NUM=$(( $(wc -l < "$RESULTS_FILE") ))
    echo "$RUN_NUM,$(date -u +%Y-%m-%dT%H:%M:%SZ),$T_START,$T_END,$RECOVERY" >> "$RESULTS_FILE"
    echo "[INFO] Result saved to $RESULTS_FILE"

    if [[ $i -lt $COUNT ]]; then
        echo "[INFO] Settling for ${SETTLE_SECONDS}s before next run..."
        sleep "$SETTLE_SECONDS"
    fi
done

echo ""
echo "[INFO] All $COUNT run(s) complete. Results in $RESULTS_FILE"
