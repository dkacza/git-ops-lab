#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <path-to-budget-tracker-repo>" >&2
    exit 1
fi

APP_REPO="$(cd "$1" && pwd)"

NAMESPACE="budget-tracker"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RESULTS_DIR="$SCRIPT_DIR/results"

CI_COMMIT_PATTERN="ci: update image tags to sha-"
CI_WAIT_TIMEOUT=600
SYNC_TIMEOUT=120
ROLLOUT_TIMEOUT=180

echo "[INFO] Pre-flight: checking cluster connectivity..."
kubectl cluster-info > /dev/null

# Trigger CI by committing a dummy file to the app repo
echo "[INFO] Triggering CI run in $APP_REPO..."
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$APP_REPO/.measurement-trigger"
git -C "$APP_REPO" add .measurement-trigger
git -C "$APP_REPO" commit -m "measurement: trigger CI run"
git -C "$APP_REPO" push

T_START_E2E=$(git -C "$APP_REPO" log -1 --format="%ct")
echo "[INFO] T_start_e2e: $(date -u -r "$T_START_E2E" +%Y-%m-%dT%H:%M:%SZ)"

# Snapshot generations before CI has had any chance to run
PRE_GEN_BACKEND=$(kubectl get deployment backend  -n "$NAMESPACE" -o jsonpath='{.metadata.generation}')
PRE_GEN_FRONTEND=$(kubectl get deployment frontend -n "$NAMESPACE" -o jsonpath='{.metadata.generation}')
echo "[INFO] Pre-sync generations — backend: $PRE_GEN_BACKEND, frontend: $PRE_GEN_FRONTEND"

# Wait for CI to commit the updated image tag back to git-ops-lab
echo "[INFO] Polling for CI commit (timeout: ${CI_WAIT_TIMEOUT}s)..."
T_START_CD=""
DEADLINE=$(($(date +%s) + CI_WAIT_TIMEOUT))
while [[ $(date +%s) -lt $DEADLINE ]]; do
    git -C "$REPO_ROOT" fetch origin main -q
    while IFS= read -r line; do
        COMMIT_TS="${line%% *}"
        SUBJECT="${line#* }"
        if [[ "$COMMIT_TS" -gt "$T_START_E2E" ]] && [[ "$SUBJECT" == *"$CI_COMMIT_PATTERN"* ]]; then
            T_START_CD="$COMMIT_TS"
            echo "[INFO] CI commit detected: '$SUBJECT' at $(date -u -r "$T_START_CD" +%Y-%m-%dT%H:%M:%SZ)"
            break 2
        fi
    done < <(git -C "$REPO_ROOT" log origin/main --format="%ct %s" -20)
    sleep 2
done

if [[ -z "$T_START_CD" ]]; then
    echo "[ERROR] No CI commit matching '$CI_COMMIT_PATTERN' found after ${CI_WAIT_TIMEOUT}s." >&2
    exit 1
fi

echo "[INFO] T_start_cd: $(date -u -r "$T_START_CD" +%Y-%m-%dT%H:%M:%SZ)"

# Wait for Argo CD to apply the new manifests
echo "[INFO] Waiting for Argo CD to sync..."
SYNCED=false
DEADLINE=$(($(date +%s) + SYNC_TIMEOUT))
while [[ $(date +%s) -lt $DEADLINE ]]; do
    GEN_B=$(kubectl get deployment backend  -n "$NAMESPACE" -o jsonpath='{.metadata.generation}')
    GEN_F=$(kubectl get deployment frontend -n "$NAMESPACE" -o jsonpath='{.metadata.generation}')
    if [[ "$GEN_B" -gt "$PRE_GEN_BACKEND" ]] && [[ "$GEN_F" -gt "$PRE_GEN_FRONTEND" ]]; then
        SYNCED=true
        break
    fi
    sleep 0.25
done

if [[ "$SYNCED" != "true" ]]; then
    echo "[ERROR] Sync timeout after ${SYNC_TIMEOUT}s — Argo CD may not have synced. Check webhook configuration." >&2
    exit 1
fi

# Wait for both rollouts to complete
echo "[INFO] Sync detected. Waiting for rollout to complete..."
kubectl rollout status deployment/backend  -n "$NAMESPACE" --timeout="${ROLLOUT_TIMEOUT}s"
kubectl rollout status deployment/frontend -n "$NAMESPACE" --timeout="${ROLLOUT_TIMEOUT}s"

T_END=$(date +%s)
CD_DURATION=$((T_END - T_START_CD))
E2E_DURATION=$((T_END - T_START_E2E))
echo "[INFO] Done."
echo "[INFO] CD duration:  ${CD_DURATION}s"
echo "[INFO] E2E duration: ${E2E_DURATION}s"

# Append result to CSV
mkdir -p "$RESULTS_DIR"
RESULTS_FILE="$RESULTS_DIR/argocd-e2e-$(date +%Y%m%d).csv"
if [[ ! -f "$RESULTS_FILE" ]]; then
    echo "run,timestamp_utc,t_start_e2e,t_start_cd,t_end,cd_duration_seconds,e2e_duration_seconds" > "$RESULTS_FILE"
fi
RUN_NUM=$(( $(wc -l < "$RESULTS_FILE") ))
echo "$RUN_NUM,$(date -u +%Y-%m-%dT%H:%M:%SZ),$T_START_E2E,$T_START_CD,$T_END,$CD_DURATION,$E2E_DURATION" >> "$RESULTS_FILE"
echo "[INFO] Result saved to $RESULTS_FILE"
