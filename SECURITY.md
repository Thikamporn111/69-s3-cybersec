# Security baseline

This project is hardened for a local classroom lab. No application can guarantee protection from every future vulnerability or a compromised host.

## Included controls

- All host ports bind to `127.0.0.1`; PostgreSQL and pgAdmin are not reachable from the LAN.
- Strapi is reachable only through an unprivileged Nginx reverse proxy, over TLS.
- Authentication endpoints have rate limiting in both Nginx and Strapi. The strict Nginx zone covers every route that accepts or consumes a credential, a reset token, or an email trigger, and tolerates a trailing slash so a slash-suffixed request cannot escape it.
- Uploaded files are served with a `sandbox` Content-Security-Policy, so an uploaded HTML or SVG file cannot run script in the admin panel's origin.
- Request body size, query depth, connection count, timeouts, CPU, and memory are limited.
- CORS only permits the two local Strapi origins.
- Containers use `no-new-privileges`; Nginx and Strapi drop all Linux capabilities.
- Strapi runs in production mode as the non-root `node` user with a read-only root filesystem.
- Remote transfer and unauthenticated OpenAPI endpoints are disabled.
- JWT lifetime is one hour, and dependency versions are pinned by `package-lock.json`.
- Container logs are rotated at 10 MB with five files kept per service.
- Database files, uploads, TLS keys, REST credentials, and `.env` files are excluded from Git and Docker build contexts.

## TLS

Nginx terminates TLS 1.2/1.3 on the published port using the self-signed certificate in `security/certs/`. Session cookies carry the `secure` flag. A plain HTTP request to that port returns a redirect to the HTTPS URL on the same port.

`Strict-Transport-Security` is deliberately **not** sent. HSTS is scoped to the host name and ignores the port, so sending it for `localhost` would force HTTPS on every other localhost service on the machine. Enable it once this stack has a real hostname and a certificate from a trusted CA.

pgAdmin is published directly rather than through the proxy, so it is still plain HTTP on `127.0.0.1` and its session cookie cannot carry the `secure` flag. Put it behind the proxy before using it anywhere but a single trusted machine.

## Storage location

Keep the working copy, `.env`, `api.rest`, and the PostgreSQL data directory outside any cloud-synced folder. Sync clients do not read `.gitignore`; a project kept under OneDrive, Dropbox, or Google Drive uploads every secret and every database file to a third-party service. A PostgreSQL data directory is especially sensitive because its `pg_hba.conf` trusts local connections, so anyone holding a copy can mount it and read the database without a password.

## Secrets

Use a different randomly generated value for every password and secret. Recommended minimums:

- `DATABASE_PASSWORD`, `PGADMIN_PASSWORD`, `STRAPI_ADMIN_PASSWORD`: at least 20 random characters.
- Strapi salts and JWT secrets: at least 32 random bytes.
- `STRAPI_APP_KEYS`: at least four independent random keys separated by commas.

Changing `DATABASE_PASSWORD` in `.env` does not update an already initialized PostgreSQL volume. Change the database role password first or recreate the lab database after making a backup.

## Known gaps

- JWTs cannot be revoked. `jwtManagement` is set to `legacy-support`, so a leaked token stays valid until it expires, and logout has no server-side effect.
- Public registration is open and Strapi reports whether an email is already taken, which allows account enumeration. There is no CAPTCHA.
- Container images are pinned by tag, not by digest, so a re-pull can bring a different image.
- Strapi Community Edition has no MFA or SSO for administrators.
- The PostgreSQL port is published to `127.0.0.1` even though only pgAdmin needs it, and the `db` container has outbound network access because publishing a port requires a non-internal network.
- No encrypted, tested backups. `POSTGRES_DATA_PATH` points at live data, not a backup.

## Before any public deployment

Do not publish this classroom stack directly to the Internet. A real deployment additionally needs a certificate from a trusted CA with HSTS enabled, a trusted production email provider, MFA/SSO for administrators, CAPTCHA or an upstream bot-management service, centralized logs and alerts, encrypted backups, regular patching, and an external security review.

The local lab intentionally discards outgoing email while still generating reset tokens. Configure a trusted production email provider before any real deployment.

## Upstream dependency status

On 2026-09-02, `npm audit --omit=dev` still reports advisories inherited from Strapi 5.52.2, including a high-severity Vite development-server advisory and moderate React Router advisories. This project never runs `strapi develop` or a Vite server in the runtime image; only the built Strapi production server is exposed through Nginx. Do not use `npm audit fix --force`, because npm currently proposes an incompatible Strapi downgrade. Recheck and update when Strapi publishes compatible dependency fixes.
