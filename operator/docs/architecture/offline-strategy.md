# Offline Strategy

## Hive boxes
- `jobs` — last 100 JobRecords
- `deploymentSnapshots` — last 50, mirrors k8s revisionHistoryLimit
  reality (cluster only keeps 3; app keeps more from Git history)
- `componentHealth` — last known status per component
- `telemetryCache` — last known value per metric, always paired with
  its real `asOf` timestamp
- `syncMetadata` — last successful sync time per data domain, used to
  compute STALE vs HISTORICAL vs LIVE in the UI

## NOT stored in Hive
Incidents and chaos experiment docs — these are static markdown files
bundled as Flutter assets, not fetched/cached data.

## Retention
Bounded, not unlimited (`build rule 47: do not store unnecessary data`).
Oldest records evicted first per box once the cap is hit.
