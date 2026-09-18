import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'data/diagnostic_repository.dart';
import '../../shared/models/diagnostic_result.dart';
import '../../app/scenario.dart';
import '../../core/configuration/environment.dart';
import '../../core/security/action_registry.dart';
import '../../core/security/audit_log_repository.dart';

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
    final environment = ref.read(environmentProvider);
    const actionId = 'run_diagnostic_check';
    final boundary = ActionRegistry.boundaryFor(actionId);

    final result = await AsyncValue.guard(() => repo.runWorkerCapacityCheck());
    state = result;

    // Audit every run attempt, success or failure — this is why we log
    // from result.when() rather than only on the happy path: a failed
    // diagnostic run is still an action that happened and belongs in
    // the trail.
    result.when(
      data: (value) => AuditLogRepository.record(
        actionId: actionId,
        boundary: boundary,
        environment: environment.label,
        outcome: 'completed',
        detail: value.outcome.name,
      ),
      error: (err, stack) => AuditLogRepository.record(
        actionId: actionId,
        boundary: boundary,
        environment: environment.label,
        outcome: 'failed',
        detail: err.toString(),
      ),
      loading: () {}, // unreachable here — guard() never leaves loading
    );
  }
}

final diagnosticRunProvider =
    AsyncNotifierProvider<DiagnosticRunNotifier, DiagnosticResult?>(DiagnosticRunNotifier.new);
