import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/widgets/environment_badge.dart';
import '../../shared/models/job_record.dart';
import '../../core/errors/operational_state.dart' as ops;
import 'workloads_providers.dart';

class WorkloadsScreen extends ConsumerWidget {
  const WorkloadsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobsState = ref.watch(recentJobsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Workloads'),
        actions: const [Padding(
          padding: EdgeInsets.only(right: 16),
          child: EnvironmentBadge(),
        )],
      ),
      body: jobsState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Failed to load: $err')),
        data: (state) => switch (state) {
          ops.Loading() => const Center(child: CircularProgressIndicator()),
          ops.Empty() => const Center(child: Text('No recent jobs.')),
          ops.Error(:final reason) => Center(child: Text('Error: $reason')),
          ops.Data(:final value, :final asOf) => _buildList(context, value, asOf),
        },
      ),
    );
  }

  Widget _buildList(BuildContext context, List<JobRecord> jobs, DateTime asOf) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('OFFLINE CACHE • as of ${asOf.toIso8601String()}',
            style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 12),
        // Real Atlas fact: atlas:queue:pending is almost always empty —
        // the scheduler drains it near-instantly (~5-25ms). Showing a
        // "queue depth: 0" number here would look broken, not healthy.
        // Job list (not queue depth) is the honest signal to show.
        ...jobs.map((j) => Card(
              child: ListTile(
                title: Text(j.jobId, style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
                subtitle: Text('payload: ${j.payload} • ${j.createdAt.toIso8601String()}'),
                trailing: Chip(label: Text(j.status.toUpperCase())),
              ),
            )),
      ],
    );
  }
}
