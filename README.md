# 69-s3-cybersec

REST authentication lab using Strapi, PostgreSQL, pgAdmin, and a hardened Nginx
reverse proxy.

## Start

1. Copy `.env.example` to `.env` and fill every required value with its own
   unique random secret. Never reuse one value in two variables.
2. Keep the project on a trusted computer, outside any cloud-synced folder such
   as OneDrive, Dropbox, Google Drive or WPS Cloud. Do not forward its ports
   through a router or tunnel.
3. Run `docker compose pull`.
4. Run `docker compose build --pull`.
5. Run `docker compose up -d`.

Local services:

- Strapi REST/Admin: `http://localhost:9093`
- pgAdmin: `http://localhost:8083`

PostgreSQL publishes no host port. Reach it through pgAdmin, which shares the
internal `data` network, or open a shell with:

```
docker compose exec db psql -U "$DATABASE_USER" -d "$DATABASE_DB"
```

The lab runs over plain HTTP because every port binds to `127.0.0.1` and never
leaves the machine. TLS is required before this stack is reachable from
anywhere else; `security/certs/openssl.cnf` is kept so a local certificate is
one command away when that day comes. See `SECURITY.md`.

## Testing the auth flow

`run-user-reset-test.cmd` runs register, login, profile, forgot password, reset
and login-again against a throwaway user, then clears the reset token it used.
Prefer it over pasting a token into `api.rest` by hand.

The Nginx auth zone allows 10 credential requests a minute; one full run spends
5 of them. A `429` means you ran it twice inside a minute -- wait and retry.

## Password reset and the token in the database

The local lab uses a non-delivery email transport. Forgot Password generates
and stores a reset token without exposing a mailbox, so lab verification means
reading `reset_password_token` from PostgreSQL.

Strapi Community Edition stores that token **in plain text with no expiry**, so
it stays a working account-takeover credential until somebody uses it. Anyone
who can open pgAdmin, copy `./data/postgres`, or read an unencrypted dump can
take over any account that has a token in its row.

Clear tokens after testing:

```
powershell -ExecutionPolicy Bypass -File .\scripts\purge-reset-tokens.ps1
```

Never leave a real token in `api.rest`. Configure a real trusted email provider
before deployment. `SECURITY.md` has the full picture.

## Documents

- `SECURITY.md` -- the controls in place, and the gaps that are not.
- `ROTATE-SECRETS.md` -- how to change each secret where it actually lives.
  Editing `.env` alone does not change a running PostgreSQL role, a pgAdmin
  login, or the Strapi administrator's password.
- `scripts/backup-db.sh` / `restore-db.sh` -- verified encrypted backups.
  `BACKUP_DIR` must point outside this project.
- `scripts/purge-reset-tokens.ps1` / `.sh` -- clear reset tokens.
