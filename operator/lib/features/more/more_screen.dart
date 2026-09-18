import 'package:flutter/material.dart';
import '../../shared/widgets/environment_badge.dart';
import '../workloads/workloads_screen.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('More'),
        actions: const [Padding(
          padding: EdgeInsets.only(right: 16),
          child: EnvironmentBadge(),
        )],
      ),
      body: ListView(
        children: [
          ListTile(
            title: const Text('Workloads'),
            subtitle: const Text('Recent jobs'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const WorkloadsScreen()),
            ),
          ),
          const ListTile(title: Text('Observability'), subtitle: Text('Phase 4 — not yet wired')),
          const ListTile(title: Text('Reliability'), subtitle: Text('Phase 4 — not yet wired')),
          const ListTile(title: Text('Incidents'), subtitle: Text('Phase 4 — not yet wired')),
          const ListTile(title: Text('Audit'), subtitle: Text('Phase 7+')),
          const ListTile(title: Text('Settings'), subtitle: Text('Phase 2')),
        ],
      ),
    );
  }
}
