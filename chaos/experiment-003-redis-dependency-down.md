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
