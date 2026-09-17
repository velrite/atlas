import 'package:hive_flutter/hive_flutter.dart';

/// Box names match offline-strategy.md exactly. Bounded retention
/// (build rule 47) is enforced by callers when writing, not here.
class HiveBoxes {
  static const jobs = 'jobs';
  static const deploymentSnapshots = 'deploymentSnapshots';
  static const componentHealth = 'componentHealth';
  static const telemetryCache = 'telemetryCache';
  static const syncMetadata = 'syncMetadata';

  static Future<void> initAll() async {
    await Hive.initFlutter();
    await Future.wait([
      Hive.openBox(jobs),
      Hive.openBox(deploymentSnapshots),
      Hive.openBox(componentHealth),
      Hive.openBox(telemetryCache),
      Hive.openBox(syncMetadata),
    ]);
  }
}
