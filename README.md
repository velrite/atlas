# Atlas — Distributed Resilience Platform

Atlas is a production-shaped distributed workload execution platform built on Google Cloud, demonstrating — with real measurements, not claims — that a system can continue operating correctly while parts of it fail.

**Status: COMPLETE.** All 18 planned phases are implemented, deployed, and verified. Every capability below has been demonstrated on real infrastructure with real evidence (metrics, logs, traces, or experiment results) — see `docs/decisions/`, `docs/incidents/`, and `docs/reliability/` for the full paper trail behind every claim in this README.

## What Atlas Does

A client submits a workload (a unit of work with resource requirements, priority, and a retry policy). Atlas queues it, schedules it onto available capacity across a distributed pool of workers running on Google Kubernetes Engine, executes it, and reports the result — while continuing to function correctly through worker failures, node failures, bad deployments, and simulated regional outages.

This is **not** an AI/ML project. There is no model serving, no GPU workload, and no AI service anywhere in this platform. The subject under test is distributed systems and site reliability engineering.

## What This Project Demonstrates

- **Distributed workload scheduling** — queue → scheduler → worker, with real capacity-based bin-packing decisions, not round robin. A genuine race condition in the scheduler's capacity accounting was found through testing, root-caused, fixed with an atomic reservation, and re-verified (see `docs/incidents/`).
- **Infrastructure as Code** — Terraform across environments, remote state, keyless service-account impersonation (no static credentials, ever — blocked at the org-policy level and treated as a design constraint, not a workaround).
- **Kubernetes/GKE operated with production concerns** — namespace-scoped RBAC, Workload Identity (node-level and pod-level, deliberately separated), PodDisruptionBudgets, resource governance sized against real allocatable capacity rather than nominal machine specs, and NetworkPolicy.
- **GitOps deployment via Argo CD** — running in core mode, managing the platform declaratively from Git. Deliberate drift was injected (an unauthorized `kubectl scale`) and self-healed in under 3 seconds, measured and documented, not just claimed.
- **CI/CD via GitLab CI/CD** — connected as a CI/CD-only project against this GitHub repository, covering test, lint, SAST, dependency/IaC scanning, build, image scanning, and a fully keyless push to Artifact Registry via GitLab-to-GCP Workload Identity Federation. The loop closes all the way to deployment: a merged commit results in a new image built, scanned, pushed, and automatically deployed via GitOps — no manual `kubectl` or `helm` step anywhere in the path.
- **Observability** via Google Managed Prometheus, Grafana (wired through the GMP datasource-syncer pattern), and OpenTelemetry distributed tracing across the full API → queue → scheduler → worker request path, including trace-context propagation through Redis-mediated handoffs, not just HTTP hops.
- **SLO engineering** — SLIs and error budgets defined from real measured baselines (API latency, scheduling latency, job success rate), with contaminated test data explicitly identified and excluded from the baseline rather than silently accepted, and a genuine platform bug (a worker crashing ungracefully on malformed input) found and fixed as a direct result of baselining honestly.
- **Progressive delivery** — Argo Rollouts canary strategy with automated rollback wired to real health/SLO signals, demonstrated against an actually-broken deployment, not a simulated one.
- **Automated failure recovery** — detection → decision → remediation → verification, evidenced with real timestamps throughout (see `docs/incidents/` for node-drain stalls, image-pull authorization gaps, and capacity race conditions, each independently diagnosed and resolved).
- **Multi-region resilience** (active/active), with measured RTO/RPO from controlled failover experiments, and an explicit, documented decision on cross-region queue architecture rather than an assumed one.
- **Chaos engineering experiments** with hypotheses, blast radius definitions, and documented outcomes — including experiments that did not go as expected, and including at least one experiment run against the live system during video documentation, with a real recovery and a real GitOps drift correction afterward.
- **Security** — least-privilege IAM (every service account scoped to exactly what it needs, verified via `auth can-i` checks rather than assumed), Workload Identity, RBAC, NetworkPolicy, image/dependency/IaC scanning, policy-as-code admission control, and a written threat model covering assets, attack surfaces, trust boundaries, and residual risk.
- **FinOps** — cost attribution by namespace/workload, and a measured comparison of fixed vs. autoscaled capacity cost, backed by real GCP billing data rather than estimates where real data was available.

## What Atlas Explicitly Does Not Do

- No AI, ML, GPU workloads, or AI services of any kind
- Does not attempt to survive simultaneous total failure of both regions
- Does not attempt to survive GCP-wide control-plane outages
- Does not defend against malicious/Byzantine worker behavior
- Does not implement a distributed database — workload state uses managed GCP primitives rather than a hand-built consensus system

Scoping these out is a deliberate, documented decision, not an oversight — see ADR-001 and the final retrospective in `docs/decisions/` for the reasoning.

## Repository Structure

```
atlas/
├── terraform/            Infrastructure as Code (modules + environments)
├── kubernetes/           Raw Kubernetes manifests
├── helm/                 Helm charts for platform components
├── gitops/               Argo CD Application definitions and GitOps config
├── scheduler/            Job scheduler source code
├── workloads/            API, queue producer/consumer, worker source code
├── observability/        Prometheus/Grafana/OpenTelemetry configuration
├── security/             Threat model, IAM policies, network policies
├── policies/             Policy-as-code definitions (admission control)
├── chaos/                Chaos engineering experiment definitions and results
├── tests/                Automated tests
├── scripts-*.sh          Session startup/teardown and CI helper scripts
├── .gitlab-ci.yml        CI/CD pipeline definition
└── docs/
    ├── architecture/      System design documents
    ├── decisions/         Architecture Decision Records (ADRs)
    ├── reliability/       SLO definitions, error budget policy, drift/chaos evidence
    ├── incidents/         Incident reports from real failures and chaos testing
    ├── runbooks/          Operational runbooks (safe startup/shutdown, recovery procedures)
    ├── security/          Security documentation, threat model
    └── troubleshooting/   Known issues and resolutions
```


## Build Log

Atlas was built phase by phase, with each phase documented before the next began. See `docs/decisions/` for the full set of ADRs and `docs/architecture/` for design documents.

| Phase | Focus | Status |
|---|---|---|
| 0 | Architecture, requirements, documentation skeleton | ✅ Complete |
| 1 | GCP project setup, Terraform bootstrap, cost guardrails | ✅ Complete |
| 2 | Network + single-region GKE cluster (dev) | ✅ Complete |
| 3 | Artifact Registry, Workload Identity, base RBAC | ✅ Complete |
| 4 | Core workload platform (API + Queue + Scheduler + Worker) | ✅ Complete |
| 5 | Kubernetes manifests / Helm charts | ✅ Complete |
| 6 | GitLab CI/CD pipeline | ✅ Complete |
| 7 | GitOps with Argo CD + drift demonstration | ✅ Complete |
| 8 | Observability (Prometheus/Grafana/OpenTelemetry) | ✅ Complete |
| 9 | SLO definition + burn-rate alerting | ✅ Complete |
| 10 | Autoscaling on real signals | ✅ Complete |
| 11 | Progressive delivery + automated rollback | ✅ Complete |
| 12 | Security hardening + policy-as-code | ✅ Complete |
| 13 | Multi-region expansion | ✅ Complete |
| 14 | Chaos engineering experiments | ✅ Complete |
| 15 | Incident documentation | ✅ Complete |
| 16 | Load/capacity testing | ✅ Complete |
| 17 | FinOps cost attribution | ✅ Complete |
| 18 | Final documentation pass | ✅ Complete |

## Evidence, Not Claims

Every capability listed above is backed by a document in this repository, not just a description here:

- **ADRs** (`docs/decisions/`) — every major architectural decision, including alternatives considered and trade-offs accepted, updated where later phases superseded earlier choices.
- **Incident reports** (`docs/incidents/`) — every real failure encountered during development, with root cause, remediation, and post-fix verification. These are not hypothetical — they happened during the actual build.
- **Reliability docs** (`docs/reliability/`) — SLO definitions with real measured justification, drift/self-heal evidence with timestamps, chaos experiment results including experiments that revealed real bugs.
- **Runbooks** (`docs/runbooks/`) — the actual, tested procedure for safely tearing down and rebuilding this entire platform, kept current through every phase that changed infrastructure.

## Infrastructure Note

This project runs on Google Cloud Platform under a billing account with active budget alerts. Infrastructure that incurs cost is documented at the point it is created, including expected cost drivers, and is destroyed between work sessions when not actively in use — see `docs/runbooks/session-startup-shutdown.md` for the exact, verified procedure.
