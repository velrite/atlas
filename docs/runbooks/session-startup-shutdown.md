# Runbook: Session Startup and Shutdown

This project's infrastructure is destroyed between work sessions to avoid
continuous billing, given multi-day gaps between sessions are normal for
this project. This runbook is the authoritative sequence for both
directions. Follow it in order; do not skip steps based on memory of a
prior session, since Cloud Shell resets between sessions and tools/context
do not persist.

## Shutdown (end of a work session)

1. Confirm what is currently running before destroying anything:
   kubectl get pods -A
   gcloud container clusters list --project=velrite-tf-test

2. Run the teardown script to generate a destroy plan:
   bash /home/velrite_tech/atlas/scripts-teardown.sh

3. Review the plan output carefully. It should list the atlas-dev cluster,
   its node pool, the atlas-vpc network and subnet, the atlas-images
   Artifact Registry repository, and related IAM bindings. It should NOT
   list anything belonging to other projects (Forge, Project 7) sharing
   this GCP account.

4. If the plan looks correct, apply it:
   cd /home/velrite_tech/atlas/terraform/environments/dev
   terraform apply destroy.tfplan

5. Verify actual GCP state independently of Terraform, since Terraform
   state alone is not sufficient proof of teardown:
   gcloud container clusters list --project=velrite-tf-test
   gcloud compute networks list --project=velrite-tf-test
   gcloud artifacts repositories list --project=velrite-tf-test --location=us-central1

   All three should show no Atlas resources remaining.

## Startup (beginning of a work session)

1. Confirm the active GCP project:
   gcloud config set project velrite-tf-test
   gcloud config get-value project

2. Reinstall Terraform if this is a fresh Cloud Shell VM (check first):
   terraform version
   (if not found, reinstall per the HashiCorp apt method used in Phase 1)

3. Run the startup script to generate a creation plan:
   bash /home/velrite_tech/atlas/scripts-startup.sh

4. Review the plan output. It should show the same resources listed above
   being created, not changed or destroyed.

5. If the plan looks correct, apply it:
   cd /home/velrite_tech/atlas/terraform/environments/dev
   terraform apply startup.tfplan

   Cluster creation takes several minutes. Node pool creation with
   e2-standard-4 machines and machine type changes may also take a few
   minutes even as an in-place update.

6. Fetch cluster credentials:
   gcloud container clusters get-credentials atlas-dev --zone us-central1-a --project velrite-tf-test
   kubectl get nodes

7. Recreate the platform namespace, service account, and RBAC (these are
   not Terraform-managed and do not come back automatically):
   kubectl create namespace atlas-platform
   kubectl create serviceaccount atlas-workload-ksa --namespace atlas-platform
   kubectl annotate serviceaccount atlas-workload-ksa --namespace atlas-platform \
     iam.gke.io/gcp-service-account=atlas-workload@velrite-tf-test.iam.gserviceaccount.com
   kubectl apply -f /home/velrite_tech/atlas/kubernetes/rbac/atlas-platform-role.yaml
   kubectl apply -f /home/velrite_tech/atlas/kubernetes/rbac/atlas-platform-rolebinding.yaml

8. Reinstall the workload platform via Helm:
   helm install atlas-platform /home/velrite_tech/atlas/helm/atlas-platform --namespace atlas-platform

9. Reinstall Argo CD (core mode) if this session's work involves GitOps:
   kubectl create namespace argocd
   kubectl apply -n argocd --server-side --force-conflicts \
     -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/core-install.yaml

10. Verify everything is healthy before continuing with new work:
    kubectl get pods -n atlas-platform
    kubectl get pods -n argocd

## Node pool changes (machine type, disk size) require a PDB workaround

If any future change modifies the node pool's machine_type, disk_size_gb,
or similar in-place-updatable node_config fields, GKE performs this as a
rolling one-node-at-a-time drain and replace, even though Terraform reports
it as an in-place update rather than destroy/recreate. This drain will
stall indefinitely, with no error, if a Deployment with only one replica
also has a PodDisruptionBudget with minAvailable set to 1, since evicting
that pod would violate the PDB (0 allowed disruptions). This happened
during the Phase 7 node upgrade from e2-medium to e2-standard-4 and cost
approximately two hours of stalled operation before being diagnosed.

Before applying any node pool machine_type or disk_size_gb change:

1. Scale any single-replica Deployment that has a PodDisruptionBudget to
   zero replicas first:
   kubectl scale deployment atlas-api -n atlas-platform --replicas=0
   kubectl scale deployment atlas-worker -n atlas-platform --replicas=0

2. Apply the Terraform change as normal.

3. Monitor the operation directly rather than relying on
   `gcloud container operations wait`, which can time out client-side
   while the operation continues running server-side regardless:
   gcloud container operations describe <operation-id>      --project=velrite-tf-test --zone=us-central1-a      --format="yaml(status,detail,progress)"

   A stalled drain shows 0% node completion with a NODE_PDB_DELAY_SECONDS
   metric that climbs over time. status: DONE with NODES_COMPLETE equal to
   NODES_TOTAL confirms genuine completion.

4. Once the operation reports status: DONE, scale the affected Deployments
   back to their normal replica count:
   kubectl scale deployment atlas-api -n atlas-platform --replicas=1
   kubectl scale deployment atlas-worker -n atlas-platform --replicas=1

5. Verify pod health and the new node spec directly, not just that the
   apply command exited successfully:
   kubectl get pods -n atlas-platform
   gcloud container node-pools describe atlas-dev-pool --cluster=atlas-dev      --zone=us-central1-a --project=velrite-tf-test      --format="value(config.machineType,config.diskSizeGb)"
   kubectl describe nodes | grep -A 3 "Allocatable:"

A terraform apply or gcloud command that appears to hang or disconnects
client-side during a node pool mutation has NOT necessarily failed or lost
its work. GKE operations run server-side once submitted and are unaffected
by the client disconnecting. Always check real operation status via
gcloud container operations list/describe before assuming a stuck or
disconnected command needs to be re-run from scratch.

## Current node specification

As of the Phase 7 upgrade, the atlas-dev-pool node pool runs 2x
e2-standard-4 machines (3920m allocatable CPU per node) with a 30GB
pd-balanced boot disk each, up from the original e2-medium (940m
allocatable) with a 100GB default disk. This was changed specifically to
create real headroom for Argo CD and later observability tooling, after
confirming via `gcloud compute regions describe us-central1` that regional
CPU quota had substantial headroom (2 of 32 used) while regional
SSD_TOTAL_GB quota was the actual binding constraint (200 of 250GB
consumed, almost entirely by this project's own nodes at the old 100GB
disk size). Any future node pool sizing change should re-check both
quotas, not assume CPU is always the limiting factor.

## Known limitations of this runbook

This runbook is specific to the Atlas project's resource names and paths.
Reusing this pattern for a different project requires substituting
project-specific names (cluster name, namespace, service account names,
Helm chart path) rather than running these commands unmodified.

This runbook is specific to the Atlas project's resource names and paths.
Reusing this pattern for a different project requires substituting project-
specific names (cluster name, namespace, service account names, Helm chart
path) rather than running these commands unmodified.
