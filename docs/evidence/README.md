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
