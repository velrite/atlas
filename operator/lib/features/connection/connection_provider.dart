import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/operations_api_client.dart';
import '../../core/network/connection_status.dart';
import '../../core/configuration/environment.dart';

final operationsApiClientProvider = Provider<OperationsApiClient>((ref) {
  // TEMP for real-device test (Phase 9 device verification):
  // pointed at the real LoadBalancer external IP so a physical phone
  // can reach it over the internet, since Cloud Shell's port-forward
  // only binds to Cloud Shell's own localhost. Revert to
  // http://localhost:8080 + kubectl port-forward once this test is done
  // and the LoadBalancer Service is torn down.
  return OperationsApiClient(baseUrl: 'http://34.10.76.39');
});

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
      state = AsyncData(ConnectionFailed(e.toString(), DateTime.now()));
    }
  }
}

final connectionProvider =
    AsyncNotifierProvider<ConnectionNotifier, ConnectionStatus>(ConnectionNotifier.new);
