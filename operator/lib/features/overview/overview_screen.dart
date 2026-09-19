import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/widgets/environment_badge.dart';
import '../../shared/models/component_health.dart';
import '../../shared/utilities/operational_reasoning.dart';
import '../../core/errors/operational_state.dart' as ops;
import '../../core/network/connection_status.dart';
import '../../core/configuration/environment.dart';
import '../../app/scenario.dart';
import '../diagnostics/diagnostics_screen.dart';
import '../connection/connection_provider.dart';
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

  // ── Connection banner helpers ──
  // These only ever translate the real ConnectionStatus values built in
  // Phase 9 chunk 1 (Unknown/Checking/Healthy/Failed) into something
  // visible. Nothing here is invented — it's a direct mirror of whatever
  // OperationsApiClient actually observed.
  IconData _connectionIcon(AsyncValue<ConnectionStatus> state) => state.when(
        data: (status) => switch (status) {
          ConnectionUnknown() => Icons.help_outline,
          ConnectionChecking() => Icons.sync,
          ConnectionHealthy() => Icons.check_circle,
          ConnectionFailed() => Icons.error_outline,
        },
        loading: () => Icons.sync,
        error: (_, _) => Icons.error_outline,
      );

  Color _connectionColor(AsyncValue<ConnectionStatus> state) => state.when(
        data: (status) => switch (status) {
          ConnectionUnknown() => Colors.grey,
          ConnectionChecking() => Colors.blueGrey,
          ConnectionHealthy() => Colors.green,
          ConnectionFailed() => Colors.red,
        },
        loading: () => Colors.blueGrey,
        error: (_, _) => Colors.red,
      );

  String _connectionLabel(AsyncValue<ConnectionStatus> state) => state.when(
        data: (status) => switch (status) {
          ConnectionUnknown() => 'Operations API: not checked yet',
          ConnectionChecking() => 'Checking Operations API…',
          ConnectionHealthy(:final checkedAt) =>
            'Operations API: healthy (as of ${checkedAt.toIso8601String()})',
          ConnectionFailed(:final reason, :final checkedAt) =>
            'Operations API: failed — $reason (as of ${checkedAt.toIso8601String()})',
        },
        loading: () => 'Checking Operations API…',
        error: (err, _) => 'Operations API check errored: $err',
      );

  Widget _buildConnectionBanner(
      BuildContext context, WidgetRef ref, AsyncValue<ConnectionStatus> connectionState) {
    final isChecking = connectionState.when(
      data: (status) => status is ConnectionChecking,
      loading: () => true,
      error: (_, _) => false,
    );

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(_connectionIcon(connectionState), color: _connectionColor(connectionState), size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _connectionLabel(connectionState),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            TextButton(
              onPressed: isChecking
                  ? null
                  : () => ref.read(connectionProvider.notifier).checkConnection(),
              child: const Text('Check'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final healthState = ref.watch(componentHealthProvider);
    final scenario = ref.watch(scenarioProvider);
    final environment = ref.watch(environmentProvider);
    final connectionState = ref.watch(connectionProvider);

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
      body: Column(
        children: [
          // OFFLINE never shows this row at all — there is nothing real
          // behind it to check in that mode, and showing a status anyway
          // would be fabricated data. Only INTEGRATION renders it.
          if (environment == Environment.integration)
            _buildConnectionBanner(context, ref, connectionState),
          Expanded(
            child: healthState.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, stack) => Center(child: Text('Failed to load: $err')),
              data: (state) => switch (state) {
                ops.Loading() => const Center(child: CircularProgressIndicator()),
                ops.Empty() => const Center(child: Text('No component health data.')),
                ops.Error(:final reason) => Center(child: Text('Error: $reason')),
                ops.Data(:final value, :final asOf) => _buildBody(context, value, asOf),
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context, List<ComponentHealth> value, DateTime asOf) {
    final issue = findPrimaryIssue(value);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'OFFLINE CACHE • as of ${asOf.toIso8601String()}',
          style: Theme.of(context).textTheme.labelSmall,
        ),
        const SizedBox(height: 12),
        if (issue != null) ...[
          Card(
            color: Colors.amber.withValues(alpha: 0.1),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.warning_amber_outlined, color: Colors.amber),
                      const SizedBox(width: 8),
                      Text('Primary issue',
                          style: Theme.of(context).textTheme.labelLarge),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text('${issue.component.name.toUpperCase()}: ${issue.detail}'),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    icon: const Icon(Icons.monitor_heart_outlined),
                    label: Text('Run ${issue.recommendedDiagnostic} Diagnostic'),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const DiagnosticsScreen()),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
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
    );
  }
}
