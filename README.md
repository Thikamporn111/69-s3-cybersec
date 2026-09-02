# 69-s3-cybersec

REST authentication lab using Strapi, PostgreSQL, pgAdmin, and a hardened Nginx reverse proxy.

## Start

1. Copy `.env.example` to `.env` and fill every required value with unique random secrets.
2. Keep the project on a trusted computer, outside any cloud-synced folder such as OneDrive, Dropbox, or Google Drive. Do not forward its ports through a router or tunnel.
3. Run `docker compose pull`.
4. Run `docker compose build --pull`.
5. Run `docker compose up -d`.

Local services:

- Strapi REST/Admin: `http://localhost:9093`
- pgAdmin: `http://localhost:8083`

PostgreSQL publishes no host port. Reach it through pgAdmin, which shares the internal `data` network, or open a shell with:

```
docker compose exec db psql -U "$DATABASE_USER" -d "$DATABASE_DB"
```

The lab runs over plain HTTP because every port binds to `127.0.0.1` and never leaves the machine. TLS is required before this stack is reachable from anywhere else; `security/certs/openssl.cnf` is kept so a local certificate is one command away when that day comes. See `SECURITY.md`.

The local lab uses a non-delivery email transport. Forgot Password generates and stores a reset token without exposing a mailbox. For lab verification only, inspect `reset_password_token` in PostgreSQL as documented in `api.rest`; configure a real trusted email provider before deployment.
