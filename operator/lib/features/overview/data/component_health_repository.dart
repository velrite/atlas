import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show rootBundle;
import '../../../shared/models/component_health.dart';
import '../../../core/errors/operational_state.dart';
import '../../../core/errors/error_kind.dart';
import '../../../core/persistence/capped_cache.dart';
import '../../../core/persistence/hive_boxes.dart';

abstract class ComponentHealthRepository {
  Future<OperationalState<List<ComponentHealth>>> fetchAll();
}

class OfflineComponentHealthRepository implements ComponentHealthRepository {
  final String scenario;
  const OfflineComponentHealthRepository(this.scenario);

  @override
  Future<OperationalState<List<ComponentHealth>>> fetchAll() async {
    List<ComponentHealth> list;
    List<Map<String, dynamic>> raw;

    try {
      final jsonStr = await rootBundle.loadString('fixtures/$scenario/components.json');
      raw = (jsonDecode(jsonStr) as List).cast<Map<String, dynamic>>();
      list = raw.map((e) => ComponentHealth.fromJson(e)).toList();
    } on FormatException catch (e) {
      return Error(ErrorKind.malformedResponse, e.message);
    } catch (e) {
      return Error(ErrorKind.notFound, 'Fixture not found for scenario "$scenario": $e');
    }

    // Caching is a side effect of a successful read, not a condition of
    // one. A Hive write failure (e.g. box not open — happens in widget
    // tests that don't init Hive) must never turn real, already-loaded
    // data into a false Error state.
    try {
      await CappedCache.writeAll(
        boxName: HiveBoxes.componentHealth,
        records: raw,
        maxEntries: 20,
      );
      await CappedCache.writeSyncTime('componentHealth', DateTime.now());
    } catch (e) {
      debugPrint('ComponentHealth cache write skipped: $e');
    }

    return Data(list, asOf: DateTime.now(), freshness: DataFreshness.offlineCache);
  }

  static List<ComponentHealth> readLastKnown() {
    final raw = CappedCache.readAll(HiveBoxes.componentHealth);
    return raw.map((e) => ComponentHealth.fromJson(e)).toList();
  }
}
