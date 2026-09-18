import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'data/job_repository.dart';
import '../../shared/models/job_record.dart';
import '../../core/errors/operational_state.dart';
import '../../app/scenario.dart';

final jobRepositoryProvider = Provider<JobRepository>((ref) {
  final scenario = ref.watch(scenarioProvider);
  return OfflineJobRepository(scenario.name);
});

final recentJobsProvider = FutureProvider<OperationalState<List<JobRecord>>>((ref) async {
  final repo = ref.watch(jobRepositoryProvider);
  return repo.fetchRecent();
});
