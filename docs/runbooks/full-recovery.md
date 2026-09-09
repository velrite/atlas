Full Environment Recovery Runbook

Use after a full teardown or any Cloud Shell/cluster loss. scripts/startup.sh automates all of this.

Quick path:
Step 1: bash scripts/teardown.sh -- PLAN ONLY, review, then run the printed terraform apply command yourself.
Step 2: bash scripts/startup.sh -- rebuilds everything, has a plan-then-confirm gate before Terraform apply.

If startup.sh exits early after triggering an image rebuild (fresh Artifact Registry has no images), wait for the GitLab pipeline to go green through gitops-update, then re-run bash scripts/startup.sh.

What startup.sh does, in order:
1. Confirms gcloud project context, pulls latest repo.
2. terraform init and plan, with a safety check rejecting the plan if any resource shows project equal to the literal word yes instead of the real project ID -- happened once from an unconfirmed interactive prompt.
3. Requires typing apply to confirm before terraform apply runs -- nothing destructive ever runs unattended.
4. Gets kubectl credentials and hard-checks the context matches the expected cluster exactly, aborting on mismatch, since this account has unrelated clusters too.
5. Applies RBAC, recreates the atlas-workload-ksa Kubernetes service account with its Workload Identity annotation. Easiest step to forget, since it belongs to Phase 3 but is not in Terraform or the Helm chart. Without it, pods fail to even get created, with an error looking up service account message.
6. Helm install or upgrade of the platform.
7. Checks if Artifact Registry is empty, true after a teardown and rebuild since destroying the registry wipes all images. If empty, triggers a pipeline rebuild via an empty commit and exits early.
8. Installs Argo CD in core mode, applies the default AppProject since core mode does not auto create it, applies the Application manifest.
9. Installs Grafana from the pinned version manifest, recreates the Grafana-internal service account token and a placeholder datasource through Grafana's own HTTP API, since none of that state survives a namespace deletion. Binds Workload Identity, deploys the CronJob, triggers one run, reimports the dashboard JSON with the datasource UID rewritten.
10. Installs the OTel Collector with its own dedicated service account and Workload Identity binding.

Known gotchas hit and fixed during a real recovery:
The argocd CLI sync command in core mode fails with a configmap not found error. Auto-sync already catches up on its own polling interval regardless. To force it immediately, patch the Application with the hard-refresh annotation instead of using the CLI sync command.
The datasource-syncer binary's real flag names are datasource-uids, plural, and grafana-api-token -- not grafana-datasource-uid. Running the binary with a bad flag prints its own accurate help text.
Terraform prompting interactively for project_id and silently accepting a stray leftover value is a real and dangerous failure mode when no tfvars file exists. Always pass the variable explicitly.
Artifact Registry images do not survive a terraform destroy and reapply cycle, even though the registry resource itself is recreated identically. The values file's pinned image tag will point at something that no longer exists. startup.sh detects and handles this automatically.
Cloud Shell terminals drop mid-command routinely, including during long Terraform applies. Nothing is lost server side when this happens -- reconnect and check real current state rather than assuming a command needs rerunning from scratch.
Always recheck kubectl current-context after every credentials fetch, since other unrelated clusters exist on this same account.

Verifying the recovery actually worked:
Submit one real job through the API and confirm it completes successfully. Confirm the Grafana dashboard shows real nonzero data by querying a metric through the datasource proxy. Confirm a real trace exists in Cloud Trace containing the submit_job, schedule_job, and execute_job span names for that job, which is the actual end to end proof rather than just checking that pods are running.
