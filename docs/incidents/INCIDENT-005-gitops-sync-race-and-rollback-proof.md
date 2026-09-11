# INCIDENT-006: GitLab-to-GitHub Sync Race Condition + Argo Rollouts Rollback Proof

## Summary
Two related real issues surfaced during Phase 11 Step 6 evidence capture:
(1) scripts-sync-github.sh's blind `git push` to GitHub raced against
concurrent manual/CI pushes and failed repeatedly, causing gitops-update
jobs to fail after a successful image build+push; (2) once the sync issue
was mitigated, a deliberate-break test was run end-to-end to prove Argo
Rollouts' automatic canary abort and rollback, producing real timing
evidence.

## Part 1: Sync race condition

### Root cause
scripts-sync-github.sh originally did a plain `git push` to GitHub with no
fetch/rebase first. Since GitHub was also being pushed to directly and by
CI at various points, the script's stale local clone repeatedly lost the
race, causing `! [rejected] main -> main (fetch first)` failures.

### Fix
Rewrote the script to fetch + rebase onto GitHub's real current tip
immediately before pushing, with one retry on conflict. Preserved the
original `x-access-token:${GITHUB_PUSH_TOKEN}@` auth URL format (an earlier
fix attempt dropped this prefix by mistake and had to be corrected).

### Residual gap (not yet closed)
Even after the fix, isolated pushes during this same session still hit
`(fetch first)` at points where a human and CI pushed to GitHub in close
succession outside the sync script's own retry window (see git history
around commits 8455407, d98aaee, bef789e, 268ad6b). These were resolved
manually each time via fetch + merge, never via force-push, so no history
was lost. This suggests the sync script's single retry may not be
sufficient under tight human+CI push concurrency -- a candidate follow-up
is increasing retry count or serializing gitops-update pushes with a lock.
Flagged as future hardening work, not blocking for Phase 11 completion.

## Part 2: Rollback proof (Phase 11 Step 6)

### Method
With the platform Healthy on image b8bf4eb2, a deliberate change was made
to workloads/api/main.py's /ready endpoint to unconditionally return 500.
This was committed, pushed through the pipeline, and the resulting image
(d98aaee2) was manually promoted via values.yaml once confirmed built and
present in Artifact Registry (gitops-update did not land the bump
automatically for this commit -- same class of issue as Part 1).

### Real evidence
- Break injected (git push): 03:12:51 UTC
- Broken image observed in live Rollout spec: 03:13:02 UTC (11s)
- Automatic abort (`status.phase: Degraded`): 03:15:00 UTC
- Total injection-to-abort: 129 seconds (progressDeadlineSeconds=120 + reconcile overhead)
- Rollout events confirmed the exact mechanism:
  `RolloutAborted: ReplicaSet "atlas-api-5b64649cf9" has timed out progressing`
  followed by `ScalingReplicaSet ... from 1 to 0`.
- `status.stableRS` remained pinned to the original stable ReplicaSet
  (67bb47546c) throughout -- traffic never shifted to the broken canary.
- A health check against the live Service returned HTTP 200 continuously
  through the entire abort sequence.
- The breakage was then reverted in git; the platform returned to
  `Phase: Healthy` on the corrected image, confirmed via live rollout and
  pod status plus a final HTTP 200 health check.

### Conclusion
Argo Rollouts' `progressDeadlineAbort` mechanism works as designed: a
genuinely broken deploy was detected and automatically rolled back with no
human intervention, in a time consistent with the configured deadline, with
zero observed customer-facing impact (stable ReplicaSet never lost
availability).
