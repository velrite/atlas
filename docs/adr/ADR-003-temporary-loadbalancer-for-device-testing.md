# ADR-003: Temporary LoadBalancer Exposure for Real-Device Testing

## Status
Accepted (temporary, time-boxed)

## Context
Atlas Operator's Phase 9 goal was to verify a real Android device could
reach the real `operations-api` backend. Development happens in GCP
Cloud Shell, which is a remote VM — not the developer's physical
machine — so a phone connected to a laptop cannot reach Cloud Shell's
`kubectl port-forward` (different machines; USB/adb does not bridge
them).

## Problem
How does a real, physical Android phone reach a backend that otherwise
has zero external exposure by design (per ADR-001 / system-overview)?

## Options Considered

### Option A — Cloud Shell Web Preview
Uncertain whether Web Preview's authenticated-browser-session model
would even work with a non-browser Flutter HTTP client. Flagged as
unverified and not attempted.

### Option B — Sideload an APK, point it at a temporary public
`LoadBalancer` Service in front of `operations-api`
Chosen. Concrete, uses infrastructure already understood from this
project (Services, NetworkPolicy), and gives a real external IP with
no auth-flow guesswork.

## Decision
Option B: a `LoadBalancer` Service (`operations-api-external`) was
created, exposing `operations-api`'s zero-auth `/health` and `/ready`
endpoints to the public internet for the duration of the test.

## Consequences
### Positive
Real end-to-end verification: a physical device reaching a real pod
over the internet.

### Negative — explicitly accepted, not hidden
`operations-api` has **no authentication**. For as long as the
`LoadBalancer` Service exists, its `/health`/`/ready` endpoints are
reachable by anyone on the internet, not just the test phone. This is
acceptable only because the test window was short and the endpoints
themselves reveal no sensitive data — but this is not a pattern to
leave running, and the Service must be deleted immediately after
testing:

    kubectl delete service operations-api-external -n default

Android's cleartext-HTTP block also had to be relaxed for this one test
build (`android:usesCleartextTraffic="true"`), which must not ship in
any build meant for real users.

## Revisit conditions
Superseded once a real Ingress + TLS + auth story exists for Atlas
Operator's backend (tracked as future work, not yet implemented).

## Addendum (2026-09-20): what actually happened
- The first LoadBalancer Service was found already absent when
  re-checked (cause not investigated).
- A new `operations-api-external` Service was created for the test and
  answered `/health` and `/ready` from Cloud Shell before the phone test.
- After device verification the Service was deleted and the cleartext
  flag was removed from the main manifest. The before/after service
  lists are evidence item 19.
- While the Service was public (about 34 minutes at deletion), the pod
  log tail showed automated internet scanners probing paths such as
  `/vendor/phpunit/.../eval-stdin.php`, a ThinkPHP `invokefunction`
  URL, and `/containers/json`. Every one returned 404, because the
  service only serves `/health` and `/ready`. Only the last lines of the
  log were reviewed, so this is not a full audit. It does show that a
  zero-auth public endpoint gets probed within minutes, which is why
  the teardown was done straight after the test.

