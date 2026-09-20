# Engineering Maturity Assessment

An honest, non-promotional read of where this project actually stands.

## Genuinely strong
- Deployment mechanism (Argo Rollouts canary) is real and has been
  exercised, not just configured.
- CI/CD pipeline is real, runs on real infrastructure (a self-hosted
  runner built and debugged during this project), and includes real
  security-scanning stages (`sast`, `dependency-scan`, `iac-scan`,
  `image-scan`).
- Component health is modeled honestly (per-source labeling) rather than
  faked into a uniform "green/red" signal.
- Debugging discipline was consistent: every fix in this log was
  verified with real command output before being called done, not
  assumed.

## Production-shaped but not production-proven
- Argo Rollouts canary and rollback timing (125s) was observed once in
  this environment, not load-tested or repeated across many deploys.
- The four Cloud Monitoring SLO alert policies exist and are live, but
  no external traffic or real user load has validated them against real
  incidents.

## Incomplete
- No authentication anywhere in the request path (Atlas API,
  Operations API, or the mobile app).
- No persistent storage for `redis` or Grafana — both lose state
  silently on pod reschedule.
- `startup.sh`'s CRD-ordering fix has not been exercised by a full fresh
  run.

## What would break at scale
- `redis` with no PVC becomes a real data-loss risk under any node churn
  or cluster upgrade, not just accidental pod deletion.
- Zero-auth APIs would need real authentication before any wider network
  exposure beyond the current NetworkPolicy-only model.

## What requires further testing
- The `startup.sh` reordering fix, end-to-end, on a genuinely fresh
  environment.
- Live data beyond `/health` and `/ready` (component health, jobs,
  diagnostics): the Operations API has no endpoints for them yet.
  (Real-device connectivity was verified 2026-09-20: Healthy, Failed,
  Healthy.)
