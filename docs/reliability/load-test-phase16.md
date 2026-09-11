# Phase 16: Load and Capacity Test

## Corrected root cause (two prior commits misdiagnosed this - stated plainly)
Two earlier k6 runs got 100% `dial: i/o timeout` on every request. The
first attempt's writeup incorrectly attributed this to NetworkPolicy Egress
semantics (a "fix" using `namespaceSelector` was applied and committed).
That fix did not actually resolve the problem, and a second run still
failed 100%. Real root cause, confirmed via a controlled test with ALL
NetworkPolicies removed: the `atlas-api` Service is `ClusterIP` exposing
only port **80** (which forwards to the pods' containerPort 8080
internally) - but the k6 script and every diagnostic pod built during this
investigation explicitly called the Service on `:8080`, a port the Service
itself never exposed. Confirmed by testing the same URL on port 80 with
zero NetworkPolicy changes, which succeeded immediately. The earlier
NetworkPolicy "fix" was real, harmless config, but not the actual cause -
this is stated honestly rather than left uncorrected in the doc history.

## Real captured results (this run, against the correct port)
-      http_reqs......................: 18922   90.044966/s
-      http_req_failed................: 0.00%   0 out of 18922
-    ✓ http_req_duration..............: avg=217.86ms min=2.25ms   med=94.16ms  max=1.7s     p(90)=619.07ms p(95)=784.47ms
-      checks.........................: 100.00% 18922 out of 18922
- Max observed `atlas:queue:pending` depth: 18516
- Scheduler-side scheduled-job log lines in window: 9

## Honest interpretation
Queue depth grew measurably during sustained load, suggesting the scheduler/worker pipeline could not fully keep pace at this concurrency - consistent with the scheduler being single-threaded (Phase 8/10).

## What this does NOT establish
Fixed 2-replica atlas-worker baseline; KEDA autoscaling was not deliberately
triggered here (measured separately in Phase 10).
