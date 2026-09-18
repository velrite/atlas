import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'data/diagnostic_repository.dart';
import '../../shared/models/diagnostic_result.dart';
import '../../app/scenario.dart';

final diagnosticRepositoryProvider = Provider<DiagnosticRepository>((ref) {
  final scenario = ref.watch(scenarioProvider);
  return OfflineDiagnosticRepository(scenario);
});

// AsyncValue starts as loading:false/no-data via .loading() guard in the
// notifier — we model "not run yet" as null data, distinct from "running".
class DiagnosticRunNotifier extends AsyncNotifier<DiagnosticResult?> {
  @override
  Future<DiagnosticResult?> build() async => null; // not run yet

  Future<void> run() async {
    state = const AsyncLoading();
    final repo = ref.read(diagnosticRepositoryProvider);
    state = await AsyncValue.guard(() => repo.runWorkerCapacityCheck());
  }
}

final diagnosticRunProvider =
    AsyncNotifierProvider<DiagnosticRunNotifier, DiagnosticResult?>(DiagnosticRunNotifier.new);
