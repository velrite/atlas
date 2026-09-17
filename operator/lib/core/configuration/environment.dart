import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Atlas Operator's active mode. Per ADR-001 / build rule 8:
/// the app must never silently switch between these — the current
/// value must always be visible somewhere in the UI chrome.
enum Environment {
  offline,
  integration,
  live;

  String get label => switch (this) {
        Environment.offline => 'OFFLINE',
        Environment.integration => 'INTEGRATION',
        Environment.live => 'LIVE',
      };
}

class EnvironmentNotifier extends Notifier<Environment> {
  // Defaults to offline: there is no Operations API yet
  // (see api-capability-map.md), so "live" has nothing real to connect to.
  @override
  Environment build() => Environment.offline;

  void setEnvironment(Environment env) => state = env;
}

final environmentProvider =
    NotifierProvider<EnvironmentNotifier, Environment>(EnvironmentNotifier.new);
