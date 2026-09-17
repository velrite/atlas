import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import '../../../shared/models/component_health.dart';
import '../../../core/errors/operational_state.dart';
import '../../../core/errors/error_kind.dart';

abstract class ComponentHealthRepository {
  Future<OperationalState<List<ComponentHealth>>> fetchAll();
}

class OfflineComponentHealthRepository implements ComponentHealthRepository {
  final String scenario;
  const OfflineComponentHealthRepository(this.scenario);

  @override
  Future<OperationalState<List<ComponentHealth>>> fetchAll() async {
    try {
      final jsonStr = await rootBundle.loadString('fixtures/$scenario/components.json');
      final list = (jsonDecode(jsonStr) as List)
          .map((e) => ComponentHealth.fromJson(e as Map<String, dynamic>))
          .toList();
      return Data(list, asOf: DateTime.now(), freshness: DataFreshness.offlineCache);
    } on FormatException catch (e) {
      return Error(ErrorKind.malformedResponse, e.message);
    } catch (e) {
      return Error(ErrorKind.notFound, 'Fixture not found for scenario "$scenario": $e');
    }
  }
}
