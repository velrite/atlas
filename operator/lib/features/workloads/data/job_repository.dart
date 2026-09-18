import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show rootBundle;
import '../../../shared/models/job_record.dart';
import '../../../core/errors/operational_state.dart';
import '../../../core/errors/error_kind.dart';
import '../../../core/persistence/capped_cache.dart';
import '../../../core/persistence/hive_boxes.dart';

abstract class JobRepository {
  Future<OperationalState<List<JobRecord>>> fetchRecent();
}

class OfflineJobRepository implements JobRepository {
  final String scenario;
  const OfflineJobRepository(this.scenario);

  @override
  Future<OperationalState<List<JobRecord>>> fetchRecent() async {
    List<JobRecord> list;
    List<Map<String, dynamic>> raw;

    try {
      final jsonStr = await rootBundle.loadString('fixtures/$scenario/jobs.json');
      raw = (jsonDecode(jsonStr) as List).cast<Map<String, dynamic>>();
      list = raw.map((e) => JobRecord.fromJson(e)).toList();
    } on FormatException catch (e) {
      return Error(ErrorKind.malformedResponse, e.message);
    } catch (e) {
      return Error(ErrorKind.notFound, 'Fixture not found for scenario "$scenario": $e');
    }

    try {
      await CappedCache.writeAll(
        boxName: HiveBoxes.jobs,
        records: raw,
        maxEntries: 100,
      );
      await CappedCache.writeSyncTime('jobs', DateTime.now());
    } catch (e) {
      debugPrint('Jobs cache write skipped: $e');
    }

    return Data(list, asOf: DateTime.now(), freshness: DataFreshness.offlineCache);
  }
}
