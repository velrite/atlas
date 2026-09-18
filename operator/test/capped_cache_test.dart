import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:atlas_operator/core/persistence/capped_cache.dart';

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
    await Hive.openBox('testCappedBox');
    await Hive.openBox('syncMetadata');
  });

  tearDown(() async {
    await Hive.deleteBoxFromDisk('testCappedBox');
    await Hive.deleteBoxFromDisk('syncMetadata');
  });

  test('writeAll evicts oldest entries beyond maxEntries', () async {
    final records = List.generate(10, (i) => {'id': i});
    await CappedCache.writeAll(boxName: 'testCappedBox', records: records, maxEntries: 5);

    final result = CappedCache.readAll('testCappedBox');
    expect(result.length, 5);
    expect(result.first['id'], 5);
    expect(result.last['id'], 9);
  });

  test('data survives a simulated app restart (box closed and reopened)', () async {
    await CappedCache.writeAll(
      boxName: 'testCappedBox',
      records: [{'jobId': 'restart-test-123'}],
      maxEntries: 10,
    );

    await Hive.box('testCappedBox').close();
    await Hive.openBox('testCappedBox');

    final result = CappedCache.readAll('testCappedBox');
    expect(result.length, 1);
    expect(result.first['jobId'], 'restart-test-123');
  });

  test('sync timestamp is recorded and readable per domain', () async {
    final now = DateTime.now();
    await CappedCache.writeSyncTime('testDomain', now);
    final read = CappedCache.readSyncTime('testDomain');
    expect(read, isNotNull);
    expect(read!.difference(now).inSeconds.abs() < 2, isTrue);
  });
}
