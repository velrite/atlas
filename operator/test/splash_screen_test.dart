import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:atlas_operator/app/splash_screen.dart';
import 'package:atlas_operator/shared/widgets/velrite_wordmark.dart';

void main() {
  testWidgets('SplashScreen shows wordmark, then navigates to RootShell', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: SplashScreen())),
    );
    expect(find.byType(VelriteWordmark), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1300));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget); // confirms RootShell loaded
  });
}
