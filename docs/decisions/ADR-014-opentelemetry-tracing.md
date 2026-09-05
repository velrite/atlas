# ADR-014: OpenTelemetry Tracing

Status: Accepted, verified end-to-end.

Manual W3C traceparent propagation via a trace_context field on the Job dataclass (inject at API submit, extract at scheduler/worker) since Redis hops have no HTTP headers to auto-propagate. Self-deployed OTel Collector, googlecloud exporter to Cloud Trace.

Real bug hit: setuptools 82.0.0 (Feb 2026) removed pkg_resources entirely, breaking opentelemetry-instrumentation-flask. Fixed by pinning setuptools>=69.0.0,<82. See INCIDENT-004.

Verified: traceId 0c6fe9e853f10099fdc3528f5e6e48ea, 4 spans across atlas-api/scheduler/worker, correct order and timing.
