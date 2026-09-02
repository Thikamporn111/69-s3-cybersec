# Security baseline

This project is hardened for a local classroom lab. No application can guarantee protection from every future vulnerability or a compromised host.

## Included controls

- Every published port binds to `127.0.0.1`. PostgreSQL publishes no port at all and sits on an internal network with no route to the internet.
- Strapi is reachable only through an unprivileged Nginx reverse proxy.
- Authentication endpoints have rate limiting in both Nginx and Strapi. The strict Nginx zone covers every route that accepts or consumes a credential, a reset token, or an email trigger, and tolerates a trailing slash so a slash-suffixed request cannot escape it.
- Sessions are revocable. `jwtManagement` runs in `refresh` mode, so access tokens are short lived and refresh tokens are tracked server side; logging out or revoking a session takes effect immediately.
- Uploaded files are served with a `sandbox` Content-Security-Policy, so an uploaded HTML or SVG file cannot run script in the admin panel's origin.
- Request body size, query depth, connection count, timeouts, CPU, and memory are limited.
- CORS only permits the two local Strapi origins.
- Containers use `no-new-privileges`; Nginx and Strapi drop all Linux capabilities.
- Strapi runs in production mode as the non-root `node` user with a read-only root filesystem.
- Remote transfer and unauthenticated OpenAPI endpoints are disabled.
- Every container image is pinned by digest as well as tag, and npm dependencies are pinned by `package-lock.json`.
- Container logs are rotated at 10 MB with five files kept per service.
- Database files, uploads, TLS keys, REST credentials, and `.env` files are excluded from Git and Docker build contexts.

## Storage location

Keep the working copy, `.env`, `api.rest`, and the PostgreSQL data directory outside any cloud-synced folder. Sync clients do not read `.gitignore`; a project kept under OneDrive, Dropbox, or Google Drive uploads every secret and every database file to a third-party service. A PostgreSQL data directory is especially sensitive because its `pg_hba.conf` trusts local connections, so anyone holding a copy can mount it and read the database without a password.

## Secrets

Use a different randomly generated value for every password and secret. Recommended minimums:

- `DATABASE_PASSWORD`, `PGADMIN_PASSWORD`, `STRAPI_ADMIN_PASSWORD`: at least 20 random characters.
- Strapi salts and JWT secrets: at least 32 random bytes.
- `STRAPI_APP_KEYS`: at least four independent random keys separated by commas.

Changing `DATABASE_PASSWORD` in `.env` does not update an already initialized PostgreSQL volume. Change the database role password first or recreate the lab database after making a backup.

## Known gaps

These are accepted for a single-machine lab and must be closed before the stack is reachable from anywhere else.

- **No TLS.** Traffic to `127.0.0.1` cannot be intercepted from the network, so a certificate buys nothing here while making every request harder to make. `security/certs/openssl.cnf` generates a local certificate in one command when it is needed. Note that HSTS must stay off for a `localhost` certificate: HSTS is scoped to the host name and ignores the port, so it would force HTTPS on every other localhost service on the machine. Strapi's helmet default is disabled in `config/middlewares.js` and stripped again at the proxy for that reason.
- **Public registration is open** and Strapi reports whether an email is already taken, which allows account enumeration. There is no CAPTCHA.
- **No MFA or SSO** for administrators; Strapi Community Edition does not offer either.
- **No encrypted, tested backups.** `POSTGRES_DATA_PATH` points at live data, not a backup.
- **Password reset cannot be completed through email.** The nodemailer sink transport discards every message while still writing `reset_password_token` to the database, so lab verification means reading that column. Never carry that practice into a real deployment.

## Before any public deployment

Do not publish this classroom stack directly to the Internet. A real deployment additionally needs a certificate from a trusted CA with HSTS enabled, a trusted production email provider, MFA/SSO for administrators, CAPTCHA or an upstream bot-management service, centralized logs and alerts, encrypted backups, regular patching, and an external security review.

## Upstream dependency status

On 2026-09-02, `npm audit --omit=dev` still reports advisories inherited from Strapi 5.52.2, including a high-severity Vite development-server advisory and moderate React Router advisories. This project never runs `strapi develop` or a Vite server in the runtime image; only the built Strapi production server is exposed through Nginx. Do not use `npm audit fix --force`, because npm currently proposes an incompatible Strapi downgrade. Recheck and update when Strapi publishes compatible dependency fixes.
