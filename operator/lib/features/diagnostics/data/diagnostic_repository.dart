import '../../../shared/models/diagnostic_result.dart';
import '../../../app/scenario.dart';

abstract class DiagnosticRepository {
  Future<DiagnosticResult> runWorkerCapacityCheck();
}

// Offline: real ~800ms delay so the loading state is genuinely visible
// (not instant), then a canned result matching the current fixture
// scenario. Numbers here match fixtures/degraded/components.json exactly
// — same worker CPU 94% / requeue +418% evidence used on Overview, so
// the two screens never contradict each other.
class OfflineDiagnosticRepository implements DiagnosticRepository {
  final FixtureScenario scenario;
  const OfflineDiagnosticRepository(this.scenario);

  @override
  Future<DiagnosticResult> runWorkerCapacityCheck() async {
    final start = DateTime.now();
    await Future.delayed(const Duration(milliseconds: 800));
    final duration = DateTime.now().difference(start);

    if (scenario == FixtureScenario.degraded) {
      return DiagnosticResult(
        diagnosticName: 'Worker Capacity',
        outcome: DiagnosticOutcome.degraded,
        summary: 'Worker capacity saturation — CPU and requeue rate both elevated.',
        evidence: const [
          DiagnosticCheck('Worker CPU', '94%', isConcern: true),
          DiagnosticCheck('Requeue rate', '+418%', isConcern: true),
          DiagnosticCheck('Redis', 'Healthy'),
          DiagnosticCheck('API', 'Healthy'),
          DiagnosticCheck('Scheduler', 'Healthy'),
        ],
        ranAt: DateTime.now(),
        duration: duration,
      );
    }

    return DiagnosticResult(
      diagnosticName: 'Worker Capacity',
      outcome: DiagnosticOutcome.ok,
      summary: 'Worker capacity nominal.',
      evidence: const [
        DiagnosticCheck('Worker CPU', 'normal range'),
        DiagnosticCheck('Requeue rate', 'baseline'),
        DiagnosticCheck('Redis', 'Healthy'),
        DiagnosticCheck('API', 'Healthy'),
        DiagnosticCheck('Scheduler', 'Healthy'),
      ],
      ranAt: DateTime.now(),
      duration: duration,
    );
  }
}
