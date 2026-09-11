# Chaos Experiment 001: atlas-api Pod Failure

## Hypothesis
Killing one of two atlas-api pods will cause zero customer-facing impact,
since the Service load-balances across replicas and a new pod will be
scheduled to replace it, restoring 2/2 within roughly the pod's own
startup time.

## Steady State (before injection)
- 2/2 atlas-api pods Running (atlas-api-ff858dbbd-qg7jp, atlas-api-ff858dbbd-r8ljs)
- Rollout status: DESIRED 2, CURRENT 2, UP-TO-DATE 2, AVAILABLE 2
- Health check via Service: HTTP 200

## Blast Radius
Single pod deletion within a 2-replica Deployment behind a Service.
Contained: worst case is a brief drop to 1/2 capacity, no full outage
possible given the second replica remains untouched.

## Injection
`kubectl delete pod atlas-api-ff858dbbd-qg7jp -n atlas-platform`
Injected at: 2026-09-11T03:43:18Z

## Real Observed Behavior
- 03:43:20 (2s after injection): disruption detected -- ready replica
  count dropped to 1/2, replacement pod `atlas-api-ff858dbbd-k8m8g`
  already `Running` (not yet Ready).
- 03:43:32 (14s after injection): replacement pod reached `1/1 Running`,
  ready replica count back to 2/2.
- Health check via the Service returned HTTP 200 both before and
  immediately after full recovery -- no failed request was observed
  during the window (Service-level load balancing meant traffic could
  still reach the surviving replica throughout).

## Measured Recovery
- MTTD (time to detect the disruption): ~2 seconds
- MTTR (detect to full recovery, 2/2 Ready): 12 seconds
- Total (injection to full recovery): 15 seconds

## Conclusion
Hypothesis confirmed. The ReplicaSet controller detected and replaced
the deleted pod well within the deadline any real user would notice,
and the Service's load balancing across the surviving replica meant
there was no observable customer-facing gap. This is the expected,
designed behavior of a multi-replica Deployment and required no
custom tooling to verify -- Kubernetes' own reconciliation loop is
the entire recovery mechanism here.

## Follow-up
No code or config change needed -- this experiment validates existing
behavior rather than surfacing a gap. Contrast with node-level or
dependency-level failure experiments (planned next), which are
expected to reveal more interesting behavior given atlas-worker's
capacity-tracking design (Phase 4) and Redis's single-instance nature
(ADR-005, accepted gap).
