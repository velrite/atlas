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
