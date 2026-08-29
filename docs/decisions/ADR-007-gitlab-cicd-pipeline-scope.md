# ADR-007: GitLab CI/CD Pipeline Scope for Phase 6 (Push Stage Deferred)

## Status
Accepted

## Context
Phase 6 required a real, executing GitLab CI/CD pipeline covering test, lint, SAST, dependency scanning, IaC scanning, build, and image scanning, connected to the GitHub-hosted repository via a GitLab CI/CD-only project.

## Problem
Authenticating GitLab's shared runners to Google Cloud to push built images to Artifact Registry requires either a downloadable service account key or Workload Identity Federation between GitLab and GCP. A downloadable key is blocked by the same organization policy, constraints/iam.disableServiceAccountKeyCreation, that affected the Terraform service account in ADR-002. Workload Identity Federation is the correct keyless approach but requires meaningful additional setup: a Workload Identity Pool, an OIDC provider trusting GitLab's token issuer, and IAM bindings mapping GitLab's identity claims to a GCP service account.

## Decision
The Phase 6 pipeline implements every stage through image scanning as fully real and executing: unit test placeholder, Python lint, Bandit SAST, Trivy dependency scanning, Checkov IaC scanning, Docker builds for all three components tagged by commit SHA, and Trivy image scanning of the built artifacts. The push-to-Artifact-Registry stage is implemented as an explicit placeholder that reports what would be pushed rather than silently pretending to push, or blocking the entire pipeline on missing GCP authentication. GitOps manifest updates are similarly deferred as a placeholder until Argo CD exists in Phase 7.

## Alternatives Considered
Creating a downloadable service account key for a new CI-specific service account was considered and rejected both because organization policy blocks it and because it would reintroduce the exact long-lived credential risk already rejected in ADR-002 for Terraform. Skipping the pipeline stages that require registry authentication entirely, rather than including them as explicit placeholders, was considered and rejected because it would understate what the pipeline actually does and make the gap less visible to a reviewer.

## Trade-offs
Deferring registry push means this phase's pipeline does not yet complete a full CI/CD loop end to end; images built in CI are not yet the images running in the cluster, which still runs the images pushed manually in Phase 5. This is explicitly acknowledged, not hidden, and is closed in a dedicated follow-up phase implementing Workload Identity Federation between GitLab and GCP, which is a substantial enough piece of configuration to warrant being built and verified on its own rather than rushed into this phase.

## Consequences
Every pipeline run through image scanning produces real, verifiable pass/fail results and real scan output, giving genuine evidence of supply-chain security practice. The gap between "pipeline builds and scans images" and "pipeline deploys those images" is documented here and will be closed before Phase 6 is considered fully complete, tracked as Phase 6b: GitLab-to-GCP Workload Identity Federation.
