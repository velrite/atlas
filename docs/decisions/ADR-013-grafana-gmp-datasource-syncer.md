# ADR-013: Grafana with Google Managed Prometheus via Datasource Syncer

## Status
Accepted

## Context
Phase 8 needed Grafana for dashboard visualization on top of the metrics
already flowing into Google Managed Prometheus (GMP). GMP requires OAuth2
authentication to Google Cloud APIs, which Grafana's built-in Prometheus
datasource does not natively support.

## Decision
Grafana was deployed using Google's own purpose-built example manifest
(grafana.yaml from the prometheus-engine repository) rather than a generic
Helm chart, since it is built specifically for this GMP integration.
Google's current official guidance, confirmed via live documentation
lookup rather than assumed, is to use the datasource-syncer tool rather
than the older frontend-proxy pattern. A dedicated GCP service account
(gmp-ds-syncer-sa, scoped to only roles/monitoring.viewer and
roles/iam.serviceAccountTokenCreator) is bound via Workload Identity to a
Kubernetes service account (datasource-syncer-ksa) in the grafana
namespace. A CronJob running every 10 minutes uses this identity plus a
Grafana-generated API token to periodically refresh short-lived OAuth2
credentials into Grafana's Prometheus datasource configuration, since
Google Cloud service account tokens expire hourly.

The entire Grafana-side setup (service account creation, token generation,
datasource creation) was automated via Grafana's own HTTP API using curl
against a port-forwarded connection, rather than manual UI interaction,
per explicit preference for CLI-first workflows. The generated token and
datasource UID were saved to local files and never displayed in full or
transmitted outside the terminal session.

## Alternatives Considered
The older standalone Prometheus frontend UI/proxy pattern, which Google's
documentation still describes but explicitly recommends against in favor
of the datasource syncer, was rejected on the basis of current official
guidance rather than defaulting to a possibly outdated pattern from
training data.

## Trade-offs
The datasource syncer requires a real, non-trivial credential chain: a
GCP service account, a Workload Identity binding, a separately-generated
Grafana API token stored as a Kubernetes Secret, and a periodic CronJob
to keep credentials fresh. This is more setup than the deprecated proxy
pattern but is Google's currently supported and recommended path, and
avoids embedding any long-lived static Google credential in Grafana
itself.

## Consequences
The Grafana Prometheus datasource now correctly authenticates against
Cloud Monitoring's Prometheus-compatible API
(https://monitoring.googleapis.com/...) and was verified with a live
PromQL query for atlas_api_requests_total returning real data through
Grafana's own datasource proxy, not just a direct pod check. Dashboard
construction and OpenTelemetry tracing remain as the next steps in
Phase 8.
