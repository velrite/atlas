# Reliability Model

## Health check strategy

Atlas Operator never presents a fabricated uniform health signal. Each
component's health is labeled by its real evidence source:

- `httpHealthCheck` — `atlas-api`, `operations-api` (`/health`, `/ready`)
- `podStatus` — `redis` (no HTTP surface at all, only `redis-cli PING`)
- `metricsInferred` — `atlas-scheduler`, `atlas-worker` (Prometheus
  metrics only, no HTTP health route)

## Real observed degraded scenario

The one degraded scenario currently modeled end-to-end (fixtures +
Diagnostics reasoning + Overview "Primary issue" card) is a worker
capacity saturation pattern, kept consistent everywhere it appears:

- Worker CPU: 94%
- Requeue rate: +418%
- Redis / API / Scheduler: Healthy

This consistency is deliberate — the same evidence numbers appear on
both the Overview screen and the Diagnostics screen so the two never
contradict each other.

## Queue behavior

`atlas:queue:pending` is almost always empty in practice — the
scheduler drains it in roughly 5–25ms. Showing "queue depth: 0" as a
health signal would look broken even when the system is healthy, so job
list state is treated as the more honest signal, not queue depth.

## Rollback

Argo Rollouts canary steps: 7 total.
`progressDeadlineAbort` measured at 125s rollback time in testing.

## Known reliability gaps (explicitly not hidden)

- `redis` has no PVC — job loss on pod replacement is silent, with no
  error surfaced anywhere in the system today. **NOT YET
  ADDRESSED.**
- Grafana has no PVC either — its SQLite datastore resets on pod
  reschedule, which has wiped its GMP datasource token twice during this
  project's history, both times requiring manual recovery. **NOT
  AUTOMATED.**
- GMP (Google Managed Prometheus) query results can lag real `/metrics`
  values by several minutes (Monarch backend ingestion lag). Any UI
  showing GMP-derived data must show a freshness timestamp and must
  never imply real-time accuracy.
