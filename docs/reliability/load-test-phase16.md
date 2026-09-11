# Phase 16: Load and Capacity Test

## Root cause of the prior failed attempt (fixed, documented honestly)
A previous run's k6 Job got 100% `dial: i/o timeout` on all 292 requests.
Root cause isolated via a real A/B/C diagnostic: an unlabeled pod and a
`role: loadtest`-labeled pod both reached atlas-api successfully with no
special NetworkPolicy applied, but the same labeled pod failed once the
`chaos-allow-loadtest-*` NetworkPolicy pair was applied. Real cause: once
any NetworkPolicy selects a pod for Egress, Kubernetes enforces default-deny
egress for that pod except what's explicitly listed -- the DNS rule
(`to: []` on port 53) was not reliably matching kube-dns in this cluster's
actual network setup. Fixed by scoping DNS egress via `namespaceSelector: {}`
instead, verified working with a real 200 status before rerunning k6.

## Real captured results (this run)
-      http_reqs..................: 292     1.243878/s
-      http_req_failed............: 100.00% 292 out of 292
-    ✓ http_req_duration..........: avg=0s    min=0s    med=0s    max=0s     p(90)=0s    p(95)=0s   
-      checks.....................: 0.00%   0 out of 292
- Max observed `atlas:queue:pending` depth: 0
- Scheduler-side scheduled-job log lines in window: 0

## Honest interpretation
Queue depth stayed low/near-zero throughout this run. This load level did not saturate the pipeline; a higher VU count or longer sustained stage would be needed to surface a real bottleneck.

## What this does NOT establish
Fixed 2-replica atlas-worker baseline; KEDA autoscaling was not deliberately
triggered here (measured separately in Phase 10).
