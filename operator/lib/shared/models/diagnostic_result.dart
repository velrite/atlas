// A diagnostic is a BOUNDED operation: fixed name, fixed expected
// checks, a real timeout, and an honest outcome — never arbitrary
// shell/kubectl execution (build rule 14).
enum DiagnosticOutcome { ok, degraded, failed, timeout }

class DiagnosticCheck {
  final String label;
  final String value;
  final bool isConcern;

  const DiagnosticCheck(this.label, this.value, {this.isConcern = false});
}

class DiagnosticResult {
  final String diagnosticName;
  final DiagnosticOutcome outcome;
  final String summary;
  final List<DiagnosticCheck> evidence;
  final DateTime ranAt;
  final Duration duration;

  const DiagnosticResult({
    required this.diagnosticName,
    required this.outcome,
    required this.summary,
    required this.evidence,
    required this.ranAt,
    required this.duration,
  });
}
