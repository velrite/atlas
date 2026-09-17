import 'package:flutter_riverpod/flutter_riverpod.dart';

// Which offline fixture SET is shown (healthy vs degraded).
// Separate from Environment (offline/integration/live) — this only
// exists so we can test state handling without a real degraded Atlas.
enum FixtureScenario { healthy, degraded }

class FixtureScenarioNotifier extends Notifier<FixtureScenario> {
  @override
  FixtureScenario build() => FixtureScenario.healthy;

  void toggle() {
    state = state == FixtureScenario.healthy
        ? FixtureScenario.degraded
        : FixtureScenario.healthy;
  }
}

final scenarioProvider =
    NotifierProvider<FixtureScenarioNotifier, FixtureScenario>(FixtureScenarioNotifier.new);
