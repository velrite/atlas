# INCIDENT-002: First GKE Deployment - Image Pull Authorization and Regional Disk Quota

## Severity
Low to Medium (development environment; caused deployment delay, not data loss or security exposure)

## Summary
The first deployment of the Atlas workload platform to the real atlas-dev GKE cluster failed initially for two independent reasons: container images could not be pulled from Artifact Registry, and a subsequent attempt to add cluster capacity failed due to a regional SSD quota limit shared across all projects in this GCP account.

## Detection
Detected immediately via kubectl pod status (ErrImagePull, then ImagePullBackOff) and later via a failed terraform apply reporting a 403 quota error from the GKE API.

## Root Cause 1: Image Pull Authorization
GKE nodes authenticate to Artifact Registry using the node pool's own service account (in this case, the Compute Engine default service account), not the Workload Identity-bound service account used by application pods. The node service account had never been granted artifactregistry.reader, since only the pod-level Workload Identity service account (atlas-workload) had been granted that role in Phase 3. Docker pushes from Cloud Shell succeeded because they used the developer's own authenticated user credentials, which have no bearing on what the cluster's nodes are authorized to do.

## Root Cause 2: Regional SSD Quota
After fixing the image pull issue, the atlas-worker pod remained unschedulable due to insufficient CPU headroom on the existing two-node pool, since GKE system daemonsets (kube-dns, fluentbit, gke-metadata-server, and others) consume the majority of each e2-medium node's allocatable CPU before any application workload is scheduled. An attempt to add a third node to restore real headroom failed with a regional quota error: SSD_TOTAL_GB quota of 250GB was already mostly consumed across this GCP account's projects, leaving insufficient quota for a third node's boot disk.

## Contributing Factors
Node pool service account permissions and pod-level Workload Identity permissions are easy to conflate, since both ultimately relate to "the workload platform's GCP access," but they are enforced at different layers (kubelet image pull versus in-pod API calls) and must be granted separately. Regional disk quota is shared across all projects under one GCP billing account's region, meaning a quota constraint was hit not because of anything wrong with this project's design, but because of cumulative usage across Forge, Project 7, and Atlas within the same account.

## Remediation
Granted roles/artifactregistry.reader to the node pool's Compute Engine default service account, resolving image pull authorization. Reverted the attempted node count increase from 3 back to 2, since it could not be provisioned under current quota, and instead reduced the worker Deployment's CPU request from 200m to 50m and memory request from 128Mi to 96Mi, which allowed the existing two-node pool to schedule all four platform components (Redis, API, scheduler, worker) within real allocatable capacity.

## Verification
All four Deployments confirmed Running with 1/1 readiness. A real job was submitted to the live cluster via port-forward to the atlas-api Service, and confirmed succeeded with a measured scheduling latency of 0.006 seconds and total duration of 2.01 seconds, matching the simulated 2-second workload almost exactly. Scheduler and worker logs independently confirmed the same job ID and timing.

## Lessons Learned
Node-level and pod-level GCP permissions must both be explicitly granted and are easy to under-provision by only considering one of them. Resource requests should be sized against measured allocatable capacity, not nominal machine specs, since GKE system overhead can consume the majority of a small node's capacity. Regional quotas are an account-wide constraint that can surface unexpectedly when multiple projects share a billing account and region, and should be checked before assuming horizontal scaling (adding nodes) is always the available fix; vertical adjustment of workload resource requests is a legitimate alternative when quota is constrained.
