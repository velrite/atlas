# ADR-002: Remote GCS State + Service Account Impersonation (No Static Keys)

## Status
Accepted

## Context
Terraform needs a durable place to store state that survives Cloud Shell VM resets, and a well-scoped identity to act as, separate from the developer personal GCP user account.

## Problem
Using local state risks state loss on Cloud Shell reset, which can cause Terraform to lose track of real infrastructure and attempt destructive recreation. Using the personal user account directly for all Terraform operations conflates human and automation permissions. The initial plan to use a downloadable JSON service account key was blocked by an organization policy constraint, constraints/iam.disableServiceAccountKeyCreation, which prevents key creation on service accounts in this project.

## Decision
Terraform state is stored remotely in a dedicated GCS bucket, velrite-tf-test-atlas-tfstate, with object versioning enabled, using GCS native optimistic-locking state locking. A dedicated service account, atlas-terraform@velrite-tf-test.iam.gserviceaccount.com, is used for all Terraform operations via service account impersonation rather than a static downloadable key. The Cloud Shell user, already authenticated as an Owner on the project, is granted roles/iam.serviceAccountTokenCreator on the Terraform service account, allowing Terraform to request short-lived tokens on demand. No key file is ever created or stored on disk.

## Alternatives Considered
Local state was rejected because it does not survive Cloud Shell session resets, a documented recurring issue in this environment. A static downloadable JSON key was the original plan but is blocked by organization policy, and is inferior regardless of policy since it is a long-lived credential with no built-in expiry that must be manually rotated and protected at rest. Using personal user credentials directly for all Terraform operations was rejected on least-privilege and auditability grounds.

## Trade-offs
Impersonation requires the acting user to already hold roles/iam.serviceAccountTokenCreator on the target service account, meaning Terraform operations still depend on an authenticated human session in this Cloud Shell based workflow. This is acceptable for solo development. If this pipeline later runs from GitLab CI/CD runners rather than Cloud Shell, Workload Identity Federation should be used instead so the runner authenticates without any long-lived credential at all, human or machine.

## Consequences
Every terraform command must be run from a session authenticated as a user with impersonation rights on the Terraform service account. No key file exists anywhere in this project, removing an entire class of credential-leak risk. This is a strictly better outcome than the original key-based plan and was arrived at only because organization policy forced the reconsideration.
