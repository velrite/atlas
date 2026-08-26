# Atlas — Distributed Resilience Platform

Atlas is a production-shaped distributed workload execution platform built on
Google Cloud, designed to demonstrate — with real measurements, not claims —
that a system can continue operating correctly while parts of it fail.

**Status: IN PROGRESS.** This repository is being built incrementally and
publicly. Sections describing unfinished capability are marked as such.
Nothing in this repo is claimed complete until it has been verified and
documented with evidence (metrics, logs, or experiment results).

## What Atlas Does

A client submits a workload (a unit of work with resource requirements,
priority, and a retry policy). Atlas queues it, schedules it onto available
capacity across a distributed pool of workers running on Google Kubernetes
Engine, executes it, and reports the result — while continuing to function
correctly through worker failures, node failures, bad deployments, and
(eventually) simulated regional outages.

This is **not** an AI/ML project. There is no model serving, no GPU workload,
and no AI service anywhere in this platform. The subject under test is
distributed systems and site reliability engineering.

## What This Project Demonstrates

- Distributed workload scheduling (queue → scheduler → worker, with real
  capacity-based decisions, not round robin)
- Infrastructure as Code (Terraform) across environments
- Kubernetes/GKE operated with production concerns: RBAC, Workload Identity,
  NetworkPolicy, PodDisruptionBudgets, resource governance
- GitOps deployment via Argo CD, including deliberate drift + reconciliation
- CI/CD via GitLab CI/CD (connected as a CI/CD-only project against this
  GitHub repository) covering test, lint, security scanning, build, and
  GitOps-triggered deployment
- Observability via Prometheus, Grafana, and OpenTelemetry distributed tracing
  across the full request path
- SLO engineering: SLIs chosen and justified from real baseline measurements,
  not assumed targets
- Progressive delivery (canary) with automatic rollback on SLO/health breach
- Automated failure recovery: detection → decision → remediation →
  verification, evidenced with timestamps
- Multi-region resilience (active/active), with measured RTO/RPO from
  controlled failover experiments
- Chaos engineering experiments with hypotheses, blast radius definitions,
  and documented outcomes — including experiments that did not go as expected
- Security: least-privilege IAM, Workload Identity, RBAC, Secret Manager,
  NetworkPolicy, image/dependency/IaC scanning, policy-as-code admission
  control, and a written threat model
- FinOps: cost attribution by namespace/workload, and a measured comparison
  of fixed vs autoscaled capacity cost

## What Atlas Explicitly Does Not Do

- No AI, ML, GPU workloads, or AI services of any kind
- Does not attempt to survive simultaneous total failure of both regions
- Does not attempt to survive GCP-wide control-plane outages
- Does not defend against malicious/Byzantine worker behavior
- Does not implement a distributed database — workload state uses managed
  GCP primitives rather than a hand-built consensus system

Scoping these out deliberately is documented, not an oversight.

## Repository Structure
atlas/
├── terraform/          Infrastructure as Code (modules + environments)
├── kubernetes/         Raw Kubernetes manifests
├── helm/               Helm charts for platform components
├── gitops/             Argo CD Application definitions and GitOps config
├── scheduler/          Job scheduler source code
├── workloads/          API, queue producer/consumer, worker source code
├── observability/      Prometheus/Grafana/OpenTelemetry configuration
├── security/           Threat model, IAM policies, network policies
├── policies/           Policy-as-code definitions (admission control)
├── chaos/              Chaos engineering experiment definitions and results
├── tests/              Automated tests
├── docs/
│   ├── architecture/   System design documents
│   ├── decisions/      Architecture Decision Records (ADRs)
│   ├── reliability/    SLO definitions, error budget policy
│   ├── incidents/      Incident reports from chaos/failure testing
│   ├── runbooks/       Operational runbooks
│   ├── security/       Security documentation
│   └── troubleshooting/ Known issues and resolutions
└── .gitlab-ci.yml      CI/CD pipeline definition
## Build Log

This project is built phase by phase, with each phase documented before the
next begins. See `docs/decisions/` for architecture decisions and
`docs/architecture/` for design documents as they are written.

| Phase | Focus | Status |
|---|---|---|
| 0 | Architecture, requirements, documentation skeleton | In progress |
| 1 | GCP project setup, Terraform bootstrap, cost guardrails | Not started |
| 2 | Network + single-region GKE cluster (dev) | Not started |
| 3 | Artifact Registry, Workload Identity, base RBAC | Not started |
| 4 | Core workload platform (API + Queue + Scheduler + Worker) | Not started |
| 5 | Kubernetes manifests / Helm charts | Not started |
| 6 | GitLab CI/CD pipeline | Not started |
| 7 | GitOps with Argo CD + drift demonstration | Not started |
| 8 | Observability (Prometheus/Grafana/OpenTelemetry) | Not started |
| 9 | SLO definition + burn-rate alerting | Not started |
| 10 | Autoscaling on real signals | Not started |
| 11 | Progressive delivery + automated rollback | Not started |
| 12 | Security hardening + policy-as-code | Not started |
| 13 | Multi-region expansion | Not started |
| 14 | Chaos engineering experiments | Not started |
| 15 | Incident documentation | Not started |
| 16 | Load/capacity testing | Not started |
| 17 | FinOps cost attribution | Not started |
| 18 | Final documentation pass | Not started |

## Infrastructure Note

This project runs on Google Cloud Platform under a billing account with
active budget alerts. Infrastructure that incurs cost is documented at the
point it is created, including expected cost drivers, and is destroyed
between work sessions where noted in the relevant phase's documentation.
