import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import '../../../shared/models/deployment_snapshot.dart';
import '../../../core/errors/operational_state.dart';
import '../../../core/errors/error_kind.dart';

abstract class DeploymentRepository {
  Future<OperationalState<List<DeploymentSnapshot>>> fetchHistory();
}

class OfflineDeploymentRepository implements DeploymentRepository {
  final String scenario;
  const OfflineDeploymentRepository(this.scenario);

  @override
  Future<OperationalState<List<DeploymentSnapshot>>> fetchHistory() async {
    try {
      final jsonStr = await rootBundle.loadString('fixtures/$scenario/deployments.json');
      final list = (jsonDecode(jsonStr) as List)
          .map((e) => DeploymentSnapshot.fromJson(e as Map<String, dynamic>))
          .toList();
      return Data(list, asOf: DateTime.now(), freshness: DataFreshness.offlineCache);
    } on FormatException catch (e) {
      return Error(ErrorKind.malformedResponse, e.message);
    } catch (e) {
      return Error(ErrorKind.notFound, 'Fixture not found for scenario "$scenario": $e');
    }
  }
}
