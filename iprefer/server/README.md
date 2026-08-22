# iprefer-sync

The sync backend. Cloudflare Workers + D1 (records) + R2 (photos).

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
| `POST /v1/auth/dev` | dev-only token issuance (`DEV_AUTH=1`) |
| `POST /v1/sync/push` | `{ops:[…]}` → `{applied, seq}`; idempotent |
| `GET /v1/sync/pull?since=&limit=` | → `{ops:[…], seq, hasMore}` |
| `PUT/GET/HEAD /v1/photos/<entryId>.<ext>` | photo blob, scoped to the caller |

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
npm run db:local     # apply schema.sql to the local D1
npm run dev          # wrangler dev on :8787
npm test             # 38 protocol tests against the running dev server
```

The tests are plain node against real HTTP with real D1/R2 bindings — they
cover auth, idempotency, tenant isolation, delete-and-photo-cleanup,
pagination, and input validation.

## Auth

Session tokens are HMAC-signed bearer tokens (`auth.ts`). That path is the real
one already; only *issuance* has a dev shortcut. Sign in with Apple slots in as
`/v1/auth/apple`: verify Apple's identity JWT against
`https://appleid.apple.com/auth/keys`, map `sub` → `users.apple_sub`, then call
the same `mintToken`. Nothing that guards a request changes.

`SESSION_SECRET` falls back to a fixed dev value **only** when `DEV_AUTH=1`. In
production `DEV_AUTH` is absent, so a missing secret is a hard failure rather
than a quietly insecure default.

## Not done yet

- Sign in with Apple (needs a Services ID + key from the Apple account)
- Deploy (needs `wrangler d1 create` / `r2 bucket create`, and dropping
  `DEV_AUTH` + setting a real `SESSION_SECRET`)
- The Flutter client's outbox / tombstones / sync service
