# ADR-009: Argo CD Core Installation Mode for GitOps

## Status
Accepted

## Context
Phase 7 required installing Argo CD to manage the Atlas platform
declaratively from Git, on a cluster with real but not unlimited resource
headroom, following the deliberate node pool upgrade to e2-standard-4 to
support exactly this kind of additional tooling.

## Problem
Argo CD's full installation includes a web UI, API server, Dex
authentication server, and notifications controller in addition to the
core reconciliation engine, adding both resource consumption and attack
surface not strictly required to demonstrate or operate GitOps
reconciliation for a small, single-cluster project managed via CLI.

## Decision
Argo CD is installed in core mode (manifests/core-install.yaml), providing
only the Application Controller, ApplicationSet Controller, Repo Server,
and Redis. All interaction is via the argocd CLI configured with
argocd login --core and kubectl applied against Application and AppProject
custom resources directly, with no web UI or API server running.

## Alternatives Considered
The full installation was considered and rejected for this phase, since
its additional components (UI, API server, Dex, notifications) are not
required to demonstrate the core GitOps capability this phase targets:
declarative sync from Git and automated drift correction. Running the full
installation would also consume meaningfully more of the cluster's
resource budget for components not being actively exercised.

## Trade-offs
Core mode has no web UI, meaning application status, sync history, and
resource trees must be inspected via the CLI or kubectl rather than a
visual dashboard. This is an acceptable trade-off for a project managed
entirely through code and CLI tooling already, but would be reconsidered
for a team-facing production deployment where a visual dashboard has real
operational value for people other than the platform's builder.

Core mode does not automatically create a default AppProject, which the
full installation does. This was not immediately obvious and caused an
InvalidSpecError until the AppProject was created explicitly, documented
in docs/reliability/gitops-drift-reconciliation-evidence.md.

## Consequences
The atlas-platform Helm chart is now managed as an Argo CD Application
with automated sync, prune, and self-heal enabled. A deliberate drift
test confirmed self-heal reverts an unauthorized direct change within
approximately three seconds. Should the web UI become valuable later
(for instance, to visually demonstrate canary rollouts in a later phase),
core mode can be upgraded to full mode by applying the standard
install.yaml over the existing core installation, per Argo CD's own
documented upgrade path, without needing to reinstall from scratch.
