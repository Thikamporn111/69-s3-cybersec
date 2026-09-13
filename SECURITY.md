# Security baseline

This project is hardened for a local classroom lab. No application can be made
free of risk: hardening raises the cost of an attack and shrinks what a
successful one reaches. It cannot rule one out, and nothing here protects a
compromised host, a future vulnerability in Strapi, PostgreSQL, pgAdmin, Nginx,
Docker or Windows, or a secret that has been copied somewhere else.

Last reviewed 2026-09-12.

## Included controls

### Network exposure

- Every published port binds to `127.0.0.1`. PostgreSQL publishes no port at
  all and sits on an internal network with no route to the internet.
- Strapi is reachable only through an unprivileged Nginx reverse proxy.
- The proxy sets `X-Forwarded-For` to `$remote_addr` rather than appending to
  whatever the client sent, so a client cannot inject a forged hop. Strapi is
  configured with `maxIpsCount: 1` and reads only the last entry.
- CORS only permits the two local Strapi origins.
- Requests with a known scanner user agent get 403; methods outside the allowed
  set get 405.

### Credentials and sessions

- Authentication endpoints are rate limited in both Nginx and Strapi. The
  strict Nginx zone allows **10 credential requests a minute with a burst of
  10** and covers every route that accepts or consumes a credential, a reset
  token, or an email trigger; it tolerates a trailing slash so a slash-suffixed
  request cannot escape it. Strapi's own limiter sits behind it at 10 per
  minute **per path and per IP**. Bypassing either one still runs into the
  other. One full run of `run-user-reset-test.ps1` spends 5 of the proxy's 10,
  so two runs a minute is the practical ceiling.
- Sessions are revocable. `jwtManagement` runs in `refresh` mode: the access
  token lives 10 minutes (`SESSION_ACCESS_TOKEN_LIFESPAN`), and the long-lived
  refresh token is a server-side session that `POST /api/auth/logout` kills at
  once. A stolen refresh token stops working the moment the user logs out; a
  stolen access token stays usable until it expires, which is the ceiling this
  design sets. `logout`, `getSessions` and `revokeSession` are granted to the
  authenticated role and `refresh` to the public role, because refreshing
  happens without a valid access token.
- `JWT_EXPIRES_IN` is no longer set in `docker-compose.yaml`. It did nothing in
  `refresh` mode while reading as though the ceiling were an hour. The fallback
  in `config/plugins.js` is 10 minutes, so switching back to the plain plugin
  JWT cannot silently restore an hour-long token that nothing can revoke.
- pgAdmin locks out after 5 failed logins and requires a 20-character minimum
  password. **Strapi has no lockout**, only the rate limits above.
- pgAdmin refuses to store a database password in `pgadmin4.db`
  (`ALLOW_SAVE_PASSWORD: False`). That file lives in `./data/pgadmin` on the
  host, so anyone copying the folder would otherwise carry a recoverable
  database credential with it. The password is typed per connection instead.

### Application surface

- Uploaded files are served through `location ^~ /uploads/` in
  `security/nginx.conf` with `Content-Security-Policy: sandbox`, which puts the
  response in an opaque origin: an uploaded HTML or SVG file cannot run script
  against the admin panel's origin or read its storage. Images and media still
  render. The same location rejects every method except GET and HEAD. The
  policy is set at the proxy, not in `config/middlewares.js`, because the proxy
  is the only path by which an uploaded file reaches a browser.
- Request body size, query depth, connection count, timeouts, CPU and memory
  are limited.
- Remote transfer and unauthenticated OpenAPI endpoints are disabled. Cron is
  disabled.
- `register.allowedFields` is empty, so a registration request cannot set any
  field beyond username, email and password.

### Runtime and supply chain

- Containers use `no-new-privileges`; Nginx and Strapi drop all Linux
  capabilities.
- Strapi runs in production mode as the non-root `node` user with a read-only
  root filesystem and `noexec,nosuid,nodev` tmpfs mounts.
- Every container image is pinned by digest as well as tag, and npm
  dependencies are pinned by `package-lock.json`.
- Container logs are rotated at 10 MB with five files kept per service.
- Database files, uploads, TLS keys, REST credentials, dumps and `.env` files
  are excluded from Git and from Docker build contexts. Git history has been
  checked: no `.env` or `api.rest` has ever been committed, and every secret in
  a tracked file is a `${VARIABLE}` reference.

## Monitoring and response

The proxy writes a JSON access log (`log_format json_combined` in
`security/nginx.conf`), and `scripts/watch-attacks.ps1` reads it to report who
connected, when, and how. It sorts each request into attacking / suspicious /
just-viewing, pops a Windows alert on an attack, and writes a dated report and
CSV under `scripts/reports/` (gitignored -- they hold IPs, paths and payloads).

```
powershell -ExecutionPolicy Bypass -File .\scripts\watch-attacks.ps1 -Since 1h   # review the last hour
powershell -ExecutionPolicy Bypass -File .\scripts\watch-attacks.ps1 -Follow     # watch live, alert on attacks
```

It detects brute force (repeated failed or 429'd auth), scanner user-agents, SQL
injection, path traversal, XSS probes, sensitive-file probes (`/.env`, `/.git`),
and forged `X-Forwarded-For`. Because this lab is bound to `127.0.0.1`, every
source address is the local machine; the IP and `XFF` columns only identify a
real attacker once the stack faces a network.

**The response is detection, recording, alerting and -- once networked --
blocking. It is never counter-attack.** Attacking the source of an attack
("hacking back") is an offence under Thailand's Computer Crime Act even when you
were targeted first, and the apparent source is typically a spoofed address or a
hijacked third party, so a counter-strike lands on a victim rather than the
attacker. Blocking an offending IP (for example in the firewall, or an Nginx
`deny`) is lawful and is the correct equivalent of "striking back"; it is not
wired in here because on a `127.0.0.1`-only lab it would only block the local
machine. Add it when the stack is exposed and real client IPs appear.

## Password reset: what the database exposes

This is the sharpest edge in the lab and it deserves its own section.

Strapi Community Edition stores `reset_password_token` **in plain text** in
`up_users` and `admin_users`, and **sets no expiry**. Calling Forgot Password
writes a token into the account's row, where it stays a working one-shot
account-takeover credential until somebody uses it. Not for an hour. Until
somebody uses it.

So anyone who can read the database can take over any account that has a token
sitting in its row. In this lab that means anyone who can open pgAdmin, copy
`./data/postgres`, or read an unencrypted dump. Reading the token out of
pgAdmin is not a loophole in the lab's design; it is the design working exactly
as an attacker with database access would use it.

There is no Strapi setting that hashes the token or gives it a lifetime.
Clearing the tokens is the control:

- `scripts/purge-reset-tokens.ps1` (or `.sh`) clears every token, or only those
  whose row has been untouched for N minutes, which approximates an expiry
  window. Run it after any forgot-password test, and on a schedule if the lab
  is left running.
- `run-user-reset-test.ps1` runs the whole register/login/forgot/reset cycle
  with the token held in a variable, never printed and never written to a file,
  and clears it afterwards even if the run fails part way.
- **Never leave a real token in `api.rest`.** A token pasted there and left
  behind is a standing admin-takeover credential in a plain text file. Paste
  one only for the seconds it takes to send the request, restore the
  placeholder, then purge.

Whether to keep the reset flow at all is a judgement call. It is kept here
because demonstrating register/login/forgot/reset is the point of the lab. If
the flow were not part of the assignment, removing the `forgot-password` and
`reset-password` permissions from the public role and dropping those routes from
the proxy would be the smaller attack surface, because an endpoint nobody can
complete through email is surface with no corresponding function.

## Secrets

Every value in `.env` must be independently random. Reusing one value in two
places turns one compromise into two.

A rotated `.env` was generated on 2026-09-12 as `.env.new`; until
`ROTATE-SECRETS.md` has been worked through, the values actually in force are
still the previous ones, including the `PGADMIN_PASSWORD` /
`DATABASE_PASSWORD` collision described below.

Recommended minimums:

- `DATABASE_PASSWORD`, `PGADMIN_PASSWORD`: at least 20 random characters.
- `STRAPI_ADMIN_PASSWORD` and the `REST_*` passwords: at least 20 random
  characters. A pattern built from the project name and the year is not random;
  anyone who has seen the repository can guess it, and the rate limits are then
  the only thing between them and the account.
- Strapi salts and JWT secrets: at least 32 random bytes.
- `STRAPI_APP_KEYS`: at least four independent random keys separated by commas.

`PGADMIN_PASSWORD` must not equal `DATABASE_PASSWORD`. It did in an earlier
revision, inherited from a compose file that set
`PGADMIN_DEFAULT_PASSWORD: ${DATABASE_PASSWORD}`, which meant the pgAdmin web
login and the PostgreSQL superuser shared one secret.

Changing a value in `.env` does not update an already initialized PostgreSQL
volume or pgAdmin database. `ROTATE-SECRETS.md` has the procedure.

## Storage location

Keep the working copy, `.env`, `api.rest`, and the PostgreSQL data directory
outside any cloud-synced folder. Sync clients do not read `.gitignore`; a
project kept under OneDrive, Dropbox, Google Drive or WPS Cloud uploads every
secret and every database file to a third-party service. A PostgreSQL data
directory is especially sensitive because its `pg_hba.conf` trusts local
connections, so anyone holding a copy can mount it and read the database
without a password.

`./data/postgres` and `./data/pgadmin` are live data inside the project folder.
They are gitignored, but a folder-level copy, a zip sent to a classmate, or a
sync client picks them up regardless.

## Backups

`scripts/backup-db.sh` writes an AES-256 encrypted `pg_dump` to `BACKUP_DIR`,
then decrypts it again and checks the plaintext really is a dump before
reporting success -- an unverified backup is a guess. `scripts/restore-db.sh`
reverses it and asks for the database name first, because it drops every
object. Both read `.env` as data rather than sourcing it, so a password
containing shell metacharacters cannot execute.

`BACKUP_DIR` must point outside the project tree. An encrypted archive stored
beside the `.env` that holds `BACKUP_PASSPHRASE` is not a backup, it is a copy:
one folder grab yields both the ciphertext and the key. Keep it out of any
cloud-synced folder too. `POSTGRES_DATA_PATH` is live data, not a backup,
whatever the folder is called.

## Known gaps

These are accepted for a single-machine lab and must be closed before the stack
is reachable from anywhere else.

- **No TLS.** Traffic to `127.0.0.1` cannot be intercepted from the network, so
  a certificate buys nothing here while making every request harder to make.
  `security/certs/openssl.cnf` generates a local certificate in one command
  when it is needed. Note that HSTS must stay off for a `localhost`
  certificate: HSTS is scoped to the host name and ignores the port, so it
  would force HTTPS on every other localhost service on the machine. Strapi's
  helmet default is disabled in `config/middlewares.js` and stripped again at
  the proxy for that reason.
- **Reset tokens are plain text and never expire.** See the section above.
  Mitigated by the purge scripts, not fixed.
- **The refresh token is returned in the JSON body**, not an HttpOnly cookie
  (`sessions.httpOnly: false`), because `api.rest` reads it from the body. Page
  script can therefore read it, so an XSS bug costs a session that lives up to
  `SESSION_MAX_REFRESH_LIFESPAN` rather than just the 10-minute access token.
  Set `SESSION_REFRESH_HTTPONLY=true` in `.env` once no client needs to read
  it.
- **Public registration is open** and Strapi reports whether an email is
  already taken, which allows account enumeration. There is no CAPTCHA.
- **No MFA or SSO** for administrators; Strapi Community Edition does not offer
  either. There is no login lockout on Strapi, only rate limiting.
- **Password reset cannot be completed through email.** The nodemailer sink
  transport discards every message while still writing `reset_password_token`
  to the database, so lab verification means reading that column. Never carry
  that practice into a real deployment.
- **The pgAdmin container has outbound network access**, because a published
  port requires a non-internal Docker network. Its upgrade check is disabled,
  but the egress path exists. PostgreSQL and Strapi's data network do not have
  one.
- **The lab's threat model stops at the host.** Anyone with an account on this
  Windows machine can read `.env`, `api.rest` and `./data/postgres`, and that
  is game over regardless of anything above. Full-disk encryption and a locked
  screen are part of this baseline, not separate from it.

## Before any public deployment

Do not publish this classroom stack directly to the Internet. A real deployment
additionally needs a certificate from a trusted CA with HSTS enabled, a trusted
production email provider, reset tokens that are hashed at rest and expire,
MFA/SSO for administrators, login lockout, CAPTCHA or an upstream
bot-management service, centralized logs and alerts, offsite encrypted backups,
regular patching, and an external security review.

## Upstream dependency status

On 2026-09-02, `npm audit --omit=dev` still reports advisories inherited from
Strapi 5.52.2, including a high-severity Vite development-server advisory and
moderate React Router advisories. This project never runs `strapi develop` or a
Vite server in the runtime image; only the built Strapi production server is
exposed through Nginx. Do not use `npm audit fix --force`, because npm
currently proposes an incompatible Strapi downgrade. Recheck and update when
Strapi publishes compatible dependency fixes:

```
docker compose exec strapi npm run audit:prod
```
