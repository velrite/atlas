# Navigation

Bottom nav, 4 top-level tabs (Android, one-hand mobile use):

  Overview | Deployments | Diagnostics | More

"More" opens: Workloads, Observability, Incidents, Audit, Settings.
Kept off the bottom bar to avoid a cluttered 8-icon nav rail on a
phone screen (build rule 23: calm, not dense-for-its-own-sake).

Each top-level screen can push detail routes:
  Overview → tap unhealthy component → Diagnostic detail
  Deployments → tap a revision → Deployment detail → Compare view
  Incidents → tap incident → Incident detail → linked Deployment / Runbook

No mutating action exists anywhere yet (see ADR-001, consequence #2).
