#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <scenario>" >&2
    echo "  scenario: label for this run, e.g. idle, sync, self-healing" >&2
    exit 1
fi

SCENARIO="$1"
NAMESPACE="argocd"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RESULTS_DIR="$SCRIPT_DIR/results"
INTERVAL=0.25

echo "[INFO] Pre-flight: checking cluster connectivity..."
kubectl cluster-info > /dev/null

mkdir -p "$RESULTS_DIR"
RESULTS_FILE="$RESULTS_DIR/argocd-resources-$(date +%Y%m%d).csv"
echo "timestamp_utc,scenario,pod,cpu_millicores,memory_mib" > "$RESULTS_FILE"

trap 'echo; echo "[INFO] Stopped. Results saved to $RESULTS_FILE"; exit 0' INT

echo "[INFO] Sampling every ${INTERVAL}s — scenario: $SCENARIO. Press Ctrl+C to stop."

while true; do
    TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    while read -r pod cpu mem; do
        echo "$TIMESTAMP,$SCENARIO,$pod,$cpu,$mem" >> "$RESULTS_FILE"
    done < <(kubectl top pods -n "$NAMESPACE" --no-headers 2>/dev/null)
    sleep "$INTERVAL"
done
