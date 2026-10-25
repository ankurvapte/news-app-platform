#!/usr/bin/env sh
# Restores a backup INTO THE LIVE database of <svc>, replacing its current data.
# Stops the service first so nothing writes during the restore, then starts it.
#   ./scripts/restore.sh users backups/users/users-20261025T140000Z.dump
# Take a fresh backup first if the current data matters:
#   docker compose exec users-backup pg-backup
set -eu
cd "$(dirname "$0")/.."
svc="${1:?usage: $0 <articles|users> <dump file>}"
dump="${2:?usage: $0 <articles|users> <dump file>}"
[ -f "$dump" ] || { echo "no such file: $dump" >&2; exit 1; }

if [ "${RESTORE_YES:-}" != "1" ]; then
  printf 'Replace ALL data in %s-db with %s? Type the service name to confirm: ' "$svc" "$dump"
  read -r answer
  [ "$answer" = "$svc" ] || { echo "aborted"; exit 1; }
fi

docker compose stop "$svc-svc"
# --clean --if-exists: drop each object before recreating it from the dump.
# --single-transaction: all or nothing; a failed restore leaves the old data in place.
docker compose exec -T "$svc-db" pg_restore -U "$svc" -d "$svc" \
  --clean --if-exists --no-owner --single-transaction --exit-on-error < "$dump"
docker compose start "$svc-svc"
echo "Restored $dump into $svc-db; $svc-svc started again. Check: curl https://localhost/health/$svc/ready"
