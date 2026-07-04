#!/usr/bin/env bash
set -euo pipefail

# Measures Jenkins process resource consumption via SSH.
#
# Unlike the pull-based stacks (which use kubectl top on in-cluster pods),
# Jenkins runs on an external VM. Resource sampling is done via SSH using
# ps to read process-level CPU% and RSS. This is an architectural difference,
# not a measurement inconsistency — see README for thesis boundary note.
#
# CSV columns: timestamp_utc, pod, cpu_percent, memory_mib

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <vm-ip>" >&2
    exit 1
fi

VM_IP="$1"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RESULTS_DIR="$SCRIPT_DIR/results"
INTERVAL=0.25
SSH_USER="azureuser"

mkdir -p "$RESULTS_DIR"
RESULTS_FILE="$RESULTS_DIR/jenkins-resources-$(date +%Y%m%d).csv"
echo "timestamp_utc,pod,cpu_percent,memory_mib" > "$RESULTS_FILE"

trap 'echo; echo "[INFO] Stopped. Results saved to $RESULTS_FILE"; exit 0' INT

echo "[INFO] Sampling Jenkins process on $VM_IP every ${INTERVAL}s. Press Ctrl+C to stop."

while true; do
    TIMESTAMP=$(python3 -c "from datetime import datetime,timezone; print(datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%S.%f')[:-3]+'Z')")
    # ps output: %cpu  rss(kB)
    SAMPLE=$(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 "$SSH_USER@$VM_IP" \
      "ps -C java -o %cpu,rss --no-headers 2>/dev/null | head -1" 2>/dev/null || echo "0 0")
    CPU_PCT=$(echo "$SAMPLE" | awk '{print $1}')
    RSS_KB=$(echo  "$SAMPLE" | awk '{print $2}')
    MEM_MIB=$(echo "scale=2; $RSS_KB / 1024" | bc 2>/dev/null || echo "0")
    echo "$TIMESTAMP,jenkins-process,$CPU_PCT,$MEM_MIB" >> "$RESULTS_FILE"
    sleep "$INTERVAL"
done
