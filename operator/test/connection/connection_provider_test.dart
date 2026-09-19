import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:atlas_operator/core/network/operations_api_client.dart';
import 'package:atlas_operator/core/network/connection_status.dart';
import 'package:atlas_operator/core/configuration/environment.dart';
import 'package:atlas_operator/features/connection/connection_provider.dart';

// A fake http.Client so this test never makes a real network call —
// same principle as FakePathProviderPlatform from Phase 6: prove the
// logic works without depending on anything external actually running.
class _FakeHttpClient extends http.BaseClient {
  final int statusCode;
  _FakeHttpClient({this.statusCode = 200});

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final bytes = utf8.encode('{"status":"ok"}');
    return http.StreamedResponse(Stream.value(bytes), statusCode);
  }
}

void main() {
  test('stays Unknown in OFFLINE mode, never calls the network', () async {
    final container = ProviderContainer(overrides: [
      operationsApiClientProvider.overrideWithValue(
        OperationsApiClient(client: _FakeHttpClient(statusCode: 500)),
      ),
    ]);
    addTearDown(container.dispose);

    await container.read(connectionProvider.notifier).checkConnection();
    final status = container.read(connectionProvider).value;
    expect(status, isA<ConnectionUnknown>());
  });

  test('reports Healthy when both checks succeed in INTEGRATION mode', () async {
    final container = ProviderContainer(overrides: [
      operationsApiClientProvider.overrideWithValue(
        OperationsApiClient(client: _FakeHttpClient(statusCode: 200)),
      ),
    ]);
    addTearDown(container.dispose);

    container.read(environmentProvider.notifier).setEnvironment(Environment.integration);
    await container.read(connectionProvider.notifier).checkConnection();
    final status = container.read(connectionProvider).value;
    expect(status, isA<ConnectionHealthy>());
  });

  test('reports Failed honestly when the real call fails, does not throw', () async {
    final container = ProviderContainer(overrides: [
      operationsApiClientProvider.overrideWithValue(
        OperationsApiClient(client: _FakeHttpClient(statusCode: 503)),
      ),
    ]);
    addTearDown(container.dispose);

    container.read(environmentProvider.notifier).setEnvironment(Environment.integration);
    await container.read(connectionProvider.notifier).checkConnection();
    final status = container.read(connectionProvider).value;
    expect(status, isA<ConnectionFailed>());
  });
}
