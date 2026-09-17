# ADR-001: Atlas Operator Foundational Decisions

Status: Accepted
Date: 2026-09-17

## Context
Atlas Operator is a new mobile client for the existing Atlas platform.
Atlas has no HTTP Ingress, no auth layer, and no Operations API yet.
Six foundational decisions were needed before any code could be written.

## Decisions

1. **Repo location:** `atlas/operator/` inside the existing atlas repo.
   One source of truth, one CI/CD pipeline family.

2. **Connectivity:** Operations API runs in-cluster. Dev and
   INTEGRATION mode reach it via `kubectl port-forward`. No public
   Ingress is added in this phase — Atlas currently has zero external
   exposure (ClusterIP only, no Ingress controller), and adding one is
   a real change to Atlas's network posture that deserves its own ADR
   later, not a side effect of building a mobile app.

3. **Platforms:** Android only. Dev environment is GCP Cloud Shell /
   mobile terminal — no Mac available for iOS builds.

4. **Local persistence:** Hive. Pure-Dart, no native build step,
   fits the fixture/snapshot data shape (jobs, deployment snapshots,
   component health, sync metadata).

5. **Auth:** None in this phase. Atlas's own API has zero auth today
   (NetworkPolicy is the only access control). Building operator-side
   auth before the Operations API exists would be auth theater.
   Single-user (Dee) until the Operations API is built.

6. **Branding:** No existing Atlas brand assets. A minimal visual
   system is defined fresh in `docs/design/visual-system.md`.

## Consequences
- The Operations API (Phase 8 of the master build plan) is a real
  backend project, not a config step — it does not exist yet.
- Any mutating action is out of scope until the Operations API exists
  AND a GitOps-safe write path is designed (Argo CD selfHeal reverts
  direct cluster patches in under 3 seconds — mutations must go
  through Git, not direct patches).
- Multi-region is explicitly out of scope (Atlas Phase 13 deferred).
