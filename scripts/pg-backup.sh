#!/bin/sh
# Runs INSIDE a <svc>-backup container (postgres:17-alpine image, mounted at
# /usr/local/bin/pg-backup). Dumps one database to /backups (a host folder),
# then keeps only the newest $BACKUP_KEEP dumps.
#   Scheduled: the container's loop calls it every $BACKUP_INTERVAL_SECONDS.
#   Manual:    docker compose exec users-backup pg-backup
# Connection comes from the standard libpq env vars: PGHOST, PGUSER, PGDATABASE, PGPASSWORD.
set -eu
keep="${BACKUP_KEEP:-7}"
name="$PGDATABASE-$(date -u +%Y%m%dT%H%M%SZ).dump"

# Custom format (-Fc): compressed, and pg_restore can restore it table by table.
# Write to a temp name first so a half-written file never looks like a backup.
pg_dump --format=custom --file="/backups/.$name.partial"
mv "/backups/.$name.partial" "/backups/$name"
echo "{\"level\":\"INFO\",\"message\":\"backup written\",\"file\":\"$name\",\"bytes\":$(wc -c < "/backups/$name")}"

# Retention: newest first, delete everything after the first $keep.
ls -1t /backups/"$PGDATABASE"-*.dump | tail -n +"$((keep + 1))" | while read -r old; do
  rm -f -- "$old"
  echo "{\"level\":\"INFO\",\"message\":\"old backup deleted\",\"file\":\"$(basename "$old")\"}"
done
