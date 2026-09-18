import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:atlas_operator/features/diagnostics/diagnostics_screen.dart';

void main() {
  testWidgets('DiagnosticsScreen runs check and shows OK result on healthy scenario',
      (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: DiagnosticsScreen()),
      ),
    );

    // AsyncNotifier.build() is async — even though it resolves to null
    // immediately, it doesn't complete within the same frame as
    // pumpWidget. Pump once to let the initial build settle before
    // asserting on the "not run yet" state.
    await tester.pump();
    expect(find.text('No diagnostic run yet. Tap Run to check worker capacity.'), findsOneWidget);

    await tester.tap(find.text('Run'));
    await tester.pump(); // enter running-diagnostic loading state
    expect(find.text('Running diagnostic…'), findsOneWidget);

    await tester.pumpAndSettle(); // let the 800ms fixture delay finish
    expect(find.text('OK'), findsOneWidget);
    expect(find.text('Worker capacity nominal.'), findsOneWidget);
  });
}
