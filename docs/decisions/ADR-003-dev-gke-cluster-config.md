# ADR-003: Zonal Single-Region Dev GKE Cluster (Standard Mode, On-Demand Nodes)

## Status
Accepted

## Context
Phase 2 requires a real GKE cluster to build and test the core workload platform against, before multi-region work begins in Phase 13 per ADR-001. A concrete decision was needed on cluster mode, node sizing, and node pricing model.

## Problem
What is the cheapest cluster configuration that still exercises genuine GKE primitives (RBAC, Workload Identity, NetworkPolicy, node pools) needed by later phases, without over-provisioning for a cluster that initially runs no real workload.

## Decision
A zonal (not regional) GKE Standard cluster was created in us-central1-a, named atlas-dev, with a single node pool of 2 e2-medium on-demand nodes. Workload Identity is enabled at the cluster level. The default node pool was removed and replaced with an explicitly configured pool so that machine type, labels, and workload metadata mode are all controlled by Terraform rather than left as GKE defaults.

## Alternatives Considered
A regional cluster was rejected for dev because it incurs the GKE cluster management fee, roughly 72 dollars a month, for control plane replication across zones, which is a production HA concern not needed while proving out the workload platform. GKE Autopilot was considered as a pod-based billing alternative but was not selected for this phase because Standard mode gives direct control over node pools, which later phases explicitly need for node pool level chaos experiments, taints, and Spot node migration. Spot or preemptible nodes were considered from the start but deliberately deferred until the chaos engineering phase, so that early debugging of the workload platform is not confounded by random node preemption.

## Trade-offs
On-demand e2-medium nodes cost more per hour than Spot equivalents, but provide stable, predictable capacity while the platform code itself is still being built and debugged. The cluster is zonal, meaning it has a single control plane replica; a zone outage would take the dev cluster down entirely, which is acceptable for a development environment and is explicitly not the multi-region resilience claim, which is scoped to Phase 13 onward.

## Consequences
This cluster will be destroyed between work sessions to avoid ongoing compute charges, consistent with the per-second billing model GKE and Compute Engine use. Node pool configuration, particularly the switch to Spot nodes, will be revisited explicitly in the chaos engineering phase rather than assumed now.
