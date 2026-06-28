#!/usr/bin/env bash
set -euo pipefail

# Measures Jenkins failure recovery time via SSH.
#
# Unlike the pull-based stacks (where Kubernetes restarts pods automatically),
# Jenkins runs as a systemd service on an external VM. Recovery is measured as
# the time from `systemctl stop jenkins` to Jenkins returning HTTP 200 on /login.
# This reflects the OS service restart mechanism rather than Kubernetes scheduling —
# an architectural difference documented in the thesis.

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <vm-ip>" >&2
    exit 1
fi

VM_IP="$1"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RESULTS_DIR="$SCRIPT_DIR/results"
JENKINS_PORT=8080
SSH_USER="azureuser"
RECOVERY_TIMEOUT=180

echo "[INFO] Pre-flight: verifying Jenkins is reachable..."
if ! curl -sf "http://$VM_IP:$JENKINS_PORT/login" > /dev/null 2>&1; then
    echo "[ERROR] Jenkins at http://$VM_IP:$JENKINS_PORT is not reachable. Ensure the VM is running." >&2
    exit 1
fi
echo "[INFO] Jenkins is up."

echo "[INFO] Stopping Jenkins service..."
ssh -o StrictHostKeyChecking=no "$SSH_USER@$VM_IP" "sudo systemctl stop jenkins"
T_START=$(date +%s)
echo "[INFO] T_start: $(date -u -r "$T_START" +%Y-%m-%dT%H:%M:%SZ)"

echo "[INFO] Starting Jenkins service..."
ssh -o StrictHostKeyChecking=no "$SSH_USER@$VM_IP" "sudo systemctl start jenkins"

echo "[INFO] Polling http://$VM_IP:$JENKINS_PORT/login until HTTP 200 (timeout: ${RECOVERY_TIMEOUT}s)..."
RECOVERED=false
DEADLINE=$(($(date +%s) + RECOVERY_TIMEOUT))
while [[ $(date +%s) -lt $DEADLINE ]]; do
    if curl -sf "http://$VM_IP:$JENKINS_PORT/login" > /dev/null 2>&1; then
        RECOVERED=true
        break
    fi
    sleep 0.25
done

if [[ "$RECOVERED" != "true" ]]; then
    echo "[ERROR] Jenkins did not recover within ${RECOVERY_TIMEOUT}s." >&2
    exit 1
fi

T_END=$(date +%s)
RECOVERY=$((T_END - T_START))
echo "[INFO] Jenkins recovered. Recovery time: ${RECOVERY}s"

mkdir -p "$RESULTS_DIR"
RESULTS_FILE="$RESULTS_DIR/jenkins-failure-recovery-$(date +%Y%m%d).csv"
if [[ ! -f "$RESULTS_FILE" ]]; then
    echo "run,timestamp_utc,t_start,t_end,recovery_seconds" > "$RESULTS_FILE"
fi
RUN_NUM=$(( $(wc -l < "$RESULTS_FILE") ))
echo "$RUN_NUM,$(date -u +%Y-%m-%dT%H:%M:%SZ),$T_START,$T_END,$RECOVERY" >> "$RESULTS_FILE"
echo "[INFO] Result saved to $RESULTS_FILE"
