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
