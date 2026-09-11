# Grafana datasource-syncer

`datasource-syncer-cronjob.yaml` is committed for disaster recovery reference,
but the CronJob depends on two pieces of Grafana-internal state that are
NEVER committed and do NOT survive a Grafana pod reschedule or namespace
rebuild (Grafana has no persistent volume - SQLite state is ephemeral):

1. The `datasource-syncer-token` Secret (a Grafana service-account API token)
2. The datasource UID referenced in the CronJob's `--datasource-uids` arg

**If Grafana's pod is ever rescheduled (including by an unrelated chaos
experiment or node drain) or the `grafana` namespace is rebuilt, this CronJob
WILL start failing with 401 errors** until both are regenerated. This
happened for real on 2026-09-11 (Grafana pod rescheduled during Phase 14
chaos experiments) and required a manual fix - see the fix procedure below.

## Fix procedure (manual, until this is automated in scripts/startup.sh)

1. Port-forward to Grafana: `kubectl port-forward -n grafana svc/grafana 3000:3000`
2. Create a new service account + token via Grafana's HTTP API
3. Check if the old datasource UID still resolves (`GET /api/datasources/uid/<uid>`);
   if 404, create a fresh datasource
4. Update the `datasource-syncer-token` Secret with the new token
5. Patch the CronJob's `--datasource-uids` arg if the UID changed
6. Trigger a manual test run: `kubectl create job --from=cronjob/datasource-syncer <name> -n grafana`

**Real gap, not yet closed:** this should be added to `scripts/startup.sh`
as an idempotent check-and-repair step. Tracked as follow-up work for
Phase 18's final documentation pass.
