# ADR-015: SLI/SLO Definitions

## Status
Proposed -- baseline data is real but low-volume (21 jobs). Targets
below are a reasonable starting point, not a statistically robust
production baseline. Revisit once genuine traffic volume exists.

## Real baseline data (captured 2026-09-09, 21 test jobs, 1h window)

| Metric | p50 | p95 | p99 |
|---|---|---|---|
| API request latency | 5ms | 5ms | 5ms |
| Scheduling latency | 7.5ms | 9.75ms | 9.95ms |
| Worker job duration | 2.375s | 4.725s | 4.945s |

Success rate: 100% (21/21) -- after fixing INCIDENT-004's payload
validation gap; prior contaminated test data (malformed payloads)
showed an artificially low ~13% success rate and was excluded.

Worker job duration directly reflects test payloads' random
1-4s simulated_duration_seconds, not real workload characteristics --
this SLI's target will need revisiting once real jobs run.

## Proposed SLIs

1. **API availability**: proportion of /jobs POST requests returning
   2xx, measured via atlas_api_requests_total{status=~"2.."} /
   atlas_api_requests_total.
2. **API latency**: proportion of /jobs POST requests completing
   under a latency threshold, measured via
   atlas_api_request_duration_seconds histogram.
3. **Scheduling latency**: time from job submission to scheduler
   assignment, measured via
   atlas_scheduler_scheduling_latency_seconds histogram.
4. **Job success rate**: proportion of executed jobs reaching
   succeeded (not retry or dead_letter) on first attempt, measured
   via atlas_worker_jobs_executed_total{outcome="succeeded"} /
   atlas_worker_jobs_executed_total.

## Proposed SLO targets (initial, low-confidence given sample size)

| SLI | Target | Rationale |
|---|---|---|
| API availability | 99.5% over 30d | Standard starting point for a dev-tier service; real baseline is 100% but sample is too small to commit to five-nines |
| API latency (p95) | < 100ms | Real p95 is 5ms; large headroom deliberately left given tiny sample and no real network/load variance yet |
| Scheduling latency (p95) | < 50ms | Real p95 is ~10ms; similar headroom reasoning |
| Job success rate | 99% over 30d | Real baseline is 100%/21, but a single-digit sample can't justify a tighter number; will tighten after real volume |

## Error budget policy (proposed)
30-day rolling window. If the error budget for any SLO is exhausted,
new feature work pauses in favor of reliability work until the
budget recovers. This policy itself is not yet exercised in practice
and should be revisited once genuine traffic patterns are observed.

## Next steps
- Re-baseline after a period of real (non-test) traffic once Atlas
  has actual users/workloads, and tighten targets accordingly.
- Wire these SLOs into actual alerting (Phase 9 continuation).
- Consider a burn-rate alerting approach (multi-window, multi-burn-rate)
  rather than simple threshold alerts, once real traffic volume
  justifies it.
