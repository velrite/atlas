import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import '../../../shared/models/job_record.dart';
import '../../../core/errors/operational_state.dart';
import '../../../core/errors/error_kind.dart';

abstract class JobRepository {
  Future<OperationalState<List<JobRecord>>> fetchRecent();
}

// Not wired into a screen yet — Workloads UI is Phase 4.
class OfflineJobRepository implements JobRepository {
  final String scenario;
  const OfflineJobRepository(this.scenario);

  @override
  Future<OperationalState<List<JobRecord>>> fetchRecent() async {
    try {
      final jsonStr = await rootBundle.loadString('fixtures/$scenario/jobs.json');
      final list = (jsonDecode(jsonStr) as List)
          .map((e) => JobRecord.fromJson(e as Map<String, dynamic>))
          .toList();
      return Data(list, asOf: DateTime.now(), freshness: DataFreshness.offlineCache);
    } on FormatException catch (e) {
      return Error(ErrorKind.malformedResponse, e.message);
    } catch (e) {
      return Error(ErrorKind.notFound, 'Fixture not found for scenario "$scenario": $e');
    }
  }
}
