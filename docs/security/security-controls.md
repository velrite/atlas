# Security Controls

## Implemented

| Control | Mechanism | Scope |
|---|---|---|
| Admission policy | Kyverno `ClusterPolicy`: `disallow-latest-tag`, `disallow-privileged-containers`, `require-resource-requests-limits` | Cluster-wide on `atlas-dev` |
| Network segmentation | Kubernetes `NetworkPolicy`, default-deny + explicit allow | Namespace-scoped |
| CI supply-chain checks | `sast`, `dependency-scan`, `iac-scan`, `image-scan` stages in `.gitlab-ci.yml` | Every pipeline run |
| CI authentication to GCP | Workload Identity Federation (`GITLAB_OIDC_TOKEN`), no static GCP keys in CI | `push` stage |
| Local persistence | Hive (on-device only, capped, no cloud sync) | Atlas Operator app |

## Explicitly NOT implemented (do not claim otherwise)

- **Atlas's own API has zero authentication.** Access control today is
  network-policy-only, not identity-based. Any claim of "zero trust" or
  "authenticated API" is false as of this writing.
- **Atlas Operator has no auth of its own** — deliberate, per ADR-001,
  since the backend it talks to has none either.
- **`operations-api` currently has no TLS and no auth** on its
  `/health`/`/ready` endpoints. During Phase 9 real-device testing
  (ADR-003), this was briefly exposed to the public internet via a
  temporary `LoadBalancer` Service and Android's cleartext-HTTP block
  was relaxed for that one test build. Both were reverted / must be
  reverted after the test — see ADR-003 for the full trade-off.

## Before publishing any screenshot from this project

Redact or crop out:
- The classic GitLab Personal Access Token value (`glpat-...`) used
  during the CI runner fix — it should also be revoked, not just hidden.
- The GitLab runner registration token
  (`glrt-...`) visible in `/etc/gitlab-runner/config.toml`.
- Any real external IP addresses if you consider them sensitive (the
  temporary LoadBalancer IP used for device testing is not itself
  secret, but the service should already be deleted by publication
  time).
- Any `CI_JOB_TOKEN` or `GITHUB_PUSH_TOKEN` values that might appear in
  raw CI job logs.
