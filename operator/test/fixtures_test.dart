import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:atlas_operator/shared/models/component_health.dart';
import 'package:atlas_operator/shared/models/deployment_snapshot.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('healthy components fixture: 4 records, all healthy', () async {
    final jsonStr = await rootBundle.loadString('fixtures/healthy/components.json');
    final list = (jsonDecode(jsonStr) as List)
        .map((e) => ComponentHealth.fromJson(e as Map<String, dynamic>))
        .toList();
    expect(list.length, 4);
    expect(list.every((c) => c.status == HealthStatus.healthy), isTrue);
  });

  test('degraded components fixture: exactly one degraded, and it is the worker', () async {
    final jsonStr = await rootBundle.loadString('fixtures/degraded/components.json');
    final list = (jsonDecode(jsonStr) as List)
        .map((e) => ComponentHealth.fromJson(e as Map<String, dynamic>))
        .toList();
    final degraded = list.where((c) => c.status == HealthStatus.degraded);
    expect(degraded.length, 1);
    expect(degraded.first.component, AtlasComponent.worker);
  });

  test('degraded deployments fixture: last deployment differs from last known good', () async {
    final jsonStr = await rootBundle.loadString('fixtures/degraded/deployments.json');
    final list = (jsonDecode(jsonStr) as List)
        .map((e) => DeploymentSnapshot.fromJson(e as Map<String, dynamic>))
        .toList();
    expect(list.first.rolloutPhase, 'Degraded');
    expect(list.firstWhere((s) => s.rolloutPhase == 'Healthy').revisionIndex, 27);
  });
}
