import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'data/deployment_repository.dart';
import '../../shared/models/deployment_snapshot.dart';
import '../../core/errors/operational_state.dart';
import '../../app/scenario.dart';

final deploymentRepositoryProvider = Provider<DeploymentRepository>((ref) {
  final scenario = ref.watch(scenarioProvider);
  return OfflineDeploymentRepository(scenario.name);
});

final deploymentHistoryProvider =
    FutureProvider<OperationalState<List<DeploymentSnapshot>>>((ref) async {
  final repo = ref.watch(deploymentRepositoryProvider);
  return repo.fetchHistory();
});
