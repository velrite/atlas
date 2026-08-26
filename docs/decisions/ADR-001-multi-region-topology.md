# ADR-001: Two Independent Regional GKE Clusters, Active/Active

## Status
Accepted

## Context

Atlas is required to demonstrate multi-region resilience for a distributed
workload execution platform. A decision must be made early because it
affects nearly every later phase: how the network, GitOps configuration,
scheduler, and queue are designed.

The realistic options for running Kubernetes workloads across two GCP
regions are:

1. A single GKE cluster is not an option in the way it might first be
   imagined — GKE clusters do not span regions as one control plane serving
   nodes in two separate regions. A "regional" GKE cluster in GCP terminology
   replicates the control plane across zones *within one region* for control
   plane HA — it does not extend to a second region. To operate in two
   regions, two separate cluster resources are required.

2. Two independent regional GKE clusters, operated as **active/passive**:
   one cluster serves all traffic; the second is idle (or scaled to zero)
   until a failover event.

3. Two independent regional GKE clusters, operated as **active/active**:
   both clusters serve traffic simultaneously, with a Global Load Balancer
   distributing based on health and proximity.

## Problem

Which topology should Atlas implement to credibly demonstrate multi-region
resilience while keeping cost and complexity proportionate to a
single-engineer project with intermittent, multi-day gaps between work
sessions?

## Decision

Atlas will implement **two independent GKE clusters in two GCP regions,
operated active/active**, for the stateless job-execution plane, sitting
behind a GCP Global External HTTPS Load Balancer.

The queue design supporting this (single global queue vs per-region queues)
is deliberately **not decided in this ADR** — it depends on which managed
GCP primitive is selected in the workload platform phase, and will be
recorded in its own ADR once that trade-off is evaluated with the actual
service in hand.

## Alternatives Considered

- **Active/passive**: Simpler to reason about and cheaper if the passive
  cluster is scaled down, but it does not exercise real concurrent
  multi-region traffic handling, and failover behavior is materially
  different (and generally slower) than active/active. Rejected because it
  demonstrates less engineering depth and the project's explicit goal is to
  prove resilience under real, not simulated-at-rest, conditions.

- **Single "global" cluster via a service mesh spanning regions
  (e.g., Anthos-style multi-cluster mesh)**: Technically possible but adds
  substantial operational complexity (mesh control plane, cross-cluster
  service discovery) that is not justified at this project's scale and
  would obscure the core distributed-systems lessons Atlas is meant to
  teach. Rejected for this project's scope; noted as a legitimate
  production alternative worth mentioning in the final "what I'd change for
  real production" retrospective.

## Trade-offs

**Gains from active/active:**
- Real concurrent multi-region load, not a cold-standby simulation
- Forces genuine engineering decisions about queue architecture, data
  consistency, and idempotency across regions
- More representative of how resilience is actually built in production
  systems that need low RTO

**Costs of active/active:**
- Both clusters incur compute cost simultaneously when both are running,
  roughly double the cost of a single-region setup for the same node sizing
- Greater operational complexity: two sets of node pools, two sets of
  Kubernetes RBAC/NetworkPolicy to keep consistent, cross-region networking
  to reason about
- Given documented multi-day gaps between work sessions, ongoing dual-region
  cost is a real risk if clusters are left running unnecessarily; this will
  be mitigated operationally (documented teardown steps between sessions,
  and multi-region will only be provisioned starting at Phase 13, not
  before) rather than architecturally

## Consequences

- Development through Phase 12 will occur against a **single-region**
  cluster to avoid paying for dual-region infrastructure before the
  workload platform, CI/CD, GitOps, observability, and security layers are
  proven
- The second region is added deliberately in Phase 13, specifically to
  study multi-region behavior, and is expected to be torn down between
  sessions unless actively under test
- All Terraform for GKE will be written as a reusable module parameterized
  by region from the start, so the second cluster in Phase 13 is a matter
  of invoking the module again with different variables, not rewriting
  infrastructure code
