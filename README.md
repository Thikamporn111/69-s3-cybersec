# 69-s3-cybersec

REST authentication lab using Strapi, PostgreSQL, pgAdmin, and a hardened Nginx reverse proxy.

## Start

1. Copy `.env.example` to `.env` and fill every required value with unique random secrets.
2. Generate the local TLS certificate (once):

   ```
   openssl req -x509 -nodes -newkey rsa:2048 -days 825 \
     -keyout security/certs/server.key \
     -out security/certs/server.crt \
     -config security/certs/openssl.cnf
   ```

   The key and certificate are ignored by Git. Regenerate them on every machine.
3. Keep the project on a trusted computer, outside any cloud-synced folder such as OneDrive, Dropbox, or Google Drive. Do not forward its ports through a router or tunnel.
4. Run `docker compose pull`.
5. Run `docker compose build --pull`.
6. Run `docker compose up -d`.

Local services:

- Strapi REST/Admin: `https://localhost:9093`
- pgAdmin: `http://localhost:8083`
- PostgreSQL: `localhost:54327`

The certificate is self-signed, so the browser shows a warning on first visit. That is expected for a local lab. A plain `http://localhost:9093` request is redirected to HTTPS on the same port.

The local lab uses a non-delivery email transport. Forgot Password generates and stores a reset token without exposing a mailbox. For lab verification only, inspect `reset_password_token` in PostgreSQL as documented in `api.rest`; configure a real trusted email provider before deployment.

All published ports bind to `127.0.0.1` only. See `SECURITY.md` before exposing this project outside the local machine.
