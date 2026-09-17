import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:atlas_operator/app/root_shell.dart';
import 'package:atlas_operator/core/configuration/environment.dart';

void main() {
  testWidgets('RootShell renders with default OFFLINE environment', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: RootShell()),
      ),
    );

    // Only the currently visible tab's badge is painted/found.
    expect(find.text('OFFLINE'), findsOneWidget);

    // "Overview" legitimately appears twice: the bottom nav tab label,
    // and the AppBar title on the active screen. Disambiguate instead
    // of guessing a count.
    expect(find.widgetWithText(AppBar, 'Overview'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  test('environmentProvider defaults to offline', () {
    final container = ProviderContainer();
    expect(container.read(environmentProvider), Environment.offline);
  });
}
