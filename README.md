## Topic:
Comparative analysis of selected CI/CD tools in terms of functionality, performance, and integration with modern development environments 

## Stacks to compare
The main goal of the thesis is to compare the GitOps tools.
As a supplement these will also be compared to the traditional Jenkins setup in order to highlight their advantages.

All the tools will use the same CI tool in order to ensure the quality of results.

#### Stack 1
GitHub Actions
Argo CD	Pull (GitOps)
#### Stack 2
GitHub Actions	
Flux	Pull (GitOps)
#### Stack 3	
GitHub Actions	
Jenkins	Push (traditional)

## Setup
Single-node AKS cluster on Azure (Standard_B2as_v2).
Each setup runs on a plain restored cluster.
Cluster provisioning and teardown commands are in `aks/instructions.md`.

Running on single node is a constraint. We cannot test the node-failover scenarios. This has to be presented as a boundary of the research and an idea for future expansion.


## Compared Characteristics

All characteristics compared across the three stacks. Quantitative ones are backed by measurement scripts; qualitative ones serve as descriptive differentiators in the thesis.

#### End-to-end deployment time *(quantitative)*
Time from a git commit to both application pods passing their readiness probes. The CI phase is identical across all stacks (same GitHub Actions workflow); differences are attributable to the CD tool. Measured in two variants: CD latency (git-ops-lab commit → pods ready) and full E2E latency (app repo commit → pods ready).

#### Self-healing latency *(quantitative — pull-based only)*
Time for the CD tool to detect and revert a configuration drift introduced directly on the cluster. Pull-based tools (Argo CD, Flux) reconcile continuously against the git state. Jenkins has no equivalent — drift is not detected or corrected without a manual pipeline re-run.

#### Resource consumption *(quantitative)*
CPU and memory footprint of the CD tool sampled at 250ms intervals across three scenarios: idle, active sync, and self-healing. Jenkins carries a significantly larger baseline footprint due to the JVM.

#### Failure recovery *(quantitative)*
Time for the CD tool to recover after all its pods are deleted. All tools are deployed as Kubernetes-native workloads, so pod restart is handled by the scheduler; the measured value reflects container startup and initialisation time.

#### Synchronisation latency *(qualitative)*
With webhooks configured, pull-based tools (Argo CD, Flux) detect git changes near-instantaneously — the latency is GitHub webhook delivery time, not tool behaviour. Without webhooks they fall back to polling (Argo CD default: 3 min, Flux default: 1 min). Jenkins is push-based and triggers immediately on git push regardless of webhook configuration. Not measured quantitatively as the value would reflect network round-trip to the AKS cluster, not the CD tool itself.

#### Rollback process *(qualitative)*
GitOps rollback is a `git revert` commit — auditable, PR-reviewable, and processed by the CD tool identically to any other commit. Jenkins rollback requires re-triggering the full CI pipeline with a previous artifact version; there is no built-in audit trail and the pipeline must be written to support it explicitly.

#### Failed deployment detection *(qualitative)*
Pull-based tools automatically surface deployment failures (e.g. bad image tag → `ImagePullBackOff` → `Degraded` health status) in their dashboards without any pipeline changes. Jenkins requires explicit post-deploy verification steps in the pipeline; failures are only visible if the pipeline checks for them. Not measured quantitatively as the detection time is determined by Kubernetes's `progressDeadlineSeconds` parameter, not the CD tool.

#### Operational complexity *(qualitative)*
Described in terms of configuration steps, required credentials, and cluster access model. Pull-based tools operate entirely from within the cluster and require only read access to the git repository — no inbound credentials need to be stored in the CI system. Jenkins requires cluster credentials (kubeconfig or service account token) to be stored in the CI environment, widening the secret surface area.

## Application
A minimal two-service web application used as the deployment target across all three stacks.
Application is a simple budget manager.

#### Frontend
nginx serving static content. Calls the backend API and displays the response.
Proxies `/api/*` requests to the backend service — no CORS configuration required.

#### Backend
Lightweight HTTP service written in Go exposing:
- `/health` — readiness and liveness probe endpoint
- `/api/data` — returns version and timestamp (version and build time injected at build via `-ldflags`)
- `/api/transactions` — CRUD for budget transactions (in-memory)
- `/api/limits` — per-category budget limits
- `/api/categories` — available categories
- `/api/summary` — computed stats: balance, category breakdown, savings rate, largest expense, overspend alerts

The application is a **budget tracker**. It was chosen because the backend contains real, non-trivial business logic (aggregation, savings rate, overspend detection) which makes CI unit tests meaningful rather than cosmetic.

No database. State is in-memory and resets on pod restart. Both services are intentionally minimal to keep build times fast and measurements consistent. Application startup time should not be the differentiating factor — CD tool performance is.

Deployment is considered complete when both pods pass their readiness probes.

#### Unit tests
Business logic lives in `backend/calculator.go` and is covered by `backend/calculator_test.go` (20 tests). Tests run as part of the Docker build (`go test ./...`) and will be executed by the GitHub Actions CI pipeline.

Application source code available at: https://github.com/dkacza/budget-tracker

#### Kubernetes namespace
All resources are deployed to the `budget-tracker` namespace.

## Repository structure

This lab uses a two-repo GitOps setup:

**`git-ops-lab`** (this repo) — config repo; the desired cluster state that CD tools reconcile against.
```
argo-cd/
  application.yaml        — Argo CD Application CRD
  manifests/              — Kubernetes manifests watched by Argo CD
    namespace.yaml
    backend-deployment.yaml
    backend-service.yaml
    frontend-deployment.yaml
    frontend-service.yaml
  aks/
    instructions.md         — AKS cluster setup guide
    provision-aks.sh        — provisions AKS cluster and static public IP
    deprovision-aks.sh      — tears down the resource group and all resources
    install-argocd-aks.sh   — installs Argo CD on AKS with static IP + webhook
  local/
    instructions.md         — local cluster setup guide
    install-argo-local.sh   — installs Argo CD on local cluster with port-forward
flux/
  manifests/              — Kubernetes manifests watched by Flux (planned)
measurements/
  e2e-deployment/
    measure_cd.sh           — measures CD latency: git-ops-lab commit → pods ready
    measure_e2e.sh          — measures full E2E latency: app repo commit → pods ready
    results/                — CSV output, one file per day per stack
  self-healing/
    measure_self_healing.sh — introduces replica drift on backend, measures reaction and recovery time
    results/                — CSV output, one file per day per stack
  resource-consumption/
    measure_resources.sh    — samples kubectl top for all Argo CD pods at 250ms interval
    render_graph.py         — renders aggregated CPU and memory graph from CSV
    results/                — CSV and PNG output, overwritten on each run
  failure-recovery/
    measure_failure_recovery.sh — kills all Argo CD pods, measures time until all are Ready again
    results/                — CSV output, one file per day per stack
old/
  README-rancher.md       — original README from the local Rancher Desktop setup
```

**`budget-tracker`** — application source code, Dockerfiles, GitHub Actions CI pipelines.

Images are published to GHCR (`ghcr.io/dkacza/budget-tracker-backend`, `ghcr.io/dkacza/budget-tracker-frontend`). On each CI run the image tag in the relevant `manifests/` directory is updated and committed here, triggering the CD tool to sync.

## Progress

#### Argo CD stack
For ArgoCD setup refer to `argo-cd/aks/instructions.md`

- [x] Config repo structure created (`argo-cd/manifests/`)
- [x] Kubernetes manifests prepared for GHCR images
- [x] Argo CD installed on AKS cluster
- [x] Argo CD Application CRD configured
- [x] GitHub Actions CI pipeline wired up
- [x] Automated installation script
- [x] Static public IP + GitHub webhook configured

#### Flux stack
- [ ] Not started

#### Jenkins stack
- [ ] Not started

#### Measurement scripts
- [x] E2E deployment — `measure_cd.sh`: git-ops-lab commit → pods ready (CD latency)
- [x] E2E deployment — `measure_e2e.sh`: app repo commit → pods ready (full pipeline latency)
- [x] Self-healing latency — `measure_self_healing.sh`: replica drift on backend → reaction and recovery time
- [x] Resource consumption — `measure_resources.sh`: samples all Argo CD pods at 250ms; `render_graph.py`: aggregated CPU/memory graph
- [x] Failure recovery — `measure_failure_recovery.sh`: kills all Argo CD pods, measures time until all are Ready again


### Software Versions:
- AKS: 1.31
- ArgoCD: 3.3.6

### Constraints
- Single-node cluster — node-failover scenarios are out of scope

## Change Log
- *24.04.2026* - Failed deployment detection time metric scrapped. Argo CD's `Degraded` health status for a failed rollout is derived directly from Kubernetes's `ProgressDeadlineExceeded` condition, which fires after `progressDeadlineSeconds`. The measured value would equal that parameter regardless of which GitOps tool is used — it is not attributable to the CD tool. The qualitative difference (GitOps tools surface failures automatically; Jenkins requires explicit post-deploy verification in the pipeline) will be noted in the thesis without a latency measurement.
- *22.04.2026* - Rollback time metric scrapped. Via git revert the measurement is structurally identical to the E2E CD latency already captured by `measure_cd.sh` — both are a git-ops-lab commit followed by Argo CD sync and pod rollover. The only meaningfully different rollback path (Argo CD native `argocd app rollback`) is not comparable across stacks. The thesis will treat rollback as a qualitative process difference: GitOps rollback is a git revert (auditable, PR-reviewable), Jenkins rollback requires re-triggering the full CI pipeline.
- *22.04.2026* - Synchronisation latency metric scrapped. With webhooks configured on both pull-based stacks, the measured value reflects GitHub's webhook delivery latency (network round-trip to AKS Poland Central), not CD tool behaviour. Argo CD and Flux would produce near-identical results with no tool-attributable signal. To be noted in the thesis as a qualitative observation: pull-based tools achieve near-instantaneous detection when webhooks are configured.
- *21.04.2026* - Due to the fact that the webhooks are not available on the local environment switch to Azure AKS has been made.