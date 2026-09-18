import 'action_boundary.dart';

/// A single record of a user-triggered action inside Atlas Operator.
/// This is the audit trail — every time a user taps something that
/// isn't purely passive screen-viewing, one of these gets written.
class AuditRecord {
  final String id;
  final DateTime timestamp;
  final String actionId;
  final ActionBoundary boundary;
  final String environment; // OFFLINE / INTEGRATION / LIVE, as a string
  final String outcome; // e.g. "completed", "blocked", "failed"
  final String? detail;

  const AuditRecord({
    required this.id,
    required this.timestamp,
    required this.actionId,
    required this.boundary,
    required this.environment,
    required this.outcome,
    this.detail,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'timestamp': timestamp.toIso8601String(),
        'actionId': actionId,
        'boundary': boundary.name,
        'environment': environment,
        'outcome': outcome,
        if (detail != null) 'detail': detail,
      };

  factory AuditRecord.fromJson(Map<String, dynamic> json) => AuditRecord(
        id: json['id'] as String,
        timestamp: DateTime.parse(json['timestamp'] as String),
        actionId: json['actionId'] as String,
        boundary: ActionBoundary.values.firstWhere(
          (b) => b.name == json['boundary'],
          orElse: () => ActionBoundary.read,
        ),
        environment: json['environment'] as String,
        outcome: json['outcome'] as String,
        detail: json['detail'] as String?,
      );
}
