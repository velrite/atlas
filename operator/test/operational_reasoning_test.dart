import 'package:flutter_test/flutter_test.dart';
import 'package:atlas_operator/shared/models/component_health.dart';
import 'package:atlas_operator/shared/utilities/operational_reasoning.dart';

void main() {
  test('findPrimaryIssue returns null when nothing is degraded', () {
    final components = [
      ComponentHealth(
        component: AtlasComponent.api,
        status: HealthStatus.healthy,
        source: HealthSource.httpHealthCheck,
        asOf: DateTime.now(),
      ),
    ];
    expect(findPrimaryIssue(components), isNull);
  });

  test('findPrimaryIssue surfaces the degraded worker', () {
    final components = [
      ComponentHealth(
        component: AtlasComponent.api,
        status: HealthStatus.healthy,
        source: HealthSource.httpHealthCheck,
        asOf: DateTime.now(),
      ),
      ComponentHealth(
        component: AtlasComponent.worker,
        status: HealthStatus.degraded,
        source: HealthSource.metricsInferred,
        asOf: DateTime.now(),
        detail: 'Worker CPU 94%',
      ),
    ];
    final issue = findPrimaryIssue(components);
    expect(issue, isNotNull);
    expect(issue!.component, AtlasComponent.worker);
    expect(issue.recommendedDiagnostic, 'Worker Capacity');
  });
}
