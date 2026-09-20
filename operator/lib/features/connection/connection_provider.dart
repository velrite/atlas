import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/operations_api_client.dart';
import '../../core/network/connection_status.dart';
import '../../core/configuration/environment.dart';

final operationsApiClientProvider = Provider<OperationsApiClient>((ref) {
  // Base URL is injected at build time: --dart-define=OPS_API_URL=http://<host>
  // Defaults to http://localhost:8080 (kubectl port-forward svc/operations-api 8080:80).
  // Never commit a real IP here (see ADR-003 and INCIDENT-010).
  return OperationsApiClient(
    baseUrl: const String.fromEnvironment('OPS_API_URL', defaultValue: 'http://localhost:8080'),
  );
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
