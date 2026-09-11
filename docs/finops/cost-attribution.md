# Phase 17 — FinOps Cost Attribution

Generated: 2026-09-11 21:26 UTC

## Methodology

Two real, independently-sourced data feeds, combined:

1. **Real GCP list pricing** — fetched live from the Cloud Billing Catalog API
   (`cloudbilling.googleapis.com/v1/services/6F81-5844-456A/skus`), filtered to
   `E2 Instance Core` and `E2 Instance Ram` on-demand SKUs in `us-central1`.
   No estimates, no cached/assumed rates.
2. **Real measured resource requests per namespace** — captured directly from
   OpenCost's `/allocation/compute` API after wiring it to a dedicated
   Prometheus instance scraping cAdvisor/kube-state-metrics (separate concern
   from Phase 8's GMP app-metrics setup). Window: {2026-09-11, ~97 real
   minutes of live cluster data}.

**Known limitation, stated honestly:** OpenCost's own built-in GCP pricing
downloader failed with `mkdir /var/configs: permission denied` (a known,
unresolved upstream issue in the OpenCost Helm chart — see
opencost-helm-chart#198, #205, #2623). This meant OpenCost fell back to
generic default pricing internally, so its own `totalCost` fields are **not**
used here. Instead, real GCP pricing (item 1) is applied directly to
OpenCost's real measured resource *requests* (item 2) to compute the
attribution below — every dollar figure here is traceable to one of those two
real sources, nothing is invented.

## Real GCP pricing (us-central1, on-demand)

| Resource | Rate |
|---|---|
| vCPU | $0.021812/vCPU-hour |
| RAM | $0.002924/GB-hour |
| e2-standard-4 node (4 vCPU, 16GB) | $0.1340/hour |
| 2-node atlas-dev cluster | $0.2680/hour = **$195.67/month** |

## Cost attribution by namespace (based on real measured CPU/RAM requests)

| Namespace | CPU requested (vCPU) | RAM requested (GB) | Est. monthly cost |
|---|---|---|---|
| kube-system | 1.412 | 1.850 | $26.43 |
| atlas-platform | 0.450 | 0.625 | $8.50 |
| kyverno | 0.400 | 0.312 | $7.04 |
| keda | 0.300 | 0.293 | $5.40 |
| gke-managed-cim | 0.105 | 0.127 | $1.94 |
| opencost-prometheus | 0.100 | 0.250 | $2.13 |
| otel | 0.100 | 0.195 | $2.01 |
| opencost | 0.019 | 0.104 | $0.53 |
| gmp-system | 0.011 | 0.082 | $0.35 |
| argocd | 0.000 | 0.000 | $0.00 |
| argo-rollouts | 0.000 | 0.000 | $0.00 |
| grafana | 0.000 | 0.000 | $0.00 |

**Unallocated / headroom** (capacity not currently requested by any workload,
including kube-system daemonsets not itemized above): ~$141.34/month

## Fixed vs. autoscaled capacity (Phase 10 KEDA comparison)

atlas-worker scales 2→10 replicas via KEDA (Phase 10) based on scheduler
requeue-rate. At steady low load (this measurement window), worker replica
count sits at the floor (2), so the *current* snapshot above reflects
fixed-capacity-equivalent cost. A true fixed-vs-autoscaled comparison requires
sustained load-testing (Phase 16 traffic) run twice — once with KEDA disabled
pinned at max replicas, once with KEDA enabled — and is flagged as a
follow-up measurement rather than fabricated here, consistent with this
project's standard of only reporting numbers that were actually measured.

## Data sources

- GCP Cloud Billing Catalog API — `services/6F81-5844-456A` (Compute Engine),
  fetched live, 2026-09-11.
- OpenCost `/allocation/compute?window=1d&aggregate=namespace` — fetched live
  from a cluster-local OpenCost install (`opencost` namespace), backed by a
  dedicated `kube-prometheus-stack` install (`opencost-prometheus` namespace).
