#!/usr/bin/env bash
#
# generate-docs.sh
#
# Generates senior-level platform engineering documentation for the
# Atlas / Atlas Operator project, based on the ACTUAL engineering history
# of this build (real incidents, real fixes, real infrastructure state).
#
# Nothing in this script invents metrics, incidents, or capabilities that
# were not actually implemented or observed during this project. Anything
# not yet verified is explicitly labeled "NOT YET VERIFIED" or "PLANNED".
#
# Usage:
#   chmod +x generate-docs.sh
#   ./generate-docs.sh
#
set -euo pipefail

# SAFETY (added 2026-09-20): this script rewrites docs from built-in text and would
# undo later manual edits (INCIDENT-009/010, ADR-003 addendum, debt table).
if [ "${1:-}" != "--force-overwrite" ]; then
  echo "Refusing to run: this overwrites hand-edited docs. Use --force-overwrite if you really mean it." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# 0. Locate the repository. Refuse to run outside a real git repo.
# ---------------------------------------------------------------------------
if ! git rev-parse --show-toplevel >/dev/null 2>&1; then
  echo "ERROR: not inside a git repository. cd into the atlas repo and rerun." >&2
  exit 1
fi

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
ORIGIN_URL="$(git remote get-url origin 2>/dev/null || echo "")"

if [ -z "$ORIGIN_URL" ]; then
  echo "ERROR: no 'origin' remote configured. Set one up before running this script." >&2
  exit 1
fi

echo "Repository root : $REPO_ROOT"
echo "Current branch  : $CURRENT_BRANCH"
echo "Origin remote   : $ORIGIN_URL"
echo

DOCS_DIR="$REPO_ROOT/docs"
EVIDENCE_DIR="$DOCS_DIR/evidence"

mkdir -p \
  "$DOCS_DIR/architecture" \
  "$DOCS_DIR/operations" \
  "$DOCS_DIR/reliability" \
  "$DOCS_DIR/security" \
  "$DOCS_DIR/incidents" \
  "$DOCS_DIR/adr" \
  "$DOCS_DIR/engineering" \
  "$EVIDENCE_DIR"

# ---------------------------------------------------------------------------
# 1. Architecture: system overview
# ---------------------------------------------------------------------------
cat > "$DOCS_DIR/architecture/system-overview.md" <<'EOF1'
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
EOF1

# ---------------------------------------------------------------------------
# 2. Architecture: infrastructure
# ---------------------------------------------------------------------------
cat > "$DOCS_DIR/architecture/infrastructure.md" <<'EOF2'
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
EOF2

# ---------------------------------------------------------------------------
# 3. ADRs — real decisions actually made during this project
# ---------------------------------------------------------------------------
cat > "$DOCS_DIR/adr/ADR-001-operator-foundation.md" <<'EOF3'
# ADR-001: Atlas Operator Foundation

## Status
Accepted

## Context
Atlas needed a mobile operational interface. It had to be built against
real Atlas facts (no fabricated data), and had to live somewhere
sensible relative to the existing Atlas repository.

## Problem
Where does the mobile app live, how does it connect to Atlas, which
platform does it target first, and what does it persist locally?

## Decision
- Repo location: `atlas/operator/` inside the existing `atlas` repository
  (not a separate repo).
- Connectivity (dev/INTEGRATION): reach the backend via
  `kubectl port-forward`, no public Ingress added.
- Platform: Android only (development environment has no macOS/iOS
  toolchain available).
- Local persistence: Hive.
- Auth: none yet — Atlas itself has no auth, so the app is single-user
  until an Operations API with its own auth exists.

## Consequences
### Positive
Keeps the operator co-versioned with the platform it observes; avoids
building auth the backend doesn't support yet.

### Negative
Real-device testing is harder than it would be with a public Ingress —
this directly caused the Phase 9 device-connectivity investigation (see
`docs/incidents/`).

## Explicit out-of-scope
No control in the app may ever trigger `terraform apply`/`destroy` or
otherwise change Atlas's infrastructure lifecycle.
EOF3

cat > "$DOCS_DIR/adr/ADR-002-self-hosted-ci-runner.md" <<'EOF4'
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
EOF4

cat > "$DOCS_DIR/adr/ADR-003-temporary-loadbalancer-for-device-testing.md" <<'EOF5'
# ADR-003: Temporary LoadBalancer Exposure for Real-Device Testing

## Status
Accepted (temporary, time-boxed)

## Context
Atlas Operator's Phase 9 goal was to verify a real Android device could
reach the real `operations-api` backend. Development happens in GCP
Cloud Shell, which is a remote VM — not the developer's physical
machine — so a phone connected to a laptop cannot reach Cloud Shell's
`kubectl port-forward` (different machines; USB/adb does not bridge
them).

## Problem
How does a real, physical Android phone reach a backend that otherwise
has zero external exposure by design (per ADR-001 / system-overview)?

## Options Considered

### Option A — Cloud Shell Web Preview
Uncertain whether Web Preview's authenticated-browser-session model
would even work with a non-browser Flutter HTTP client. Flagged as
unverified and not attempted.

### Option B — Sideload an APK, point it at a temporary public
`LoadBalancer` Service in front of `operations-api`
Chosen. Concrete, uses infrastructure already understood from this
project (Services, NetworkPolicy), and gives a real external IP with
no auth-flow guesswork.

## Decision
Option B: a `LoadBalancer` Service (`operations-api-external`) was
created, exposing `operations-api`'s zero-auth `/health` and `/ready`
endpoints to the public internet for the duration of the test.

## Consequences
### Positive
Real end-to-end verification: a physical device reaching a real pod
over the internet.

### Negative — explicitly accepted, not hidden
`operations-api` has **no authentication**. For as long as the
`LoadBalancer` Service exists, its `/health`/`/ready` endpoints are
reachable by anyone on the internet, not just the test phone. This is
acceptable only because the test window was short and the endpoints
themselves reveal no sensitive data — but this is not a pattern to
leave running, and the Service must be deleted immediately after
testing:

    kubectl delete service operations-api-external -n default

Android's cleartext-HTTP block also had to be relaxed for this one test
build (`android:usesCleartextTraffic="true"`), which must not ship in
any build meant for real users.

## Revisit conditions
Superseded once a real Ingress + TLS + auth story exists for Atlas
Operator's backend (tracked as future work, not yet implemented).
EOF5

# ---------------------------------------------------------------------------
# 4. Incident / debugging history — real, in order
# ---------------------------------------------------------------------------
cat > "$DOCS_DIR/incidents/incident-log.md" <<'EOF6'
# Incident & Debugging Log

This log preserves the real failures encountered while building Atlas
and Atlas Operator, in the order they happened. Nothing here is
production impact — all of it occurred during development/CI, and is
labeled as such.

---

## INCIDENT-001: Hive test fake failed platform-interface verification

### Symptom
`flutter test` failed to even load `capped_cache_test.dart`:
`Assertion failed: "Platform interfaces must not be implemented with 'implements'"`.

### Root Cause
`FakePathProviderPlatform` extended `PlatformInterface` and implemented
`PathProviderPlatform` using plain `implements`, without the required
`with MockPlatformInterfaceMixin`. Recent `plugin_platform_interface`
versions verify this at runtime and reject fakes that skip it.

### Resolution
Added `with MockPlatformInterfaceMixin` to the fake's class declaration.
One line.

### Verification
`flutter analyze` clean, `flutter test` all green (+14 initially, growing
as more tests were added later).

### Preventive control
None needed beyond awareness — this is a one-time fix per fake platform
implementation.

---

## INCIDENT-002: Hive cache-write failures silently converted successful reads into errors

### Symptom
Widget tests failed to find real fixture data (e.g. `WorkloadsScreen
shows real fixture job IDs`) even though the underlying fixture JSON was
correct.

### Root Cause
Repository code treated a Hive cache **write** failure (expected in
widget tests, which don't open Hive boxes) as if it invalidated the
**read** that had already succeeded, returning `Error(...)` instead of
`Data(...)`.

### Resolution
Wrapped the cache-write step in its own `try/catch`, logging
`"... cache write skipped: <error>"` via `debugPrint` but always
returning the real, already-loaded data regardless of whether the cache
write succeeded.

### Verification
Same tests now pass; the `"cache write skipped"` log lines are expected
and harmless noise in test output, not failures.

### Preventive control
General pattern: caching is a side effect of a successful read, never a
precondition of returning that read's data.

---

## INCIDENT-003: `startup.sh` installed a Helm chart's Rollout before Argo Rollouts CRDs existed

### Symptom
After a fresh `startup.sh` run, `atlas-api`'s `Rollout` object sat
un-reconciled (`DESIRED 2, CURRENT/AVAILABLE blank`) with no controller
acting on it.

### Root Cause
`startup.sh`'s Argo Rollouts CRD + controller install block was placed
at the very end of the script ("Phase 11"), but an earlier step (Helm
install of the `atlas-platform` chart) creates a `kind: Rollout` object
— a type that only exists once those CRDs are installed. Manual,
out-of-order CRD installation was required to unblock this during the
session.

### Resolution
Moved the entire Argo Rollouts CRD + controller install block from the
end of the script to immediately before the Helm install step. Verified
with `grep -n` (new position confirmed) and `bash -n scripts/startup.sh`
(syntax check).

### Verification status
**NOT YET VERIFIED end-to-end.** The reordering was verified for
ordering and syntax only — it has not yet been exercised by a full,
fresh `startup.sh` run in this project. The first real rebuild that uses
this script is the actual test of the fix.

### Preventive control
CRD-dependent manifests must always be installed after their CRDs in any
automation script, verified by re-running the full script fresh (not
just inspecting it) before calling a script fix "done."

---

## INCIDENT-004: GitLab CI exhausted free compute minutes

### Symptom
Every pipeline job failed instantly with `"No more compute minutes
available."`, before any job actually started.

### Root Cause
GitLab.com's free-tier shared/instance runner minutes were exhausted —
a real, hard billing quota, not a configuration bug.

### Resolution
See `docs/adr/ADR-002-self-hosted-ci-runner.md` — a dedicated,
self-hosted GitLab Runner was built on its own GCE VM.

### Verification
Confirmed via the GitLab pipelines UI once the runner was correctly
configured (see INCIDENT-005 and INCIDENT-006 below for the two
follow-up issues this surfaced).

---

## INCIDENT-005: Self-hosted runner online but jobs still stuck

### Symptom
After deploying `atlas-gce-runner` and confirming it "Online" in the
GitLab UI, a pipeline still showed: *"This job is stuck because the
project doesn't have any runners online assigned to it."*

### Investigation
Confirmed the runner's `systemd` service was genuinely running
(`sudo systemctl status gitlab-runner`). Compared the job's tag
requirements (`.gitlab-ci.yml`'s `test` job specifies no tags) against
the runner's registered configuration (`/etc/gitlab-runner/config.toml`
showed `tag_list = ["atlas-gce"]`, and by default a newly registered
runner does not run untagged jobs).

### Root Cause
The runner was tagged (`atlas-gce`) but not configured to accept
untagged jobs, and the untagged `test` job (and others) had no matching
tag to pair against.

### Resolution
```
curl --request PUT \
  --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
  --data "run_untagged=true" \
  "https://gitlab.com/api/v4/runners/<runner_id>"
```

### Verification
API response confirmed `"run_untagged":true`; a retriggered pipeline
still failed at this point — see INCIDENT-006, the second half of this
same saga.

---

## INCIDENT-006: Shared runners still claimed jobs despite a healthy dedicated runner

### Symptom
Even with the self-hosted runner online, untagged, and idle, pipelines
kept failing with the original "No more compute minutes" error.

### Root Cause
Both runner types (GitLab's exhausted shared pool, and the new project
runner) were simultaneously eligible for the job. GitLab defaulted to
the exhausted shared pool rather than the available project runner,
because shared runners were never explicitly disabled for the project.

### Resolution
Disabled shared runners for the project via the GitLab API (the UI
toggle described in GitLab's own documentation could not be located in
this GitLab UI version):
```
curl --request PUT \
  --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
  --data "shared_runners_enabled=false" \
  "https://gitlab.com/api/v4/projects/<project_id>"
```
A classic Personal Access Token (scope `api`) was used after a
fine-grained (beta) token's permission set was confirmed not to cleanly
expose a plain "update project settings" REST permission.

### Verification
Full pipeline (`test`, `lint`, `sast`, `dependency-scan`, `iac-scan`,
`build-api`, `build-scheduler`, `build-worker`, `image-scan`, `push`,
`gitops-update`) — all 11 jobs passed on `atlas-gce-runner`.

### Security follow-up
The classic PAT used for this fix should be revoked once its one job is
done, rather than left live with a broad `api` scope.

---

## INCIDENT-007: `gitops-update` job hit a real merge conflict syncing GitHub and GitLab

### Symptom
The `gitops-update` CI job (which auto-commits an updated image tag to
`helm/atlas-platform/values.yaml` and syncs it from GitLab to GitHub)
failed with a rebase conflict on that same file, even after its own
built-in retry logic.

### Root Cause
A race between the CI job's automated push to both remotes and a
developer manually pushing test commits directly to `main` on both
remotes at the same time. Two writers touching the same file on both
remotes back-to-back.

### Resolution
Manually resynced: fetched, rebased, and (once confirmed the only
divergent commit on the losing side was an empty test commit with no
real content) used `git push gitlab main --force-with-lease` to bring
GitLab back in line with GitHub's now-authoritative state.

### Verification
`git log --oneline` on both `origin/main` and `gitlab/main` confirmed
identical tips after the resync.

### Preventive control
Documented, not yet automated: avoid manual pushes to `main` while a
`gitops-update` pipeline stage is in flight. The underlying race
(`scripts-sync-github.sh`'s own comments reference this exact failure
mode as "INCIDENT-005" in its internal numbering) is a known,
accepted risk rather than a fully closed one.

---

## INCIDENT-008: Cloud Shell disk exhaustion building the first Android APK

### Symptom
`flutter build apk --release` repeatedly failed with `"No space left on
device"` while Gradle attempted to download the Android NDK
(~1GB+ package), even after clearing Gradle caches and apt caches.

### Root Cause
Cloud Shell's persistent `/home` partition is hard-capped at 4.8GB.
Flutter SDK, Android SDK, Gradle caches, and the NDK download together
exceeded that cap regardless of cleanup — this was a disk-capacity
ceiling, not a config bug. (A related but ultimately insufficient fix
was attempted first: removing an explicit `ndkVersion` line from
`android/app/build.gradle.kts` — this did not stop the NDK download,
because at least one Flutter plugin dependency requests its own NDK
version independently of the app module's own setting.)

### Resolution
Relocated `ANDROID_HOME`, `GRADLE_USER_HOME`, and `PUB_CACHE` off the
capped `/home` partition and onto Cloud Shell's larger ephemeral root
filesystem (`/opt/android-sdk`, `/opt/gradle-home`, `/opt/pub-cache`).

### Verification
`flutter build apk --release` completed successfully:
`app-release.apk`, 50.3MB, in `build/app/outputs/flutter-apk/`.

### Preventive control
Document the `/opt`-based SDK/Gradle relocation as the standard Cloud
Shell setup for this project, rather than rediscovering it on a future
fresh Cloud Shell session.

---

## INCIDENT-009: No UI control existed to switch environments

### Symptom
After a real device successfully installed the app, there was no way to
enter `INTEGRATION` mode to actually trigger the Phase 9 connectivity
check — the app stayed in `OFFLINE` with no reachable control.

### Root Cause
`setEnvironment()` existed on the underlying Riverpod notifier, but no
widget in the app ever called it. `EnvironmentBadge` displayed the
current mode but was read-only by design up to this point — this was
unfinished wiring, not a bug in existing code.

### Resolution
Made `EnvironmentBadge` tappable, cycling
`OFFLINE -> INTEGRATION -> LIVE -> OFFLINE` on tap, calling the
already-existing `setEnvironment()`.

### Verification
`flutter analyze` clean, `flutter test` 23/23 passing.

### Status
Real-device verification of the resulting `INTEGRATION` connectivity
check against the temporary public LoadBalancer (ADR-003) is
**IN PROGRESS / NOT YET FULLY CONFIRMED** as of this document's
generation — confirm actual on-device banner state before marking Phase
9 fully closed.
EOF6

# ---------------------------------------------------------------------------
# 5. Reliability
# ---------------------------------------------------------------------------
cat > "$DOCS_DIR/reliability/reliability-model.md" <<'EOF7'
# Reliability Model

## Health check strategy

Atlas Operator never presents a fabricated uniform health signal. Each
component's health is labeled by its real evidence source:

- `httpHealthCheck` — `atlas-api`, `operations-api` (`/health`, `/ready`)
- `podStatus` — `redis` (no HTTP surface at all, only `redis-cli PING`)
- `metricsInferred` — `atlas-scheduler`, `atlas-worker` (Prometheus
  metrics only, no HTTP health route)

## Real observed degraded scenario

The one degraded scenario currently modeled end-to-end (fixtures +
Diagnostics reasoning + Overview "Primary issue" card) is a worker
capacity saturation pattern, kept consistent everywhere it appears:

- Worker CPU: 94%
- Requeue rate: +418%
- Redis / API / Scheduler: Healthy

This consistency is deliberate — the same evidence numbers appear on
both the Overview screen and the Diagnostics screen so the two never
contradict each other.

## Queue behavior

`atlas:queue:pending` is almost always empty in practice — the
scheduler drains it in roughly 5–25ms. Showing "queue depth: 0" as a
health signal would look broken even when the system is healthy, so job
list state is treated as the more honest signal, not queue depth.

## Rollback

Argo Rollouts canary steps: 7 total.
`progressDeadlineAbort` measured at 125s rollback time in testing.

## Known reliability gaps (explicitly not hidden)

- `redis` has no PVC — job loss on pod replacement is silent, with no
  error surfaced anywhere in the system today. **NOT YET
  ADDRESSED.**
- Grafana has no PVC either — its SQLite datastore resets on pod
  reschedule, which has wiped its GMP datasource token twice during this
  project's history, both times requiring manual recovery. **NOT
  AUTOMATED.**
- GMP (Google Managed Prometheus) query results can lag real `/metrics`
  values by several minutes (Monarch backend ingestion lag). Any UI
  showing GMP-derived data must show a freshness timestamp and must
  never imply real-time accuracy.
EOF7

cat > "$DOCS_DIR/reliability/slo.md" <<'EOF8'
# SLOs

Four live Cloud Monitoring alert policies exist for Atlas (per project
ADR-015, referenced in prior architecture work):

- API p95 latency < 100ms
- Scheduling p95 latency < 50ms
- Job success rate > 99%
- API availability > 99.5%

These are **implemented alert policies**, not independently measured or
publicly reported production SLA numbers. No uptime, traffic volume, or
user-facing performance claims beyond these four policy definitions
should be made without new, explicit measurement.
EOF8

# ---------------------------------------------------------------------------
# 6. Security
# ---------------------------------------------------------------------------
cat > "$DOCS_DIR/security/security-controls.md" <<'EOF9'
# Security Controls

## Implemented

| Control | Mechanism | Scope |
|---|---|---|
| Admission policy | Kyverno `ClusterPolicy`: `disallow-latest-tag`, `disallow-privileged-containers`, `require-resource-requests-limits` | Cluster-wide on `atlas-dev` |
| Network segmentation | Kubernetes `NetworkPolicy`, default-deny + explicit allow | Namespace-scoped |
| CI supply-chain checks | `sast`, `dependency-scan`, `iac-scan`, `image-scan` stages in `.gitlab-ci.yml` | Every pipeline run |
| CI authentication to GCP | Workload Identity Federation (`GITLAB_OIDC_TOKEN`), no static GCP keys in CI | `push` stage |
| Local persistence | Hive (on-device only, capped, no cloud sync) | Atlas Operator app |

## Explicitly NOT implemented (do not claim otherwise)

- **Atlas's own API has zero authentication.** Access control today is
  network-policy-only, not identity-based. Any claim of "zero trust" or
  "authenticated API" is false as of this writing.
- **Atlas Operator has no auth of its own** — deliberate, per ADR-001,
  since the backend it talks to has none either.
- **`operations-api` currently has no TLS and no auth** on its
  `/health`/`/ready` endpoints. During Phase 9 real-device testing
  (ADR-003), this was briefly exposed to the public internet via a
  temporary `LoadBalancer` Service and Android's cleartext-HTTP block
  was relaxed for that one test build. Both were reverted / must be
  reverted after the test — see ADR-003 for the full trade-off.

## Before publishing any screenshot from this project

Redact or crop out:
- The classic GitLab Personal Access Token value (`glpat-...`) used
  during the CI runner fix — it should also be revoked, not just hidden.
- The GitLab runner registration token
  (`glrt-...`) visible in `/etc/gitlab-runner/config.toml`.
- Any real external IP addresses if you consider them sensitive (the
  temporary LoadBalancer IP used for device testing is not itself
  secret, but the service should already be deleted by publication
  time).
- Any `CI_JOB_TOKEN` or `GITHUB_PUSH_TOKEN` values that might appear in
  raw CI job logs.
EOF9

# ---------------------------------------------------------------------------
# 7. Operations
# ---------------------------------------------------------------------------
cat > "$DOCS_DIR/operations/troubleshooting.md" <<'EOF10'
# Troubleshooting

## "Runner shows Online but jobs are stuck"
Check both: (1) does the runner accept untagged jobs
(`run_untagged` on the runner, via `GET /api/v4/runners/<id>`), and
(2) are shared runners still enabled for the project
(`shared_runners_enabled` on the project). Both must be correctly set —
see INCIDENT-005 and INCIDENT-006 in `docs/incidents/incident-log.md`.

## "No space left on device" during `flutter build apk`
Cloud Shell's `/home` is capped (~4.8GB). Relocate `ANDROID_HOME`,
`GRADLE_USER_HOME`, and `PUB_CACHE` to `/opt/...` (the larger ephemeral
root filesystem) rather than trying to fit the Android SDK + NDK +
Gradle caches inside `/home`. See INCIDENT-008.

## "Rollout stuck, never reconciles"
Confirm the Argo Rollouts CRDs and controller are actually installed
and healthy in the `argo-rollouts` namespace before assuming the
Rollout object itself is broken:
```
kubectl get pods -n argo-rollouts
kubectl describe rollout <name> -n <namespace> | tail -20
```
See INCIDENT-003 for the specific ordering bug this project hit.

## "gitops-update fails with a merge conflict"
Do not push manual commits to `main` on either remote while a
`gitops-update` pipeline stage is running — see INCIDENT-007.
EOF10

# ---------------------------------------------------------------------------
# 8. Engineering
# ---------------------------------------------------------------------------
cat > "$DOCS_DIR/engineering/technical-debt.md" <<'EOF11'
# Technical Debt

| Item | Current state | Risk | Why it exists | Recommended remediation |
|---|---|---|---|---|
| `redis` has no PVC | Job data lost silently on pod replacement | Data loss with no error surfaced | Original scope prioritized functional flow over persistence | Add a PVC or move to a managed queue |
| Grafana has no PVC | GMP datasource token wiped on pod reschedule (happened twice) | Manual recovery required each time | Same as above | Add a PVC, or move dashboard provisioning to code/config instead of stateful UI setup |
| Atlas API has zero auth | Any caller on the network can hit it | No access control beyond NetworkPolicy | Backend auth was out of scope for the phases delivered so far | Add real authentication before any wider network exposure |
| `operations-api` has no auth/TLS | Same as above, briefly worsened by ADR-003's temporary public exposure | Same as above | Phase 8 delivered the minimum viable backend for Phase 9 testing | Add auth + TLS before treating this as anything beyond a dev/test backend |
| `startup.sh` CRD-ordering fix unverified end-to-end | Fix is merged and syntax-checked, but no full fresh run has exercised it | Could still fail differently than expected on a truly fresh environment | Time constraints during this session | Run one full fresh `startup.sh` end-to-end and record the result |
| `gitops-update` race with manual pushes | Known, documented, not automated away | Occasional merge-conflict pipeline failures | The sync script already retries once; a second layer (e.g. a merge lock) was not built | Add a simple lock/queue around `main` pushes, or restrict manual pushes during active pipelines |
| Real-device Phase 9 verification | In progress at time of writing | Phase 9 could be marked "done" prematurely | Real-device testing required infra not built for it (see ADR-003) | Confirm actual on-device banner state, then decide whether the temporary LoadBalancer approach should become a permanent, secured Ingress |
EOF11

cat > "$DOCS_DIR/engineering/engineering-maturity.md" <<'EOF12'
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
- Real-device Phase 9 connectivity, confirmed with an actual observed
  banner state (healthy or failed) rather than assumed.
EOF12

# ---------------------------------------------------------------------------
# 9. Evidence checklist — screenshots, deterministic filenames, exact commands
# ---------------------------------------------------------------------------
cat > "$EVIDENCE_DIR/README.md" <<'EOF13'
# Evidence

Screenshots referenced from the documentation live in this folder using
deterministic, lowercase-kebab-case filenames. Drop a file in matching
one of the names below and every markdown reference below picks it up
automatically — no other edits needed.

| # | Filename | Proves | Command to run before capturing | Expected result (structure) | Strength |
|---|---|---|---|---|---|
| 01 | `01-cluster-nodes.png` | The GKE cluster is real and its nodes are Ready | `kubectl config current-context` then `kubectl get nodes -o wide` | All nodes show `STATUS Ready`; context matches `atlas-dev` | CRITICAL |
| 02 | `02-atlas-platform-workloads.png` | Atlas's real components are running with expected replica counts | `kubectl get all -n atlas-platform` | `redis` 1/1, `atlas-scheduler` 1/1, `atlas-worker` 2/2 Deployments; `atlas-api` shown as a healthy Rollout, not a plain Deployment | CRITICAL |
| 03 | `03-atlas-api-rollout-healthy.png` | Argo Rollouts canary deployment mechanism is real | `kubectl get rollout atlas-api -n atlas-platform` then `kubectl describe rollout atlas-api -n atlas-platform \| tail -20` | `Phase: Healthy`, replica counts match desired | CRITICAL |
| 04 | `04-argo-rollouts-controller.png` | The Rollouts controller itself is live (not just the CRDs) | `kubectl get pods -n argo-rollouts` | One `argo-rollouts` pod, `1/1 Running` | STRONG |
| 05 | `05-kyverno-policies.png` | Admission-control security policies are real and enforced | `kubectl get clusterpolicy` | Three policies listed: `disallow-latest-tag`, `disallow-privileged-containers`, `require-resource-requests-limits` | CRITICAL |
| 06 | `06-operations-api-live.png` | The Phase 8 backend is deployed and passing its own health checks | `kubectl get pods -l app=operations-api` then `kubectl logs -l app=operations-api --tail=20` | `1/1 Running`; logs show real `GET /health 200`, `GET /ready 200` lines | CRITICAL |
| 07 | `07-gitlab-pipeline-passed.png` | The full CI/CD pipeline runs and passes on real infrastructure | Open the GitLab pipeline URL for the relevant commit | All 11 jobs (`test`, `lint`, `sast`, `dependency-scan`, `iac-scan`, `build-api`, `build-scheduler`, `build-worker`, `image-scan`, `push`, `gitops-update`) show Passed | CRITICAL |
| 08 | `08-self-hosted-runner-online.png` | CI runs on a self-managed runner, not just GitLab's shared pool | GitLab UI → Settings → CI/CD → Runners | `atlas-gce-runner` shown Online, tag `atlas-gce`, `run_untagged: true` | STRONG |
| 09 | `09-artifact-registry-images.png` | Built container images are real and versioned by commit SHA | `gcloud artifacts docker images list us-central1-docker.pkg.dev/velrite-tf-test/atlas-images` | Image list includes `operations-api`, `atlas-scheduler`, `atlas-worker` tagged with real short SHAs | STRONG |
| 10 | `10-gitops-values-diff.png` | GitOps: a real commit updated the deployed image tag | `git log -p -1 <gitops-update commit sha> -- helm/atlas-platform/values.yaml` | Diff shows `tag:` changed to a real image SHA, commit message `GitOps update image tag [ci skip]` | STRONG |
| 11 | `11-networkpolicy-default-deny.png` | Network segmentation is enforced, not assumed | `kubectl get networkpolicy -A` | Default-deny plus explicit allow policies listed per namespace | STRONG |
| 12 | `12-operations-api-networkpolicy.png` | The new Phase 8 service follows the same segmentation model | `kubectl get networkpolicy -n default -o yaml \| grep -A 10 operations-api` | An explicit allow rule scoped to `operations-api`'s real ports | SUPPORTING |
| 13 | `13-atlas-operator-overview-degraded.png` | The mobile app surfaces a real degraded scenario end-to-end | Open Atlas Operator, OFFLINE mode, degraded fixture scenario, Overview tab | "Primary issue" card shows Worker CPU 94%, requeue +418%, matches Diagnostics screen exactly | STRONG |
| 14 | `14-atlas-operator-diagnostics-run.png` | The Diagnostics "Run" button produces evidence-based, non-fabricated output | Tap Run on Diagnostics tab | DEGRADED outcome, same 94%/+418% evidence numbers as screenshot 13 | STRONG |
| 15 | `15-atlas-operator-deployments-history.png` | The app reads real deployment history, not fabricated data | Open Deployments tab | Revision history matches real `kubectl get rollout ... -o json` revisionHistory (capped at 3 by `revisionHistoryLimit`) | SUPPORTING |
| 16 | `16-environment-badge-integration.png` | The app can actually switch into INTEGRATION mode | Tap the environment badge until it reads INTEGRATION (amber) | Badge color changes from grey (OFFLINE) to amber (INTEGRATION) | SUPPORTING |
| 17 | `17-connection-banner-healthy-or-failed.png` | Real-device connectivity to a real backend — the actual Phase 9 goal | With INTEGRATION mode active on a real device, observe the Overview connection banner | Banner shows `ConnectionHealthy` (or, if genuinely failed, `ConnectionFailed` with the real reason — do not stage a fake pass) | CRITICAL |
| 18 | `18-android-manifest-cleartext-flag.png` | Documents the exact, deliberate, temporary security trade-off made for device testing | `cat android/app/src/main/AndroidManifest.xml` | `android:usesCleartextTraffic="true"` visible, with the surrounding code comment explaining it is TEMP | SUPPORTING (pairs with ADR-003) |
| 19 | `19-loadbalancer-external-ip.png` | The temporary public exposure used for testing, and its teardown | `kubectl get service operations-api-external -n default` before, then `kubectl delete service operations-api-external -n default` after, `kubectl get service -n default` confirming it is gone | Before: real external IP shown. After: service no longer listed | CRITICAL (proves the trade-off was time-boxed, not left running) |
| 20 | `20-ci-security-scan-stages.png` | Supply-chain security scanning is real, not just named in a YAML file | Open the `sast`, `dependency-scan`, `image-scan` job logs in the passed pipeline | Each job shows real scan output/tool invocation, exits 0 | STRONG |
| 21 | `21-flutter-test-suite-green.png` | The mobile app has real automated test coverage, not just manual demoing | `flutter test` in `atlas/operator` | All tests passing (test count reflects current suite size) | STRONG |
| 22 | `22-incident-fix-commit.png` | At least one real incident-to-fix-to-commit trail exists in git history | `git log --oneline --grep="Phase 9"` or similar, then `git show <hash> --stat` | Commit message references the real fix (e.g. EnvironmentBadge tappable fix), file diff matches | SUPPORTING |

## Notes for the reviewer

- Screenshots proving **runtime behavior** (rollout healthy, pipeline
  passed, real device connectivity) are prioritized over screenshots of
  static configuration (YAML files) wherever both are possible for the
  same claim.
- Item 19 is intentionally a two-part "before/after" capture — the
  point is proving the temporary public exposure was actually torn down,
  not just that it once existed.
- If item 17 shows `ConnectionFailed` rather than `ConnectionHealthy` at
  capture time, **do not discard that screenshot** — a real, honestly
  reported failure with its real error string is still valid engineering
  evidence and should be captured alongside the investigation that
  follows it, per this project's "never fabricate" rule.

## Top 10 to capture first if time is short

1. `07-gitlab-pipeline-passed.png`
2. `02-atlas-platform-workloads.png`
3. `03-atlas-api-rollout-healthy.png`
4. `06-operations-api-live.png`
5. `17-connection-banner-healthy-or-failed.png`
6. `05-kyverno-policies.png`
7. `01-cluster-nodes.png`
8. `19-loadbalancer-external-ip.png`
9. `13-atlas-operator-overview-degraded.png`
10. `21-flutter-test-suite-green.png`
EOF13

# ---------------------------------------------------------------------------
# 10. README — update or create, without destroying existing content
# ---------------------------------------------------------------------------
README_PATH="$REPO_ROOT/README.md"
GENERATED_SECTION_MARK="<!-- BEGIN GENERATED ENGINEERING DOCS SECTION -->"
GENERATED_SECTION_END="<!-- END GENERATED ENGINEERING DOCS SECTION -->"

GENERATED_BLOCK=$(cat <<'EOF14'
<!-- BEGIN GENERATED ENGINEERING DOCS SECTION -->
## Engineering Documentation

This section is generated by `generate-docs.sh` and is safe to
regenerate at any time — it will not touch content outside these
markers.

- [System Overview](docs/architecture/system-overview.md)
- [Infrastructure](docs/architecture/infrastructure.md)
- [ADR-001: Atlas Operator Foundation](docs/adr/ADR-001-operator-foundation.md)
- [ADR-002: Self-Hosted CI Runner](docs/adr/ADR-002-self-hosted-ci-runner.md)
- [ADR-003: Temporary LoadBalancer for Device Testing](docs/adr/ADR-003-temporary-loadbalancer-for-device-testing.md)
- [Incident & Debugging Log](docs/incidents/incident-log.md)
- [Reliability Model](docs/reliability/reliability-model.md)
- [SLOs](docs/reliability/slo.md)
- [Security Controls](docs/security/security-controls.md)
- [Troubleshooting](docs/operations/troubleshooting.md)
- [Technical Debt](docs/engineering/technical-debt.md)
- [Engineering Maturity Assessment](docs/engineering/engineering-maturity.md)
- [Evidence / Screenshots](docs/evidence/README.md)

### Evidence

Drop screenshots into `docs/evidence/` using the exact filenames listed
in [`docs/evidence/README.md`](docs/evidence/README.md) — for example:

![Cluster Nodes](docs/evidence/01-cluster-nodes.png)
![Atlas Platform Workloads](docs/evidence/02-atlas-platform-workloads.png)
![Atlas API Rollout Healthy](docs/evidence/03-atlas-api-rollout-healthy.png)
![Operations API Live](docs/evidence/06-operations-api-live.png)
![GitLab Pipeline Passed](docs/evidence/07-gitlab-pipeline-passed.png)
![Connection Banner](docs/evidence/17-connection-banner-healthy-or-failed.png)

GitHub renders these inline automatically once the matching file exists
at that path — no other edit is required after uploading a screenshot.
<!-- END GENERATED ENGINEERING DOCS SECTION -->
EOF14
)

if [ -f "$README_PATH" ] && grep -qF "$GENERATED_SECTION_MARK" "$README_PATH"; then
  echo "Updating existing generated section in README.md ..."
  python3 - "$README_PATH" "$GENERATED_SECTION_MARK" "$GENERATED_SECTION_END" <<'PYEOF'
import sys
path, start_mark, end_mark = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path, "r") as f:
    content = f.read()
start = content.index(start_mark)
end = content.index(end_mark) + len(end_mark)
new_block = open("/tmp/generated_block.md").read().strip()
content = content[:start] + new_block + content[end:]
with open(path, "w") as f:
    f.write(content)
PYEOF
elif [ -f "$README_PATH" ]; then
  echo "Appending generated section to existing README.md ..."
  {
    echo ""
    echo "$GENERATED_BLOCK"
  } >> "$README_PATH"
else
  echo "Creating README.md ..."
  {
    echo "# Atlas"
    echo ""
    echo "$GENERATED_BLOCK"
  } > "$README_PATH"
fi

# Write the block to /tmp for the python update path above
echo "$GENERATED_BLOCK" > /tmp/generated_block.md
if [ -f "$README_PATH" ] && grep -qF "$GENERATED_SECTION_MARK" "$README_PATH"; then
  python3 - "$README_PATH" "$GENERATED_SECTION_MARK" "$GENERATED_SECTION_END" <<'PYEOF'
import sys
path, start_mark, end_mark = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path, "r") as f:
    content = f.read()
start = content.index(start_mark)
end = content.index(end_mark) + len(end_mark)
new_block = open("/tmp/generated_block.md").read().strip()
content = content[:start] + new_block + content[end:]
with open(path, "w") as f:
    f.write(content)
PYEOF
fi

# ---------------------------------------------------------------------------
# 11. Validate expected files exist
# ---------------------------------------------------------------------------
echo
echo "Validating generated files..."
EXPECTED_FILES=(
  "$DOCS_DIR/architecture/system-overview.md"
  "$DOCS_DIR/architecture/infrastructure.md"
  "$DOCS_DIR/adr/ADR-001-operator-foundation.md"
  "$DOCS_DIR/adr/ADR-002-self-hosted-ci-runner.md"
  "$DOCS_DIR/adr/ADR-003-temporary-loadbalancer-for-device-testing.md"
  "$DOCS_DIR/incidents/incident-log.md"
  "$DOCS_DIR/reliability/reliability-model.md"
  "$DOCS_DIR/reliability/slo.md"
  "$DOCS_DIR/security/security-controls.md"
  "$DOCS_DIR/operations/troubleshooting.md"
  "$DOCS_DIR/engineering/technical-debt.md"
  "$DOCS_DIR/engineering/engineering-maturity.md"
  "$EVIDENCE_DIR/README.md"
  "$README_PATH"
)

MISSING=0
for f in "${EXPECTED_FILES[@]}"; do
  if [ ! -f "$f" ]; then
    echo "MISSING: $f"
    MISSING=1
  fi
done

if [ "$MISSING" -eq 1 ]; then
  echo "ERROR: one or more expected files were not created. Aborting before commit." >&2
  exit 1
fi

echo "All expected files present."
echo

# ---------------------------------------------------------------------------
# 12. Stage, commit, push — explicit paths only, never a blind `git add .`
# ---------------------------------------------------------------------------
cd "$REPO_ROOT"

git add \
  "$DOCS_DIR" \
  "$README_PATH"

echo "Staged changes:"
git status --short

if git diff --cached --quiet; then
  echo "No documentation changes to commit."
else
  git commit -m "docs: add comprehensive platform engineering documentation

Generated by generate-docs.sh. Covers architecture, ADRs, real incident
history, reliability model, SLOs, security controls, operations
runbooks, technical debt, engineering maturity assessment, and the
evidence/screenshot checklist with deterministic filenames."

  echo "Pushing to origin/$CURRENT_BRANCH ..."
  if git push origin "$CURRENT_BRANCH"; then
    echo "Push succeeded."
  else
    echo "ERROR: push failed. Documentation commit is intact locally; resolve and push manually:" >&2
    echo "  git push origin $CURRENT_BRANCH" >&2
    exit 1
  fi
fi

echo
echo "Done. Documentation is in docs/, screenshot checklist is in docs/evidence/README.md."
