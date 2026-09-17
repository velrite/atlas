import 'package:flutter/material.dart';
import '../features/overview/overview_screen.dart';
import '../features/deployments/deployments_screen.dart';
import '../features/diagnostics/diagnostics_screen.dart';
import '../features/more/more_screen.dart';

class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 0;

  static const _screens = [
    OverviewScreen(),
    DeploymentsScreen(),
    DiagnosticsScreen(),
    MoreScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), label: 'Overview'),
          NavigationDestination(icon: Icon(Icons.rocket_launch_outlined), label: 'Deployments'),
          NavigationDestination(icon: Icon(Icons.monitor_heart_outlined), label: 'Diagnostics'),
          NavigationDestination(icon: Icon(Icons.more_horiz), label: 'More'),
        ],
      ),
    );
  }
}
