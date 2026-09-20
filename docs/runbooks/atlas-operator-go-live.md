# Atlas Operator: go live from a torn-down state

Last verified end to end on 2026-09-20 with the cluster already running.
The from-scratch path (Step 1) is NOT VERIFIED: the `startup.sh` fixes were
checked for syntax and placement only. Expect to debug that step.

The only live signal in the app is the connection banner (Operations API
`/health` and `/ready`). Every other screen shows offline fixture data.

## Prerequisites
- Cloud Shell with the project set: `gcloud config set project velrite-tf-test`
- Repo at `~/atlas`
- For CI, start the runner VM: `gcloud compute instances start atlas-ci-runner --zone=us-central1-a`

## Step 1: rebuild the platform (plan, then confirm)

    cd ~/atlas && ./scripts/startup.sh
    kubectl get nodes
    kubectl get pods -n argo-rollouts
    kubectl get rollout atlas-api -n atlas-platform

The Argo Rollouts controller must be in `argo-rollouts`, not `default`.
The Rollout should reach Phase: Healthy.

## Step 2: images
If the registry `atlas-images` was destroyed, pods show ImagePullBackOff.
Push to `main` and let CI build them (runner `atlas-gce-runner` must be Online),
or build by hand. The build context is `workloads/`, not the service folder:

    docker build -f workloads/<service>/Dockerfile -t <tag> workloads/

## Step 3: deploy the Operations API (CI does not build it)

    cd ~/atlas/operations-api
    SHA=$(git rev-parse --short=8 HEAD)
    IMG=us-central1-docker.pkg.dev/velrite-tf-test/atlas-images/operations-api:${SHA}
    gcloud auth configure-docker us-central1-docker.pkg.dev
    docker build -t "$IMG" .
    docker push "$IMG"
    sed "s/COMMIT_SHA/${SHA}/" k8s/deployment.yaml > /tmp/operations-api-deployment.yaml
    kubectl apply -f /tmp/operations-api-deployment.yaml
    kubectl apply -f k8s/networkpolicy.yaml
    kubectl rollout status deployment/operations-api -n default --timeout=90s

If the push dies mid-transfer, run `docker push` again. No rebuild is needed.

## Step 4: temporary public door (ADR-003). Zero auth. Delete it right after testing.

    kubectl expose deployment operations-api --name=operations-api-external --type=LoadBalancer --port=80 --target-port=8080 -n default
    kubectl label svc operations-api-external purpose=temporary-device-test -n default
    OPS_IP=$(kubectl get svc operations-api-external -n default -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
    echo "IP: $OPS_IP"
    curl -s -m 5 -o /dev/null -w "%{http_code}\n" http://$OPS_IP/health
    curl -s -m 5 -o /dev/null -w "%{http_code}\n" http://$OPS_IP/ready

Both should print 200. If the IP is empty or you get 000, wait a minute and repeat the last four lines.

## Step 5: build the APK
The Android SDK lives under `/opt`, which is ephemeral. If it is gone, redo the
relocation from INCIDENT-008. The cleartext flag was removed from the manifest on
2026-09-20, and a plain-HTTP test build needs it back. Add it for this test build only:

    export ANDROID_HOME=/opt/android-sdk GRADLE_USER_HOME=/opt/gradle-home PUB_CACHE=/opt/pub-cache
    cd ~/atlas/operator
    sed -i 's|android:icon="@mipmap/ic_launcher">|android:icon="@mipmap/ic_launcher" android:usesCleartextTraffic="true">|' android/app/src/main/AndroidManifest.xml
    grep -n usesCleartext android/app/src/main/AndroidManifest.xml
    flutter build apk --release --dart-define=OPS_API_URL=http://$OPS_IP

Download `build/app/outputs/flutter-apk/app-release.apk` from the Cloud Shell menu.
Never commit the IP or the cleartext flag.

## Step 6: prove it on the phone
Tap the badge until it reads INTEGRATION, then tap Check. Expect Healthy with a fresh timestamp.
Then run `kubectl scale deployment operations-api -n default --replicas=0` and tap Check.
Expect Failed. Run `kubectl scale deployment operations-api -n default --replicas=1`,
wait for the pod, and tap Check again. Expect Healthy.

## Step 7: close it up

    kubectl delete service operations-api-external -n default
    cd ~/atlas/operator && git checkout -- android/app/src/main/AndroidManifest.xml

Then tear down cloud resources with `scripts/teardown.sh` (plan-only by design) and stop the
runner VM: `gcloud compute instances stop atlas-ci-runner --zone=us-central1-a`.

## Known limits
No authentication anywhere. The Operations API serves only `/health` and `/ready`, so
component health, jobs, deployments and diagnostics are fixtures.
See `docs/engineering/technical-debt.md`.
