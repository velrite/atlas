# ADR-012: Metrics Instrumentation via Google Managed Prometheus

## Status
Accepted

## Context
Phase 8 required real metrics, logs, and traces from Atlas's own
components, not just infrastructure-level dashboards, to provide the
measurement foundation for SLO definition in the next phase.

## Problem
Choose a metrics collection approach that provides genuine application-level
visibility (request rates, scheduling latency, job outcomes) without adding
unnecessary resource cost or duplicating capability already present in the
cluster.

## Decision
Google Managed Prometheus, already running in the gmp-system namespace as
part of GKE at no additional cost, is used as the metrics backend rather
than installing a separate self-managed Prometheus. The API, scheduler,
and worker were each instrumented directly using the prometheus-client
Python library: the API exposes a Flask /metrics route on its existing
port 8080; the scheduler and worker, which have no HTTP server otherwise,
each run a minimal metrics HTTP server on port 9090 via
prometheus_client.start_http_server. Three PodMonitoring custom resources,
GMP's mechanism for declaring scrape targets, direct GMP to scrape all
three components every 15 seconds.

Metrics chosen reflect what the platform's own domain model already
considers meaningful: request count and latency for the API; jobs
scheduled, jobs requeued for lack of capacity, scheduling latency, and
live worker count for the scheduler; jobs executed by outcome
(succeeded, dead_letter, retry) and execution duration for the worker.

## Alternatives Considered
Installing a separate, self-managed Prometheus was considered and rejected
after confirming GMP was already running and had substantial available
capacity, since duplicating metrics collection infrastructure would
consume resources without adding capability GMP does not already provide
for cluster-level and, once instrumented, application-level metrics.

## Trade-offs
Google Managed Prometheus is GKE-specific and would need to be replaced
with self-managed Prometheus or another backend if this platform were ever
run outside GKE. This is accepted as a reasonable trade-off given the
project's explicit GKE focus, and is noted here as a portability
limitation rather than left unstated.

## Consequences
All three workload components now expose Prometheus-format metrics and
are actively scraped by GMP every 15 seconds. This is a prerequisite for
Phase 9 SLO definition, which requires real baseline measurements rather
than assumed targets, and for later chaos engineering phases, which need
to observe the platform's behavior quantitatively during induced failures.
