# Phase 8: Metrics Instrumentation Verification Evidence

## What Was Verified
Google Managed Prometheus (gmp-system) confirmed already running on
atlas-dev at no additional cost. All three workload components (API,
scheduler, worker) instrumented with prometheus-client, exposing
Prometheus-format metrics on their respective ports. Three PodMonitoring
custom resources created, one per component, directing GMP to scrape
every 15 seconds.

## Verification Method
Real jobs were submitted to the live API via disposable kubectl run pods
(kubectl run --rm -i --restart=Never with curlimages/curl), avoiding
kubectl exec, which risks opening an interactive shell session that
cannot be exited from a mobile terminal. Each of the two atlas-api
replicas was queried directly by pod IP to confirm metric data, since
querying through the load-balanced Service does not guarantee hitting
the specific replica that handled a given request.

## Result
atlas_api_requests_total{endpoint="/jobs",method="POST",status="202"}
correctly read 2.0 on the replica that handled both test submissions,
with 0 on the other replica, confirming the counter increments correctly
per request. The request duration histogram showed real values (sum
0.0042s across 2 requests). kubectl get podmonitoring
atlas-api-monitoring -o yaml confirmed status condition
ConfigurationCreateSuccess: True, meaning GMP has accepted the scrape
configuration and is actively collecting from the matched pods.

## Lesson: Per-Pod In-Memory Registries in a Multi-Replica Deployment
Each pod runs its own independent in-memory prometheus_client registry.
A metric incremented by a request handled on one replica is invisible
when querying a different replica's /metrics endpoint directly. This is
correct, expected behavior, not a bug, but it means manually spot-checking
one pod's /metrics output is an unreliable way to verify traffic occurred
across a multi-replica Deployment. This is precisely the problem GMP's
cluster-wide scraping solves: it scrapes every matching pod independently
and aggregates the results, which is why PromQL queries against
Cloud Monitoring, not manual per-pod curl checks, should be the actual
source of truth going forward.

## Not Yet Done
Grafana for visualization and OpenTelemetry distributed tracing across
the full API to queue to scheduler to worker request path remain
outstanding for Phase 8 and are tracked as the next work, not assumed
complete.
