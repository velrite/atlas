# INCIDENT-004: pkg_resources removed from setuptools 82+

Summary: atlas-api CrashLoopBackOff after adding OTel tracing. opentelemetry-instrumentation-flask imports pkg_resources at runtime; setuptools 82.0.0 (Feb 2026) removed it entirely.

First fix attempt (setuptools>=69.0.0, no upper bound) failed since pip installed 84.0.0, still missing pkg_resources. Confirmed via local Docker repro of the exact Dockerfile install. Real fix: setuptools>=69.0.0,<82, re-verified locally before pushing.

Secondary issues hit while resolving: GitLab/GitHub remotes diverged after a Cloud Shell terminal drop skipped a gitlab push (always check git ls-remote on both after pushing); argocd app sync --core repeatedly failed with configmap argocd-cm not found, worked around via kubectl annotate argocd.argoproj.io/refresh=hard.

Lesson: an unbounded >= pin on a transitive runtime dependency can silently drift to a version that removed the thing being depended on. Verify the actual installed version inside the real container, not just that a requirements line exists.
