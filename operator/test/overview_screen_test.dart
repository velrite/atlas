import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:atlas_operator/features/overview/overview_screen.dart';
import 'package:atlas_operator/app/scenario.dart';

void main() {
  testWidgets('OverviewScreen shows Primary issue card only in degraded scenario',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: OverviewScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Primary issue'), findsNothing);

    container.read(scenarioProvider.notifier).toggle();
    await tester.pumpAndSettle();

    expect(find.text('Primary issue'), findsOneWidget);
    expect(find.textContaining('WORKER:'), findsOneWidget);
  });
}
