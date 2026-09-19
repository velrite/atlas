import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:atlas_operator/features/overview/overview_screen.dart';
import 'package:atlas_operator/app/scenario.dart';
import 'package:atlas_operator/core/configuration/environment.dart';

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

  testWidgets('Connection banner is hidden in OFFLINE, shown in INTEGRATION',
      (tester) async {
    // Default container — no overrides — means default OFFLINE, same as
    // the app's real-world default (see EnvironmentNotifier.build()).
    final offlineContainer = ProviderContainer();
    addTearDown(offlineContainer.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: offlineContainer,
        child: const MaterialApp(home: OverviewScreen()),
      ),
    );
    // Same reasoning as below: bounded pumps instead of pumpAndSettle(),
    // since we don't need every animation in the tree to finish — just
    // enough frames for our own async providers to resolve.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('Operations API'), findsNothing);

    // A second, separate container forced into INTEGRATION mode — this
    // is the only case Phase 9's banner is meant to ever appear in.
    final integrationContainer = ProviderContainer(
      overrides: [
        environmentProvider.overrideWith(
          () => _FakeIntegrationEnvironmentNotifier(),
        ),
      ],
    );
    addTearDown(integrationContainer.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: integrationContainer,
        child: const MaterialApp(home: OverviewScreen()),
      ),
    );
    // AsyncNotifier.build() resolves asynchronously even for an
    // immediate value — one pump lets ConnectionUnknown actually land
    // before we assert on it (same gotcha as elsewhere in this project).
    // pumpAndSettle() is avoided here: it waits for ALL animations
    // anywhere on screen to finish, and hangs forever against any
    // repeating one. A few bounded pumps are enough for our own
    // async provider state to resolve without depending on the rest
    // of the widget tree ever going fully still.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('Operations API: not checked yet'), findsOneWidget);
    expect(find.text('Check'), findsOneWidget);
  });
}

class _FakeIntegrationEnvironmentNotifier extends EnvironmentNotifier {
  @override
  Environment build() => Environment.integration;
}
