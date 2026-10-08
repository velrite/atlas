# Atlas: Distributed Resilience Platform

Atlas is a distributed workload execution platform on Google Kubernetes Engine. I built it to answer one question with measurements instead of claims: what actually happens when parts of the system fail?

**Status:** Atlas phases 0-12 and 14-18 are complete and documented. Phase 13 (multi-region) was designed in [ADR-001](docs/decisions/ADR-001-multi-region-topology.md) and deliberately deferred in [ADR-018](docs/decisions/ADR-018-followup-phase13-deferred.md). Nothing in this repository claims multi-region behavior. Atlas Operator, a mobile app built later, is a separate and smaller body of work with its own section below. Every number comes from a recorded experiment, and the linked document holds the evidence.

This is not an AI/ML project. There is no model serving, GPU workload, or AI service anywhere in it.

---

## Engineering Problem

A client submits a job with a payload and resource requirements. The platform has to decide which worker can run it without exceeding that worker's capacity, run it, retry it on failure, and keep doing all of that correctly while workers, nodes and deployments fail underneath it.

Running a job is the easy part. The hard part is staying correct and recoverable while capacity and infrastructure state keep changing.

---

## Architecture

    client
      |  POST /jobs
      v
    atlas-api            Flask, delivered as an Argo Rollouts canary
      |  enqueue job + W3C trace context
      v
    Redis                atlas:queue:pending
      |
      v
    atlas-scheduler      capacity-aware best-fit, atomic capacity reservation
      |  assign, or requeue when no worker has room
      v
    Redis                atlas:queue:worker:<worker-id>
      |
      v
    atlas-worker         2 to 10 replicas (KEDA), 3 attempts then dead-letter

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

**Delivery sync.** The GitLab to GitHub sync pushed blindly and lost races against manual pushes. It now fetches and rebases first. ([INCIDENT-005](docs/incidents/INCIDENT-005-gitops-sync-race-and-rollback-proof.md))

**CI capacity.** GitLab shared-runner minutes ran out. CI now runs on a self-hosted runner on a separate GCE VM, outside the cluster on purpose: the builds need privileged Docker-in-Docker, which the cluster's Kyverno policy correctly refuses. Getting it working took two more fixes: the runner carried a tag, so it ignored untagged jobs until `run_untagged` was enabled, and GitLab kept sending jobs to the exhausted shared pool until shared runners were disabled for the project through the API. ([ADR-002 Operator](docs/adr/ADR-002-self-hosted-ci-runner.md))

**Rebuild from empty.** After a teardown the image registry is empty and `values.yaml` pointed at an image that no longer existed (plus a duplicate `tag:` key), so pods sat in ImagePullBackOff until images were rebuilt and the tag was fixed.

**Install order.** Third-party CRDs over the annotation size limit fail under plain `kubectl apply` while the controller still looks healthy. They need `--server-side`. The Rollouts CRDs also have to be installed before the Helm release that creates a `Rollout`, and the manifest has no namespace of its own: without `-n argo-rollouts` the controller landed in `default` and never reconciled anything. `scripts/startup.sh` is changed accordingly, and that change is not yet proven by a full fresh run (see limitations).

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
       |  Workload Identity Federation (OIDC, scoped to this project and branch)
       v
    GCP identity --> Artifact Registry

    Terraform
       |  service account impersonation
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

Targets and reasoning are in [ADR-015](docs/decisions/ADR-015-slo-definitions.md). Two of the alerts fired during burst testing and recovered on their own.

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

Implemented: namespace-scoped RBAC, Workload Identity, Workload Identity Federation, NetworkPolicy with default-deny and explicit allows, three Kyverno policies enforced at admission (resource requests and limits, no `:latest` tags, no privileged containers), SAST plus dependency, IaC and image scanning in CI, and a written [threat model](docs/security/threat-model.md).

Admission control was tested for real: a pod without resource limits was rejected at the API server. That was demonstrated on the original cluster. `scripts/startup.sh` does not install Kyverno, so a rebuilt cluster has these policies only if they are applied again by hand.

Gaps, stated plainly: the Atlas API has no authentication and relies on NetworkPolicy alone. Redis has no auth. Secret Manager is not used.

---

## FinOps

Two nodes of `e2-standard-4` cost $0.2680/hour, or $195.67/month, using list prices pulled from the Cloud Billing Catalog API. Attribution by namespace applies those prices to resource requests measured by OpenCost. OpenCost's own pricing downloader failed with a known upstream permission bug, so its cost totals are not used. A fixed versus autoscaled cost comparison has not been run. Details: [cost-attribution.md](docs/finops/cost-attribution.md).

---

## Atlas Operator and Operations API

Atlas Operator (`operator/`) is a Flutter Android app for checking on Atlas from a phone. It uses Riverpod for state and a capped Hive cache on the device. Its backend, `operations-api/`, is a small FastAPI service in the cluster that serves only `/health` and `/ready`. The app has three modes shown on a badge in the app bar, which cycles on tap: OFFLINE (fixtures), INTEGRATION (a real call to the Operations API) and LIVE (not connected to anything real yet).

**Verified on a real device**
- In INTEGRATION mode the connection banner went Healthy, then Failed (the backend was scaled to 0 replicas), then Healthy again (scaled back to 1). The sequence is recorded in the Operator incident log as INCIDENT-009.
- The first device attempt failed with `SocketException ... errno = 1`. Cause: the main Android manifest had no `INTERNET` permission. The debug and profile manifests do have it, which is why a debug build would never have shown the problem. Fixed and recorded as INCIDENT-010.
- `flutter analyze` is clean and 24 tests pass at the last run.
- Recent pipelines ran green. Shared runners are disabled for the project, so the jobs ran on the self-hosted runner.

**Not live, by design**
- Every screen except the connection banner shows offline fixture data (component health, jobs, deployments, diagnostics). Diagnostics shows a FIXTURE DATA label whenever the badge is not OFFLINE, so a LIVE badge can never sit above fixture numbers unlabelled.
- There is no authentication in the app or in the Operations API.
- The Operations API image is not built by CI. It is built and pushed by hand.
- The app can display Atlas but can never run `terraform apply` or `destroy` (Operator [ADR-001](docs/adr/ADR-001-operator-foundation.md)).

**Public exposure used for the device test**
A temporary LoadBalancer put the zero-auth endpoints on the internet for about 34 minutes ([ADR-003](docs/adr/ADR-003-temporary-loadbalancer-for-device-testing.md)). The pod log tail showed automated scanners probing for phpunit, ThinkPHP and Docker API paths, and every probe got a 404. Only the end of the log was read, so this is not a full audit. The Service was deleted straight after, and the temporary cleartext-HTTP flag was removed from the manifest.

**Other real problems from this build:** a test fake that skipped `MockPlatformInterfaceMixin`; a cache write failure that turned a good read into an error; `pumpAndSettle()` hanging on a loading spinner; Cloud Shell's 4.8 GB home disk running out during the first Android build (the SDK moved to `/opt`); and the badge having no tap handler, so INTEGRATION mode could not be entered. All are in [the Operator incident log](docs/incidents/incident-log.md).

To bring it back up: [go-live runbook](docs/runbooks/atlas-operator-go-live.md).

---

## Production-Shaped, Not Production-Claimed

Atlas uses production practices: GitOps, workload identity, RBAC, NetworkPolicy, admission policy, SLOs with alerting, automated rollback, distributed tracing, cost attribution and chaos testing. It is an independently built engineering system, not infrastructure serving customers.

Out of scope by design: simultaneous failure of multiple regions, a GCP control-plane outage, Byzantine workers, and a custom distributed database. Multi-region itself is designed but not built.

---

## Known Limitations

- Redis is a single instance with no persistence, so a pod replacement loses in-flight jobs. The next fix is a persistent volume with AOF.
- The scheduler is a single-threaded loop, which is the likely throughput ceiling.
- Worker capacity is self-reported, not measured from cgroups.
- No authentication on the Atlas API, the Operations API or Redis.
- Grafana state is not persistent and its recovery is not automated.
- Autoscaling is configured, but a fixed versus autoscaled cost run has not been done.
- Regional failover has not been built or measured.
- `scripts/startup.sh` has not been run end to end since its latest fixes. They were checked for syntax and placement only. Reading the script shows step 5 waits on `deployment/atlas-api` although `atlas-api` is a Rollout, which would likely stop a fresh run. That is found by reading, not by running, and it is not fixed yet.
- `startup.sh` does not install Kyverno or KEDA, so a rebuild restores them only if they are applied by hand.
- Operator screens other than the connection banner are fixtures, as described above.

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
| Operator 0-9 | Flutter app, Operations API, real-device connection check | Complete |
| Operator 10+ | Live data endpoints behind the app's other screens | Not started |

---

## Repository Layout

    terraform/        modules and environments (GCS backend, impersonation)
    helm/             atlas-platform chart
    gitops/           Argo CD Application and AppProject
    workloads/        api, scheduler, worker, shared job model
    scheduler/        scheduler source
    operations-api/   FastAPI backend for the Operator app
    operator/         Flutter Android app
    observability/    dashboards and alert policies
    policies/         Kyverno policies
    security/         security configuration
    chaos/            experiments with hypothesis, blast radius, outcome
    scripts/          startup.sh, teardown.sh, generate-docs.sh
    tests/            automated tests
    docs/             decisions, adr, incidents, reliability, runbooks, security, finops
    .gitlab-ci.yml    pipeline definition

## Documentation

Two sets of ADRs and incident numbers exist and they restart at 001:

- Atlas: ADRs in [docs/decisions/](docs/decisions/) (ADR-001 to ADR-019) and incident reports in [docs/incidents/](docs/incidents/) (INCIDENT-001 to INCIDENT-006 files).
- Atlas Operator: ADRs in [docs/adr/](docs/adr/) (ADR-001 to ADR-003) and its log in [docs/incidents/incident-log.md](docs/incidents/incident-log.md), which numbers its entries INCIDENT-001 to INCIDENT-010 separately.

Other documents:

- Chaos experiments: [chaos/](chaos/)
- Failure matrix: [docs/reliability/failure-matrix.md](docs/reliability/failure-matrix.md)
- Load test: [docs/reliability/load-test-phase16.md](docs/reliability/load-test-phase16.md)
- Operator system overview: [docs/architecture/system-overview.md](docs/architecture/system-overview.md)
- Operator security controls: [docs/security/security-controls.md](docs/security/security-controls.md)
- Technical debt: [docs/engineering/technical-debt.md](docs/engineering/technical-debt.md)
- Engineering maturity: [docs/engineering/engineering-maturity.md](docs/engineering/engineering-maturity.md)
- Runbooks: [full recovery](docs/runbooks/full-recovery.md), [session startup and shutdown](docs/runbooks/session-startup-shutdown.md), [Operator go-live](docs/runbooks/atlas-operator-go-live.md)
- Retrospective: [docs/RETROSPECTIVE.md](docs/RETROSPECTIVE.md)

`scripts/generate-docs.sh` regenerates the Operator docs from built-in text. It refuses to run without `--force-overwrite`, because it would revert later hand edits.

## Evidence

These screenshots were captured against the running cluster. [docs/evidence/README.md](docs/evidence/README.md) lists every file in this folder. Screenshots for the Atlas Operator work (Operations API, CI runner, LoadBalancer teardown, Flutter tests) are in [operator/docs/evidence](operator/docs/evidence/README.md). A phone screenshot of the connection banner is not included yet.

Captured so far:

<details>
<summary>Show all 23 screenshots</summary>

**01-cluster-nodes**

<img src="docs/evidence/01-cluster-nodes.png" width="700" alt="cluster nodes">

**02-namespaces**

<img src="docs/evidence/02-namespaces.png" width="700" alt="namespaces">

**03-argocd-application-health**

<img src="docs/evidence/03-argocd-application-health.png" width="700" alt="argocd application health">

**04-canary-rollout-steps**

<img src="docs/evidence/04-canary-rollout-steps.png" width="700" alt="canary rollout steps">

**05-canary-automatic-rollback-incident006**

<img src="docs/evidence/05-canary-automatic-rollback-incident006.png" width="700" alt="canary automatic rollback incident006">

**06-gitlab-pipeline-success**

<img src="docs/evidence/06-gitlab-pipeline-success.png" width="700" alt="gitlab pipeline success">

**07-artifact-registry-image-history**

<img src="docs/evidence/07-artifact-registry-image-history.png" width="700" alt="artifact registry image history">

**08-workload-identity-federation-no-static-keys**

<img src="docs/evidence/08-workload-identity-federation-no-static-keys.png" width="700" alt="workload identity federation no static keys">

**09-networkpolicy-default-deny**

<img src="docs/evidence/09-networkpolicy-default-deny.png" width="700" alt="networkpolicy default deny">

**10-kyverno-real-denial**

<img src="docs/evidence/10-kyverno-real-denial.png" width="700" alt="kyverno real denial">

**11-kyverno-clusterpolicy-status**

<img src="docs/evidence/11-kyverno-clusterpolicy-status.png" width="700" alt="kyverno clusterpolicy status">

**12-poddisruptionbudgets**

<img src="docs/evidence/12-poddisruptionbudgets.png" width="700" alt="poddisruptionbudgets">

**13-chaos-node-drain**

<img src="docs/evidence/13-chaos-node-drain.png" width="700" alt="chaos node drain">

**14-chaos-redis-dependency-down**

<img src="docs/evidence/14-chaos-redis-dependency-down.png" width="700" alt="chaos redis dependency down">

**15-chaos-pod-failure-recovery**

<img src="docs/evidence/15-chaos-pod-failure-recovery.png" width="700" alt="chaos pod failure recovery">

**16-keda-scaledobject-status**

<img src="docs/evidence/16-keda-scaledobject-status.png" width="700" alt="keda scaledobject status">

**19-cloud-monitoring-alert-policies**

<img src="docs/evidence/19-cloud-monitoring-alert-policies.png" width="700" alt="cloud monitoring alert policies">

**19B-cloud-monitoring-alert-policies**

<img src="docs/evidence/19B-cloud-monitoring-alert-policies.png" width="700" alt="cloud monitoring alert policies">

**20-gitops-dual-remote-sync**

<img src="docs/evidence/20-gitops-dual-remote-sync.png" width="700" alt="gitops dual remote sync">

**21-terraform-no-static-keys**

<img src="docs/evidence/21-terraform-no-static-keys.png" width="700" alt="terraform no static keys">

**22-finops-cost-attribution**

<img src="docs/evidence/22-finops-cost-attribution.png" width="700" alt="finops cost attribution">

**23-documentation-index**

<img src="docs/evidence/23-documentation-index.png" width="700" alt="documentation index">

**24-full-platform-health-snapshot**

<img src="docs/evidence/24-full-platform-health-snapshot.png" width="700" alt="full platform health snapshot">

</details>


Atlas Operator screenshots:

<details>
<summary>Show the 12 Atlas Operator screenshots</summary>

**01-cluster-nodes**

<img src="operator/docs/evidence/01-cluster-nodes.png" width="700" alt="cluster nodes">

**02-atlas-platform-workloads**

<img src="operator/docs/evidence/02-atlas-platform-workloads.png" width="700" alt="atlas platform workloads">

**03-atlas-api-rollout-healthy**

<img src="operator/docs/evidence/03-atlas-api-rollout-healthy.png" width="700" alt="atlas api rollout healthy">

**04-argo-rollouts-controller**

<img src="operator/docs/evidence/04-argo-rollouts-controller.png" width="700" alt="argo rollouts controller">

**06-operations-api-live**

<img src="operator/docs/evidence/06-operations-api-live.png" width="700" alt="operations api live">

**07-gitlab-pipeline-passed**

<img src="operator/docs/evidence/07-gitlab-pipeline-passed.png" width="700" alt="gitlab pipeline passed">

**08-self-hosted-runner-online**

<img src="operator/docs/evidence/08-self-hosted-runner-online.png" width="700" alt="self hosted runner online">

**09-networkpolicy-default-deny**

<img src="operator/docs/evidence/09-networkpolicy-default-deny.png" width="700" alt="networkpolicy default deny">

**15-loadbalancer-teardown**

<img src="operator/docs/evidence/15-loadbalancer-teardown.png" width="700" alt="loadbalancer teardown">

**16-ci-security-scans**

<img src="operator/docs/evidence/16-ci-security-scans.png" width="700" alt="ci security scans">

**17-flutter-test-suite-green**

<img src="operator/docs/evidence/17-flutter-test-suite-green.png" width="700" alt="flutter test suite green">

**18-incident-fix-commit**

<img src="operator/docs/evidence/18-incident-fix-commit.png" width="700" alt="incident fix commit">

</details>

## Running It

`scripts/startup.sh` builds the environment and pauses for plan confirmation before any `terraform apply`. `scripts/teardown.sh` only prints the destroy plan and never applies it. The cluster costs roughly $0.27/hour while up and is destroyed between sessions.
