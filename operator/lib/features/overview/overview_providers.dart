import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'data/component_health_repository.dart';
import '../../shared/models/component_health.dart';
import '../../core/errors/operational_state.dart';
import '../../app/scenario.dart';

final componentHealthRepositoryProvider = Provider<ComponentHealthRepository>((ref) {
  final scenario = ref.watch(scenarioProvider);
  return OfflineComponentHealthRepository(scenario.name);
});

final componentHealthProvider =
    FutureProvider<OperationalState<List<ComponentHealth>>>((ref) async {
  final repo = ref.watch(componentHealthRepositoryProvider);
  return repo.fetchAll();
});
