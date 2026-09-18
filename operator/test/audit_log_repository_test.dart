import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:atlas_operator/core/security/action_boundary.dart';
import 'package:atlas_operator/core/security/audit_log_repository.dart';

class FakePathProviderPlatform extends PlatformInterface
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  FakePathProviderPlatform() : super(token: _token);
  static final Object _token = Object();

  @override
  Future<String?> getApplicationDocumentsPath() async => '.';
  @override
  Future<String?> getApplicationCachePath() async => '.';
  @override
  Future<String?> getTemporaryPath() async => '.';
  @override
  Future<String?> getApplicationSupportPath() async => '.';
  @override
  Future<String?> getLibraryPath() async => '.';
  @override
  Future<String?> getExternalStoragePath() async => '.';
  @override
  Future<List<String>?> getExternalCachePaths() async => ['.'];
  @override
  Future<List<String>?> getExternalStoragePaths({dynamic type}) async => ['.'];
  @override
  Future<String?> getDownloadsPath() async => '.';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  PathProviderPlatform.instance = FakePathProviderPlatform();

  setUp(() async {
    await Hive.initFlutter();
    await Hive.openBox(AuditLogRepository.boxName);
  });

  tearDown(() async {
    await Hive.deleteBoxFromDisk(AuditLogRepository.boxName);
  });

  test('record() writes an entry that readAll() can see', () async {
    await AuditLogRepository.record(
      actionId: 'run_diagnostic_check',
      boundary: ActionBoundary.read,
      environment: 'OFFLINE',
      outcome: 'completed',
    );

    final entries = AuditLogRepository.readAll();
    expect(entries.length, 1);
    expect(entries.first.actionId, 'run_diagnostic_check');
    expect(entries.first.boundary, ActionBoundary.read);
    expect(entries.first.outcome, 'completed');
  });

  test('audit log caps at maxEntries, keeping most recent', () async {
    for (var i = 0; i < AuditLogRepository.maxEntries + 10; i++) {
      await AuditLogRepository.record(
        actionId: 'run_diagnostic_check',
        boundary: ActionBoundary.read,
        environment: 'OFFLINE',
        outcome: 'completed $i',
      );
    }

    final entries = AuditLogRepository.readAll();
    expect(entries.length, AuditLogRepository.maxEntries);
    expect(
      entries.last.outcome,
      'completed ${AuditLogRepository.maxEntries + 9}',
    );
  });
}
