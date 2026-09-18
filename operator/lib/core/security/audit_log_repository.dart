import 'package:flutter/foundation.dart' show debugPrint;
import '../persistence/capped_cache.dart';
import 'action_boundary.dart';
import 'audit_record.dart';

/// Reads and writes the local audit trail. Every controlled or
/// high-risk action attempt should end up here. Right now only
/// read-boundary actions exist, so this proves the plumbing works
/// ahead of Phase 8/9 needing it for real.
class AuditLogRepository {
  static const String boxName = 'auditLog';
  static const int maxEntries = 200;

  /// Writes a new audit record. Like the data repositories, a failed
  /// write (e.g. Hive box not open, which happens in widget tests)
  /// must never throw and break the screen the user is actually
  /// looking at — it's logged and swallowed, same pattern already used
  /// in ComponentHealthRepository/JobRepository.
  static Future<void> record({
    required String actionId,
    required ActionBoundary boundary,
    required String environment,
    required String outcome,
    String? detail,
  }) async {
    final entry = AuditRecord(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      timestamp: DateTime.now(),
      actionId: actionId,
      boundary: boundary,
      environment: environment,
      outcome: outcome,
      detail: detail,
    );

    try {
      final existing = CappedCache.readAll(boxName);
      final updated = [...existing, entry.toJson()];
      await CappedCache.writeAll(
        boxName: boxName,
        records: updated,
        maxEntries: maxEntries,
      );
    } catch (e) {
      debugPrint('Audit log write skipped: $e');
    }
  }

  static List<AuditRecord> readAll() {
    final raw = CappedCache.readAll(boxName);
    return raw.map((e) => AuditRecord.fromJson(e)).toList();
  }
}
