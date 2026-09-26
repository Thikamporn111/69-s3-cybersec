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

## Testing every REST route from `.env`

`api.rest` (and the committed template `api.rest.example`) reads **every** input
-- URL, request headers, and body -- from `.env`. Nothing is pasted into the
file itself; `baseUrl` is built from `APP_HOST` and `APP_PORT`. Fill the values
in `.env` first (see `.env.example` for the full list):

- Admin: `STRAPI_ADMIN_FIRSTNAME`, `STRAPI_ADMIN_LASTNAME`,
  `STRAPI_ADMIN_EMAIL`, `STRAPI_ADMIN_PASSWORD` (Register / Login / Forgot).
- User: `REST_USER_USERNAME`, `REST_USER_EMAIL`, `REST_USER_IDENTIFIER`,
  `REST_USER_PASSWORD`.
- `REST_REMEMBER_ME` for the `rememberMe` field (`true` / `false`).
- New-password targets: `REST_ADMIN_RESET_PASSWORD`, `REST_RESET_PASSWORD`.
- Content payloads (Section 3): `REST_STUDENT_*`, `REST_SUBJECT_*` and
  `REST_TEACHER_*`. Their `REST_*_ID` values are runtime -- fill them from the
  Create responses before List-with-ID / Update (see below).

Two values are runtime and must be written back into `.env` as you go:

- After **Login**, copy the returned Bearer token into `STRAPI_ADMIN_TOKEN`
  (admin) or `REST_USER_TOKEN` (user) before running Profile / Logout.
- After **Forgot Password**, read the reset code from PostgreSQL
  (`reset_password_token` in `admin_users` / `up_users`) and put it into
  `STRAPI_ADMIN_RESET_TOKEN` / `REST_USER_RESET_CODE` before Reset Password.

Run the requests in order; routes that depend on a token or reset code return
401 / 400 until its `.env` value is filled. Never commit `.env` or `api.rest`;
`api.rest.example` and `.env.example` are the safe templates.

## Section 3: content API (student / subject / teacher)

Section 3 of `api.rest` performs Create / List All / List with ID / Update on
three content types. Two things in Strapi have to be prepared first, because
the auth sections never needed them:

1. **Rebuild Strapi** so the content types shipped in `strapi/src/api/`
   (`student`, `subject`, `teacher`) exist in the running instance:

   ```
   docker compose up -d --build strapi
   ```

   Their prototypes live in `strapi/src/api/<name>/content-types/<name>/schema.json`
   and build into the image, so a fresh clone reproduces them without any
   Content-Type Builder work.

2. **Permissions are granted automatically.** On every start the bootstrap in
   `strapi/src/index.js` makes sure the *Authenticated* role has `create`,
   `find`, `findOne` and `update` on *Student*, *Subject* and *Teacher* --
   nothing more: `delete` is not granted and *Public* gets nothing. Section 3
   sends every request with the user Bearer token from `2.2 User Login`, so
   without these grants each request returns `403 Forbidden`. Unticking one of
   these in *Settings > Users & Permissions > Roles* only lasts until the next
   restart; change `strapi/src/index.js` to remove it for good.

Then fill the content values in `.env`:

- `REST_STUDENT_CODE` / `REST_SUBJECT_CODE` / `REST_TEACHER_CODE` are required
  unique fields: a second Create with the same code returns a `400` validation
  error, so use a fresh code per run.
- `REST_SUBJECT_CREDIT` is a JSON number and must not be quoted.
- `REST_STUDENT_ID` / `REST_SUBJECT_ID` / `REST_TEACHER_ID` stay empty until
  the Create requests have run.

Flow: after `2.2 User Login` put a fresh token into `REST_USER_TOKEN`, run
`3.1.1 Create` (plus `3.2.1` and `3.3.1`), copy each response's
`data.documentId` into the matching `REST_*_ID`, then run List All, List with
ID and Update. Strapi 5 identifies one document by its `documentId` -- a
string, not the numeric `id` in the response -- and that is the value the URL
needs.

The admin Bearer token from Section 1 is a separate credential and cannot
authenticate the `/api/*` content routes; the user token from `2.2` is the one
Section 3 reuses.

### Automated check

`run-content-test.cmd` (or `.un-content-test.ps1 -Cleanup`) registers a
throwaway user, logs in, and runs all 12 Section 3 requests, checking each
response body -- the new `documentId`, that List All contains it, that List
with ID returns it, and that Update really changed the field. `-Cleanup`
deletes the test records and user afterwards (in SQL, since the API has no
delete route). It spends 2 of the 10 auth requests a minute.

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
