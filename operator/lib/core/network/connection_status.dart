/// What we currently know about the real Operations API connection.
/// This only exists to represent Phase 8's actual capability today:
/// health/ready checks. It does NOT claim to represent real Atlas
/// component health or job data — Operations API doesn't serve that
/// yet (that's Chunk 2, not built). Showing anything beyond
/// connected/disconnected here would be exactly the kind of
/// fabricated claim this project has ruled out from day one.
sealed class ConnectionStatus {
  const ConnectionStatus();
}

class ConnectionUnknown extends ConnectionStatus {
  const ConnectionUnknown();
}

class ConnectionChecking extends ConnectionStatus {
  const ConnectionChecking();
}

class ConnectionHealthy extends ConnectionStatus {
  final DateTime checkedAt;
  const ConnectionHealthy(this.checkedAt);
}

class ConnectionFailed extends ConnectionStatus {
  final String reason;
  final DateTime checkedAt;
  const ConnectionFailed(this.reason, this.checkedAt);
}
