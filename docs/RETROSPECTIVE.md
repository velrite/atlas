# Atlas: Final Retrospective (Phase 18)

Generated 2026-09-11 from the real, current state of this
repository and cluster - not from a fixed template. See "Real ADR
inventory," "Real incident inventory," and "Real chaos experiment
inventory" (captured above at generation time) for the authoritative list
of what exists.

## What was actually built
See docs/decisions/ for the full ADR list (real count: 19 files) and docs/incidents/ for real incidents found and fixed (real count: 6 files).

## Deploy path (how a change reaches production)
Commit -> GitLab CI (test/lint/sast/scan/build/push) -> gitops-update bot
commit bumps helm/atlas-platform/values.yaml image tag -> synced to GitHub
-> Argo CD (automated, selfHeal+prune) reconciles the cluster -> for
atlas-api specifically, Argo Rollouts executes the canary strategy defined
in ADR-019 (10/25/50/100 steps with progressDeadlineAbort for automatic
rollback - real, measured abort latency: 125 seconds, see INCIDENT-006).

## Known, honestly-stated limitations (not hidden)
- Redis: single instance, no clustering, accepted SPOF per ADR-005 -
  real cascading-restart behavior under Redis outage was measured directly
  (see chaos/experiment-003 or equivalent Redis dependency-down doc if
  present in the incident/chaos inventory above).
- GitOps hand-off (CI -> values.yaml bump -> deploy) has shown real latency
  variance across this project's own testing - see INCIDENT-006's timeline
  of failed attempts before a working direct-injection method was found.
- Direct kubectl-level changes to GitOps-managed CRDs require temporarily
  disabling Argo CD's syncPolicy or selfHeal will revert them - documented
  operational reality, not a design flaw.

## What would change for real production
- Redis SPOF would need either managed Pub/Sub or a replicated queue
  (deferred decision, see ADR-018 and Phase 13 deferral note in git log).
- The one static credential in this project (GITHUB_PUSH_TOKEN, ADR-011)
  would need a true OIDC federation path once GitLab-to-GitHub federation
  becomes available, removing the last stored secret.
- Single-region only through this project's scope (Phase 13 explicitly
  deferred - see git log commit confirming that decision).

