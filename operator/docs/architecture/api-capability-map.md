# API Capability Map

This defines what the Operations API (not yet built — separate phase)
must expose, grounded only in verified Atlas facts. Nothing here is
invented ahead of evidence.

| Capability | Real Atlas source | Status |
|---|---|---|
| Job submission/status | `atlas-api` `/jobs`, `/jobs/{id}` (port 80 → 8080) | VERIFIED |
| API health | `atlas-api` `/health`, `/ready` | VERIFIED |
| Scheduler/worker health | No HTTP route. Must derive from k8s pod status or metrics (`atlas_scheduler_live_workers`, `atlas_worker_jobs_executed_total`) | VERIFIED (derived only) |
| Redis health | No HTTP. `redis-cli PING` only, or infer from `/ready` | VERIFIED (derived only) |
| Metrics query | GMP Prometheus-compatible endpoint, `monitoring.googleapis.com`, requires GCP OAuth server-side | VERIFIED |
| Deployment history | k8s Rollout object (confirmed: no `argocd-server` pod exists — Argo CD is core-mode, k8s API only) + Git log of `values.yaml` + Artifact Registry | VERIFIED |
| SLO status | Cloud Monitoring Alert Policies (4 real policies) | VERIFIED |
| GitOps sync status | k8s API read of Argo CD `Application` CR (no Argo REST API exists) | VERIFIED |
| Incidents / chaos docs | Static markdown in repo | VERIFIED (static, not live) |
| Mutating actions (rollback, restart, etc.) | NONE implemented | BLOCKED — Argo CD selfHeal reverts direct patches in <3s; any write path must go through Git → CI → Argo CD, not designed yet |
| Multi-region anything | Does not exist (Phase 13 deferred) | OUT OF SCOPE |

## Operational constraints on the future Operations API pod
- Must declare CPU/memory requests AND limits on every container, or
  Kyverno's `require-resource-requests-limits` policy rejects it at
  admission (confirmed live and enforcing).
- Needs an explicit NetworkPolicy allow rule to reach `atlas-api` —
  default-deny means silent timeout, not a clean auth error, if missed.
- Must hold GCP credentials itself (Workload Identity) — the mobile
  client must never receive a GCP token directly.
