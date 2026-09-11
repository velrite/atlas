# ADR-018 Follow-Up: Multi-Region Expansion (Phase 13) Deliberately Deferred

## Status
Deferred by deliberate scope decision. Not implemented. This is a
documented engineering trade-off, not an oversight or a skipped step.

## Context
ADR-018 committed to an active/active, two-region GKE topology behind a
Global External HTTPS Load Balancer, with the queue's cross-region
architecture explicitly left open pending real implementation experience.
By Phase 12, Atlas had already produced real, evidenced work across
observability, SLOs, autoscaling, progressive delivery with a genuine
automated-rollback proof, and policy-as-code with genuine captured
admission rejections. Phase 13 was evaluated against what it would add
to that.

## The real trade-off, stated plainly
Multi-region is expensive in the one resource this project can't get
back: continuous runtime spend on infrastructure that exists to
demonstrate a pattern rather than to serve real traffic. A second
GKE cluster (2x e2-standard-4, matching the existing node pool) plus a
Global External HTTPS Load Balancer roughly doubles the project's
ongoing compute cost, and unlike every other phase so far -- which
produced artifacts that keep their value after teardown (dashboards,
alert policies, rollout strategies, admission policies, incident
writeups) -- a live second region only demonstrates its value while
it is running and being actively exercised. Left idle between work
sessions, it is pure cost with no compounding signal.

Multi-region also does not stand alone: it depends on a genuinely hard,
still-unresolved decision -- the queue's cross-region architecture. Redis
today is a single in-cluster instance with no replication (ADR-005,
accepted since Phase 4). Extending it to two regions has no clean
default answer:
- **Two independent per-region Redis instances** is simplest and cheapest,
  but is not actually active/active for the queue -- a job submitted in
  Region A can never be picked up by a Region B worker. This satisfies
  the topology requirement while quietly failing the point of the
  requirement.
- **Cloud Pub/Sub** is naturally global and would be the correct answer
  for a real production system, but it means replacing Redis as the
  queue entirely -- a real, non-trivial rewrite of `workloads/common/job.py`
  and the scheduler's assignment logic, not a config change.
- **Redis cross-region replication** gets closest to true active/active
  but introduces real operational complexity (replication lag, split-brain
  handling, failover orchestration) disproportionate to a project whose
  explicit goal from ADR-018 onward has been single-region-first for cost,
  with multi-region deferred until it could be done for a real reason.

Building the topology (two clusters + LB) without resolving this
underlying decision would produce a demo that looks multi-region but
isn't meaningfully active/active -- the kind of surface-level result
this project has deliberately avoided at every other phase (see
INCIDENT-001 through 005, all of which exist because this project chose
to dig into real root causes rather than accept a shallow "it works").

## Decision
Defer Phase 13 implementation. Keep the architecture decision fully
documented (this file + ADR-018) so the reasoning is auditable, rather
than silently dropping the phase or building a hollow version of it.

## If this were built, here is exactly how (kept precise, not vague)
1. Confirm regional quota headroom in the second region
   (`gcloud compute regions describe <region>`) before provisioning --
   this project already hit a real regional SSD quota wall once (Phase 5)
   and treats this check as non-optional.
2. Instantiate the existing, already region-parameterized GKE Terraform
   module (`terraform/modules/gke`, which already takes `region`/`zone`
   as variables) a second time in `terraform/environments/dev/main.tf`
   for the second region, with its own VPC/subnet and node pool sized to
   match the existing one.
3. Resolve the Redis cross-region decision FIRST, before deploying the
   second region's workloads -- this is the actual hard part of the
   phase and determines what the rest of the work looks like. Given this
   project's existing values (favor teaching-clear mechanics, avoid
   over-engineering, Phase 4's ADR-005 reasoning), Cloud Pub/Sub would be
   the recommended real answer if this were built for production;
   per-region-isolated Redis would be the recommended answer if the goal
   were purely to demonstrate the GKE/LB topology cheaply without solving
   queue semantics.
4. Deploy a Global External HTTPS Load Balancer with backend services
   pointing at both regional clusters' Services.
5. Run a real, explicitly-labeled *simulated* regional failure (scale one
   region's Deployments to 0 or block it via NetworkPolicy -- this project
   does not claim to simulate an actual GCP regional outage) and measure
   real RTO/RPO with real timestamps, following the same
   hypothesis-then-inject-then-measure discipline used throughout.
6. Update ADR-018's status and document what was actually built vs. what
   was originally planned, since implementation always reveals things a
   pre-implementation ADR can't know -- consistent with how every other
   ADR in this project has been treated.

## Consequences
- Atlas remains single-region through the end of this project's build.
- This is disclosed as a known, deliberate limitation in the eventual
  Phase 18 final retrospective, not hidden.
- The reasoning above -- not just the conclusion -- is the artifact:
  the ability to identify a hard sub-decision, weigh three real options
  against a project's own stated values and constraints, and make an
  explicit, reversible scope call under a real cost constraint, is itself
  evidence of the systems thinking this project exists to demonstrate.
