import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/widgets/environment_badge.dart';
import '../../shared/models/diagnostic_result.dart';
import 'diagnostics_providers.dart';

class DiagnosticsScreen extends ConsumerWidget {
  const DiagnosticsScreen({super.key});

  Color _outcomeColor(DiagnosticOutcome outcome) => switch (outcome) {
        DiagnosticOutcome.ok => Colors.green,
        DiagnosticOutcome.degraded => Colors.amber,
        DiagnosticOutcome.failed => Colors.red,
        DiagnosticOutcome.timeout => Colors.grey,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final runState = ref.watch(diagnosticRunProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnostics'),
        actions: const [Padding(
          padding: EdgeInsets.only(right: 16),
          child: EnvironmentBadge(),
        )],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              title: const Text('Worker Capacity'),
              subtitle: const Text('Checks worker CPU and requeue rate for saturation.'),
              trailing: FilledButton(
                onPressed: runState.isLoading
                    ? null
                    : () => ref.read(diagnosticRunProvider.notifier).run(),
                child: runState.isLoading
                    ? const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Run'),
              ),
            ),
          ),
          const SizedBox(height: 16),
          runState.when(
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Running diagnostic…'),
              ),
            ),
            error: (err, stack) => Card(
              color: Colors.red.withValues(alpha: 0.08),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Diagnostic failed: $err'),
              ),
            ),
            data: (result) {
              if (result == null) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('No diagnostic run yet. Tap Run to check worker capacity.'),
                );
              }
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.circle, color: _outcomeColor(result.outcome), size: 14),
                          const SizedBox(width: 8),
                          Text(result.outcome.name.toUpperCase(),
                              style: const TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(result.summary),
                      const SizedBox(height: 12),
                      Text('Evidence', style: Theme.of(context).textTheme.labelLarge),
                      ...result.evidence.map((e) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(e.label),
                                Text(
                                  e.value,
                                  style: TextStyle(
                                    color: e.isConcern ? Colors.amber.shade800 : null,
                                    fontWeight: e.isConcern ? FontWeight.bold : null,
                                  ),
                                ),
                              ],
                            ),
                          )),
                      const SizedBox(height: 8),
                      Text(
                        'Ran ${result.ranAt.toIso8601String()} • ${result.duration.inMilliseconds}ms',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
