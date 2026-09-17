# Atlas Operator — Architecture Overview

## Layers

    Flutter UI (widgets)
         ↓
    State layer (Riverpod StateNotifiers)
         ↓
    Repository interfaces (abstract — one per capability domain)
         ↓
    ┌─────────────┴─────────────┐
    OfflineDataSource        LiveDataSource
    (Hive fixtures)          (HTTP client → Operations API,
                               port-forwarded in dev/INTEGRATION)

## Why Riverpod
Eight feature domains (overview, deployments, workloads, observability,
reliability, diagnostics, incidents, audit) each need the same
loading/data/error/stale state shape. That's more than the "three
concrete cases" threshold for justifying an abstraction (build rule 37).

Alternative considered: plain `ChangeNotifier` + `Provider`.
Rejected: Riverpod's compile-time safety catches a missing provider at
build time instead of runtime, and its `AsyncNotifier` maps directly
onto the Loading/Data/Error/Stale state model this app needs everywhere.

## Why a repository interface per domain (not one big API client)
Because Atlas's real capabilities are NOT uniform:
- Jobs: real HTTP API today (`/jobs`, `/jobs/{id}`)
- Component health: HTTP for `atlas-api` only; k8s pod status for
  scheduler/worker/redis (no HTTP health route exists there)
- Deployments: k8s API (Rollout object) + Git log — no Argo API exists
  (Argo CD runs in core mode, confirmed no `argocd-server` pod)
- Incidents/chaos: static markdown files, not an API at all

One repository interface per domain lets each implementation reflect
its real, different backing source instead of pretending they're
uniform REST resources.

## Environment modes
`OFFLINE`, `INTEGRATION`, `LIVE` — see state-model.md. The app never
silently switches between them; the active mode is always visible in
the UI chrome.
