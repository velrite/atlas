import 'package:flutter/material.dart';
import '../../shared/widgets/environment_badge.dart';

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
        children: const [
          ListTile(title: Text('Workloads'), subtitle: Text('Phase 3+')),
          ListTile(title: Text('Observability'), subtitle: Text('Phase 3+')),
          ListTile(title: Text('Incidents'), subtitle: Text('Phase 3+')),
          ListTile(title: Text('Audit'), subtitle: Text('Phase 7+')),
          ListTile(title: Text('Settings'), subtitle: Text('Phase 2')),
        ],
      ),
    );
  }
}
