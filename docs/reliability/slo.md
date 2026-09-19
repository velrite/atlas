# SLOs

Four live Cloud Monitoring alert policies exist for Atlas (per project
ADR-015, referenced in prior architecture work):

- API p95 latency < 100ms
- Scheduling p95 latency < 50ms
- Job success rate > 99%
- API availability > 99.5%

These are **implemented alert policies**, not independently measured or
publicly reported production SLA numbers. No uptime, traffic volume, or
user-facing performance claims beyond these four policy definitions
should be made without new, explicit measurement.
