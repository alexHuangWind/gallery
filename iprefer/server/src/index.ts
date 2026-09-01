/// iPrefer sync API.
///
/// Contract, in one paragraph: the phone is the source of truth and never
/// blocks on this service. Entries are created and deleted, never edited, so
/// the server is an append-only op log per user. Clients push their pending
/// ops (idempotent) and pull everything after a cursor. Photos live in R2,
/// keyed `<userId>/<entryId>.<ext>`, and travel separately from records
/// because they are four orders of magnitude bigger.
///
/// CURSOR RULE — the subtle part. `push` reports the seq it wrote, but the
/// client must NOT advance its pull cursor to it. Another device's op may
/// hold a lower seq that this client has not seen yet; jumping the cursor
/// forward would skip it forever. The pull cursor advances only from a pull
/// response. Re-receiving your own op is harmless: applying `create` for an
/// entry you already have is a no-op.

import { AppleAuthError, verifyAppleIdentityToken } from './apple';
import { authenticate, authenticateToken, mintToken } from './auth';
import type { Env, StoredOp } from './types';
import {
  MAX_PHOTO_BYTES,
  ValidationError,
  isEntryId,
  parseOps,
  photoContentType,
  photoNameFor,
} from './validate';

const DEFAULT_PULL_LIMIT = 200;
const MAX_PULL_LIMIT = 500;

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8' },
  });

const error = (status: number, message: string) => json({ error: message }, status);

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const url = new URL(request.url);
    const path = url.pathname;

    try {
      if (path === '/v1/health') return json({ ok: true });

      // Every handler below is `return await` on purpose: returning the
      // promise bare would let a rejection escape this try/catch entirely
      // (the try block has already exited by then), turning every
      // ValidationError into a 500.
      if (path === '/v1/auth/apple' && request.method === 'POST') {
        return await appleAuth(request, env);
      }
      if (path === '/v1/auth/dev' && request.method === 'POST') {
        return await devAuth(request, env);
      }

      // Account deletion authenticates on the token alone, without the
      // "account still exists" half of `authenticate`. The row is exactly what
      // this endpoint removes, so requiring it would make the second call 401
      // — and an idempotent delete owes a 204 whether or not it is the first
      // one to arrive.
      if (path === '/v1/account' && request.method === 'DELETE') {
        const owner = await authenticateToken(request, env);
        if (!owner) return error(401, 'unauthorized');
        return await deleteAccount(env, owner);
      }

      // Everything below needs a session.
      const userId = await authenticate(request, env);
      if (!userId) return error(401, 'unauthorized');

      if (path === '/v1/sync/push' && request.method === 'POST') {
        return await push(request, env, userId, ctx);
      }
      if (path === '/v1/sync/pull' && request.method === 'GET') {
        return await pull(url, env, userId);
      }
      if (path.startsWith('/v1/photos/')) {
        return await photos(
          request,
          env,
          userId,
          decodeURIComponent(path.slice('/v1/photos/'.length)),
        );
      }

      return error(404, 'not found');
    } catch (e) {
      if (e instanceof ValidationError) return error(400, e.message);
      // A token we won't accept is a 401, and the reason is safe to say: it
      // tells an honest client what to fix and tells an attacker nothing they
      // couldn't determine by trying.
      if (e instanceof AppleAuthError) return error(401, e.message);
      console.error('unhandled', e);
      return error(500, 'internal error');
    }
  },
} satisfies ExportedHandler<Env>;

/// Sign in with Apple. Exchanges Apple's identity token for one of ours.
///
/// Apple's `sub` is stable per developer account, but it stays internal: our
/// user id is our own uuid, so nothing downstream is coupled to an identity
/// provider we might not be the only one of forever.
async function appleAuth(request: Request, env: Env): Promise<Response> {
  const body = (await request.json().catch(() => null)) as
      { identityToken?: unknown } | null;

  const identity = await verifyAppleIdentityToken(env, body?.identityToken);

  // INSERT OR IGNORE against the UNIQUE apple_sub, then read back: two
  // simultaneous first sign-ins from two devices settle on one user rather
  // than racing to create two.
  await env.DB.prepare(
    'INSERT OR IGNORE INTO users (id, apple_sub, created_at) VALUES (?, ?, ?)',
  )
    .bind(crypto.randomUUID(), identity.sub, Date.now())
    .run();

  const row = await env.DB.prepare('SELECT id FROM users WHERE apple_sub = ?')
    .bind(identity.sub)
    .first<{ id: string }>();
  if (!row) return error(500, 'could not resolve the account');

  return json({ token: await mintToken(env, row.id), userId: row.id });
}

/// Dev-only token issuance: the same token, minted without Apple, for local
/// work. Guarded by DEV_AUTH, which lives in .dev.vars and is therefore never
/// deployed.
async function devAuth(request: Request, env: Env): Promise<Response> {
  if (env.DEV_AUTH !== '1') return error(404, 'not found');

  const body = (await request.json().catch(() => null)) as { localId?: unknown } | null;
  const localId = typeof body?.localId === 'string' ? body.localId : null;
  if (!localId) return error(400, 'localId is required');

  // Stable: the same localId always maps to the same user, so a dev client
  // that restarts keeps its archive.
  const userId = `dev-${localId}`;
  await env.DB.prepare('INSERT OR IGNORE INTO users (id, apple_sub, created_at) VALUES (?, NULL, ?)')
    .bind(userId, Date.now())
    .run();

  return json({ token: await mintToken(env, userId), userId });
}

async function push(
  request: Request,
  env: Env,
  userId: string,
  ctx: ExecutionContext,
): Promise<Response> {
  const ops = parseOps(await request.json().catch(() => null));
  if (ops.length === 0) return json({ applied: 0, seq: await highestSeq(env, userId) });

  const now = Date.now();
  // INSERT OR IGNORE + the unique index is the whole idempotency story: a
  // retried push after a dropped response writes nothing twice.
  const insert = env.DB.prepare(
    'INSERT OR IGNORE INTO ops (user_id, entry_id, type, payload, created_at) VALUES (?, ?, ?, ?, ?)',
  );
  const statements = ops.map((op) =>
    insert.bind(userId, op.entryId, op.type, op.payload ? JSON.stringify(op.payload) : null, now),
  );

  const results = await env.DB.batch(statements);
  const applied = results.reduce((n, r) => n + (r.meta?.changes ?? 0), 0);

  // A deleted entry's photo is garbage. Mirror the client's ordering: the
  // record is authoritative and goes first, the blob is cleaned up after and
  // is allowed to fail — an orphaned object costs storage, an orphaned record
  // would be a broken tile.
  const deletedKeys = ops.filter((o) => o.type === 'delete').map((o) => `${userId}/${o.entryId}`);
  if (deletedKeys.length > 0) {
    ctx.waitUntil(deletePhotosByPrefix(env, deletedKeys));
  }

  return json({ applied, seq: await highestSeq(env, userId) });
}

async function pull(url: URL, env: Env, userId: string): Promise<Response> {
  const since = Number(url.searchParams.get('since') ?? '0');
  if (!Number.isFinite(since) || since < 0) return error(400, 'since must be a non-negative number');

  const requested = Number(url.searchParams.get('limit') ?? DEFAULT_PULL_LIMIT);
  const limit = Math.min(
    Number.isFinite(requested) && requested > 0 ? Math.trunc(requested) : DEFAULT_PULL_LIMIT,
    MAX_PULL_LIMIT,
  );

  // limit + 1 so hasMore needs no second query.
  const { results } = await env.DB.prepare(
    'SELECT seq, entry_id, type, payload FROM ops WHERE user_id = ? AND seq > ? ORDER BY seq ASC LIMIT ?',
  )
    .bind(userId, Math.trunc(since), limit + 1)
    .all<{ seq: number; entry_id: string; type: string; payload: string | null }>();

  const rows = results ?? [];
  const hasMore = rows.length > limit;
  const page = hasMore ? rows.slice(0, limit) : rows;

  const ops: StoredOp[] = page.map((r) => ({
    seq: r.seq,
    entryId: r.entry_id,
    type: r.type as StoredOp['type'],
    payload: r.payload ? JSON.parse(r.payload) : null,
  }));

  return json({
    ops,
    // Only advance to what we actually returned; with hasMore the client
    // simply pulls again from here.
    seq: ops.length > 0 ? ops[ops.length - 1].seq : Math.trunc(since),
    hasMore,
  });
}

async function photos(
  request: Request,
  env: Env,
  userId: string,
  name: string,
): Promise<Response> {
  const dot = name.lastIndexOf('.');
  const entryId = dot > 0 ? name.slice(0, dot) : '';
  if (!isEntryId(entryId)) return error(400, 'photo name must be <entryId>.<ext>');
  photoNameFor(entryId, name); // throws ValidationError on a bad extension

  // Keyed under the user: one account can never address another's blob.
  const key = `${userId}/${name}`;

  if (request.method === 'PUT') {
    // Headers first, before the lookup below: these cost nothing, and a flood
    // of malformed uploads should not each buy themselves a database query.
    //
    // A chunked request carries no content-length. The old `?? '0'` read that
    // as zero, waved it straight past the cap, and then handed R2 a stream of
    // unknown length, which throws — a 500 for a request we should simply have
    // refused. Requiring the length makes the cap mean something and makes the
    // refusal a 411.
    const declared = request.headers.get('content-length');
    const length = declared === null ? Number.NaN : Number(declared);
    if (!Number.isFinite(length) || length < 0) {
      return error(411, 'content-length is required');
    }
    if (length > MAX_PHOTO_BYTES) return error(413, 'photo is too large');
    if (!request.body) return error(400, 'body is required');

    // A photo only means anything for an entry this account has actually
    // pushed. Without the check a valid token is a licence to fill R2 with
    // objects for invented entry ids — and nothing would ever remove them,
    // because cleanup is driven by `delete` ops for entries that exist. The
    // client's own ordering already satisfies this: sync_service.dart pushes
    // the outbox and only then uploads photos.
    if (!(await hasCreateOp(env, userId, entryId))) {
      return error(409, 'push the entry before its photo');
    }

    await env.PHOTOS.put(key, request.body, {
      // From the extension, never from the request's own Content-Type header.
      httpMetadata: { contentType: photoContentType(name) },
    });
    return new Response(null, { status: 204 });
  }

  if (request.method === 'HEAD') {
    const head = await env.PHOTOS.head(key);
    return new Response(null, { status: head ? 200 : 404 });
  }

  if (request.method === 'GET') {
    const object = await env.PHOTOS.get(key);
    if (!object) return error(404, 'not found');
    // Derived from the name we just validated rather than read back off the
    // object: anything stored before the PUT above started deriving it still
    // carries whatever type its uploader claimed. nosniff then stops a browser
    // second-guessing us and content-sniffing its way to the same place.
    return new Response(object.body, {
      headers: {
        'content-type': photoContentType(name),
        'x-content-type-options': 'nosniff',
        etag: object.httpEtag,
      },
    });
  }

  return error(405, 'method not allowed');
}

/// Erases the account: every op, every photo, the user row itself.
///
/// App Store Guideline 5.1.1(v) — an app that lets you create an account must
/// let you delete it from inside the app, not by emailing someone. Idempotent,
/// because the client has no way to tell a dropped response from a refusal and
/// will simply ask again.
///
/// TODO(sign-in-with-apple): Apple also expects the Sign in with Apple grant
/// itself to be revoked on deletion, via POST https://appleid.apple.com/auth/
/// revoke. That call needs a Services ID, a private key (.p8) and its key id,
/// to sign the client_secret JWT with — none of which exist for this account
/// yet, so it is deliberately not attempted here. Until the owner provisions
/// them, deletion removes everything on our side but leaves Apple's grant
/// standing: the same person signing in again lands on a brand new user id
/// with an empty archive, which is correct but not the whole obligation.
async function deleteAccount(env: Env, userId: string): Promise<Response> {
  // Records first — they are what the client reads, and photos are only
  // reachable through them. An interrupted delete therefore leaves invisible
  // blobs (which the retry collects) rather than entries pointing at nothing.
  await env.DB.prepare('DELETE FROM ops WHERE user_id = ?').bind(userId).run();

  await deleteAllPhotos(env, userId);

  // The user row goes last because losing it is what stops this account's
  // tokens working everywhere else (see `authenticate`). Removing it first
  // would revoke the session in the middle of the deletion it is performing.
  await env.DB.prepare('DELETE FROM users WHERE id = ?').bind(userId).run();

  // Nothing here is swallowed: unlike the best-effort cleanup after a delete
  // op, a half-finished account deletion must be a 5xx so the client retries.
  return new Response(null, { status: 204 });
}

/// Every object this account owns. R2 lists a page at a time, so this pages —
/// an archive of a few thousand photos is entirely plausible. The trailing
/// slash is load-bearing: a bare `dev-alice` prefix would also match
/// `dev-alice2/…`.
async function deleteAllPhotos(env: Env, userId: string): Promise<void> {
  let cursor: string | undefined;
  do {
    const listed = await env.PHOTOS.list({ prefix: `${userId}/`, cursor });
    const keys = listed.objects.map((o) => o.key);
    if (keys.length > 0) await env.PHOTOS.delete(keys);
    cursor = listed.truncated ? listed.cursor : undefined;
  } while (cursor);
}

/// Has this account ever pushed a `create` for this entry? Gates photo
/// uploads. Deliberately not "…and no `delete` since": a delete op racing an
/// in-flight upload would then 409 forever, and the client has no way to
/// abandon a photo it keeps being told to retry. An orphan from that race is
/// collected by the next delete op's cleanup anyway.
async function hasCreateOp(env: Env, userId: string, entryId: string): Promise<boolean> {
  const row = await env.DB.prepare(
    "SELECT 1 AS ok FROM ops WHERE user_id = ? AND entry_id = ? AND type = 'create'",
  )
    .bind(userId, entryId)
    .first<{ ok: number }>();
  return row !== null;
}

async function highestSeq(env: Env, userId: string): Promise<number> {
  const row = await env.DB.prepare('SELECT MAX(seq) AS seq FROM ops WHERE user_id = ?')
    .bind(userId)
    .first<{ seq: number | null }>();
  return row?.seq ?? 0;
}

/// Photo keys are `<userId>/<entryId>` plus an extension we do not know here,
/// so list the prefix and delete what is actually there.
async function deletePhotosByPrefix(env: Env, prefixes: string[]): Promise<void> {
  for (const prefix of prefixes) {
    try {
      const listed = await env.PHOTOS.list({ prefix });
      const keys = listed.objects.map((o) => o.key);
      if (keys.length > 0) await env.PHOTOS.delete(keys);
    } catch (e) {
      // Not the prefix: it is `<userId>/<entryId>`, and a storage hiccup is
      // not worth writing an account identifier into a retained log.
      console.error('photo cleanup failed', e);
    }
  }
}
