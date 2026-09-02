#!/usr/bin/env bash
# Restore an encrypted backup produced by scripts/backup-db.sh.
#
#   ./scripts/restore-db.sh "<BACKUP_DIR>/69-s3-20260902-030000.sql.gz.enc"
#
# This DROPS and recreates every object in the target database.
set -euo pipefail

cd "$(dirname "$0")/.."

archive="${1:-}"
[ -n "$archive" ] && [ -f "$archive" ] || { echo "usage: $0 <encrypted-backup-file>" >&2; exit 1; }
[ -f .env ] || { echo "error: .env not found." >&2; exit 1; }

get_env() {
  sed -n "s/^$1=//p" ./.env | head -1 | tr -d '\r' \
    | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'\$//"
}

DATABASE_USER="$(get_env DATABASE_USER)"
DATABASE_DB="$(get_env DATABASE_DB)"
BACKUP_PASSPHRASE="$(get_env BACKUP_PASSPHRASE)"

[ -n "$DATABASE_USER" ] && [ -n "$DATABASE_DB" ] && [ -n "$BACKUP_PASSPHRASE" ] \
  || { echo "error: DATABASE_USER, DATABASE_DB and BACKUP_PASSPHRASE must be set in .env" >&2; exit 1; }
export BACKUP_PASSPHRASE

echo "This overwrites every table in '$DATABASE_DB' with the contents of"
echo "  $archive"
printf "Type the database name to confirm: "
read -r answer
[ "$answer" = "$DATABASE_DB" ] || { echo "Aborted."; exit 1; }

openssl enc -d -aes-256-cbc -pbkdf2 -iter 600000 -pass env:BACKUP_PASSPHRASE -in "$archive" \
  | gunzip \
  | docker compose exec -T db psql -U "$DATABASE_USER" -d "$DATABASE_DB" -v ON_ERROR_STOP=1

echo "Restored. Reload Strapi with: docker compose restart strapi"
