# ADR-017: Kyverno for Policy-as-Code Admission Control

## Status
Accepted, implemented, verified (Phase 12)

## Context
Atlas had RBAC and (as of this phase) NetworkPolicy, but no admission-time
enforcement of pod-spec hygiene: nothing prevented a future GitOps-deployed
manifest from omitting resource limits, using a `:latest` tag, or running
privileged. This is exactly the kind of drift that would otherwise only be
caught by manual review.

## Decision
Installed Kyverno (server-side apply, per this project's established
CRD-size gotcha -- the plain `install.yaml` also triggers the same
"annotations too long" failure mode as Argo CD and Argo Rollouts if applied
client-side). Three ClusterPolicies, all `validationFailureAction: Enforce`
(hard block, not audit-only), scoped to the atlas-platform namespace:

1. `require-resource-requests-limits` -- every container must define
   cpu/memory requests and limits.
2. `disallow-latest-tag` -- no `:latest` tag or untagged images; enforces
   the SHA-tagging discipline already used by CI (Phase 6+).
3. `disallow-privileged-containers` -- no `securityContext.privileged: true`.

## Evidence
Three real, deliberate violations were submitted and genuinely blocked at
admission time (not just flagged), each with Kyverno's actual returned
error message as proof:
- A pod with no resource limits: rejected citing
  `require-resource-requests-limits` / `validate-resources`.
- A pod using `nginx:latest`: rejected citing `disallow-latest-tag` /
  `require-image-tag`.
- A pod with `privileged: true`: rejected citing
  `disallow-privileged-containers` / `privileged-containers-disallowed`.
All three confirmed absent from the cluster afterward (`kubectl get pod`
returned NotFound for each), proving the block was real, not advisory.

A background PolicyReport scan across every live and historical workload in
atlas-platform (atlas-api, atlas-scheduler, atlas-worker, redis, and all
their ReplicaSet history) showed PASS=3/FAIL=0/ERROR=0 on every entry --
confirming the policies do not regress any real, already-deployed workload,
because those workloads already carried SHA tags and explicit resource
limits from the Phase 5/8 discipline.

One real false start during verification: an ad-hoc `kubectl run` debug pod
using `curlimages/curl:latest` with no resource limits was itself blocked
by the same two policies -- not a bug, but a reminder that even one-off
debug pods must now be policy-compliant (pinned tag + explicit resources).
Verification commands were corrected accordingly.

## Consequences
- Any future manifest -- whether from GitOps or a manual `kubectl apply` --
  that violates these three rules will be rejected at admission time with a
  clear, actionable error message, before it can ever run.
- Enforcement is hard-block (`Enforce`), not audit-only, by deliberate
  choice: the project's existing discipline (SHA tags, explicit limits) was
  already real practice, so enforcing it structurally costs nothing and
  closes a real gap.
- Kyverno is now a hard dependency for deploying ANY new pod into
  atlas-platform -- if Kyverno's admission controller is ever down, new
  pod creation blocks entirely (Kyverno's own webhook failure policy
  applies here; not further hardened in this phase, flagged as a
  future consideration).
