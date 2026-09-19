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
