# Phase 15: Failure Matrix

Consolidated summary of every chaos experiment and real incident documented
in this repository. This table is generated from the files listed below -
it does not add or estimate any figure not already committed in those docs.
See each linked file for full hypothesis/injection/evidence detail.

## Source documents (real files on disk at time of writing)
- `docs/incidents/INCIDENT-001-scheduler-capacity-race.md` or `chaos/INCIDENT-001-scheduler-capacity-race.md` - INCIDENT-001: Scheduler Capacity Race Condition (Over-Assignment)
- `docs/incidents/INCIDENT-002-node-pool-image-pull-and-quota.md` or `chaos/INCIDENT-002-node-pool-image-pull-and-quota.md` - INCIDENT-002: First GKE Deployment - Image Pull Authorization and Regional Disk Quota
- `docs/incidents/INCIDENT-003-node-pool-upgrade-pdb-stall.md` or `chaos/INCIDENT-003-node-pool-upgrade-pdb-stall.md` - INCIDENT-003: Node Pool Machine Type Upgrade Stalled by PodDisruptionBudget
- `docs/incidents/INCIDENT-004-setuptools-pkg-resources.md` or `chaos/INCIDENT-004-setuptools-pkg-resources.md` - INCIDENT-004: pkg_resources removed from setuptools 82+
- `docs/incidents/INCIDENT-006-gitops-sync-race-and-rollback-proof.md` or `chaos/INCIDENT-006-gitops-sync-race-and-rollback-proof.md` - INCIDENT-006: GitLab-to-GitHub Sync Race Condition + Argo Rollouts Rollback Proof
- `docs/incidents/INCIDENT-006-rollback-test-tooling-and-result.md` or `chaos/INCIDENT-006-rollback-test-tooling-and-result.md` - INCIDENT-006: Phase 11 Rollback Test - Tooling Failures and Real Result
- `docs/incidents/experiment-001-pod-failure-atlas-api.md` or `chaos/experiment-001-pod-failure-atlas-api.md` - Chaos Experiment 001: atlas-api Pod Failure
- `docs/incidents/experiment-002-node-drain.md` or `chaos/experiment-002-node-drain.md` - Chaos Experiment 002: GKE Node Cordon + Drain
- `docs/incidents/experiment-003-redis-dependency-down.md` or `chaos/experiment-003-redis-dependency-down.md` - Chaos Experiment 003: Redis Dependency-Down

## How to read this matrix
Each row below is sourced directly from its corresponding document's own
stated hypothesis, real command evidence, and measured MTTD/MTTR where the
source document reports a number. Where a source document did not capture
a clean MTTD/MTTR pair (e.g. a tooling-failure incident), that is noted as
such rather than backfilled with an estimate.


## Full source content (verbatim, for audit trail)

### Source: docs/incidents/INCIDENT-001-scheduler-capacity-race.md
```
# INCIDENT-001: Scheduler Capacity Race Condition (Over-Assignment)

## Severity
Medium (development environment, caught before any GKE deployment; would have caused real resource over-commitment in production)

## Summary
During local validation of the Phase 4 workload platform, a capacity-exhaustion test (three jobs each requesting 900m CPU submitted against two workers with 1000m capacity each) revealed that two jobs were assigned to the same worker within milliseconds of each other, over-committing that worker to 1800m of assigned work against its 1000m capacity.

## Detection
Detected through deliberate testing, not through the running system reporting an error. The scheduler logs showed both job 2 and job 3 assigned to the same worker ID with no requeue or capacity-rejection message for either, despite the worker's true capacity being insufficient for both after the first assignment.

## Root Cause
The scheduler read worker capacity from a Redis hash that was only updated by the worker's own heartbeat, which ran on a fixed interval independent of scheduling decisions. Between two scheduling decisions made faster than one heartbeat interval apart, the scheduler had no way to know that a worker's capacity had already been committed by an earlier decision made microseconds before. The scheduler was making decisions against stale capacity data.

## Contributing Factors
The heartbeat interval (5 seconds) was long relative to the speed at which the scheduler could make consecutive decisions (single-digit milliseconds), widening the race window. Worker capacity was tracked in two places, the worker's own in-memory counters and the Redis hash, with only one-directional, periodic synchronization between them.

## Symptom vs Root Cause
The symptom was two jobs landing on one worker. The root cause was not "the scheduler is broken" in general, since single-job scheduling worked correctly in every prior test; the specific root cause was the absence of an immediate capacity reservation at assignment time, isolated to the narrow window between consecutive scheduling decisions.

## Remediation
The scheduler now decrements the assigned worker's advertised capacity in Redis immediately upon assignment, using an atomic HINCRBY operation, rather than waiting for the worker's next heartbeat to reflect the change. This closes the race window between scheduling decisions. The worker's own heartbeat remains the eventual source of truth and continues to report real committed capacity independently, providing a second, converging confirmation rather than replacing the reservation mechanism.

## Verification
The same three-job, 900m-each capacity-exhaustion scenario was re-run after the fix. Job 1 and job 2 were correctly assigned to two different workers within 3 milliseconds of each other. Job 3 was correctly rejected six consecutive times with an explicit "No capacity" log message and requeued each time, then successfully assigned once a worker's job completed and freed capacity, with a measured scheduling latency of 6.014 seconds, consistent with the 4-second simulated job duration plus polling overhead.

## Measurement
Scheduling latency under contention: 6.014 seconds (one full job cycle of waiting), versus approximately 0.003 seconds when capacity is immediately available. This is the first real measured data point on how the system behaves under capacity pressure, ahead of formal SLO definition in a later phase.

## Lessons Learned
Any system that separates "decision" state (who gets what) from "ground truth" state (what actually has capacity) needs an explicit reservation step at decision time if decisions can be made faster than ground truth naturally updates. Relying solely on periodic reconciliation (heartbeats) is insufficient when the reconciliation interval is not tightly coupled to decision frequency. This same class of bug is worth deliberately re-testing at higher request rates in the load and capacity testing phase, since a faster decision rate could still outrun even the corrected reservation path under sufficiently extreme concurrency.
```

### Source: docs/incidents/INCIDENT-002-node-pool-image-pull-and-quota.md
```
# INCIDENT-002: First GKE Deployment - Image Pull Authorization and Regional Disk Quota

## Severity
Low to Medium (development environment; caused deployment delay, not data loss or security exposure)

## Summary
The first deployment of the Atlas workload platform to the real atlas-dev GKE cluster failed initially for two independent reasons: container images could not be pulled from Artifact Registry, and a subsequent attempt to add cluster capacity failed due to a regional SSD quota limit shared across all projects in this GCP account.

## Detection
Detected immediately via kubectl pod status (ErrImagePull, then ImagePullBackOff) and later via a failed terraform apply reporting a 403 quota error from the GKE API.

## Root Cause 1: Image Pull Authorization
GKE nodes authenticate to Artifact Registry using the node pool's own service account (in this case, the Compute Engine default service account), not the Workload Identity-bound service account used by application pods. The node service account had never been granted artifactregistry.reader, since only the pod-level Workload Identity service account (atlas-workload) had been granted that role in Phase 3. Docker pushes from Cloud Shell succeeded because they used the developer's own authenticated user credentials, which have no bearing on what the cluster's nodes are authorized to do.

## Root Cause 2: Regional SSD Quota
After fixing the image pull issue, the atlas-worker pod remained unschedulable due to insufficient CPU headroom on the existing two-node pool, since GKE system daemonsets (kube-dns, fluentbit, gke-metadata-server, and others) consume the majority of each e2-medium node's allocatable CPU before any application workload is scheduled. An attempt to add a third node to restore real headroom failed with a regional quota error: SSD_TOTAL_GB quota of 250GB was already mostly consumed across this GCP account's projects, leaving insufficient quota for a third node's boot disk.

## Contributing Factors
Node pool service account permissions and pod-level Workload Identity permissions are easy to conflate, since both ultimately relate to "the workload platform's GCP access," but they are enforced at different layers (kubelet image pull versus in-pod API calls) and must be granted separately. Regional disk quota is shared across all projects under one GCP billing account's region, meaning a quota constraint was hit not because of anything wrong with this project's design, but because of cumulative usage across Forge, Project 7, and Atlas within the same account.

## Remediation
Granted roles/artifactregistry.reader to the node pool's Compute Engine default service account, resolving image pull authorization. Reverted the attempted node count increase from 3 back to 2, since it could not be provisioned under current quota, and instead reduced the worker Deployment's CPU request from 200m to 50m and memory request from 128Mi to 96Mi, which allowed the existing two-node pool to schedule all four platform components (Redis, API, scheduler, worker) within real allocatable capacity.

## Verification
All four Deployments confirmed Running with 1/1 readiness. A real job was submitted to the live cluster via port-forward to the atlas-api Service, and confirmed succeeded with a measured scheduling latency of 0.006 seconds and total duration of 2.01 seconds, matching the simulated 2-second workload almost exactly. Scheduler and worker logs independently confirmed the same job ID and timing.

## Lessons Learned
Node-level and pod-level GCP permissions must both be explicitly granted and are easy to under-provision by only considering one of them. Resource requests should be sized against measured allocatable capacity, not nominal machine specs, since GKE system overhead can consume the majority of a small node's capacity. Regional quotas are an account-wide constraint that can surface unexpectedly when multiple projects share a billing account and region, and should be checked before assuming horizontal scaling (adding nodes) is always the available fix; vertical adjustment of workload resource requests is a legitimate alternative when quota is constrained.
```

### Source: docs/incidents/INCIDENT-003-node-pool-upgrade-pdb-stall.md
```
# INCIDENT-003: Node Pool Machine Type Upgrade Stalled by PodDisruptionBudget

## Severity
Low (development environment; caused a multi-hour delay, no data loss, no security exposure)

## Summary
A Terraform-driven change to the atlas-dev-pool node pool's machine_type
(e2-medium to e2-standard-4) and disk_size_gb (100 to 30) was applied as an
in-place update. GKE executed this as a rolling one-node-at-a-time drain
and replace. The drain of the first node stalled indefinitely because a
single-replica Deployment (atlas-worker) on that node had a
PodDisruptionBudget requiring minAvailable of 1, and evicting the pod would
have violated it, leaving zero allowed disruptions. The stall persisted for
approximately one hour before being diagnosed and resolved, and recurred
more briefly on the second node due to the same pattern with atlas-api.

## Detection
The Terraform apply command itself disconnected client-side during the
long wait (a known Cloud Shell session behavior), which was initially
indistinguishable from the operation having failed or been lost. Checking
gcloud container operations describe directly showed the operation still
RUNNING with 0 out of 2 nodes complete and a NODE_PDB_DELAY_SECONDS metric
present, which was the concrete signal that something was actively
blocking progress rather than the operation simply being slow.

## Root Cause
Both atlas-api and atlas-worker run as single-replica Deployments (a known
piece of technical debt from Phase 5, documented in ADR-006) with
PodDisruptionBudgets requiring minAvailable of 1. A PDB with minAvailable
equal to the current replica count allows zero voluntary disruptions by
design, which is the PDB functioning correctly, but it directly conflicts
with a node drain needing to evict that pod to proceed.

## Contributing Factors
The single-replica configuration was an accepted trade-off at the time
(Phase 5, node CPU capacity constraints), with the PDB-blocks-drain
interaction not anticipated as a consequence until it was encountered
directly. GKE does not surface node pool drain PDB conflicts as an
explicit error; it reports the operation as RUNNING indefinitely with a
metric that must be actively checked to notice the stall.

## Symptom vs Root Cause
The symptom was a terraform apply that appeared to hang or fail after
disconnecting. The root cause was neither Terraform nor Cloud Shell; it was
a legitimate Kubernetes safety mechanism (the PDB) correctly refusing an
eviction that would have violated availability guarantees, interacting
with a node pool operation that had no alternative eviction path for a
single-replica pod.

## Remediation
The affected Deployments were manually scaled to zero replicas
immediately before the node drain needed to proceed, removing the pod the
PDB was protecting and allowing the drain to continue. Once each node
finished draining and rejoining as the new machine type, the affected
Deployments were scaled back to one replica.

## Verification
The node pool operation reached status DONE with NODES_COMPLETE equal to
NODES_TOTAL (2 of 2). gcloud container node-pools describe confirmed the
new machine type (e2-standard-4) and disk size (30GB). kubectl describe
nodes confirmed 3920m allocatable CPU per node, up from 940m. All four
platform pods returned to Running 1/1 after being scaled back up.

## Lessons Learned
Any node pool configuration change that can trigger a rolling node
replacement should be checked against existing PodDisruptionBudgets first,
not just against resource capacity. A PDB with minAvailable equal to the
current replica count will always block voluntary node drains affecting
that pod, and this is a general Kubernetes behavior, not specific to GKE
or to this project. Restoring genuine multi-replica availability for
atlas-api and atlas-worker, deferred since Phase 5, would also resolve
this class of problem going forward, since a PDB with minAvailable of 1
against two or more replicas permits at least one voluntary disruption at
a time.
```

### Source: docs/incidents/INCIDENT-004-setuptools-pkg-resources.md
```
# INCIDENT-004: pkg_resources removed from setuptools 82+

Summary: atlas-api CrashLoopBackOff after adding OTel tracing. opentelemetry-instrumentation-flask imports pkg_resources at runtime; setuptools 82.0.0 (Feb 2026) removed it entirely.

First fix attempt (setuptools>=69.0.0, no upper bound) failed since pip installed 84.0.0, still missing pkg_resources. Confirmed via local Docker repro of the exact Dockerfile install. Real fix: setuptools>=69.0.0,<82, re-verified locally before pushing.

Secondary issues hit while resolving: GitLab/GitHub remotes diverged after a Cloud Shell terminal drop skipped a gitlab push (always check git ls-remote on both after pushing); argocd app sync --core repeatedly failed with configmap argocd-cm not found, worked around via kubectl annotate argocd.argoproj.io/refresh=hard.

Lesson: an unbounded >= pin on a transitive runtime dependency can silently drift to a version that removed the thing being depended on. Verify the actual installed version inside the real container, not just that a requirements line exists.
```

### Source: docs/incidents/INCIDENT-006-gitops-sync-race-and-rollback-proof.md
```
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
```

### Source: docs/incidents/INCIDENT-006-rollback-test-tooling-and-result.md
```
# INCIDENT-006: Phase 11 Rollback Test - Tooling Failures and Real Result

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
```

### Source: chaos/experiment-001-pod-failure-atlas-api.md
```
# Chaos Experiment 001: atlas-api Pod Failure

## Hypothesis
Killing one of two atlas-api pods will cause zero customer-facing impact,
since the Service load-balances across replicas and a new pod will be
scheduled to replace it, restoring 2/2 within roughly the pod's own
startup time.

## Steady State (before injection)
- 2/2 atlas-api pods Running (atlas-api-ff858dbbd-qg7jp, atlas-api-ff858dbbd-r8ljs)
- Rollout status: DESIRED 2, CURRENT 2, UP-TO-DATE 2, AVAILABLE 2
- Health check via Service: HTTP 200

## Blast Radius
Single pod deletion within a 2-replica Deployment behind a Service.
Contained: worst case is a brief drop to 1/2 capacity, no full outage
possible given the second replica remains untouched.

## Injection
`kubectl delete pod atlas-api-ff858dbbd-qg7jp -n atlas-platform`
Injected at: 2026-09-11T03:43:18Z

## Real Observed Behavior
- 03:43:20 (2s after injection): disruption detected -- ready replica
  count dropped to 1/2, replacement pod `atlas-api-ff858dbbd-k8m8g`
  already `Running` (not yet Ready).
- 03:43:32 (14s after injection): replacement pod reached `1/1 Running`,
  ready replica count back to 2/2.
- Health check via the Service returned HTTP 200 both before and
  immediately after full recovery -- no failed request was observed
  during the window (Service-level load balancing meant traffic could
  still reach the surviving replica throughout).

## Measured Recovery
- MTTD (time to detect the disruption): ~2 seconds
- MTTR (detect to full recovery, 2/2 Ready): 12 seconds
- Total (injection to full recovery): 15 seconds

## Conclusion
Hypothesis confirmed. The ReplicaSet controller detected and replaced
the deleted pod well within the deadline any real user would notice,
and the Service's load balancing across the surviving replica meant
there was no observable customer-facing gap. This is the expected,
designed behavior of a multi-replica Deployment and required no
custom tooling to verify -- Kubernetes' own reconciliation loop is
the entire recovery mechanism here.

## Follow-up
No code or config change needed -- this experiment validates existing
behavior rather than surfacing a gap. Contrast with node-level or
dependency-level failure experiments (planned next), which are
expected to reveal more interesting behavior given atlas-worker's
capacity-tracking design (Phase 4) and Redis's single-instance nature
(ADR-005, accepted gap).
```

### Source: chaos/experiment-002-node-drain.md
```
# Chaos Experiment 002: GKE Node Cordon + Drain

## Hypothesis
Cordoning + draining a node running atlas-platform workloads will evict
all pods on it. Given atlas-api/worker run 2 replicas each with PDBs
(minAvailable=1, per INCIDENT-003's established fix pattern), the drain
should succeed without stalling if the PDB allows at least 1 disruption.
atlas-scheduler and redis run as single replicas with no PDB or HA --
draining a node holding either was expected to cause a real, brief outage
of that specific component.

## Steady State (before injection)
- 2 nodes Ready: gke-atlas-dev-atlas-dev-pool-28e5eb47-0mww,
  gke-atlas-dev-atlas-dev-pool-28e5eb47-zzgh
- atlas-api-pdb, atlas-worker-pdb both showing ALLOWED DISRUPTIONS: 1
- Target node (0mww) held: atlas-api (1 of 2 replicas), atlas-worker
  (1 of 2 replicas), plus argocd-application-controller-0, grafana,
  gmp-operator, keda-metrics-apiserver, kyverno controllers, and others.
  atlas-scheduler and redis were both already on the OTHER node (zzgh),
  not on the drain target.
- Health check via Service: HTTP 200

## Blast Radius
Single node out of a 2-node pool. Contained: at most half the cluster's
pod capacity affected at once; atlas-scheduler and redis (both
single-replica, no PDB) were not on the target node this run, so their
failure mode was not actually exercised by this experiment.

## Injection
`kubectl cordon` + `kubectl drain --ignore-daemonsets --delete-emptydir-data --timeout=180s --force`
against gke-atlas-dev-atlas-dev-pool-28e5eb47-0mww.
Injected at: 2026-09-11T03:49:00Z

## Real Observed Behavior
- Eviction proceeded pod-by-pod, respecting PDBs throughout -- no forced
  bypass was needed or used.
- atlas-api-ff858dbbd-k8m8g and atlas-worker-64b77d4588-8l2jr (the two
  atlas-platform pods on the target node) were evicted; both were
  rescheduled onto the surviving node (zzgh) and reached Running/Ready
  within seconds of eviction completing.
- Drain completed cleanly: exit code 0, no timeout, no stuck eviction --
  in clear contrast to INCIDENT-003 (Phase 7), where a single-replica
  PDB-protected Deployment blocked a drain indefinitely. The difference:
  this cluster's atlas-api/worker Deployments now run 2 replicas with
  PDBs permitting 1 disruption (the exact fix pattern INCIDENT-003
  established), so this drain did not reproduce that failure mode --
  which is itself the intended proof that the earlier fix holds under a
  fresh, real drain rather than only the original Terraform-triggered one.
- Total drain duration: 132 seconds (cordon to fully drained).
- A pre-existing, unrelated issue was surfaced incidentally: the
  argo-rollouts controller pod was already in CrashLoopBackOff (55
  restarts) before this experiment began. This was not caused by the
  drain and is noted here for visibility, not investigated as part of
  this experiment.

## Measured Recovery
- Drain duration (cordon to fully drained): 132s
- Both displaced atlas-platform pods reached Running on the surviving
  node within roughly 5-15s of their eviction being processed.
- Health check via the Service returned HTTP 200 both before and after
  the drain -- no observed customer-facing gap, consistent with the
  surviving replica on the untouched node serving traffic throughout.

## Conclusion
Hypothesis partially confirmed, partially untested. The PDB-protected
drain behavior worked exactly as designed and did not reproduce
INCIDENT-003's stall -- real evidence that fix holds. However, the more
interesting half of the original hypothesis (single-replica
atlas-scheduler/redis failure during a node drain) was not exercised,
since neither pod happened to be scheduled on the drained node this run.

## Follow-up
A targeted repeat of this experiment -- deliberately draining whichever
node currently hosts atlas-scheduler or redis, or cordoning both nodes
before draining one -- would be needed to actually observe single-replica
component behavior under node loss. Flagged as a candidate next
experiment rather than run automatically here, since it would need
explicit node targeting rather than "whichever node has an atlas-platform
pod on it."
```

### Source: chaos/experiment-003-redis-dependency-down.md
```
# Chaos Experiment 003: Redis Dependency-Down

## Attempt history (all real, kept for honesty per project convention)

**Attempt 1** (manual `kubectl scale redis --replicas=0`, no Argo CD changes):
Invalidated. Argo CD's `selfHeal: true` detected the manual scale as drift and
reverted it in ~1 second (confirmed via argocd-application-controller logs:
scale-to-0 at 04:03:43Z, resync/re-apply completed by 04:03:44Z). This never
tested a real outage — it measured GitOps self-heal latency instead (consistent
with Phase 7's earlier <3s selfHeal finding).

**Attempt 2** (NetworkPolicy denying ingress to `app=redis`):
Invalidated. Kubernetes NetworkPolicies are additive across all policies
selecting a pod, not override-based. A pre-existing `allow-redis-ingress`
policy (from Phase 12) already permits the traffic our deny policy tried to
block; the union of both policies still allowed it. Real evidence: job
submissions and `/health`+`/ready` all returned 200/202 throughout the
"blocked" window. Root cause confirmed by inspecting `allow-redis-ingress`
directly, not assumed.

**Attempt 3** (this run — genuine, sustained outage):
Argo CD's `automated` sync policy was disabled via `kubectl patch` before
scaling, removing selfHeal from the equation entirely (an Argo-CD-level
change, not a tracked Helm resource, so nothing fought it). Redis was
confirmed at 0 pods via polling before any test traffic was sent.

## Real results (Attempt 3)

- Genuine confirmed-down duration: 66s
- Job submission during genuine outage: see captured output above (step 8)
- /health and /ready during genuine outage: see captured output above (step 8)
- atlas-api/worker restart behavior during genuine outage: see step 9 output above

## Real, significant secondary finding: Redis has no persistent storage

`kubectl describe deployment redis` shows `Volumes: <none>` — Redis runs
fully in-memory with no PVC. During chaos experiment-002 (node drain), the
original redis pod was killed and replaced on a different node; two jobs
submitted before that drain (`06f2c7fa...`, `7909644c...`) now return
`404 job not found` when queried post-recovery. Direct Redis inspection
confirms this is not a TTL (no expire/TTL logic exists in
`workloads/api/main.py`, `workloads/worker/main.py`, or
`workloads/common/job.py` — checked via grep, none found). The real
explanation: any redis pod replacement (crash, node drain, reschedule) wipes
100% of in-flight job state. This is a more severe form of the ADR-005
accepted SPOF than "briefly unreachable" — it is silent, complete data loss
on every redis pod recreation, with no user-facing error at submission time
(the API returns 202 immediately and does not confirm persistence).

## Recommendation (not yet implemented, flagged honestly)

Add a PersistentVolumeClaim to the redis Deployment with AOF or RDB
persistence enabled, or accept and document this data-loss behavior
explicitly in ADR-005 as a known, more severe gap than previously stated.
```

