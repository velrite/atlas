# ADR-004: Workload Identity Over Static Keys for Platform Workloads

## Status
Accepted

## Context
Workloads running in the atlas-platform namespace, starting with the workload platform components built in Phase 4, need to call GCP APIs such as Artifact Registry. A decision was needed on how those pods authenticate to GCP.

## Problem
The traditional approach of mounting a downloadable service account JSON key as a Kubernetes Secret creates a long-lived credential inside the cluster with no automatic expiry, which is a standing security liability if the pod or secret is ever compromised. This project also cannot use downloadable keys at all, since organization policy constraints/iam.disableServiceAccountKeyCreation blocks their creation, as discovered in ADR-002.

## Decision
GKE Workload Identity is used to bind a dedicated Google Service Account, atlas-workload@velrite-tf-test.iam.gserviceaccount.com, to a Kubernetes Service Account, atlas-workload-ksa, in the atlas-platform namespace. Pods that run as this KSA automatically receive short-lived GCP credentials via the GKE metadata server, with no key file ever created or stored. The GSA is granted only roles/artifactregistry.reader at the project level, matching what workload platform components actually need in this phase. Kubernetes RBAC is scoped to a namespace-local Role and RoleBinding rather than a ClusterRole, verified directly with kubectl auth can-i to confirm the KSA can create deployments within its own namespace but cannot act on cluster-scoped resources such as namespaces.

## Alternatives Considered
A downloadable JSON key was not viable due to organization policy, and would have been rejected on security grounds regardless, consistent with the reasoning in ADR-002. Granting the workload GSA broad project-level roles such as Editor was rejected as a violation of least privilege; the GSA is scoped to exactly the one role currently needed and will gain additional roles explicitly, phase by phase, as new capabilities are required. A ClusterRole was considered simpler to set up than a namespace-scoped Role, but was rejected because it would grant the workload platform permissions across every namespace in the cluster, including future namespaces unrelated to it.

## Trade-offs
Namespace-scoped RBAC and incremental GSA role grants mean more Terraform and kubectl changes over time as new capabilities are needed, rather than granting broad access once. This friction is intentional and mirrors the same trade-off already accepted for the Terraform service account in ADR-002.

## Consequences
All workload platform pods built from Phase 4 onward should run as the atlas-workload-ksa service account to inherit GCP API access via Workload Identity. Any new GCP API access needed by the workload platform requires an explicit new IAM role grant to atlas-workload@velrite-tf-test.iam.gserviceaccount.com, documented at the point it is added, not granted preemptively.
