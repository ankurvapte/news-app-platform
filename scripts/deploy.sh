#!/usr/bin/env sh
# Deploys one commit of this repo, then checks it, and rolls back if it fails.
# Runs in the DEPLOY clone (see scripts/install-updater.sh), normally started by
# scripts/updater.sh; can also be run by hand there:
#   ./scripts/deploy.sh                 # deploy origin/main
#   ./scripts/deploy.sh <commit>        # deploy (or go back to) a specific commit
#
#   1. remember the deployed commit            (.deploy/deployed)
#   2. git checkout <commit>                   (its docker-compose.yml = pinned image SHAs)
#   3. docker compose pull && up -d            (only changed containers are recreated)
#   4. https://localhost/health/<svc>/ready = 200 for every service, within HEALTH_TIMEOUT
#   5. ok   → .deploy/deployed = <commit>
#      fail → check out the previous commit, up -d again, .deploy/failed = <commit>, exit 1
set -eu

# `git checkout` below rewrites this very file while it runs, and sh reads scripts
# as it goes. So run from a temporary copy instead.
if [ -z "${DEPLOY_ROOT:-}" ]; then
  DEPLOY_ROOT=$(cd "$(dirname "$0")/.." && pwd)
  copy=$(mktemp -t news-app-deploy)
  cp "$0" "$copy"
  DEPLOY_ROOT="$DEPLOY_ROOT" exec sh "$copy" "$@"
fi
cd "$DEPLOY_ROOT"
mkdir -p .deploy

log() { # level message [extra JSON fields]
  line="{\"time\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"level\":\"$1\",\"message\":\"$2\"${3:+,$3}}"
  echo "$line"; echo "$line" >> .deploy/deploy.log
}

# One deploy at a time (mkdir is atomic).
mkdir .deploy/lock 2>/dev/null || { log WARNING "another deploy is running; skipped"; exit 0; }
trap 'rmdir .deploy/lock 2>/dev/null' EXIT

git fetch -q origin main 2>/dev/null || log WARNING "git fetch failed; using local refs"
target=$(git rev-parse --verify "${1:-origin/main}^{commit}")
previous=$(cat .deploy/deployed 2>/dev/null || git rev-parse HEAD)
short=$(echo "$target" | cut -c1-7)
health_timeout="${HEALTH_TIMEOUT:-120}"

# Services to check: one per x-<svc>-image anchor in the target compose file.
services=$(git show "$target:docker-compose.yml" | sed -n 's/^x-\([a-z0-9-]*\)-image:.*/\1/p' | tr '\n' ' ')
images=$(git show "$target:docker-compose.yml" | sed -n 's/^x-[a-z0-9-]*-image: &[a-z-]* //p' | tr '\n' ' ')
log INFO "deploying" "\"commit\":\"$target\",\"previous\":\"$previous\",\"images\":\"$images\""

healthy() { # all services answer 200 through the gateway before the timeout
  deadline=$(( $(date +%s) + health_timeout ))
  for svc in $services; do
    until [ "$(curl -s -o /dev/null --max-time 5 -w '%{http_code}' "https://${PUBLIC_HOST:-localhost}/health/$svc/ready")" = 200 ]; do
      [ "$(date +%s)" -ge "$deadline" ] && { log ERROR "health check failed" "\"service\":\"$svc\",\"commit\":\"$target\""; return 1; }
      sleep 3
    done
  done
}

git checkout -q --detach "$target"
if docker compose pull -q && docker compose up -d --remove-orphans && healthy; then
  echo "$target" > .deploy/deployed
  rm -f .deploy/failed
  log INFO "deployed" "\"commit\":\"$target\",\"services\":\"$services\""
  exit 0
fi

# Roll back: the previous commit's compose file has the previous image SHAs.
log ERROR "deploy failed; rolling back" "\"commit\":\"$target\",\"rollback_to\":\"$previous\""
echo "$target" > .deploy/failed
git checkout -q --detach "$previous"
if docker compose up -d --remove-orphans && healthy; then
  log WARNING "rolled back" "\"commit\":\"$previous\",\"failed_commit\":\"$short\""
else
  log ERROR "rollback is unhealthy too; check docker compose ps" "\"commit\":\"$previous\""
fi
exit 1
