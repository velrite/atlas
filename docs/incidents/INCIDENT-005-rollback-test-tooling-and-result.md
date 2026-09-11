# INCIDENT-005: Phase 11 Rollback Test - Tooling Failures and Real Result

## Summary
Multiple real tooling failures were hit while attempting to trigger and
observe Argo Rollouts' automatic canary abort/rollback, before a working
method was found.

## Timeline of real failures (in order)
1. GitOps hand-off never landed the broken-image commit into a deployed
   Rollout revision within a 15-minute poll window - CI pipeline
   latency/queueing, not a Rollout bug.
2. `kubectl argo rollouts set image ...` failed:
   `Error: unknown command "argo" for "kubectl"` - the plugin is not
   installed in a fresh Cloud Shell session.
3. `kubectl set image rollout/atlas-api ...` failed:
   `error: no kind "Rollout" is registered for version "argoproj.io/v1alpha1"
   in scheme "pkg/scheme/scheme.go:28"` - `set image` requires the target
   kind in kubectl's built-in typed scheme; CRDs are not in it.
4. Working fix: `kubectl patch rollout atlas-api -n atlas-platform
   --type='json' -p='[{"op":"replace","path":"/spec/template/spec/containers/0/image","value":"<image>"}]'`
5. Argo CD's selfHeal reverts direct kubectl-level changes to GitOps-managed
   resources almost immediately. `spec.syncPolicy` was nulled out before
   injection and explicitly restored after, both live and in Git.

## Real observed result of the actual break test
- Broken image: `atlas-api:615f63af` (confirmed built, contains the
  forced-500 /ready handler from commit 615f63a).
- Injected directly via `kubectl patch` with Argo CD auto-sync disabled.
- Final observed Rollout phase: **Degraded**
- Detection-to-abort latency: **125 seconds**
- Live Rollout was explicitly patched back to the confirmed-good baseline
  (`atlas-api:1ac40ee7`) and Argo CD auto-sync re-enabled, confirmed
  Synced/Healthy afterward.

## Lesson for future direct-injection tests against CRD-backed resources
Never assume `kubectl set image` or the `kubectl argo rollouts` plugin are
available - verify with `kubectl api-resources | grep <kind>` and prefer
`kubectl patch` for any one-off CRD field change outside of GitOps.
