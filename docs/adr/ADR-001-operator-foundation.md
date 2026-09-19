# ADR-001: Atlas Operator Foundation

## Status
Accepted

## Context
Atlas needed a mobile operational interface. It had to be built against
real Atlas facts (no fabricated data), and had to live somewhere
sensible relative to the existing Atlas repository.

## Problem
Where does the mobile app live, how does it connect to Atlas, which
platform does it target first, and what does it persist locally?

## Decision
- Repo location: `atlas/operator/` inside the existing `atlas` repository
  (not a separate repo).
- Connectivity (dev/INTEGRATION): reach the backend via
  `kubectl port-forward`, no public Ingress added.
- Platform: Android only (development environment has no macOS/iOS
  toolchain available).
- Local persistence: Hive.
- Auth: none yet — Atlas itself has no auth, so the app is single-user
  until an Operations API with its own auth exists.

## Consequences
### Positive
Keeps the operator co-versioned with the platform it observes; avoids
building auth the backend doesn't support yet.

### Negative
Real-device testing is harder than it would be with a public Ingress —
this directly caused the Phase 9 device-connectivity investigation (see
`docs/incidents/`).

## Explicit out-of-scope
No control in the app may ever trigger `terraform apply`/`destroy` or
otherwise change Atlas's infrastructure lifecycle.
