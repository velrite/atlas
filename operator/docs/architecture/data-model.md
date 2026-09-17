# Data Model

Every model below is backed by a REAL, verified Atlas capability.
Nothing here is speculative. Multi-region fields are intentionally
absent (Atlas Phase 13 deferred — do not add them later without a
matching Atlas capability).

## JobRecord
Source: `POST /jobs`, `GET /jobs/{job_id}` (atlas-api, real, port 80
via Service → containerPort 8080)

    JobRecord {
      jobId: String        // UUID, e.g. "101513fe-7a31-4ca6-9961-..."
      status: String       // "queued" confirmed; others inferred at build time
      payload: Map<String, dynamic>  // MUST be a JSON object, not a string
      createdAt: DateTime
    }

Note: Redis has no persistent volume. A job's absence after a Redis
pod replacement does not mean it failed — it means state was lost.
Never render "job not found" and "job failed" the same way.

## ComponentHealth
Source: mixed — see api-capability-map.md for exactly which source
backs which component.

    ComponentHealth {
      component: enum { api, scheduler, worker, redis }
      status: enum { healthy, degraded, unknown }
      source: enum { httpHealthCheck, podStatus, metricsInferred }
      asOf: DateTime
    }

`scheduler`, `worker`, `redis` can only ever be `podStatus` or
`metricsInferred` — there is no HTTP health route for them. Do not
imply otherwise in the UI.

## DeploymentSnapshot
Source: k8s Rollout object (`kubectl get rollout ... -o json`) + Git
log of `helm/atlas-platform/values.yaml` + Artifact Registry image list

    DeploymentSnapshot {
      revisionIndex: int      // Argo Rollouts revision, currently up to 27
      imageTag: String        // 8-char commit SHA
      rolloutPhase: String
      currentStepIndex: int?  // canary step, of 7 total steps
      gitCommit: String
      sourceOfTruth: enum { kubeApi, git, artifactRegistry }
    }

Only 3 ReplicaSets persist (`revisionHistoryLimit: 3`) — full history
comes from Git, not the cluster. Do not claim cluster-sourced history
beyond that limit.

## SLOStatus
Source: Cloud Monitoring Alert Policies (4 real policies, ADR-015)

    SLOStatus {
      name: String            // e.g. "API p95 latency"
      target: String          // e.g. "< 100ms"
      currentValue: double?
      asOf: DateTime
      ingestionLagWarning: bool  // GMP/Monarch lag can be several minutes
    }

## IncidentRecord / ChaosExperimentRecord
Source: static markdown files in the repo, NOT an API.

    IncidentRecord { id, title, date, filePath, linkedDeploymentTag: String? }

## TelemetryPoint
Source: GMP Prometheus-compatible query API, proxied server-side
(mobile device never holds GCP credentials).

    TelemetryPoint { metric: String, value: double, asOf: DateTime }

Always paired with `ingestionLagWarning` — a metric can be correct at
`/metrics` and still read 0 from GMP for several minutes. This is not
a bug; it must be shown, not hidden.
