import 'package:hive_flutter/hive_flutter.dart';

// Writes a list of JSON-encodable records into a Hive box, keeping only
// the most recent [maxEntries]. Oldest evicted first (offline-strategy.md).
class CappedCache {
  static Future<void> writeAll({
    required String boxName,
    required List<Map<String, dynamic>> records,
    required int maxEntries,
  }) async {
    final box = Hive.box(boxName);
    await box.clear();
    final trimmed = records.length > maxEntries
        ? records.sublist(records.length - maxEntries)
        : records;
    for (var i = 0; i < trimmed.length; i++) {
      await box.put(i, trimmed[i]);
    }
  }

  static List<Map<String, dynamic>> readAll(String boxName) {
    final box = Hive.box(boxName);
    return box.values
        .map((v) => Map<String, dynamic>.from(v as Map))
        .toList();
  }

  static Future<void> writeSyncTime(String domain, DateTime time) async {
    final box = Hive.box('syncMetadata');
    await box.put(domain, time.toIso8601String());
  }

  static DateTime? readSyncTime(String domain) {
    final box = Hive.box('syncMetadata');
    final raw = box.get(domain) as String?;
    return raw != null ? DateTime.parse(raw) : null;
  }
}
