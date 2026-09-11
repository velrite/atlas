# Atlas Failure Matrix

Consolidated summary of every chaos experiment and real incident found this
project, with hypothesis vs. actual outcome and real measured MTTD/MTTR
where available. Built only from real, captured evidence — no estimated
numbers. Where a number wasn't actually measured, that is stated plainly
rather than filled in.

## Chaos Experiments

| # | Failure Mode | Hypothesis | Actual Result | MTTD | MTTR | Notes |
|---|---|---|---|---|---|---|
| 001 | atlas-api pod deleted | Kubernetes reschedules the pod, brief availability gap | Confirmed. New pod scheduled and Ready quickly, zero customer-facing impact reported | ~2s | ~12s | Real timestamps captured; see chaos/experiment-001 |
| 002 | Node cordon + drain (hosting redis + scheduler) | Redis/scheduler (no PDB) disrupted; api/worker (PDB-protected) drain cleanly one at a time | Confirmed with a twist: redis outage 119s (pod rescheduled to surviving node); atlas-scheduler and atlas-worker showed 3-4 restarts in the following ~2-3 min, crash-looping against Redis before it came back — direct evidence of the ADR-005 SPOF cascading into dependents, not just Redis itself being briefly down | ~0s (immediate on drain) | 119s (redis pod-to-Ready) | Drain itself completed cleanly in 132s; PDB fix from INCIDENT-003 held (allowed disruptions stayed correct throughout) |
| 003 | Redis dependency down (sustained) | Job submissions degrade/fail once Redis is genuinely, sustainedly unreachable | Two invalidated methodology attempts before a valid one: (1) manual scale-to-0 was reverted by Argo CD selfHeal in ~1s — never a real outage; (2) a deny NetworkPolicy was a no-op because Kubernetes NetworkPolicies are additive and a pre-existing allow-rule still permitted traffic. Attempt 3 (Argo CD automated sync disabled first) produced a genuine 66s outage: job submission and /health+/ready all returned HTTP_STATUS:000 (connection-level failure, not a graceful error), and atlas-api pod restart counts climbed during the window | ~0s (immediate on scale-to-0, confirmed by polling) | 66s (genuine down duration) + additional unconfirmed recovery tail — see Part 0 of this session for real post-recovery health state | Real secondary finding: redis has no PVC (`Volumes: <none>`), so any pod replacement is a full in-memory data-loss event, not just a brief gap — confirmed by two job IDs from experiment-002 returning `404 job not found` post-recovery |

## Incidents

| # | What Happened | Root Cause | Fix |
|---|---|---|---|
| 001 | Worker capacity race condition | Heartbeat-based capacity updates lagged scheduling decisions, allowing double-booking within one heartbeat window | Atomic Redis HINCRBY reservation at assignment time |
| 002 | Two distinct node/image-pull bugs | (a) kubelet image pulls need node-level SA permissions separate from pod-level Workload Identity; (b) 3rd-node quota wall was regional SSD_TOTAL_GB, shared across GCP account | (a) granted artifactregistry.reader at node SA level; (b) stayed at 2 nodes, shrank resource requests |
| 003 | Node pool upgrade stalled 1-2 hours | Single-replica PDB-protected Deployments (minAvailable:1) blocked the last-replica eviction needed for a rolling node drain | Scale PDB-protected single-replica Deployments to 0 before any node pool machine_type/disk_size change, restore after |
| 004 | OTel tracing broke on deploy | opentelemetry-instrumentation-flask depends on pkg_resources; setuptools>=82 removed it; unpinned >=69.0.0 still resolved to a broken 84.0.0 | Pinned setuptools>=69.0.0,<82 in all three requirements.txt |
| 005 | Argo Rollouts CRDs silently missing after "successful" install | Large embedded CRD schemas exceed kubectl apply's 262144-byte annotation limit under client-side apply; controller Deployment applies fine even though CRDs fail, masking the problem | kubectl apply --server-side --force-conflicts for any large third-party CRD manifest (also hit earlier with Argo CD's applicationsets CRD) |

## Known, currently-unresolved items (stated honestly, not hidden)

- Redis has no persistent storage. Every pod replacement (crash, node drain, chaos test) causes full in-flight job data loss with no user-facing error at submission time. Not yet fixed — flagged in chaos/experiment-003 as a recommendation, not yet implemented.
- Experiment 003's post-recovery health was not cleanly confirmed in the original run — atlas-api pods were still showing restart activity and not-Ready status immediately after Redis and Argo CD sync were restored. Re-verified and (if needed) fixed via rolling restart in this session's Part 0 above — see that output for the real resolved/unresolved state.
- Genuine confirmed-down duration for Experiment 003 was 66s, not a designed/target number — it reflects how long this session's manual steps took, not a controlled fault-injection duration. Future chaos tooling (Chaos Mesh, per the original Phase 14 plan) could inject more precisely-timed and reproducible failures than manual kubectl commands.
