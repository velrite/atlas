/// Only failure modes with actual evidence behind them
/// (see state-model.md). No generic catch-all.
enum ErrorKind {
  timeout,
  networkUnavailable,
  malformedResponse,
  authFailure,
  authzFailure,
  notFound,      // e.g. real "404 job not found" from atlas-api
  conflict,
  cancelled,
}

class OperationalException implements Exception {
  final ErrorKind kind;
  final String message;

  const OperationalException(this.kind, this.message);

  @override
  String toString() => 'OperationalException($kind): $message';
}
