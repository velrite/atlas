import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:atlas_operator/features/diagnostics/diagnostics_screen.dart';

void main() {
  testWidgets('FIXTURE DATA label appears only outside OFFLINE mode', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: DiagnosticsScreen())),
    );
    await tester.pump();
    expect(find.textContaining('FIXTURE DATA'), findsNothing);

    // The badge is tappable: OFFLINE -> INTEGRATION
    await tester.tap(find.text('OFFLINE'));
    await tester.pump();
    expect(find.text('INTEGRATION'), findsOneWidget);
    expect(find.textContaining('FIXTURE DATA'), findsOneWidget);
  });
}
