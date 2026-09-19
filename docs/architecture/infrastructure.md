# Infrastructure

## Cloud project

- GCP project: `velrite-tf-test`
- Cluster: `atlas-dev` (zonal GKE, `us-central1-a`)
- Artifact Registry repository: `atlas-images`
  (full path pattern:
  `us-central1-docker.pkg.dev/velrite-tf-test/atlas-images/<image>:<tag>`)
- Terraform root: `terraform/environments/dev`

## Shared cluster caution

`atlas-dev` is shared with unrelated `Forge` and `Project7` workloads.
Nothing in this project's tooling (startup/teardown scripts, CI runner
setup, LoadBalancer exposure) touches those namespaces.

## CI/CD compute

CI originally ran on GitLab.com's shared/instance runners. Those hit a
hard, real billing quota ("No more compute minutes available"), which is
documented as a real incident in `docs/incidents/`. The fix was a
dedicated, self-hosted GitLab Runner on its own GCE VM
(`atlas-ci-runner`, `e2-medium`, `us-central1-a`) — see
`docs/adr/ADR-002-self-hosted-ci-runner.md`.

## Startup / teardown

- `scripts/startup.sh` — Terraform apply with a plan-then-confirm gate.
  A real ordering bug was found and fixed here (Argo Rollouts CRDs were
  being installed *after* the Helm chart that requires them) — documented
  in `docs/incidents/`.
- `scripts/teardown.sh` — plan-only, never auto-destroys.

## Explicit non-goal

No control in Atlas Operator (the mobile app) can ever trigger
`terraform apply` / `destroy`, or otherwise turn Atlas's infrastructure
on or off. That requires GCP credentials the phone must never hold, and
would bypass the plan-then-confirm safety gates already built into
`startup.sh` / `teardown.sh`. The app can only ever *display* Atlas's
current state.
