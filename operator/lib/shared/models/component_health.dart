enum AtlasComponent { api, scheduler, worker, redis }
enum HealthStatus { healthy, degraded, unknown }
enum HealthSource { httpHealthCheck, podStatus, metricsInferred }

class ComponentHealth {
  final AtlasComponent component;
  final HealthStatus status;
  final HealthSource source;
  final DateTime asOf;
  final String? detail;

  const ComponentHealth({
    required this.component,
    required this.status,
    required this.source,
    required this.asOf,
    this.detail,
  });

  factory ComponentHealth.fromJson(Map<String, dynamic> json) {
    return ComponentHealth(
      component: AtlasComponent.values.byName(json['component'] as String),
      status: HealthStatus.values.byName(json['status'] as String),
      source: HealthSource.values.byName(json['source'] as String),
      asOf: DateTime.parse(json['asOf'] as String),
      detail: json['detail'] as String?,
    );
  }
}
