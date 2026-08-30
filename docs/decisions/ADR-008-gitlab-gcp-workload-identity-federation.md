# ADR-008: GitLab-to-GCP Authentication via Workload Identity Federation (Phase 6b)

## Status
Accepted

## Context
ADR-007 deferred the GitLab CI push-to-Artifact-Registry stage because authenticating GitLab's shared runners to GCP required either a blocked service account key or Workload Identity Federation, which needed dedicated setup.

## Problem
Close the gap identified in ADR-007 by implementing real, keyless authentication from GitLab CI to GCP, without ever storing a static credential in GitLab CI/CD variables.

## Decision
A dedicated Workload Identity Pool, gitlab-pool, and OIDC Provider, gitlab-provider, were created in the velrite-tf-test project, configured to trust ID tokens issued by gitlab.com. The provider's attribute condition restricts trust to exactly one GitLab project path, velrite/atlas, and one branch, main, so no other GitLab project or branch can ever use this trust relationship. A new, dedicated service account, atlas-gitlab-ci, was created specifically for CI use, separate from the atlas-terraform and atlas-workload service accounts already in use, and granted only roles/artifactregistry.writer at the project level. The service account is bound to allow impersonation only by identities matching the pool's attribute.project_path condition. The GitLab pipeline's push job declares an id_tokens block to receive a GitLab-issued OIDC token at job runtime, exchanges it for short-lived GCP credentials using gcloud iam workload-identity-pools create-cred-config, and uses the resulting access token to authenticate a standard docker login before pushing images.

## Alternatives Considered
A downloadable service account key, stored as a masked GitLab CI/CD variable, was rejected for the same reasons as ADR-002 and ADR-007: organization policy blocks key creation, and a static key is a standing credential risk regardless of policy. Reusing the existing atlas-terraform or atlas-workload service accounts for CI push was rejected on least-privilege grounds; CI has a distinct purpose (pushing built artifacts) from infrastructure provisioning or in-cluster workload identity, and conflating them would make audit and blast-radius reasoning harder.

## Trade-offs
Workload Identity Federation setup is more involved than a stored key would have been, requiring a pool, a provider with a carefully scoped attribute condition, a dedicated service account, and pipeline changes to perform the token exchange at runtime. This complexity is justified by eliminating an entire class of credential-leak risk: there is no static secret anywhere in this configuration that could be exfiltrated from GitLab, committed accidentally, or need periodic rotation.

## Consequences
The GitLab CI push stage now performs a real, verified push of commit-SHA-tagged images to Artifact Registry using short-lived, automatically-scoped credentials. This closes the gap documented in ADR-007. The attribute condition scoping to a specific project path and branch is the actual security boundary of this setup and should be reviewed before ever changing the default branch name or forking this pipeline configuration to another GitLab project.
