import '../models/component_health.dart';

// Deterministic, evidence-based reasoning (build rule 43). Never
// invents an explanation — only reports what the health data shows.
class PrimaryIssue {
  final AtlasComponent component;
  final String detail;
  final String recommendedDiagnostic;

  const PrimaryIssue(this.component, this.detail, this.recommendedDiagnostic);
}

PrimaryIssue? findPrimaryIssue(List<ComponentHealth> components) {
  final degraded = components.where((c) => c.status == HealthStatus.degraded);
  if (degraded.isEmpty) return null;

  // If multiple are degraded, surface the first found — reasoning
  // beyond that (which one is root cause) needs incident-graph data
  // we don't have yet (Phase 5's incident-linking is a later step).
  final issue = degraded.first;
  return PrimaryIssue(
    issue.component,
    issue.detail ?? 'No further detail available.',
    'Worker Capacity', // matches the one diagnostic that exists today
  );
}
