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

#### Frontend
nginx serving static content. Calls the backend API and displays the response.

#### Backend
Lightweight HTTP service exposing:
- `/health` — readiness probe endpoint
- `/api/data` — returns version and timestamp

No database. Both services are intentionally minimal to keep build times fast and measurements consistent. Application startup time should not be the differentiating factor — CD tool performance is.

Deployment is considered complete when both pods pass their readiness probes.
