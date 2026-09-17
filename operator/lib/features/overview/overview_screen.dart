import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/widgets/environment_badge.dart';
import '../../shared/models/component_health.dart';
import '../../core/errors/operational_state.dart' as ops;
import '../../app/scenario.dart';
import 'overview_providers.dart';

class OverviewScreen extends ConsumerWidget {
  const OverviewScreen({super.key});

  Color _statusColor(HealthStatus status) => switch (status) {
        HealthStatus.healthy => Colors.green,
        HealthStatus.degraded => Colors.amber,
        HealthStatus.unknown => Colors.grey,
      };

  String _sourceLabel(HealthSource source) => switch (source) {
        HealthSource.httpHealthCheck => 'HTTP health check',
        HealthSource.podStatus => 'Pod status',
        HealthSource.metricsInferred => 'Inferred from metrics',
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final healthState = ref.watch(componentHealthProvider);
    final scenario = ref.watch(scenarioProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Overview'),
        actions: [
          IconButton(
            tooltip: 'Switch fixture scenario (dev only)',
            icon: Icon(scenario == FixtureScenario.healthy
                ? Icons.check_circle_outline
                : Icons.warning_amber_outlined),
            onPressed: () => ref.read(scenarioProvider.notifier).toggle(),
          ),
          const Padding(
            padding: EdgeInsets.only(right: 16),
            child: EnvironmentBadge(),
          ),
        ],
      ),
      body: healthState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Failed to load: $err')),
        data: (state) => switch (state) {
          ops.Loading() => const Center(child: CircularProgressIndicator()),
          ops.Empty() => const Center(child: Text('No component health data.')),
          ops.Error(:final reason) => Center(child: Text('Error: $reason')),
          ops.Data(:final value, :final asOf) => ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'OFFLINE CACHE • as of ${asOf.toIso8601String()}',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                const SizedBox(height: 12),
                ...value.map((c) => Card(
                      child: ListTile(
                        leading: Icon(Icons.circle, color: _statusColor(c.status), size: 14),
                        title: Text(c.component.name.toUpperCase()),
                        subtitle: Text(
                            '${_sourceLabel(c.source)}${c.detail != null ? ' — ${c.detail}' : ''}'),
                        trailing: Text(c.status.name.toUpperCase()),
                      ),
                    )),
              ],
            ),
        },
      ),
    );
  }
}
