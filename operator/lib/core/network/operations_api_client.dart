import 'dart:convert';
import 'package:http/http.dart' as http;

/// Talks to the real Operations API deployed in Phase 8. This is the
/// first piece of code in Atlas Operator that makes an actual network
/// call to real infrastructure — everything before this was fixtures.
///
/// baseUrl defaults to the port-forward target (kubectl port-forward
/// svc/operations-api 8080:80 -n default, from Phase 8). It's a
/// constructor parameter, not hardcoded, specifically so it can be
/// pointed at 10.0.2.2:8080 (Android emulator's alias for the host
/// machine's localhost) or anywhere else without editing this file.
class OperationsApiClient {
  final String baseUrl;
  final http.Client _client;

  OperationsApiClient({
    this.baseUrl = 'http://localhost:8080',
    http.Client? client,
  }) : _client = client ?? http.Client();

  /// Real health check against the real pod. Throws on any failure —
  /// timeout, connection refused, non-200 — rather than swallowing it,
  /// because a failed real check is meaningful information the UI
  /// layer needs to show honestly, not hide.
  Future<Map<String, dynamic>> checkHealth() async {
    final response = await _client
        .get(Uri.parse('$baseUrl/health'))
        .timeout(const Duration(seconds: 5));
    if (response.statusCode != 200) {
      throw Exception('Operations API /health returned ${response.statusCode}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> checkReady() async {
    final response = await _client
        .get(Uri.parse('$baseUrl/ready'))
        .timeout(const Duration(seconds: 5));
    if (response.statusCode != 200) {
      throw Exception('Operations API /ready returned ${response.statusCode}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }
}
