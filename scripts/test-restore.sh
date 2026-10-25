#!/usr/bin/env sh
# Proves a backup can be restored, without touching the live database:
# restores the newest dump of <svc> into a throwaway Postgres container with no
# network, then compares row counts per table with the live database.
#   ./scripts/test-restore.sh users      (or: articles)
#   ./scripts/test-restore.sh users backups/users/users-20261025T140000Z.dump
set -eu
cd "$(dirname "$0")/.."
svc="${1:?usage: $0 <articles|users> [dump file]}"
dump="${2:-$(ls -1t backups/"$svc"/"$svc"-*.dump 2>/dev/null | head -n 1)}"
[ -n "$dump" ] && [ -f "$dump" ] || { echo "no dump found for $svc in backups/$svc/" >&2; exit 1; }
echo "Testing restore of $dump"

scratch="restore-test-$svc-$$"
docker run -d --rm --name "$scratch" --network none -e POSTGRES_PASSWORD=scratch postgres:17-alpine >/dev/null
trap 'docker rm -f "$scratch" >/dev/null 2>&1' EXIT
until docker exec "$scratch" pg_isready -q -U postgres 2>/dev/null; do sleep 1; done
sleep 1   # the image restarts Postgres once after first init

docker exec -i "$scratch" pg_restore -U postgres -d postgres --no-owner --exit-on-error < "$dump"

# Exact row counts for every table, as "table|count" lines, sorted.
counts_sql="SELECT format('SELECT %L || ''|'' || count(*) FROM %I;', tablename, tablename) FROM pg_tables WHERE schemaname = 'public' ORDER BY tablename"
restored=$(docker exec "$scratch" psql -U postgres -d postgres -Atc "$counts_sql" | docker exec -i "$scratch" psql -v ON_ERROR_STOP=1 -U postgres -d postgres -At)
live=$(docker compose exec -T "$svc-db" psql -U "$svc" -d "$svc" -Atc "$counts_sql" | docker compose exec -T "$svc-db" psql -v ON_ERROR_STOP=1 -U "$svc" -d "$svc" -At)

echo "table|restored  vs  live"
echo "$restored" | while IFS='|' read -r t n; do
  echo "  $t|$n  vs  $(echo "$live" | grep "^$t|" | cut -d'|' -f2)"
done
if [ -z "$restored" ]; then
  echo "FAIL: the restored database has no tables"; exit 1
elif [ "$restored" = "$live" ]; then
  echo "PASS: the backup restores, and every table has the same row count as live"
else
  echo "DIFFERENT: row counts differ (expected if data changed since the backup was taken)"; exit 2
fi
