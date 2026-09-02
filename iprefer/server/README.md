# iprefer-sync

The sync backend. Cloudflare Workers + D1 (records) + R2 (photos).

**Deployed:** `https://iprefer-sync.alex-apps.workers.dev`
(D1 `iprefer-sync`, R2 `iprefer-photos`, account alexnz.2046@gmail.com)

Two ways to get a token: `/v1/auth/apple` (Sign in with Apple — the real
path) and `/v1/auth/dev` (guarded by `DEV_AUTH`, which only ever lives in
`.dev.vars` and therefore never reaches production — see "Deploying").

Nothing about the phone changes: it stays the source of truth and never blocks
on this service. This is the other half — the part that means a reinstall or a
second device doesn't lose the archive.

## Why this shape

**Entries are created and deleted, never edited** (`CLAUDE.md` excludes edit
history). That single product fact collapses the hard part of sync: there is no
field-level merge, no last-write-wins, no vector clocks. The server is an
append-only op log per user, and the client replays it in `seq` order.

Photos go to R2 rather than D1 because a D1 row caps at 1 MB and the free tier
is 500 MB per database — but mostly because **R2 charges nothing for egress**,
and re-downloading an archive onto a new phone is the only real traffic this
service will ever see.

## Endpoints

| | |
|---|---|
| `GET /v1/health` | liveness |
| `POST /v1/auth/apple` | Sign in with Apple → `{token, userId}` |
| `POST /v1/auth/dev` | dev-only token issuance (`DEV_AUTH=1`) |
| `POST /v1/sync/push` | `{ops:[…]}` → `{applied, seq}`; idempotent |
| `GET /v1/sync/pull?since=&limit=` | → `{ops:[…], seq, hasMore}` |
| `PUT/GET/HEAD /v1/photos/<entryId>.<ext>` | photo blob, scoped to the caller |
| `DELETE /v1/account` | erases the account; 204, idempotent |

### Photos

`PUT` requires three things beyond a valid token:

- **a `create` op for that entry already pushed**, else **409**. Otherwise a
  token is a licence to fill R2 with objects for entry ids that never existed,
  and nothing would ever collect them — cleanup is driven by `delete` ops for
  entries that do. The client already satisfies this: `sync_service.dart`
  pushes the outbox before it uploads photos.
- **a `Content-Length`**, else **411**. A chunked body used to read as zero
  bytes, clear the size cap, and then hand R2 an unsized stream, which threw a
  500. Over `MAX_PHOTO_BYTES` is still **413**.
- nothing at all from the request's `Content-Type`: the stored and served type
  is derived from the (allowlisted) extension. Serving back an uploader's own
  `text/html` under a `.jpg` name is stored XSS. `GET` also sets
  `X-Content-Type-Options: nosniff`.

### Account deletion

App Store Guideline 5.1.1(v): an app offering account creation must offer
in-app deletion. `DELETE /v1/account` removes the user's ops, every R2 object
under `<userId>/`, and finally the `users` row — 204 either way, so a client
that never saw the first response can simply ask again.

Losing the `users` row is also what ends the session: `authenticate` checks the
account still exists, which costs a primary-key lookup per request and buys
immediate revocation of tokens that would otherwise stay valid for 30 days.
`DELETE /v1/account` itself checks only the token's signature — the row is what
it removes, so demanding the row would make the second call a 401.

**Not done:** revoking the Sign in with Apple grant
(`POST https://appleid.apple.com/auth/revoke`), which Apple also expects. It
needs a Services ID, a `.p8` private key and its key id to sign a
`client_secret` with, none of which exist yet. There is a `TODO` at the handler.

### The cursor rule

`push` reports the seq it wrote. **The client must not use it as the pull
cursor.** Another device's op can hold a lower seq that this client hasn't seen;
jumping the cursor forward would skip it permanently. The pull cursor advances
only from a pull response. Re-receiving your own op is harmless — applying
`create` for an entry you already have is a no-op.

### Idempotency

A unique index on `(user_id, entry_id, type)` plus `INSERT OR IGNORE` means a
retried push after a dropped response writes nothing twice. No client-side
dedupe needed.

## Running locally

```bash
npm install
npm run dev          # wrangler dev on :8787
npm test             # 54 protocol + 22 Sign in with Apple tests
```

`npm test` needs nothing running: a `pretest` applies `schema.sql` to the
local D1 and starts its own `wrangler dev` on :8787, and a `posttest` stops it
again. Point `SYNC_URL` at a server you started yourself to opt out. One
caveat — npm skips `posttest` when the tests fail, so a red run leaves the
server up; the next `npm test` reclaims it (or `npm run test:stop`).

The tests are plain node against real HTTP with real D1/R2 bindings — they
cover auth, idempotency, tenant isolation, delete-and-photo-cleanup,
pagination, input validation, account deletion, and every Apple token forgery
worth trying.

`APPLE_JWKS_URL` is **not** in `.dev.vars`. It used to pin the test double's
address, so a plain `wrangler dev` with no test running answered
`/v1/auth/apple` with a 500 from a refused fetch. The launcher passes it as a
`--var` instead, so the override lives exactly as long as the double does.

## Auth

Session tokens are HMAC-signed bearer tokens (`auth.ts`). That path is the real
one already; only *issuance* has a dev shortcut. Sign in with Apple slots in as
`/v1/auth/apple`: verify Apple's identity JWT against
`https://appleid.apple.com/auth/keys`, map `sub` → `users.apple_sub`, then call
the same `mintToken`. Nothing that guards a request changes.

`SESSION_SECRET` falls back to a fixed dev value **only** when `DEV_AUTH=1`. In
production `DEV_AUTH` is absent, so a missing secret is a hard failure rather
than a quietly insecure default.

Apple's keys are cached per isolate for an hour. An unseen `kid` — how rotation
normally shows up — forces a refetch, but at most one per isolate per five
minutes (`APPLE_JWKS_REFETCH_COOLDOWN_MS`, overridden only by the tests).
Without that ceiling, `/v1/auth/apple` is unauthenticated and a bogus `kid`
costs nothing, so every forged token became one outbound request to
appleid.apple.com. Rotation still recovers unattended, one window later.

## Deploying

```bash
npx wrangler deploy
```

Resources already exist; `SESSION_SECRET` is set as a secret. Verified after
the first deploy: `/v1/health` is 200, `/v1/auth/dev` is **404**, every other
route without a valid token is **401** — including a token correctly signed
with the dev fallback secret, which proves production is using the real one.

## Not done yet

Sign in with Apple, sync wired into app startup, and the app-side account
deletion item are all done — see `iprefer/README.md`'s "Accounts and sync".
What's actually left:

- Revoking the Sign in with Apple grant on account deletion — see the
  "Account deletion" section above; blocked on a Services ID and a `.p8` key
  this project doesn't have.
