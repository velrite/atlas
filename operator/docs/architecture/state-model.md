# State Model

## Environment (top-level, app-wide)
enum Environment { offline, integration, live }

## Data freshness (per screen / per data view)
enum DataFreshness { live, historical, stale, offlineCache, degraded }

Rule: a cached value must never render as if it were current. Every
data-bearing widget must display its freshness + an "as of" timestamp
sourced from the data itself, not from `DateTime.now()`.

## Generic async wrapper (used by every repository call)

    sealed class OperationalState<T> {
      Loading()
      Data(T value, DateTime asOf, DataFreshness freshness)
      Empty(DateTime asOf)
      Error(String reason, ErrorKind kind)
    }

    enum ErrorKind {
      timeout, networkUnavailable, malformedResponse,
      authFailure, authzFailure, notFound, conflict, cancelled
    }

Only these ErrorKinds are handled, because these are the failure modes
Atlas's real behavior supports evidence for today (e.g. `/jobs/{id}`
returning a real `404 job not found`, GMP query auth requiring GCP
OAuth server-side). No generic catch-and-swallow blocks.
