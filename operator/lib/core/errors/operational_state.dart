import 'error_kind.dart';

/// A cached value must never render as if it were current.
/// Every data-bearing widget shows freshness alongside the value.
enum DataFreshness { live, historical, stale, offlineCache, degraded }

/// The one shape every screen's data goes through: loading, got it,
/// nothing here, or broken — with WHY it's broken, not a swallowed error.
sealed class OperationalState<T> {
  const OperationalState();
}

class Loading<T> extends OperationalState<T> {
  const Loading();
}

class Data<T> extends OperationalState<T> {
  final T value;
  final DateTime asOf;
  final DataFreshness freshness;

  const Data(this.value, {required this.asOf, required this.freshness});
}

class Empty<T> extends OperationalState<T> {
  final DateTime asOf;
  const Empty(this.asOf);
}

class Error<T> extends OperationalState<T> {
  final ErrorKind kind;
  final String reason;
  const Error(this.kind, this.reason);
}
