#!/usr/bin/env bash
# Clear password-reset tokens from the lab database.
#
#   ./scripts/purge-reset-tokens.sh            # clear every token
#   ./scripts/purge-reset-tokens.sh 15         # keep tokens newer than 15 min
#   ./scripts/purge-reset-tokens.sh 0 --dry-run
#
# Strapi Community Edition stores `reset_password_token` in plain text in both
# `up_users` and `admin_users` and sets no expiry, so a token stays a working
# one-shot account-takeover credential until somebody uses it. There is no
# Strapi setting that fixes this; clearing the tokens is the control. Run this
# after any forgot-password test.
set -euo pipefail

cd "$(dirname "$0")/.."

older_than_minutes="${1:-0}"
dry_run="${2:-}"

[ -f .env ] || { echo "error: .env not found." >&2; exit 1; }

# Read .env as data, never as shell.
get_env() {
  sed -n "s/^$1=//p" ./.env | head -1 | tr -d '\r' \
    | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'\$//"
}

DATABASE_USER="$(get_env DATABASE_USER)"
DATABASE_DB="$(get_env DATABASE_DB)"
[ -n "$DATABASE_USER" ] && [ -n "$DATABASE_DB" ] \
  || { echo "error: DATABASE_USER and DATABASE_DB must be set in .env" >&2; exit 1; }

psql_q() {
  docker compose exec -T db psql -U "$DATABASE_USER" -d "$DATABASE_DB" -tAc "$1" | tr -d '[:space:]'
}

if [ "$older_than_minutes" -gt 0 ] 2>/dev/null; then
  age="AND updated_at < now() - interval '$older_than_minutes minutes'"
  echo "Clearing reset tokens older than $older_than_minutes minute(s)."
else
  age=""
  echo "Clearing every reset token."
fi

total=0
for table in up_users admin_users; do
  where="reset_password_token IS NOT NULL $age"
  count="$(psql_q "SELECT count(*) FROM $table WHERE $where;")"
  if [ "$dry_run" = "--dry-run" ]; then
    printf '  %-14s %s token(s) would be cleared\n' "$table" "$count"
  else
    [ "$count" -gt 0 ] && psql_q "UPDATE $table SET reset_password_token = NULL WHERE $where;" >/dev/null
    printf '  %-14s %s token(s) cleared\n' "$table" "$count"
  fi
  total=$((total + count))
done

echo
if [ "$dry_run" = "--dry-run" ]; then
  echo "$total token(s) match. Nothing was changed."
elif [ "$total" -eq 0 ]; then
  echo "No live reset tokens were in the database."
else
  echo "$total token(s) cleared. Those reset links no longer work."
fi
