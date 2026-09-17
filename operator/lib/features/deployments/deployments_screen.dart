import 'package:flutter/material.dart';
import '../../shared/widgets/environment_badge.dart';

class DeploymentsScreen extends StatelessWidget {
  const DeploymentsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Deployments'),
        actions: const [Padding(
          padding: EdgeInsets.only(right: 16),
          child: EnvironmentBadge(),
        )],
      ),
      body: const Center(
        child: Text(
          'UNKNOWN — Phase 3 wires real offline fixtures here.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
