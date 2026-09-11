# ADR-019: Argo Rollouts Canary Strategy + progressDeadlineAbort for Automatic Rollback

## Status
Accepted, implemented, verified (Phase 11)

## Context
Atlas needed progressive delivery for atlas-api: gradual traffic shift on
new deploys, with automatic rollback on failure. Atlas has no service mesh
or Ingress controller (explicitly out of scope per the "no Istio" project
boundary), so canary + stable ReplicaSets sharing the same existing
atlas-api Service was the only fit -- Kubernetes' own round-robin endpoint
selection approximates the weight (not exact traffic percentages, but
adequate for this architecture).

For automated rollback, Argo Rollouts' Prometheus metric provider (to wire
an AnalysisTemplate against the same GMP endpoint already used by KEDA) was
investigated and verified via web search to NOT support GCP Workload
Identity -- its only native auth options are AWS SigV4 or OAuth2
client-credentials, neither of which maps cleanly onto GCP service account
IAM without inventing an artificial OAuth2 client. That was judged
over-engineering for this project's scope.

## Decision
Use Argo Rollouts' native `progressDeadlineSeconds` + `progressDeadlineAbort: true`.
If canary pods fail to become Ready (via the existing /ready and /health
probes) within the deadline, Argo Rollouts automatically aborts and reverts
100% of traffic to stable -- zero external metrics infrastructure required.

Canary steps: setWeight 10 -> pause 30s -> setWeight 25 -> pause 30s ->
setWeight 50 -> pause 30s -> setWeight 100. progressDeadlineSeconds: 120.

## Consequences
- No dependency on GMP/Prometheus query latency or availability for rollback
  decisions -- rollback is based purely on pod readiness, which is fast and
  reliable.
- Trade-off: rollback triggers only on readiness/liveness failure, not on
  business-level signals (error rate, latency degradation) that a
  Prometheus-based AnalysisTemplate could catch. If a future need for
  KPI-based rollback gates arises, an OAuth2 client-credentials identity
  provider (not native GCP IAM) would be required -- deferred, not blocking.
- Workload Identity binding for a rollouts-metrics GSA was set up in advance
  of this decision and is currently unused; left in place as low-risk,
  flagged as removable if minimizing surface area becomes a priority.

## Evidence
Real deliberate-break test (Phase 11 Step 6, see INCIDENT-006): a genuine
500-returning /ready endpoint was shipped through the full CI/CD pipeline.
Argo Rollouts detected the canary ReplicaSet's readiness failure, waited out
progressDeadlineSeconds, and automatically aborted -- measured
detection-to-abort latency: 129 seconds (injection-to-abort, git push to
automatic abort), consistent with the 120s deadline plus normal reconcile
overhead. Traffic never left the stable ReplicaSet during the entire
episode (confirmed via `status.stableRS` and a health check returning 200
throughout). Full recovery to Healthy on the corrected image was confirmed
afterward.
