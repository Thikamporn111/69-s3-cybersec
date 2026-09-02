#!/usr/bin/env bash
# Encrypted PostgreSQL backup for the 69-s3-cybersec lab.
#
#   ./scripts/backup-db.sh
#
# Writes <BACKUP_DIR>/69-s3-<timestamp>.sql.gz.enc, encrypted with AES-256 from
# BACKUP_PASSPHRASE, then decrypts it again to prove the file is readable.
# Keep BACKUP_DIR outside the project and outside any cloud-synced folder.
set -euo pipefail

cd "$(dirname "$0")/.."

[ -f .env ] || { echo "error: .env not found." >&2; exit 1; }

# Read .env as data, never as shell. Sourcing it would execute whatever a
# password happens to contain, and the file is CRLF on Windows.
get_env() {
  sed -n "s/^$1=//p" ./.env | head -1 | tr -d '\r' \
    | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'\$//"
}

DATABASE_USER="$(get_env DATABASE_USER)"
DATABASE_DB="$(get_env DATABASE_DB)"
BACKUP_PASSPHRASE="$(get_env BACKUP_PASSPHRASE)"
BACKUP_DIR="$(get_env BACKUP_DIR)"
BACKUP_DIR="${BACKUP_DIR:-./backups}"

[ -n "$DATABASE_USER" ] || { echo "error: DATABASE_USER is not set in .env" >&2; exit 1; }
[ -n "$DATABASE_DB" ]   || { echo "error: DATABASE_DB is not set in .env" >&2; exit 1; }
if [ -z "$BACKUP_PASSPHRASE" ]; then
  echo "error: BACKUP_PASSPHRASE is not set in .env." >&2
  echo "       A plain dump holds every password hash and reset token." >&2
  exit 1
fi
export BACKUP_PASSPHRASE

mkdir -p "$BACKUP_DIR"
target="$BACKUP_DIR/69-s3-$(date +%Y%m%d-%H%M%S).sql.gz.enc"
enc_args=(-aes-256-cbc -pbkdf2 -iter 600000 -pass env:BACKUP_PASSPHRASE)

echo "Dumping $DATABASE_DB ..."
docker compose exec -T db pg_dump -U "$DATABASE_USER" -d "$DATABASE_DB" --clean --if-exists \
  | gzip -9 \
  | openssl enc "${enc_args[@]}" -salt \
  > "$target"

[ -s "$target" ] || { rm -f "$target"; echo "error: backup is empty." >&2; exit 1; }

# A backup nobody has restored is a guess. Read it straight back.
# grep stops at the first hit and closes the pipe upstream, which pipefail
# would report as a failure, so it is disabled for this check only.
if ! ( set +o pipefail
       openssl enc -d "${enc_args[@]}" -in "$target" \
         | gunzip \
         | grep -qm1 "PostgreSQL database dump" ); then
  rm -f "$target"
  echo "error: the backup could not be decrypted and read back. Removed it." >&2
  exit 1
fi

echo "OK  $target  ($(du -h "$target" | cut -f1))"
echo "Verified: decrypts cleanly and contains a PostgreSQL dump header."
