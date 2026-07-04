#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <vm-ip> [-n <count>] [-s <settle_seconds>]" >&2
    exit 1
fi

VM_IP="$1"
shift 1

COUNT=1
SETTLE_SECONDS=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        -n) COUNT="$2";          shift 2 ;;
        -s) SETTLE_SECONDS="$2"; shift 2 ;;
        *) echo "[ERROR] Unknown argument: $1" >&2; exit 1 ;;
    esac
done

JENKINS_URL="http://$VM_IP:8080"
JOB_NAME="budget-tracker-deploy"
JENKINS_USER="admin"
NAMESPACE="budget-tracker"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MANIFESTS_DIR="$REPO_ROOT/jenkins/manifests"
RESULTS_DIR="$SCRIPT_DIR/results"
CREDENTIALS_FILE="$REPO_ROOT/jenkins/jenkins-api-token.txt"

TAG_A="sha-00c452c"
TAG_B="sha-ee9dff6"

BUILD_TIMEOUT=300
ROLLOUT_TIMEOUT=180
POLL_INTERVAL=5

echo "[INFO] Pre-flight: checking cluster connectivity..."
kubectl cluster-info > /dev/null

if [[ ! -f "$CREDENTIALS_FILE" ]]; then
    echo "[ERROR] API token file not found: $CREDENTIALS_FILE" >&2
    exit 1
fi
API_TOKEN=$(cat "$CREDENTIALS_FILE")

mkdir -p "$RESULTS_DIR"
RESULTS_FILE="$RESULTS_DIR/jenkins-cd-$(date +%Y%m%d).csv"
if [[ ! -f "$RESULTS_FILE" ]]; then
    echo "run,timestamp_utc,from_tag,to_tag,duration_seconds" > "$RESULTS_FILE"
fi

for i in $(seq 1 "$COUNT"); do
    echo ""
    echo "[INFO] === Run $i/$COUNT ==="

    CURRENT_TAG=$(grep -oE 'budget-tracker-backend:sha-[a-f0-9]+' "$MANIFESTS_DIR/backend-deployment.yaml" | cut -d: -f2)
    if [[ -z "$CURRENT_TAG" ]]; then
        echo "[ERROR] Could not detect current image tag" >&2
        exit 1
    fi
    NEW_TAG=$([[ "$CURRENT_TAG" == "$TAG_A" ]] && echo "$TAG_B" || echo "$TAG_A")
    echo "[INFO] Switching $CURRENT_TAG → $NEW_TAG"

    sed -i '' "s|budget-tracker-backend:$CURRENT_TAG|budget-tracker-backend:$NEW_TAG|g"   "$MANIFESTS_DIR/backend-deployment.yaml"
    sed -i '' "s|budget-tracker-frontend:$CURRENT_TAG|budget-tracker-frontend:$NEW_TAG|g" "$MANIFESTS_DIR/frontend-deployment.yaml"

    git -C "$REPO_ROOT" add \
        "$MANIFESTS_DIR/backend-deployment.yaml" \
        "$MANIFESTS_DIR/frontend-deployment.yaml"
    git -C "$REPO_ROOT" commit -m "measurement: switch image tags to $NEW_TAG"
    git -C "$REPO_ROOT" push

    T_START=$(git -C "$REPO_ROOT" log -1 --format="%ct")
    echo "[INFO] T_start: $(date -u -r "$T_START" +%Y-%m-%dT%H:%M:%SZ)"

    # Get next expected build number before triggering
    NEXT_BUILD=$(curl -fsS "$JENKINS_URL/job/$JOB_NAME/api/json" \
        --user "$JENKINS_USER:$API_TOKEN" \
        | python3 -c "import sys,json; print(json.load(sys.stdin)['nextBuildNumber'])")

    echo "[INFO] Triggering Jenkins build #$NEXT_BUILD..."
    curl -fsS -X POST "$JENKINS_URL/job/$JOB_NAME/build" \
        --user "$JENKINS_USER:$API_TOKEN"

    # Wait for build to complete
    DEADLINE=$(($(date +%s) + BUILD_TIMEOUT))
    while true; do
        if [[ $(date +%s) -gt $DEADLINE ]]; then
            echo "[ERROR] Jenkins build timeout after ${BUILD_TIMEOUT}s" >&2
            exit 1
        fi
        STATUS=$(curl -fsS "$JENKINS_URL/job/$JOB_NAME/$NEXT_BUILD/api/json" \
            --user "$JENKINS_USER:$API_TOKEN" 2>/dev/null \
            | python3 -c "import sys,json; d=json.load(sys.stdin); print('RUNNING' if d.get('building') else d.get('result','PENDING'))" \
            2>/dev/null || echo "PENDING")
        if [[ "$STATUS" == "RUNNING" || "$STATUS" == "PENDING" ]]; then
            sleep "$POLL_INTERVAL"
        else
            break
        fi
    done

    if [[ "$STATUS" != "SUCCESS" ]]; then
        echo "[ERROR] Jenkins build #$NEXT_BUILD ended with status: $STATUS" >&2
        exit 1
    fi
    echo "[INFO] Build #$NEXT_BUILD succeeded. Waiting for rollout to complete..."

    kubectl rollout status deployment/backend  -n "$NAMESPACE" --timeout="${ROLLOUT_TIMEOUT}s"
    kubectl rollout status deployment/frontend -n "$NAMESPACE" --timeout="${ROLLOUT_TIMEOUT}s"

    T_END=$(date +%s)
    DURATION=$((T_END - T_START))
    echo "[INFO] Done. Duration: ${DURATION}s"

    RUN_NUM=$(( $(wc -l < "$RESULTS_FILE") ))
    echo "$RUN_NUM,$(date -u +%Y-%m-%dT%H:%M:%SZ),$CURRENT_TAG,$NEW_TAG,$DURATION" >> "$RESULTS_FILE"
    echo "[INFO] Result saved to $RESULTS_FILE"

    if [[ $i -lt $COUNT ]]; then
        echo "[INFO] Settling for ${SETTLE_SECONDS}s before next run..."
        sleep "$SETTLE_SECONDS"
    fi
done

echo ""
echo "[INFO] All $COUNT run(s) complete. Results in $RESULTS_FILE"
