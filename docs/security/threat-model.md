# Atlas Threat Model

## Assets
- Job payload data in transit and in Redis
- Container images in Artifact Registry
- GitHub/GitLab repo access and CI/CD pipeline tokens
- Cluster credentials (kubeconfig, service account tokens)
- Terraform state (GCS backend)
- The one deliberate static secret: GITHUB_PUSH_TOKEN (ADR-011)

## Threats
- Compromised CI/CD credential leading to unauthorized image push or repo write
- Lateral movement between pods in the same cluster (no network segmentation existed prior to this phase)
- Malicious or misconfigured pod spec deployed via GitOps (no admission-time policy enforcement existed prior to this phase)
- Unauthenticated access to Redis from any pod that can reach it on the network
- Privilege escalation via privileged containers or missing resource limits enabling noisy-neighbor DoS

## Attack Surfaces
- CI/CD pipeline (GitLab, GitHub, Workload Identity Federation)
- In-cluster pod-to-pod network (previously fully open, no NetworkPolicy)
- Admission path for new workloads (previously unenforced beyond RBAC)
- No public LB/Ingress exists yet (deferred to Phase 13), so external attack surface is currently minimal

## Trust Boundaries
- Internet -> (none yet; no public entrypoint until Phase 13)
- Namespace -> namespace (atlas-platform vs argocd/gmp-system/otel/keda/argo-rollouts)
- Pod -> pod within atlas-platform (api, scheduler, worker, redis)
- CI -> GCP (Workload Identity Federation, keyless)
- CI -> GitHub/GitLab (GITHUB_PUSH_TOKEN, the one static secret)

## Controls Already In Place (prior phases)
- Workload Identity for all workload-to-GCP-API access (no static GCP keys anywhere)
- Namespace-scoped RBAC (kubernetes/rbac/)
- Keyless CI-to-GCP push via Workload Identity Federation
- Image scanning (Trivy) and SAST (Bandit) in CI, non-blocking
- GitOps with Argo CD selfHeal (drift reconciliation proven, see docs/reliability/)
- Argo Rollouts automatic rollback on readiness failure (ADR-019, INCIDENT-006)

## Controls Added This Phase
- Default-deny NetworkPolicy in atlas-platform, with explicit least-privilege allows
- Kyverno admission policies: required resource requests/limits, no :latest tags, no privileged containers

## Residual Risk (stated honestly, not hidden)
- Redis has no AUTH configured. Any pod that a NetworkPolicy allows to reach Redis's port can read/write the full queue unauthenticated. Decision: for this dev-scoped project, NetworkPolicy segmentation (this phase) is judged sufficient mitigation rather than adding Redis AUTH + Secret Manager, since Redis is not exposed outside the atlas-platform namespace and there is no multi-tenant boundary within it. This is a real, accepted gap that would need to be closed before any production use — documented, not silently ignored.
- GITHUB_PUSH_TOKEN remains the one static, stored secret in this project, scoped narrowly (Contents read+write, this repo only) per ADR-011.
- No public LB/Ingress exists yet, so no WAF/DDoS/edge controls are evaluated yet -- deferred to Phase 13's scope.
- Single-region, single Redis instance -- no HA, acknowledged since Phase 4 (ADR-005) and deferred to Phase 13.
