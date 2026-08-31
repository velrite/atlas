#!/bin/sh
set -e
git remote add github "https://x-access-token:${GITHUB_PUSH_TOKEN}@github.com/velrite/atlas.git"
git push github main
