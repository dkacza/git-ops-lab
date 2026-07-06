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
Cluster provisioning and teardown scripts are in `aks/`.

Jenkins runs on a separate Azure VM (Standard_B2s, 2 vCPU / 4 GiB) — not inside the AKS cluster. This reflects the authentic push-based architecture: Jenkins holds cluster credentials externally and pushes via `kubectl apply`. Provisioning scripts are in `jenkins/vm/`.

Running on single node is a constraint. We cannot test the node-failover scenarios. This has to be presented as a boundary of the research and an idea for future expansion.


## Compared Characteristics

All characteristics compared across the three stacks. Quantitative ones are backed by measurement scripts; qualitative ones serve as descriptive differentiators in the thesis.

#### End-to-end deployment time *(quantitative)*
Time from a git commit to both application pods passing their readiness probes. The CI phase is identical across all stacks (same GitHub Actions workflow); differences are attributable to the CD tool. Measured in two variants: CD latency (git-ops-lab commit → pods ready) and full E2E latency (app repo commit → pods ready).

#### Self-healing latency *(quantitative — pull-based only)*
Time for the CD tool to detect and revert a configuration drift introduced directly on the cluster. Pull-based tools (Argo CD, Flux) reconcile continuously against the git state. Jenkins has no equivalent — drift is not detected or corrected without a manual pipeline re-run.

#### Resource consumption *(quantitative)*
CPU and memory footprint of the CD tool sampled during idle and sync scenarios.

#### Failure recovery *(quantitative)*
Time for the CD tool to recover after all its pods are deleted. All tools are deployed as Kubernetes-native workloads, so pod restart is handled by the scheduler; the measured value reflects container startup and initialisation time.

#### Failed deployment detection *(quantitative — pull-based only)*
Time from a bad image tag being committed to the CD tool surfacing the failure (pod in `ImagePullBackOff` / `ErrImagePull`). Pull-based tools reflect the failure in their dashboards without any pipeline changes; Jenkins would require explicit post-deploy verification steps in the pipeline to expose the same signal. The measured value is bounded from below by Kubernetes's own scheduling and pull-retry loop, but the *surfacing* is attributable to the CD tool.

#### Rollback process *(qualitative)*
GitOps rollback is a `git revert` commit — auditable, PR-reviewable, and processed by the CD tool identically to any other commit. Jenkins rollback requires re-triggering the full CI pipeline with a previous artifact version; there is no built-in audit trail and the pipeline must be written to support it explicitly.

#### Operational complexity *(qualitative)*
Described in terms of configuration steps, required credentials, and cluster access model. Pull-based tools operate entirely from within the cluster and require only read access to the git repository — no inbound credentials need to be stored in the CI system. Jenkins requires cluster credentials (kubeconfig or service account token) to be stored in the CI environment, widening the secret surface area.

#### Security
Tool's ability to withstand various kinds of attack.

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
aks/
  provision-aks.sh         — provisions AKS cluster (shared across all stacks)
  deprovision-aks.sh       — tears down the resource group and all resources
monitoring/
  install-monitoring.sh    — installs kube-prometheus-stack (Prometheus + Grafana); run once after provision-aks.sh, before any stack install
  uninstall-monitoring.sh  — removes the monitoring stack; run before deprovision-aks.sh
credentials.md             — inventory of all secrets and tokens across all stacks
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
    install-argocd-aks.sh   — creates static IP, installs Argo CD, configures webhook
    uninstall-argocd-aks.sh — removes Argo CD and deletes static IP
flux/
  manifests/              — Kubernetes manifests watched by Flux
    namespace.yaml
    backend-deployment.yaml
    backend-service.yaml
    frontend-deployment.yaml
    frontend-service.yaml
  clusters/aks/           — Flux system manifests (bootstrapped by flux CLI)
    flux-system/
    budget-tracker.yaml   — Kustomization pointing at flux/manifests
    webhook-receiver.yaml — GitHub webhook Receiver CRD
  aks/
    instructions.md         — Flux AKS setup guide
    install-flux-aks.sh     — creates static IP, bootstraps Flux, configures webhook receiver
    uninstall-flux-aks.sh   — removes Flux and deletes static IP
jenkins/
  manifests/              — Kubernetes manifests applied by Jenkins via kubectl
    namespace.yaml
    backend-deployment.yaml
    backend-service.yaml
    frontend-deployment.yaml
    frontend-service.yaml
  vm/
    provision-vm.sh             — creates Azure VM for Jenkins
    install-jenkins.sh          — installs Java 21, Jenkins LTS, kubectl on the VM (called by setup-jenkins.sh)
    setup-jenkins.sh            — wires AKS credentials, creates ServiceAccount + RBAC, saves kubeconfig
    deprovision-jenkins-vm.sh   — deletes Jenkins VM and its public IP
    instructions.md             — VM setup guide and GitHub Actions wiring instructions
measurements/
  cd-deployment/            — CD latency: git-ops-lab commit → pods ready
    measure_cd.sh           — argocd|flux (commits image-tag flip directly)
    measure_cd_jenkins.sh   — jenkins (commits image-tag flip, then triggers Jenkins job via API)
    results/                — CSV output, one file per day per stack
  e2e-deployment/           — E2E latency: app repo commit → pods ready
    measure_e2e.sh          — argocd|flux|jenkins
    results/
  self-healing/             — replica drift → reaction + recovery time
    measure_self_healing.sh — argocd|flux
    results/
  failure-recovery/         — CD-tool pod delete (or Jenkins systemd stop) → back to Ready
    measure_failure_recovery.sh          — argocd|flux
    measure_failure_recovery_jenkins.sh  — jenkins (SSH + systemctl)
    results/
  failed-detection/         — bad image tag → pod in ImagePullBackOff surfaced by CD tool
    measure_failed_detection.sh — argocd|flux
    results/
  resource-consumption/     — CPU / memory sampling of the CD process
    measure_resources_jenkins.sh — jenkins (SSH + ps, since Jenkins is on a VM)
    render_graph.py               — plots CPU + memory PNGs from a results CSV
    results/
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
- [x] Config repo structure created (`flux/manifests/`)
- [x] Kubernetes manifests prepared for GHCR images
- [x] Flux installed on AKS cluster (bootstrapped)
- [x] Budget-tracker Kustomization configured
- [x] GitHub Actions CI pipeline wired up (updates flux/manifests on push)
- [x] Static public IP + GitHub webhook configured

#### Jenkins stack
For Jenkins setup refer to `jenkins/vm/instructions.md`

- [x] Config repo structure created (`jenkins/manifests/`)
- [x] Kubernetes manifests prepared for GHCR images
- [x] Provisioning scripts (`provision-vm.sh`, `install-jenkins.sh`, `setup-jenkins.sh`) — create Azure VM, install Jenkins, wire AKS credentials
- [x] Jenkins VM provisioned and verified on AKS
- [x] `budget-tracker-deploy` pipeline job confirmed working end-to-end
- [x] GitHub Actions CI pipeline wired up (POST trigger after image tag commit)

#### Measurement scripts
- [x] E2E deployment — `e2e-deployment/measure_e2e.sh <argocd|flux|jenkins>`: app repo commit → pods ready (full pipeline latency)
- [x] CD latency — `cd-deployment/measure_cd.sh <argocd|flux>` and `cd-deployment/measure_cd_jenkins.sh <vm-ip>`: git-ops-lab commit → pods ready
- [x] Self-healing latency — `self-healing/measure_self_healing.sh <argocd|flux> -s <settle_seconds>`: replica drift → reaction and recovery time
- [x] Failure recovery — `failure-recovery/measure_failure_recovery.sh <argocd|flux>` (pod delete → all-Ready) and `failure-recovery/measure_failure_recovery_jenkins.sh <vm-ip>` (systemd stop/start → HTTP 200)
- [x] Failed deployment detection — `failed-detection/measure_failed_detection.sh <argocd|flux>`: bad image tag committed → pod in ImagePullBackOff
- [x] Resource consumption — `resource-consumption/measure_resources_jenkins.sh <vm-ip>` (SSH + ps for the JVM); Argo CD / Flux equivalents are sampled via `kubectl top` on the in-cluster pods. `render_graph.py` plots CPU + memory from the resulting CSV.


### Software Versions:
Pinned in the install scripts for reproducibility. Bump in both places (script + this section) to change.

- AKS Kubernetes: **1.31** (`aks/provision-aks.sh`)
- Argo CD: **v3.4.4** (`argo-cd/aks/install-argocd-aks.sh`)
- Flux: **v2.9.0** (`flux/aks/install-flux-aks.sh`; requires matching `flux` CLI locally)
- Jenkins LTS: **2.555.3** (`jenkins/vm/install-jenkins.sh`, held via `apt-mark hold`)
- kube-prometheus-stack (Helm chart): **87.10.1** (`monitoring/install-monitoring.sh`)

### Constraints
- Single-node cluster — node-failover scenarios are out of scope
- Jenkins runs on a separate Azure VM (Standard_B2s) — resource and failure-recovery measurements use VM process metrics (SSH + `ps`) rather than `kubectl top`. JVM heap capped at 512m for comparability. This architectural difference is intentional and documented in the thesis.

## Change Log
- *04.07.2026* - Prometheus + Grafana (kube-prometheus-stack) added as a dedicated monitoring layer, installed via `monitoring/install-monitoring.sh` after cluster provisioning and before any CD stack. Kept outside GitOps control deliberately — having the measured tool reconcile its own observer would couple monitoring lifecycle to the stack under test and risk losing metrics across stack switches.
- *24.06.2026* - Static IP lifecycle moved out of `provision-aks.sh` and into the per-stack install scripts. `install-argocd-aks.sh` and `install-flux-aks.sh` now create `gitops-tool-public-ip` on install; new `uninstall-argocd-aks.sh` and `uninstall-flux-aks.sh` scripts delete it on teardown. This ensures the IP slot is only consumed while a pull-based stack is active, leaving room for the Jenkins frontend LoadBalancer within the 3-IP subscription limit.
- *22.04.2026* - Rollback time metric scrapped. Via git revert the measurement is structurally identical to the E2E CD latency already captured by `measure_cd.sh` — both are a git-ops-lab commit followed by Argo CD sync and pod rollover. The only meaningfully different rollback path (Argo CD native `argocd app rollback`) is not comparable across stacks. The thesis will treat rollback as a qualitative process difference: GitOps rollback is a git revert (auditable, PR-reviewable), Jenkins rollback requires re-triggering the full CI pipeline.
- *22.04.2026* - Synchronisation latency metric scrapped. With webhooks configured on both pull-based stacks, the measured value reflects GitHub's webhook delivery latency (network round-trip to AKS Poland Central), not CD tool behaviour. Argo CD and Flux would produce near-identical results with no tool-attributable signal. To be noted in the thesis as a qualitative observation: pull-based tools achieve near-instantaneous detection when webhooks are configured.
- *21.04.2026* - Due to the fact that the webhooks are not available on the local environment switch to Azure AKS has been made.