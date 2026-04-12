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
Local Rancher Desktop single node cluster.
Each setup runs on a plain restored cluster.

Running on single node is a constraint. We cannot test the node-failover scenarios. This has to be presented as a boundary of the reasearch and an idea for future expansion.

## Measured metrics
Some metrics cannot be measured the same accross the pull and push based setups which should highlight the advantages of the specific approach.
#### End to end deployment
Measure the time between the commit and the finish of the pod startup.
#### Synchronisation latency
Measure the time between the commit and the detection of state change by the tool.
#### Self healing latency
Measure the time between the `kubectl edit` and reversion of the configuration drift.
#### Rollback time 
Measure how fast a bad deployment can be reverted.
#### Failed deployment detection time
Measure the time after which the tool will detect that the deployment failed.
#### Resource consumption
Measure CPU and Memory footprint of both tools.
#### Operational complexity
Describe steps and structure of each configuration approach. 
*Not a quantitive result, however it's still worth considering in the thesis*
#### Failure recovery
Measure the time between killing the pod and reconsiliation of the tool.


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
Business logic lives in `app/backend/calculator.go` and is covered by `app/backend/calculator_test.go` (20 tests). Tests run as part of the Docker build (`go test ./...`) and will be executed by the GitHub Actions CI pipeline.

#### Structure
```
app/
  backend/
    main.go             — entry point, CORS middleware
    handlers.go         — HTTP handlers
    store.go            — thread-safe in-memory state
    calculator.go       — pure business logic functions
    calculator_test.go  — unit tests
    Dockerfile          — multi-stage build; runs tests before producing binary
  frontend/
    index.html          — single-page UI
    app.js              — vanilla JS, no dependencies
    nginx.conf          — serves static files, proxies /api to backend
    Dockerfile
  k8s.yaml              — Namespace, Deployments, Services (namespace: budget-tracker)
  deploy.sh             — builds images, applies manifests, waits for rollout
```

#### Running locally on Rancher Desktop
```bash
./app/deploy.sh            # uses git short hash as version
./app/deploy.sh 1.0.0      # explicit version
```
Frontend is exposed as a `LoadBalancer` service on port `8080`.
Backend is `ClusterIP` only — reachable inside the cluster as `http://backend:8080`.

#### Kubernetes namespace
All resources are deployed to the `budget-tracker` namespace.
