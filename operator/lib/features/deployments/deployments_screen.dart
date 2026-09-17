import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/widgets/environment_badge.dart';
import '../../shared/models/deployment_snapshot.dart';
import '../../core/errors/operational_state.dart' as ops;
import 'deployments_providers.dart';

class DeploymentsScreen extends ConsumerWidget {
  const DeploymentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyState = ref.watch(deploymentHistoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Deployments'),
        actions: const [Padding(
          padding: EdgeInsets.only(right: 16),
          child: EnvironmentBadge(),
        )],
      ),
      body: historyState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Failed to load: $err')),
        data: (state) => switch (state) {
          ops.Loading() => const Center(child: CircularProgressIndicator()),
          ops.Empty() => const Center(child: Text('No deployment history.')),
          ops.Error(:final reason) => Center(child: Text('Error: $reason')),
          ops.Data(:final value, :final asOf) => _buildList(context, value, asOf),
        },
      ),
    );
  }

  Widget _buildList(BuildContext context, List<DeploymentSnapshot> snapshots, DateTime asOf) {
    final lastKnownGood = snapshots.firstWhere(
      (s) => s.rolloutPhase == 'Healthy',
      orElse: () => snapshots.first,
    );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('OFFLINE CACHE • as of ${asOf.toIso8601String()}',
            style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 12),
        Card(
          color: Colors.green.withValues(alpha: 0.08),
          child: ListTile(
            title: const Text('Last known good'),
            subtitle: Text('rev ${lastKnownGood.revisionIndex} • ${lastKnownGood.imageTag}'),
            trailing: const Icon(Icons.verified_outlined, color: Colors.green),
          ),
        ),
        const SizedBox(height: 16),
        Text('History', style: Theme.of(context).textTheme.titleSmall),
        ...snapshots.map((s) => Card(
              child: ListTile(
                title: Text('rev ${s.revisionIndex} — ${s.imageTag}'),
                subtitle: Text(
                    'Phase: ${s.rolloutPhase}${s.currentStepIndex != null ? ' (canary step ${s.currentStepIndex}/7)' : ''} • source: ${s.sourceOfTruth.name}'),
              ),
            )),
      ],
    );
  }
}
