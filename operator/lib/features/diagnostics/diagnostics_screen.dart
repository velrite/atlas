import 'package:flutter/material.dart';
import '../../shared/widgets/environment_badge.dart';

class DiagnosticsScreen extends StatelessWidget {
  const DiagnosticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnostics'),
        actions: const [Padding(
          padding: EdgeInsets.only(right: 16),
          child: EnvironmentBadge(),
        )],
      ),
      body: const Center(
        child: Text(
          'UNKNOWN — Phase 4 wires real diagnostic operations here.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
