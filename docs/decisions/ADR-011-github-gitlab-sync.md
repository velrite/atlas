# ADR-011: Closing the GitHub/GitLab Asymmetry with a Scoped GitHub Push Token

## Status
Accepted

## Context
ADR-010 accepted an asymmetry where automated gitops-update commits landed
on GitLab, authenticated via CI_JOB_TOKEN, but never reached GitHub, since
CI_JOB_TOKEN has no reach outside its own GitLab project. Argo CD's
Application is configured to watch GitHub specifically, meaning automated
tag updates were not actually being deployed, only committed to a copy of
the repository Argo CD never reads.

## Problem
Keep GitHub authoritative and visibly in sync with what is actually
deployed, since GitHub is the public-facing, portfolio-relevant copy of
this repository, without abandoning the decision to keep Argo CD watching
GitHub rather than switching it to watch GitLab instead.

## Decision
A fine-grained GitHub Personal Access Token, scoped to only the atlas
repository with Contents read-and-write permission, is stored as a masked
and protected GitLab CI/CD variable, GITHUB_PUSH_TOKEN. The gitops-update
stage, after pushing its tag-update commit to GitLab, also pushes the same
branch to GitHub using this token. This closes the loop Argo CD depends
on: GitHub now receives both the manually-authored commits already pushed
by the developer and the automated tag-update commits from CI.

## Alternatives Considered
Pointing Argo CD at GitLab instead of GitHub was rejected, since GitHub is
the repository intended for external review and should reflect what is
actually running, not lag behind an internal GitLab-only commit history.
Leaving the asymmetry unresolved, as accepted in ADR-010, was revisited
and rejected once it was confirmed in practice that this asymmetry
directly prevented Argo CD from ever seeing automated tag updates at all,
not merely a documentation inconvenience.

## Trade-offs
This introduces the project's only static, stored secret to date, a
deliberate departure from the keyless patterns used for Terraform, the
GKE workload platform, and the GitLab-to-GCP registry push, all of which
use impersonation or Workload Identity Federation. This is accepted
because no equivalent OIDC federation path between GitLab CI and GitHub
was readily available for this project's scope, and the token is scoped
as narrowly as GitHub's fine-grained token system allows: one repository,
one permission, write access to contents only.

## Consequences
Every pipeline run now re-pushes GitLab's current main branch to GitHub
after any tag-update commit decision, regardless of whether a new commit
was made in that specific run, ensuring GitHub does not silently drift
behind GitLab over multiple runs. The GITHUB_PUSH_TOKEN should be rotated
periodically and revoked immediately if this repository's CI/CD variables
are ever suspected of exposure, since it is the one credential in this
project's pipeline capable of writing to the public-facing GitHub
repository.
