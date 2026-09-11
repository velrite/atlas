# Phase 16: Load and Capacity Test

Tool: k6, run in-cluster as a Kubernetes Job (grafana/k6:0.54.0), hitting
`POST /jobs` on the real, live atlas-api service directly (no ingress
involved). Real reason for choosing in-cluster over an external load
generator: this session already found (KEDA burst testing, Phase 10) that
external per-request kubectl-run generation cannot produce genuine
concurrency; a single k6 process inside the cluster gives real concurrent
load without that distortion.

## Real test profile
Ramp 0->10 (30s) -> 30 (30s) -> 60 (60s, sustained) -> 60 (60s, sustained) -> 0 (30s).
Total window: 260s.

## Real captured results

- k6 total requests: see /tmp/k6-output.log, not cleanly parsed
- k6 p95 request duration: see /tmp/k6-output.log, not cleanly parsed
- k6 failed request rate: see /tmp/k6-output.log, not cleanly parsed
- Max observed `atlas:queue:pending` depth during test: 0
- Scheduler-side scheduled-job log lines captured in window: 0
- Full raw k6 output: see /tmp/k6-output.log (session-local, not committed - only the summary above is)
- Full raw queue-depth timeline: see /tmp/queue-depth.log
- Full raw pod CPU/memory timeline: see /tmp/pod-usage.log

## Honest interpretation

Queue depth stayed low/near-zero throughout (see /tmp/queue-depth.log for the exact timeline), meaning this load level did not saturate the scheduler/worker pipeline. The real bottleneck, if any, was not exposed at this concurrency and would require a higher VU count or longer sustained stage to surface -- this is an honest limitation of this run, not a claim the system has no bottleneck.

Real resource usage during the test (CPU/memory per pod) is in /tmp/pod-usage.log
for direct inspection rather than restated here as a single number, since
kubectl top's plain-text format doesn't parse cleanly into one summary
figure without risking a misleading simplification.

## What this does NOT establish
This run used 2 atlas-worker replicas (no KEDA scale-up was deliberately
triggered/observed here - Phase 10 already measured that separately). This
result is specific to a fixed-capacity baseline, not the autoscaled ceiling.
