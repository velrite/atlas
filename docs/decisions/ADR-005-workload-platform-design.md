# ADR-005: Core Workload Platform Design (API, Redis Queue, Capacity-Based Scheduler, Worker)

## Status
Accepted

## Context
Phase 4 required a real, working distributed job execution system: an API to accept jobs, a queue to buffer them, a scheduler to assign them based on actual capacity, and workers to execute them and report results.

## Problem
The system needed to demonstrate genuine capacity-aware scheduling, not round-robin distribution, along with idempotency protection against duplicate execution and backpressure behavior when no worker has capacity, all while remaining simple enough to reason about and debug locally before any Kubernetes deployment.

## Decision
The platform is implemented in Python with Flask for the API. Redis is used as both the job queue, via BLPOP-based blocking lists, and as the worker capacity registry, via hashes with a heartbeat timestamp field. The scheduler polls the pending queue, evaluates all workers with a recent heartbeat as live candidates, filters to those with enough CPU and memory headroom for the job, and selects the least-loaded eligible worker, a best-fit bin-packing strategy. Workers self-report capacity based on in-memory tracking of jobs currently assigned to them, not real cgroup measurement. Idempotency is enforced by having a worker check a job's stored status before executing, skipping jobs already marked succeeded elsewhere. When no worker has capacity for a job, the scheduler requeues it at the back of the pending queue rather than dropping it or blocking indefinitely, which is the system's backpressure behavior.

## Alternatives Considered
A managed queue such as Google Cloud Pub/Sub or Cloud Tasks was considered and rejected for this phase specifically because it would hide the queueing mechanics, backpressure, and delivery semantics behind a managed API, undermining the project's goal of demonstrating understanding of these mechanics directly. Round-robin scheduling was rejected because it does not reflect real-world scheduling decisions and would not exercise or demonstrate capacity-aware placement logic. Measuring worker capacity from real OS or cgroup metrics was considered more realistic but was deferred, since it adds complexity that is better addressed once the system is running in Kubernetes, where actual resource enforcement exists via requests and limits.

## Trade-offs
Redis as both queue and capacity registry is a single point of failure in this phase's design; this is acceptable for a single-region development environment and will be revisited explicitly when multi-region work begins in Phase 13, where per-region Redis versus a globally available queue becomes a real architectural decision, not an oversight. Self-reported worker capacity, rather than measured capacity, means a worker that lies about its capacity or experiences unexpected resource pressure is not caught by the scheduler; this gap is intentionally left as a future chaos engineering test case rather than solved prematurely.

## Consequences
The system was validated locally using Docker Compose prior to any GKE deployment, confirming end-to-end behavior: a single job was submitted, scheduled in 3 milliseconds, executed, and reported as succeeded with an accurate total duration matching its simulated work time. A capacity-exhaustion scenario, three jobs each requesting more resources than a single worker's remaining capacity after one assignment, was used to confirm requeue and backpressure behavior directly in logs, rather than assumed from code inspection alone.
