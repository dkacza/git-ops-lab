#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <argocd|flux|jenkins> [-n <count>] -s <settle_seconds>" >&2
    exit 1
fi

TOOL="$1"
if [[ "$TOOL" != "argocd" && "$TOOL" != "flux" && "$TOOL" != "jenkins" ]]; then
    echo "[ERROR] Unknown tool '$TOOL'. Use 'argocd', 'flux', or 'jenkins'." >&2
    exit 1
fi
shift 1

COUNT=1
SETTLE_SECONDS=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -n) COUNT="$2"; shift 2 ;;
        -s) SETTLE_SECONDS="$2"; shift 2 ;;
        *) echo "[ERROR] Unknown argument: $1" >&2; exit 1 ;;
    esac
done

if [[ -z "$SETTLE_SECONDS" ]]; then
    echo "Usage: $0 <argocd|flux|jenkins> [-n <count>] -s <settle_seconds>" >&2
    exit 1
fi

NAMESPACE="budget-tracker"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RESULTS_DIR="$SCRIPT_DIR/results"

REVERT_TIMEOUT=600
ROLLOUT_TIMEOUT=120
IDLE_TIMEOUT=60

echo "[INFO] Pre-flight: checking cluster connectivity..."
kubectl cluster-info > /dev/null

# Wait for the CD tool to reach a stable, idle state before introducing drift.
# Without this guard, a run started while the tool is mid-reconcile produces a
# near-zero reaction time (the in-flight apply overwrites the patch immediately).
wait_for_idle() {
    local deadline=$(($(date +%s) + IDLE_TIMEOUT))
    if [[ "$TOOL" == "jenkins" ]]; then
        echo "[INFO] Jenkins has no in-cluster idle status; relying on the scheduled reconcile job."
        return 0
    fi

    echo "[INFO] Waiting for $TOOL to reach idle/Synced state..."
    while [[ $(date +%s) -lt $deadline ]]; do
        case "$TOOL" in
            argocd)
                local sync_status op_phase finished_at finished_ts age
                sync_status=$(kubectl get application budget-tracker -n argocd \
                    -o jsonpath='{.status.sync.status}' 2>/dev/null || true)
                op_phase=$(kubectl get application budget-tracker -n argocd \
                    -o jsonpath='{.status.operationState.phase}' 2>/dev/null || true)
                finished_at=$(kubectl get application budget-tracker -n argocd \
                    -o jsonpath='{.status.operationState.finishedAt}' 2>/dev/null || true)
                if [[ "$sync_status" == "Synced" && "$op_phase" != "Running" ]]; then
                    if [[ -z "$finished_at" ]]; then
                        # No operationState recorded — Argo CD is idle with no recent operation
                        echo "[INFO] Argo CD is idle (sync=$sync_status, no recent operation)."
                        return 0
                    fi
                    finished_ts=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$finished_at" +%s 2>/dev/null || date -d "$finished_at" +%s)
                    age=$(( $(date +%s) - finished_ts ))
                    # Require last op to be >30s old — ensures we are well between reconciliation cycles
                    # and not at the start of a new one that would overwrite our patch immediately.
                    if [[ "$age" -gt 30 ]]; then
                        echo "[INFO] Argo CD is idle (sync=$sync_status, op=$op_phase, finishedAt=${age}s ago)."
                        return 0
                    fi
                fi
                ;;
            flux)
                local ready_status reason
                ready_status=$(kubectl get kustomization budget-tracker -n flux-system \
                    -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
                reason=$(kubectl get kustomization budget-tracker -n flux-system \
                    -o jsonpath='{.status.conditions[?(@.type=="Ready")].reason}' 2>/dev/null || true)
                # Idle = Ready=True and reason=ReconciliationSucceeded (not in progress)
                if [[ "$ready_status" == "True" && "$reason" == "ReconciliationSucceeded" ]]; then
                    echo "[INFO] Flux is idle (ready=$ready_status, reason=$reason)."
                    return 0
                fi
                ;;
        esac
        sleep 1
    done
    echo "[ERROR] $TOOL did not reach idle state within ${IDLE_TIMEOUT}s." >&2
    exit 1
}

mkdir -p "$RESULTS_DIR"
RESULTS_FILE="$RESULTS_DIR/${TOOL}-self-healing-$(date +%Y%m%d).csv"
if [[ ! -f "$RESULTS_FILE" ]]; then
    echo "run,timestamp_utc,t_start,t_revert,t_end,reaction_seconds,recovery_seconds" > "$RESULTS_FILE"
fi

for i in $(seq 1 "$COUNT"); do
    echo ""
    echo "[INFO] === Run $i/$COUNT ==="

    # Verify backend is healthy before introducing drift
    READY=$(kubectl get deployment backend -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}')
    if [[ "${READY:-0}" -lt 1 ]]; then
        echo "[ERROR] Backend deployment is not healthy. Ensure the pod is ready before measuring." >&2
        exit 1
    fi

    # Gate: ensure the CD tool is idle before we introduce drift
    wait_for_idle

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

    # Wait for the CD tool to revert the drift.
    # Our patch:       PRE_GEN → PRE_GEN+1
    # Tool revert:     PRE_GEN+1 → PRE_GEN+2
    echo "[INFO] Waiting for $TOOL to self-heal..."
    REVERTED=false
    DEADLINE=$(($(date +%s) + REVERT_TIMEOUT))
    while [[ $(date +%s) -lt $DEADLINE ]]; do
        GEN=$(kubectl get deployment backend -n "$NAMESPACE" -o jsonpath='{.metadata.generation}')
        REPLICAS=$(kubectl get deployment backend -n "$NAMESPACE" -o jsonpath='{.spec.replicas}')
        if [[ "$GEN" -gt $((PRE_GEN + 1)) && "$REPLICAS" == "1" ]]; then
            REVERTED=true
            break
        fi
        sleep 0.25
    done

    if [[ "$REVERTED" != "true" ]]; then
        case "$TOOL" in
            argocd) echo "[ERROR] Revert timeout after ${REVERT_TIMEOUT}s — Argo CD did not self-heal. Is selfHeal enabled?" >&2 ;;
            flux)   echo "[ERROR] Revert timeout after ${REVERT_TIMEOUT}s — Flux did not self-heal. Is prune/force enabled on the Kustomization?" >&2 ;;
            jenkins) echo "[ERROR] Revert timeout after ${REVERT_TIMEOUT}s — Jenkins did not self-heal. Is the budget-tracker-reconcile schedule enabled?" >&2 ;;
        esac
        exit 1
    fi

    T_REVERT=$(date +%s)
    REACTION=$((T_REVERT - T_START))
    echo "[INFO] Drift reverted by $TOOL. Reaction time: ${REACTION}s"

    # Wait for the pod to be ready again
    echo "[INFO] Waiting for pod to be ready..."
    kubectl rollout status deployment/backend -n "$NAMESPACE" --timeout="${ROLLOUT_TIMEOUT}s"

    T_END=$(date +%s)
    RECOVERY=$((T_END - T_START))
    echo "[INFO] Done. Reaction: ${REACTION}s, Full recovery: ${RECOVERY}s"

    RUN_NUM=$(( $(wc -l < "$RESULTS_FILE") ))
    echo "$RUN_NUM,$(date -u +%Y-%m-%dT%H:%M:%SZ),$T_START,$T_REVERT,$T_END,$REACTION,$RECOVERY" >> "$RESULTS_FILE"
    echo "[INFO] Result saved to $RESULTS_FILE"

    if [[ $i -lt $COUNT ]]; then
        echo "[INFO] Settling for ${SETTLE_SECONDS}s before next run..."
        sleep "$SETTLE_SECONDS"
    fi
done

echo ""
echo "[INFO] All $COUNT run(s) complete. Results in $RESULTS_FILE"
