import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:atlas_operator/features/workloads/workloads_screen.dart';

void main() {
  testWidgets('WorkloadsScreen shows real fixture job IDs', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: WorkloadsScreen()),
      ),
    );

    // Let the FutureProvider resolve (reads from rootBundle asset).
    await tester.pumpAndSettle();

    // Real job ID from fixtures/healthy/jobs.json — proves the screen
    // is reading actual fixture data, not a hardcoded placeholder.
    expect(find.textContaining('101513fe-7a31-4ca6-9961-b2518cdc7e14'), findsOneWidget);
    expect(find.text('OFFLINE'), findsOneWidget);
  });
}
