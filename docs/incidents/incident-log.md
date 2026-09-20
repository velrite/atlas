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
Resolved. On 2026-09-20, with the INTERNET permission fix from
INCIDENT-010, the badge was tapped to INTEGRATION on a real Android
device and the Check button was run against the real `operations-api`
through the temporary LoadBalancer (ADR-003). Observed sequence,
screen-recorded: Healthy, then Failed (backend deliberately scaled to
0 replicas), then Healthy (scaled back to 1).

Scope note: this closes the Phase 9 handshake, and the Phase 10 goal
only for connection truthfulness. The Operations API serves only
`/health` and `/ready`, so component health, jobs and diagnostics in
the app are still fixture data and are NOT verified against the live
cluster.

---

## INCIDENT-010: Release APK had no INTERNET permission

### Symptom
On a real device, the Overview connection banner showed:
`ClientException with SocketException: Connection failed (OS Error:
Operation not permitted, errno = 1)` when calling the Operations API.

### Investigation
errno 1 (EPERM) means the OS refused to open the socket at all, which
is a different signature from "connection refused" or a timeout.
`grep -n "uses-permission" android/app/src/main/AndroidManifest.xml`
returned nothing. `grep -rn INTERNET android/app/src/` found the
permission only in the `debug` and `profile` manifests, which Flutter's
template adds for development. The APK had been built with `--release`.

### Root Cause
The main manifest declared no `INTERNET` permission, so release builds
could not use the network.

### Resolution
Added `<uses-permission android:name="android.permission.INTERNET"/>`
to the main manifest (commit a8a06d6). In the same commit the
hardcoded backend IP was replaced with a build-time value
(`--dart-define=OPS_API_URL=...`, default `http://localhost:8080`) so a
temporary public IP is no longer committed to the repository.

### Verification
The same Check button that produced errno 1 returned Healthy after the
fix, then Failed and Healthy again during fault injection (see
INCIDENT-009). The only relevant change between the failing and passing
runs was the permission line.

### Preventive control
Any Flutter app that makes network calls must declare `INTERNET` in the
main manifest. Test release builds on a real device, not only debug
builds, because debug and profile manifests add the permission
automatically.
