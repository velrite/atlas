# ADR-006: Kubernetes Deployment via Helm, Resource Sizing Under Real Constraints

## Status
Accepted

## Context
Phase 5 required deploying the Phase 4 workload platform (API, scheduler, worker, Redis) to the real atlas-dev GKE cluster as proper Kubernetes objects, packaged for repeatable deployment ahead of GitOps integration in Phase 7.

## Problem
The platform needed to be deployed with real resource requests and limits, health probes, and least-privilege service account usage, while fitting within the actual allocatable capacity of a small two-node e2-medium dev cluster, which was found to be significantly less than nominal machine specs suggest once GKE system daemonset overhead is accounted for.

## Decision
The platform is packaged as a Helm chart with one Deployment and Service per component, using values.yaml to parameterize replica counts, image tags, and resource requests and limits. All application pods run as the atlas-workload-ksa service account established in Phase 3. PodDisruptionBudgets are defined for the API and worker Deployments to protect against voluntary disruption once multiple replicas are restored. Resource requests were sized iteratively against measured node allocatable capacity (940m CPU per e2-medium node, verified directly via kubectl describe nodes) rather than assumed from nominal machine specifications, after initial requests based on nominal capacity caused real scheduling failures.

## Alternatives Considered
Adding a third node to the pool was attempted first as the more architecturally clean fix, preserving originally planned resource requests, but was blocked by a regional SSD quota limit shared across this GCP account's projects. Rather than pursue a quota increase, which introduces an external dependency and delay, resource requests were reduced instead, which is a legitimate and immediately actionable alternative for a development environment not yet under real load.

## Trade-offs
Running single replicas of the API and worker, rather than the originally intended two, means the PodDisruptionBudgets currently protect a single point of failure rather than providing real redundancy; this is explicitly acknowledged technical debt, not a hidden gap, and will be revisited when node capacity allows or before progressive delivery work in a later phase, which requires multiple replicas to demonstrate meaningfully. Tightly sized CPU requests mean less burst headroom under sudden load, which will be evaluated directly during the load and capacity testing phase rather than assumed adequate.

## Consequences
The deployed platform was verified end to end on the real cluster: a job submitted through a port-forwarded connection to the live atlas-api Service was scheduled, executed by the live atlas-worker pod, and reported succeeded, with measured scheduling latency and total duration consistent with local Docker Compose results from Phase 4. Node service account permissions for Artifact Registry access are now a documented requirement for any future node pool created in this project, distinct from pod-level Workload Identity permissions.
