# ADR-019: Argo Rollouts Canary Strategy + progressDeadlineAbort for Automated Rollback

## Status
Accepted

## Context
Phase 11 required progressive delivery with automated rollback for atlas-api.
Atlas has no service mesh or Ingress controller (explicit "no Istio" project
boundary), so canary and stable ReplicaSets share the same existing atlas-api
Service, relying on Kubernetes' own endpoint round-robin to approximate
traffic weighting rather than exact percentage-based routing.

Argo Rollouts' Prometheus AnalysisTemplate provider was evaluated for
automated rollback wired to the same GMP endpoint KEDA already uses (Phase
10). Verified via web search: this provider only supports AWS SigV4 or
OAuth2 client-credentials auth, neither of which maps onto GCP IAM /
Workload Identity without inventing an artificial OAuth2 client - judged as
over-engineering for this project's scope.

## Decision
Use Argo Rollouts' native `progressDeadlineSeconds` (120s) +
`progressDeadlineAbort: true` instead. Real readiness probes already exist
at /ready and /health. If canary pods never become Ready within the
deadline, Argo Rollouts automatically aborts and reverts 100% of traffic to
stable - zero external metrics infrastructure required.

## Consequences / Real Operational Findings
- Direct `kubectl set image` against a Rollout resource fails with
  `no kind "Rollout" is registered for version "argoproj.io/v1alpha1"` -
  this command requires the target kind to exist in kubectl's typed client
  scheme, which does not include CRDs. `kubectl patch` (JSON patch, via the
  dynamic/unstructured client) works correctly against any CRD and is the
  correct tool for direct Rollout manipulation outside GitOps.
- The `kubectl argo rollouts` plugin is not installed by default in a fresh
  Cloud Shell session and does not persist across resets.
- Argo CD's selfHeal will revert a direct kubectl-level change back to the
  Git-declared state almost immediately. Any direct injection test against
  a GitOps-managed resource must first null out `spec.syncPolicy` on the
  Application, run the test, then explicitly restore both live state and
  syncPolicy.
- Real test result (this run): broken image
  `us-central1-docker.pkg.dev/velrite-tf-test/atlas-images/atlas-api:615f63af`
  was patched directly into the Rollout with auto-sync disabled. Final
  observed Rollout phase: **Degraded**. Detection-to-abort
  latency: **125 seconds** (see INCIDENT-006 for full detail).
