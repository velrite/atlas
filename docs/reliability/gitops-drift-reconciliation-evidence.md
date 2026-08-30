# GitOps Drift Detection and Reconciliation: Measured Evidence

## Test Description
With the atlas-platform Application under Argo CD management (syncPolicy
automated, prune true, selfHeal true), the atlas-worker Deployment, whose
Helm-declared replica count is 1, was manually scaled to 3 replicas
directly via kubectl, bypassing Git, Helm, and Argo CD entirely. This
simulates an operator or a compromised process making an unauthorized
direct change to the cluster.

## Timeline
- T+0s: kubectl scale deployment atlas-worker --replicas=3 executed
- T+3s: kubectl get pods already showed two of the three replicas in
  Terminating state, with only the original pod remaining Running. The
  Deployment's spec.replicas field, queried at this same moment, already
  read back as 1, not 3, indicating Argo CD's reconciliation had already
  reverted the Deployment spec before this check ran.
- T+18s (15 second wait plus the initial 3): pods fully reverted to a
  single Running replica. argocd app get confirmed Sync Status Synced and
  Health Status Healthy throughout, with no OutOfSync state ever observed
  in this test, since reconciliation completed faster than the manual
  check could observe an intermediate drifted state.

## Interpretation
Argo CD's self-heal reconciliation loop reacted to the unauthorized change
in under three seconds, reverting both the Deployment's declared replica
count and the resulting pod count without any manual intervention. The
speed of this reaction means that, for this specific type of drift (a
direct spec field change on a resource Argo CD already manages), the
window during which drift is actually observable in the live cluster is
extremely short, on the order of single-digit seconds, not the more
leisurely reconciliation intervals sometimes associated with GitOps
tooling.

## What This Does and Does Not Demonstrate
This confirms self-heal correctly reverts a direct, in-place change to a
resource's spec that Argo CD already tracks. It does not test drift
introduced by deleting a resource entirely, creating an unmanaged resource
in the same namespace, or modifying a resource's data outside of fields
Argo CD diffs by default. Those are legitimate further test cases,
tracked as follow-up chaos engineering scenarios rather than assumed
covered by this one result.

## Prerequisite Fix Required for This Test
Argo CD core installation mode does not create a default AppProject
automatically, unlike the full installation. Creating the Application
before the default AppProject exists produces an InvalidSpecError with a
Sync Status of Unknown. The default AppProject must be created explicitly
as its own manifest before any Application referencing project: default
can reconcile. This is documented here because it is easy to miss when
following documentation written against the full installation mode.
