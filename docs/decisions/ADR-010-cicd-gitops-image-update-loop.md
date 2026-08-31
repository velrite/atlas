# ADR-010: CI-Driven GitOps Image Tag Updates (Phase 7b)

## Status
Accepted

## Context
Phase 7 established Argo CD managing atlas-platform declaratively from
Git, but the image tag in values.yaml remained static, meaning a
successful CI build and push did not result in that new image actually
being deployed.

## Problem
Close the gap between CI producing a new artifact and that artifact
becoming the cluster's desired state, without compromising the GitOps
principle that Argo CD only ever acts on Git, and without introducing a
new long-lived credential.

## Decision
The gitops-update pipeline stage clones the repository using GitLab's
automatically-injected CI_JOB_TOKEN, a short-lived token scoped to that
specific job's permissions on that specific project, runs a small external
shell script that updates the image tag in helm/atlas-platform/values.yaml
to the current commit's short SHA, and commits and pushes this change back
to the GitLab repository. Argo CD's existing automated sync with selfHeal
then detects this Git change and deploys the new image automatically.

The tag-update logic was deliberately implemented as an external shell
script (scripts-update-tag.sh) rather than an inline sed or Python command
directly in the YAML script block, after repeated YAML parsing failures
caused by a literal colon-space sequence inside quoted strings being
misinterpreted by the YAML parser as a mapping key. Moving the logic to an
external file with no YAML quoting involved eliminated this entire class
of error.

## Alternatives Considered
Argo CD Image Updater, an add-on that polls container registries directly
and updates Application manifests itself, was considered and rejected for
this project's scale, since it would require Argo CD to hold registry-read
credentials and run its own polling loop when the pipeline already has
both the exact tag it just built and git write capability via
CI_JOB_TOKEN.

## Trade-offs
CI_JOB_TOKEN only grants write access to the GitLab-hosted copy of the
repository, not the GitHub-hosted original. Automated gitops-update
commits land on GitLab main but do not automatically propagate to GitHub
main, a known and accepted asymmetry rather than something solved with
additional cross-remote automation.

## Consequences
A full commit-to-deployment loop now exists: a code change is pushed, CI
tests, scans, builds, and pushes a uniquely tagged image, updates the
desired state in Git, and Argo CD deploys it automatically, with no manual
kubectl or helm command required after the initial push.
