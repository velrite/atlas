import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/operations_api_client.dart';
import '../../core/network/connection_status.dart';
import '../../core/configuration/environment.dart';

final operationsApiClientProvider = Provider<OperationsApiClient>((ref) {
  return OperationsApiClient();
});

/// Only meaningful in INTEGRATION mode. OFFLINE has nothing to check
/// (by design, no backend exists to it). LIVE isn't wired to anything
/// real yet either — Phase 9 is specifically the INTEGRATION handshake,
/// not a claim that LIVE mode does anything today.
class ConnectionNotifier extends AsyncNotifier<ConnectionStatus> {
  @override
  Future<ConnectionStatus> build() async => const ConnectionUnknown();

  Future<void> checkConnection() async {
    final environment = ref.read(environmentProvider);
    if (environment != Environment.integration) {
      state = const AsyncData(ConnectionUnknown());
      return;
    }

    state = const AsyncData(ConnectionChecking());
    final client = ref.read(operationsApiClientProvider);

    try {
      await client.checkHealth();
      await client.checkReady();
      state = AsyncData(ConnectionHealthy(DateTime.now()));
    } catch (e) {
      // Caught here, not left to throw up into the UI, because a
      // failed real connection is an expected, displayable state in
      // INTEGRATION mode — not a crash. Same "swallow and surface
      // honestly" pattern as the offline repositories, applied to a
      // network failure instead of a cache failure.
      state = AsyncData(ConnectionFailed(e.toString(), DateTime.now()));
    }
  }
}

final connectionProvider =
    AsyncNotifierProvider<ConnectionNotifier, ConnectionStatus>(ConnectionNotifier.new);
