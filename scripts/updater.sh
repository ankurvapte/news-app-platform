#!/usr/bin/env sh
# Pull-based CD (GitOps): one check of origin/main, run by launchd every
# 2 minutes in the DEPLOY clone (scripts/install-updater.sh sets it up).
#   origin/main = deployed commit     → nothing to do (no log line)
#   origin/main = last failed commit  → skip; it already failed and was rolled back
#   otherwise                         → scripts/deploy.sh origin/main
# Quiet unless something happens. Logs: .deploy/deploy.log (JSON lines).
set -eu
cd "$(dirname "$0")/.."
mkdir -p .deploy

# Docker Desktop not running (e.g. just after login): try again next time.
docker info >/dev/null 2>&1 || exit 0
# Offline: try again next time.
git fetch -q origin main 2>/dev/null || exit 0

target=$(git rev-parse origin/main)
[ "$target" = "$(cat .deploy/deployed 2>/dev/null)" ] && exit 0
[ "$target" = "$(cat .deploy/failed 2>/dev/null)" ] && exit 0

exec ./scripts/deploy.sh "$target"
