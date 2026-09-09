#!/usr/bin/env bash
set -e
PROJECT_ID="velrite-tf-test"
REPO_DIR="$HOME/atlas"
echo "### CURRENT STATE BEFORE TEARDOWN ###"
kubectl get pods -A 2>/dev/null | grep -v "kube-system\|gmp-\|gke-" || echo "(cluster may already be unreachable)"
gcloud container clusters list --project="$PROJECT_ID"
cd "$REPO_DIR/terraform/environments/dev"
terraform init
terraform plan -destroy -var="project_id=$PROJECT_ID" -out=destroy.tfplan
echo ""
echo "### REVIEW THE PLAN ABOVE CAREFULLY ###"
echo "It should list ONLY: atlas-dev cluster, atlas-dev-pool node pool, atlas-vpc network+subnet, atlas-images Artifact Registry repo, and related IAM bindings."
echo "It must NOT list anything belonging to Forge or Project7."
echo "Argo CD, Grafana, datasource-syncer, and OTel Collector will be destroyed with the cluster -- expected, fully rebuilt by startup.sh."
echo ""
echo "If the plan looks correct, run this ONE line yourself to actually destroy:"
echo "    cd $REPO_DIR/terraform/environments/dev && terraform apply destroy.tfplan"
echo ""
echo "After it completes, verify with:"
echo "    gcloud container clusters list --project=$PROJECT_ID"
echo "    gcloud compute networks list --project=$PROJECT_ID"
echo "    gcloud artifacts repositories list --project=$PROJECT_ID --location=us-central1"
