#!/bin/sh
set -e

# Sync GitLab's current main to GitHub. GitHub can move independently of
# GitLab (manual pushes, other tooling), so a blind "git push" here races
# and loses -- this exact failure mode caused every gitops-update job to
# fail during Phase 11 (see INCIDENT-005). Fix: fetch + rebase onto
# GitHub's real current tip immediately before pushing, retry once if
# GitHub moved again during that window.

git remote remove github 2>/dev/null || true
git remote add github "https://x-access-token:${GITHUB_PUSH_TOKEN}@github.com/velrite/atlas.git"

attempt_sync() {
  git fetch github main
  git rebase github/main main
  git push github main
}

if ! attempt_sync; then
  echo "First sync attempt failed (github moved during rebase/push) -- retrying once."
  git rebase --abort 2>/dev/null || true
  sleep 5
  attempt_sync
fi
