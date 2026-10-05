# Atlas: Distributed Resilience Platform

Atlas is a distributed workload execution platform on Google Kubernetes Engine. I built it to answer one question with measurements instead of claims: what actually happens when parts of the system fail?

**Status:** Phases 0-12 and 14-18 are complete and documented. Phase 13 (multi-region) was designed in [ADR-001](docs/decisions/ADR-001-multi-region-topology.md) and deliberately deferred in [ADR-018](docs/decisions/ADR-018-followup-phase13-deferred.md). Nothing in this repository claims multi-region behavior. Every number below comes from a recorded experiment, and the linked document holds the evidence.

This is not an AI/ML project. There is no model serving, GPU workload, or AI service anywhere in it.

---

## Engineering Problem

A client submits a job with a payload and resource requirements. The platform has to decide which worker can run it without exceeding that worker's capacity, run it, retry it on failure, and keep doing all of that correctly while workers, nodes and deployments fail underneath it.

Running a job is the easy part. The hard part is staying correct and recoverable while capacity and infrastructure state keep changing.

---

## Architecture
client
| POST /jobs
v
atlas-api Flask, delivered as an Argo Rollouts canary
| enqueue job + W3C trace context
v
Redis atlas:queue:pending
|
v
atlas-scheduler capacity-aware best-fit, atomic capacity reservation
| assign, or requeue when no worker has room
v
Redis atlas:queue:worker:<worker-id>
|
v
atlas-worker 2 to 10 replicas (KEDA), 3 attempts then dead-letter

| Component | Notes |
|---|---|
| atlas-api | Port 8080 on the pod, port 80 on the Service. Routes: `/health`, `/ready` (checks Redis), `POST /jobs`, `GET /jobs/{id}`, `/metrics`. |
| atlas-scheduler | Single-threaded loop. Metrics on :9090, no HTTP health route. |
| atlas-worker | Reports its own capacity in memory (not cgroup metrics). Metrics on :9090. |
| Redis | Single instance, no persistence, no auth. Accepted single point of failure ([ADR-005](docs/decisions/ADR-005-workload-platform-design.md)); the consequence is measured below. |

| Layer | What is used |
|---|---|
| Infrastructure | Terraform (GCS state, no keys), zonal GKE, Artifact Registry |
| Delivery | GitLab CI, Argo CD in core mode, Argo Rollouts canary (10/25/50/100) |
| Autoscaling | KEDA on the scheduler requeue rate, workers 2 to 10 |
| Observability | Google Managed Prometheus, Grafana, OpenTelemetry to Cloud Trace, four Cloud Monitoring alert policies |
| Security | Workload Identity, WIF, RBAC, NetworkPolicy default-deny, Kyverno admission policies, CI scanning |

---

## The Failure That Shaped the Scheduler

I found this one by testing, not by reading code. ([INCIDENT-001](docs/incidents/INCIDENT-001-scheduler-capacity-race.md))

**Symptom.** Under concurrent scheduling, a worker could be handed more jobs than it had room for.

**Root cause.** Workers reported capacity through a periodic heartbeat. Between heartbeats the scheduler was deciding against stale numbers, so two jobs could be assigned to a worker that had room for one.

**Fix.** The scheduler now reserves capacity atomically (a Redis `HINCRBY`) at the moment of assignment, before the decision is committed.

**Verification.** The same scenario that exposed the race was run again after the fix.

---

## Reliability Evidence

| Scenario | Outcome | Evidence |
|---|---|---|
| Scheduler capacity race | Found, fixed with atomic reservation, re-tested | [INCIDENT-001](docs/incidents/INCIDENT-001-scheduler-capacity-race.md) |
| GitOps drift | Worker manually scaled to 3 outside Git; Argo CD had reverted it by the first check at 3 s | [drift evidence](docs/reliability/gitops-drift-reconciliation-evidence.md) |
| Bad deployment | Broken readiness check shipped; rollout aborted on its own and traffic stayed on the stable version. 125 s from injection to Degraded | [ADR-019](docs/decisions/ADR-019-argo-rollouts-canary-progressdeadlineabort.md), [INCIDENT-006](docs/incidents/INCIDENT-006-rollback-test-tooling-and-result.md) |
| Malformed job payload | A bare-string payload crashed the worker and burned all 3 retries. Found, fixed with explicit validation, verified live | `workloads/worker/main.py` |
| Pod failure | One of two API pods deleted. Detected in about 2 s, restored in 12 s | [experiment 001](chaos/experiment-001-pod-failure-atlas-api.md) |
| Node drain | Node cordoned and drained. 132 s, PodDisruptionBudgets respected | [experiment 002](chaos/experiment-002-node-drain.md) |
| Redis down | Three attempts, two invalid (see below). The valid run held Redis at zero pods for 66 s and exposed silent job loss | [experiment 003](chaos/experiment-003-redis-dependency-down.md) |
| Distributed tracing | One trace across API, queue, scheduler and worker, with context carried inside the job record | [ADR-014](docs/decisions/ADR-014-opentelemetry-tracing.md) |
| GCP identity | Org policy blocks service-account key creation. Terraform uses impersonation. CI uses Workload Identity Federation | [ADR-002](docs/decisions/ADR-002-terraform-state-and-identity.md), [ADR-008](docs/decisions/ADR-008-gitlab-gcp-workload-identity-federation.md) |

The full table is in [failure-matrix.md](docs/reliability/failure-matrix.md).

---

## Failure Catalogue

**Scheduler.** Capacity reservation race, fixed with atomic reservation.

**Worker.** Malformed payload raised `AttributeError` on every attempt. It now fails fast with a clear error instead of consuming retries.

**Redis.** No persistent volume, so any pod replacement silently discards all in-flight job state, and the API has already returned 202. This is worse than "briefly unreachable". Two earlier test attempts were invalid and are kept in the record: the first measured Argo CD self-healing the scale-to-zero in about a second, the second was defeated because NetworkPolicies are additive, so an existing allow rule cancelled my deny.

**Autoscaling.** My first KEDA signal was Redis queue length. It never moved, because the scheduler drains the pending queue in milliseconds. The signal is now the scheduler's requeue rate, which directly means "no worker had capacity".

**Deployment.** The rollback test took three attempts. The Argo Rollouts CLI plugin was not installed, and `kubectl set image` does not work against custom resources. `kubectl patch` did. Argo CD's selfHeal also reverts direct patches, so auto-sync has to be paused for such a test. ([INCIDENT-006](docs/incidents/INCIDENT-006-rollback-test-tooling-and-result.md))

**Node pool.** A machine-type change stalled for 1 to 2 hours because single-replica Deployments sat behind PodDisruptionBudgets that allowed zero disruptions. Fixed by running two replicas, and confirmed by a clean drain in experiment 002. ([INCIDENT-003](docs/incidents/INCIDENT-003-node-pool-upgrade-pdb-stall.md))

**First deploy.** Image pulls failed until the node pool's own service account got `artifactregistry.reader`, and a regional SSD quota blocked a third node. ([INCIDENT-002](docs/incidents/INCIDENT-002-node-pool-image-pull-and-quota.md))

**Dependencies.** `setuptools` 82 removed `pkg_resources`, which the OpenTelemetry Flask instrumentation imports. My first fix had no upper bound and resolved to 84.0.0, which also lacks it. Pinned below 82. ([INCIDENT-004](docs/incidents/INCIDENT-004-setuptools-pkg-resources.md))

**Delivery.** The GitLab to GitHub sync pushed blindly and lost races against manual pushes. It now fetches and rebases first. ([INCIDENT-005](docs/incidents/INCIDENT-005-gitops-sync-race-and-rollback-proof.md))

**CI capacity.** GitLab shared-runner minutes ran out. CI now runs on a self-hosted runner on a separate GCE VM. It is outside the cluster on purpose: the builds need privileged Docker-in-Docker, which the cluster's Kyverno policy correctly refuses.

**Install order.** Third-party CRDs over the annotation size limit fail under plain `kubectl apply` while the controller still looks healthy. They need `--server-side`. The Rollouts CRDs also have to be installed before the Helm release that creates a `Rollout`; `scripts/startup.sh` is ordered accordingly.

**Observability.** Grafana has no persistent volume, so a pod reschedule wipes its token and datasource. This happened twice and was recovered by hand. A counter can also be correct at a pod's `/metrics` for minutes while Google Managed Prometheus still reads zero, which is backend ingestion lag, not a bug.

---

## Delivery Path and Identity
commit
|
v
GitLab CI: test, lint, SAST, dependency scan, IaC scan,
build x3, image scan, push, gitops-update
|
v
helm/atlas-platform/values.yaml image tag bumped, synced to GitHub
|
v
Argo CD (automated, selfHeal) --> Argo Rollouts canary 10 / 25 / 50 / 100

GitLab CI
| Workload Identity Federation (OIDC, scoped to this project and branch)
v
GCP identity --> Artifact Registry

Terraform
| service account impersonation
v
GCP APIs

An organization policy blocks service-account key creation, so there is no static GCP credential in this project. `gcloud iam service-accounts keys list --managed-by=user` on the Terraform service account returns zero keys. There is one deliberate static secret: the scoped GitHub token CI uses to push to GitHub ([ADR-011](docs/decisions/ADR-011-github-gitlab-sync.md)).

---

## Observability and SLO Measurement Integrity

| SLI | Alert threshold |
|---|---|
| API availability | success rate below 99.5% |
| API latency | p95 above 100 ms |
| Scheduling latency | p95 above 50 ms |
| Job success rate | below 99% |

Targets and reasoning are in [ADR-015](docs/decisions/ADR-015-slo-definitions.md). Two of the alerts fired during load testing and recovered on their own.

Baselines came from about 21 jobs: API latency around 5 ms flat, scheduling p50/p95/p99 about 7.5 / 9.75 / 9.95 ms. That is a small, low-volume sample and should be read that way.

While collecting the baseline, job success rate read about 13%. I traced it by inspecting job records in Redis directly. Several manual test commands had submitted a bare string as the payload, and the worker crashed on each one. I fixed the worker, and the baseline above was taken from clean data. A measurement that makes the SLO look bad is not discarded because it is inconvenient, and one that makes it look good is not trusted because it is convenient.

---

## Recovery Measurements

| Scenario | Measured | Method | Status |
|---|---:|---|---|
| Bad deployment to automatic abort | 125 s | Real broken image, timestamped | Verified (one timed run) |
| GitOps drift correction | under 3 s | Manual scale, first check at 3 s | Verified |
| Pod failure, detect / recover | about 2 s / 12 s | Pod deleted | Verified |
| Node drain | 132 s | Cordon and drain | Verified |
| Redis at zero pods | 66 s, with job state lost | Argo CD sync paused, pods confirmed at 0 | Verified |
| Regional failover | not measured | Phase 13 deferred | Not done |

---

## Security

Implemented: namespace-scoped RBAC, Workload Identity, Workload Identity Federation, NetworkPolicy with default-deny and explicit allows, three Kyverno policies enforced at admission (resource requests and limits, no `:latest` tags, no privileged containers), SAST and dependency, IaC and image scanning in CI, and a written [threat model](docs/security/threat-model.md).

Admission control was tested for real: a pod without resource limits was rejected at the API server.

Gaps, stated plainly: the Atlas API has no authentication and relies on NetworkPolicy alone. Redis has no auth. Secret Manager is not used.

---

## FinOps

Two nodes of `e2-standard-4` cost $0.2680/hour, or $195.67/month, using list prices pulled from the Cloud Billing Catalog API. Attribution by namespace applies those prices to resource requests measured by OpenCost. OpenCost's own pricing downloader failed with a known upstream permission bug, so its cost totals are not used. A fixed versus autoscaled cost comparison has not been run. Details: [cost-attribution.md](docs/finops/cost-attribution.md).

---

## Atlas Operator

`operator/` is a Flutter Android app for viewing and operating Atlas. It is a client of a small backend, `operations-api/` (FastAPI), not a second infrastructure platform. It is an early, partial interface and not a finished operations console.

**Real device verification.** Verified on 2026-09-20 with a real Android phone against the cluster backend:
Healthy
|
Backend scaled to 0
|
Failed
|
Backend restored to 1
|
Healthy

Also verified: `flutter analyze` clean, 24 tests passing, CI passing on the self-hosted GitLab runner.

**Current implementation boundary**

- The connection and health check is backed by the live Operations API.
- Every other screen uses fixture data and is labeled as such.
- Authentication is not implemented.
- Temporary external exposure used for device testing was torn down.
- The app does not run `terraform apply` or `destroy`, by design.

---

## Production-Shaped, Not Production-Claimed

Atlas uses production practices: GitOps, workload identity, RBAC, NetworkPolicy, admission policy, SLOs with alerting, automated rollback, distributed tracing, cost attribution and chaos testing. It is an independently built engineering system, not infrastructure serving customers.

Out of scope by design: simultaneous failure of multiple regions, a GCP control-plane outage, Byzantine workers, and a custom distributed database. Multi-region itself is designed but not built.

---

## Known Limitations

- Redis is a single instance with no persistence, so a pod replacement loses in-flight jobs. The next fix is a persistent volume with AOF.
- The scheduler is a single-threaded loop, which is the likely throughput ceiling.
- Worker capacity is self-reported, not measured from cgroups.
- No authentication on the Atlas API or Redis.
- Grafana state is not persistent and its recovery is not automated.
- Autoscaling is configured and READY, but a fixed versus autoscaled cost run has not been done.
- Regional failover has not been built or measured.

---

## Build Status

| Phases | Focus | Status |
|---|---|---|
| 0-3 | Scaffold, Terraform bootstrap, network and GKE, Artifact Registry, Workload Identity, RBAC | Complete |
| 4-6 | Workload platform, Helm deployment, GitLab CI/CD | Complete |
| 7-9 | GitOps, observability, SLOs and alerting | Complete |
| 10-11 | KEDA autoscaling, canary delivery and rollback | Complete |
| 12 | Security hardening and policy-as-code | Complete |
| 13 | Multi-region | Deferred |
| 14-15 | Chaos experiments, incident consolidation | Complete |
| 16-17 | Load testing, FinOps | Complete |
| 18 | Documentation and retrospective | Complete |

---

## Repository Layout
terraform/ modules and environments (GCS backend, impersonation)
helm/ atlas-platform chart
gitops/ Argo CD Application and AppProject
workloads/ api, scheduler, worker, shared job model
operations-api/ FastAPI backend for the Operator app
operator/ Flutter Android app
observability/ dashboards and alert policies
policies/ Kyverno policies
security/ security configuration
chaos/ experiments with hypothesis, blast radius, outcome
scripts/ startup.sh and teardown.sh
docs/ decisions, incidents, reliability, runbooks, security, finops

## Documentation

- Decisions: [docs/decisions/](docs/decisions/) (ADR-001 to ADR-019)
- Incidents: [docs/incidents/](docs/incidents/) (INCIDENT-001 to INCIDENT-006)
- Chaos experiments: [chaos/](chaos/)
- Failure matrix: [docs/reliability/failure-matrix.md](docs/reliability/failure-matrix.md)
- Load test: [docs/reliability/load-test-phase16.md](docs/reliability/load-test-phase16.md)
- Runbooks: [full-recovery](docs/runbooks/full-recovery.md), [session startup and shutdown](docs/runbooks/session-startup-shutdown.md)
- Retrospective: [docs/RETROSPECTIVE.md](docs/RETROSPECTIVE.md)

## Running It

`scripts/startup.sh` builds the environment and pauses for plan confirmation before any `terraform apply`. `scripts/teardown.sh` only prints the destroy plan and never applies it. The cluster costs roughly $0.27/hour while up and is torn down between sessions.
