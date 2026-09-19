# System Overview — Atlas + Atlas Operator

## What this is

Atlas is a distributed workload platform running on GKE (project
`velrite-tf-test`, cluster `atlas-dev`, zone `us-central1-a`). It accepts
jobs over an HTTP API, schedules them, and executes them asynchronously.

Atlas Operator is a Flutter mobile application that gives an engineer an
operational view of Atlas from a phone: component health, deployment
history, diagnostics, and (as of Phase 9) a live connectivity check
against a real backend.

Atlas is feature-complete for Phases 0–12 and 14–18. Phase 13
(multi-region) is deliberately deferred (see ADR references below) and is
explicitly out of scope — the mobile app does not claim multi-region
capability it does not have.

## Components

| Component | Role | Health surface |
|---|---|---|
| `atlas-api` | Accepts jobs (`POST /jobs`), reports status (`GET /jobs/{id}`) | `GET /health`, `GET /ready` (HTTP) |
| `atlas-scheduler` | Assigns queued jobs to workers | Prometheus metrics only (`:9090`), no HTTP health |
| `atlas-worker` | Executes jobs | Prometheus metrics only (`:9090`), no HTTP health |
| `redis` | Queue backing store, no PVC | `redis-cli PING` only, no HTTP |
| `operations-api` | New (Phase 8) — Python/FastAPI service that Atlas Operator talks to | `GET /health`, `GET /ready` |

Because each component exposes health differently, Atlas Operator labels
every health reading by its real source (`httpHealthCheck`, `podStatus`,
`metricsInferred`) rather than presenting a false uniform signal.

## Deployment mechanism

- `atlas-api` is deployed as an Argo Rollouts `Rollout` object (canary,
  7 steps, `progressDeadlineAbort` measured at 125s rollback time in
  testing).
- `atlas-scheduler`, `atlas-worker`, `redis` are plain Kubernetes
  `Deployment` objects.
- Argo CD runs in **core mode** — there is no `argocd-server` pod and no
  Argo CD REST API. All Rollout/Application state is read directly from
  the Kubernetes API (`kubectl get rollout ... -o json`), not from an
  Argo CD API.

## Networking

- All Services are `ClusterIP`. There is no Ingress controller and no
  service mesh (deliberate design decision — canary traffic splitting
  uses plain Kubernetes Service round-robin, not a mesh).
- Nothing in the cluster is externally exposed by default. The one
  exception created during Phase 9 device-verification testing was a
  temporary `LoadBalancer` Service placed in front of `operations-api`
  specifically to let a physical Android phone reach it — see
  `docs/incidents/` and `docs/security/security-controls.md` for the
  trade-off this created and why it was torn down after the test.

## Authentication

Atlas's own API has **zero authentication** as of this writing. Access
control is enforced only by Kubernetes `NetworkPolicy` (default-deny with
explicit allow rules). Any new pod that needs to reach Atlas requires its
own explicit `NetworkPolicy` allow rule, or it fails with a silent
timeout rather than a clean auth error — this was a known operational
gotcha carried into the Operations API's own NetworkPolicy design.

## Admission control

Three live Kyverno `ClusterPolicy` objects are enforced on `atlas-dev`:

- `disallow-latest-tag`
- `disallow-privileged-containers`
- `require-resource-requests-limits`

These constraints directly shaped Phase-8/CI decisions — see
`docs/adr/ADR-002-self-hosted-ci-runner.md` for how
`disallow-privileged-containers` ruled out running the CI runner's
Docker-in-Docker builds inside this same cluster.
