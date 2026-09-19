# ADR-002: Self-Hosted GitLab Runner for CI

## Status
Accepted

## Context
GitLab.com's shared/instance runners ran out of free compute minutes
mid-project, blocking every pipeline (`build-api`, `build-scheduler`,
`build-worker`, `push`, `gitops-update`) instantly, before any job could
start.

## Problem
Where do CI builds run once the free shared-runner quota is exhausted,
given that the CI pipeline requires Docker-in-Docker (`docker:24-dind`)
for image builds?

## Options Considered

### Option A — Run a self-hosted runner inside the `atlas-dev` GKE cluster
Rejected. `atlas-dev` enforces a live Kyverno `disallow-privileged-containers`
policy, and Docker-in-Docker requires privileged mode — the cluster
would reject the pod at admission. `atlas-dev` is also shared with
unrelated `Forge`/`Project7` workloads, which this project's ground
rules say never to touch.

### Option B — Purchase additional GitLab.com compute minutes
Not pursued (cost decision, out of scope for this build).

### Option C — Self-hosted runner on a dedicated GCE VM
Chosen. A separate `e2-medium` VM (`atlas-ci-runner`) runs Docker +
`gitlab-runner` with `--docker-privileged`, isolated from the GKE
cluster's admission policies entirely. The existing `.gitlab-ci.yml`
already authenticated its `push` stage via Workload Identity Federation
tied to the GitLab project identity (not the runner), so switching
runners required zero GCP IAM changes.

## Decision
Option C.

## Consequences
### Positive
CI is no longer blocked by GitLab.com's shared-runner quota; the runner
is fully isolated from the production-shaped GKE cluster's security
policies.

### Negative
- One more piece of infrastructure to patch/maintain (the runner VM
  itself).
- Two real configuration gotchas were hit and are documented as
  incidents: (1) the runner was initially registered without
  `run_untagged=true`, so it silently never picked up untagged jobs
  even while "Online"; (2) GitLab's shared runners had to be explicitly
  disabled at the project level (`shared_runners_enabled=false` via the
  API) or GitLab kept routing jobs back to the exhausted shared pool
  even with a healthy dedicated runner available.

## Revisit conditions
Revisit if GitLab.com compute minutes are purchased/reset, or if the
project moves to a managed self-hosted runner fleet.
