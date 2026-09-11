#!/usr/bin/env bash
set -e
PROJECT_ID="velrite-tf-test"
ZONE="us-central1-a"
CLUSTER="atlas-dev"
REPO_DIR="$HOME/atlas"

echo "### 1. Confirm project + repo present ###"
gcloud config set project "$PROJECT_ID"
cd "$REPO_DIR"
git pull origin main --no-edit

echo "### 2. Terraform: apply infra ###"
cd "$REPO_DIR/terraform/environments/dev"
if [ ! -f terraform.tfvars ]; then
  echo "project_id = \"$PROJECT_ID\"" > terraform.tfvars
fi
terraform init
terraform plan -var="project_id=$PROJECT_ID" -out=/tmp/atlas-startup.tfplan
STRAY=$(terraform show /tmp/atlas-startup.tfplan | grep -c "project.*= \"yes\"" || true)
if [ "$STRAY" -ne 0 ]; then
  echo "FATAL: plan contains a stray project=\"yes\" value. Aborting."
  exit 1
fi
echo ""
echo ">>> REVIEW THE PLAN ABOVE."
read -p "Type 'apply' to proceed, anything else to abort: " CONFIRM
if [ "$CONFIRM" != "apply" ]; then
  echo "Aborted by user."
  exit 1
fi
terraform apply /tmp/atlas-startup.tfplan

echo "### 3. kubectl credentials + context check ###"
gcloud container clusters get-credentials "$CLUSTER" --zone "$ZONE" --project "$PROJECT_ID"
CTX=$(kubectl config current-context)
EXPECTED="gke_${PROJECT_ID}_${ZONE}_${CLUSTER}"
if [ "$CTX" != "$EXPECTED" ]; then
  echo "FATAL: wrong kubectl context ($CTX), expected $EXPECTED."
  exit 1
fi
echo "Context confirmed: $CTX"

echo "### 4. RBAC + Workload Identity KSA + Helm platform deploy ###"
kubectl create namespace atlas-platform --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f "$REPO_DIR/kubernetes/rbac/"
kubectl create serviceaccount atlas-workload-ksa -n atlas-platform --dry-run=client -o yaml | kubectl apply -f -
kubectl annotate serviceaccount atlas-workload-ksa -n atlas-platform iam.gke.io/gcp-service-account=atlas-workload@${PROJECT_ID}.iam.gserviceaccount.com --overwrite
if helm status atlas-platform -n atlas-platform >/dev/null 2>&1; then
  helm upgrade atlas-platform "$REPO_DIR/helm/atlas-platform/" --namespace atlas-platform
else
  helm install atlas-platform "$REPO_DIR/helm/atlas-platform/" --namespace atlas-platform --create-namespace
fi

echo "### 5. Check images exist, else trigger rebuild and stop ###"
IMG_COUNT=$(gcloud artifacts docker images list us-central1-docker.pkg.dev/${PROJECT_ID}/atlas-images/atlas-api --format="value(IMAGE)" 2>/dev/null | wc -l)
if [ "$IMG_COUNT" -eq 0 ]; then
  echo "No images found -- triggering pipeline rebuild via empty commit."
  cd "$REPO_DIR"
  git commit --allow-empty -m "chore: trigger image rebuild (empty Artifact Registry detected on startup)"
  git push origin main
  git push gitlab main 2>&1 || echo "WARNING: gitlab push failed -- check manually"
  echo ">>> Wait for GitLab pipeline to go green through gitops-update, then re-run: bash scripts/startup.sh"
  exit 0
fi
kubectl rollout status deployment/atlas-api -n atlas-platform --timeout=180s
kubectl rollout status deployment/atlas-scheduler -n atlas-platform --timeout=180s
kubectl rollout status deployment/atlas-worker -n atlas-platform --timeout=180s
kubectl rollout status deployment/redis -n atlas-platform --timeout=180s

echo "### 6. Argo CD (core mode) + AppProject + Application ###"
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/core-install.yaml || echo "NOTE: applicationsets CRD may fail -- harmless, plain Applications only here."
which argocd || { curl -sSL -o "$HOME/argocd" https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64; chmod +x "$HOME/argocd"; export PATH="$HOME:$PATH"; }
argocd login --core
kubectl apply -f "$REPO_DIR/gitops/default-appproject.yaml"
kubectl apply -f "$REPO_DIR/gitops/"
sleep 10
kubectl -n argocd get applications.argoproj.io atlas-platform -o jsonpath='{.status.sync.status}{"\n"}{.status.health.status}{"\n"}'

echo "### 7. Grafana + datasource-syncer ###"
kubectl create namespace grafana --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n grafana -f https://raw.githubusercontent.com/GoogleCloudPlatform/prometheus-engine/v0.17.2/examples/grafana.yaml
kubectl wait --for=condition=available --timeout=120s deployment/grafana -n grafana
pkill -f "port-forward svc/grafana" 2>/dev/null || true
kubectl -n grafana port-forward svc/grafana 3000:3000 > /tmp/pf.log 2>&1 &
sleep 5
gcloud iam service-accounts create gmp-ds-syncer-sa --display-name="GMP Datasource Syncer" --project="$PROJECT_ID" 2>&1 || echo "GSA already exists"
gcloud projects add-iam-policy-binding "$PROJECT_ID" --member="serviceAccount:gmp-ds-syncer-sa@${PROJECT_ID}.iam.gserviceaccount.com" --role="roles/monitoring.viewer" >/dev/null
gcloud projects add-iam-policy-binding "$PROJECT_ID" --member="serviceAccount:gmp-ds-syncer-sa@${PROJECT_ID}.iam.gserviceaccount.com" --role="roles/iam.serviceAccountTokenCreator" >/dev/null
kubectl create serviceaccount datasource-syncer-ksa -n grafana --dry-run=client -o yaml | kubectl apply -f -
gcloud iam service-accounts add-iam-policy-binding gmp-ds-syncer-sa@${PROJECT_ID}.iam.gserviceaccount.com --role roles/iam.workloadIdentityUser --member "serviceAccount:${PROJECT_ID}.svc.id.goog[grafana/datasource-syncer-ksa]" >/dev/null
kubectl annotate serviceaccount datasource-syncer-ksa -n grafana iam.gke.io/gcp-service-account=gmp-ds-syncer-sa@${PROJECT_ID}.iam.gserviceaccount.com --overwrite
if [ ! -f "$HOME/.grafana-syncer-token" ]; then
  SA_RESPONSE=$(curl -s -u admin:admin -X POST http://localhost:3000/api/serviceaccounts -H "Content-Type: application/json" -d '{"name":"gmp-datasource-syncer","role":"Admin"}')
  SA_ID=$(echo "$SA_RESPONSE" | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")
  TOKEN_RESPONSE=$(curl -s -u admin:admin -X POST "http://localhost:3000/api/serviceaccounts/$SA_ID/tokens" -H "Content-Type: application/json" -d '{"name":"syncer-token"}')
  echo "$TOKEN_RESPONSE" | python3 -c "import json,sys; print(json.load(sys.stdin)['key'])" > "$HOME/.grafana-syncer-token"
fi
if [ ! -f "$HOME/.grafana-datasource-uid" ]; then
  DS_RESPONSE=$(curl -s -u admin:admin -X POST http://localhost:3000/api/datasources -H "Content-Type: application/json" -d '{"name":"Managed Prometheus","type":"prometheus","url":"http://localhost:9090","access":"proxy"}')
  echo "$DS_RESPONSE" | python3 -c "import json,sys; print(json.load(sys.stdin)['datasource']['uid'])" > "$HOME/.grafana-datasource-uid"
fi
DS_UID=$(cat "$HOME/.grafana-datasource-uid")
kubectl create secret generic datasource-syncer-token -n grafana --from-literal=token="$(cat "$HOME/.grafana-syncer-token")" --dry-run=client -o yaml | kubectl apply -f -
cat > /tmp/datasource-syncer-cronjob.yaml << CRONEOF
apiVersion: batch/v1
kind: CronJob
metadata:
  name: datasource-syncer
  namespace: grafana
spec:
  schedule: "*/10 * * * *"
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: datasource-syncer-ksa
          restartPolicy: Never
          containers:
            - name: datasource-syncer
              image: gke.gcr.io/prometheus-engine/datasource-syncer:v0.17.2-gke.2
              args:
                - --grafana-api-endpoint=http://grafana.grafana.svc.cluster.local:3000
                - --datasource-uids=${DS_UID}
                - --project-id=${PROJECT_ID}
                - --grafana-api-token=\$(GRAFANA_API_TOKEN)
              env:
                - name: GRAFANA_API_TOKEN
                  valueFrom:
                    secretKeyRef:
                      name: datasource-syncer-token
                      key: token
CRONEOF
kubectl apply -f /tmp/datasource-syncer-cronjob.yaml
cp /tmp/datasource-syncer-cronjob.yaml "$HOME/datasource-syncer-cronjob.yaml"
kubectl delete job -n grafana -l job-name --ignore-not-found 2>/dev/null || true
kubectl create job --from=cronjob/datasource-syncer "datasource-syncer-manual-$(date +%s)" -n grafana
sleep 15
kubectl logs -n grafana -l job-name --tail=10 | grep "Updated Grafana" || echo "WARNING: syncer confirmation not found -- check manually"
python3 -c "
with open('$REPO_DIR/observability/dashboards/atlas-platform-overview.json') as f:
    content = f.read()
import re
content = re.sub(r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}', '$DS_UID', content)
with open('/tmp/atlas-dashboard-restored.json', 'w') as f:
    f.write(content)
"
curl -s -u admin:admin -X POST http://localhost:3000/api/dashboards/db -H "Content-Type: application/json" -d @/tmp/atlas-dashboard-restored.json

echo "### 8. OTel Collector ###"
kubectl create namespace otel --dry-run=client -o yaml | kubectl apply -f -
gcloud iam service-accounts create atlas-otel-collector --display-name="Atlas OTel Collector" --project="$PROJECT_ID" 2>&1 || echo "GSA already exists"
gcloud projects add-iam-policy-binding "$PROJECT_ID" --member="serviceAccount:atlas-otel-collector@${PROJECT_ID}.iam.gserviceaccount.com" --role="roles/cloudtrace.agent" >/dev/null
kubectl create serviceaccount otel-collector-ksa -n otel --dry-run=client -o yaml | kubectl apply -f -
gcloud iam service-accounts add-iam-policy-binding atlas-otel-collector@${PROJECT_ID}.iam.gserviceaccount.com --role roles/iam.workloadIdentityUser --member "serviceAccount:${PROJECT_ID}.svc.id.goog[otel/otel-collector-ksa]" >/dev/null
kubectl annotate serviceaccount otel-collector-ksa -n otel iam.gke.io/gcp-service-account=atlas-otel-collector@${PROJECT_ID}.iam.gserviceaccount.com --overwrite
cat > /tmp/otel-collector-config.yaml << 'OTELCFGEOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: otel-collector-config
  namespace: otel
data:
  config.yaml: |
    receivers:
      otlp:
        protocols:
          grpc:
            endpoint: 0.0.0.0:4317
          http:
            endpoint: 0.0.0.0:4318
    processors:
      batch:
        timeout: 5s
        send_batch_size: 200
      memory_limiter:
        check_interval: 1s
        limit_mib: 400
        spike_limit_mib: 100
      resourcedetection:
        detectors: [gcp]
        timeout: 5s
    exporters:
      googlecloud:
        project: PROJECT_ID_PLACEHOLDER
      debug:
        verbosity: basic
    service:
      pipelines:
        traces:
          receivers: [otlp]
          processors: [memory_limiter, resourcedetection, batch]
          exporters: [googlecloud, debug]
OTELCFGEOF
sed -i "s/PROJECT_ID_PLACEHOLDER/${PROJECT_ID}/" /tmp/otel-collector-config.yaml
kubectl apply -f /tmp/otel-collector-config.yaml
cat > /tmp/otel-collector-deploy.yaml << 'OTELDEPEOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: otel-collector
  namespace: otel
spec:
  replicas: 1
  selector:
    matchLabels:
      app: otel-collector
  template:
    metadata:
      labels:
        app: otel-collector
    spec:
      serviceAccountName: otel-collector-ksa
      containers:
        - name: otel-collector
          image: otel/opentelemetry-collector-contrib:0.111.0
          args: ["--config=/etc/otel/config.yaml"]
          ports:
            - containerPort: 4317
            - containerPort: 4318
          resources:
            requests: {cpu: 100m, memory: 200Mi}
            limits: {cpu: 300m, memory: 400Mi}
          volumeMounts:
            - name: config
              mountPath: /etc/otel
      volumes:
        - name: config
          configMap:
            name: otel-collector-config
---
apiVersion: v1
kind: Service
metadata:
  name: otel-collector
  namespace: otel
spec:
  selector:
    app: otel-collector
  ports:
    - name: grpc
      port: 4317
      targetPort: 4317
    - name: http
      port: 4318
      targetPort: 4318
OTELDEPEOF
kubectl apply -f /tmp/otel-collector-deploy.yaml
kubectl rollout status deployment/otel-collector -n otel --timeout=90s

echo "### DONE. Full environment restored. ###"
kubectl get pods -n atlas-platform
kubectl get pods -n argocd
kubectl get pods -n grafana
kubectl get pods -n otel

# --- Argo Rollouts (Phase 11) ---
# Plain "kubectl apply -f" on the install manifest fails silently on the large
# embedded CRDs (rollouts.argoproj.io, analysisruns.argoproj.io) with
# "annotations: Too long" while the controller Deployment/RBAC apply fine --
# a misleadingly "healthy-looking" but actually broken install.
# --server-side --force-conflicts avoids the client-side annotation-size limit.
kubectl create namespace argo-rollouts --dry-run=client -o yaml | kubectl apply -f -
kubectl apply --server-side --force-conflicts -f https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml
kubectl wait --for=condition=available --timeout=120s deployment/argo-rollouts -n argo-rollouts

# Workload Identity binding for atlas-rollouts-metrics GSA.
# Currently unused (final design uses progressDeadlineAbort, not a Prometheus
# AnalysisTemplate, since Argo Rollouts' Prometheus provider doesn't support
# GCP Workload Identity) -- captured here so full recovery stays automated.
gcloud iam service-accounts create atlas-rollouts-metrics \
  --project=velrite-tf-test \
  --display-name="Argo Rollouts metrics reader (reserved, unused)" \
  2>/dev/null || echo "atlas-rollouts-metrics GSA already exists, continuing"

gcloud projects add-iam-policy-binding velrite-tf-test \
  --member="serviceAccount:atlas-rollouts-metrics@velrite-tf-test.iam.gserviceaccount.com" \
  --role="roles/monitoring.viewer" \
  --condition=None

gcloud iam service-accounts add-iam-policy-binding \
  atlas-rollouts-metrics@velrite-tf-test.iam.gserviceaccount.com \
  --project=velrite-tf-test \
  --role="roles/iam.workloadIdentityUser" \
  --member="serviceAccount:velrite-tf-test.svc.id.goog[argo-rollouts/argo-rollouts]"

kubectl annotate serviceaccount argo-rollouts -n argo-rollouts \
  iam.gke.io/gcp-service-account=atlas-rollouts-metrics@velrite-tf-test.iam.gserviceaccount.com \
  --overwrite
# --- end Argo Rollouts (Phase 11) ---
