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

import { authenticate, mintToken } from './auth';
import type { Env, StoredOp } from './types';
import {
  MAX_PHOTO_BYTES,
  ValidationError,
  isEntryId,
  parseOps,
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
      if (path === '/v1/auth/dev' && request.method === 'POST') {
        return await devAuth(request, env);
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
      console.error('unhandled', e);
      return error(500, 'internal error');
    }
  },
} satisfies ExportedHandler<Env>;

/// Dev-only token issuance. Sign in with Apple will be a sibling of this
/// (`/v1/auth/apple`) that verifies Apple's identity JWT and then mints the
/// exact same token — the verification path in auth.ts does not change.
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
    const length = Number(request.headers.get('content-length') ?? '0');
    if (length > MAX_PHOTO_BYTES) return error(413, 'photo is too large');
    if (!request.body) return error(400, 'body is required');

    await env.PHOTOS.put(key, request.body, {
      httpMetadata: { contentType: request.headers.get('content-type') ?? 'image/jpeg' },
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
    const headers = new Headers();
    object.writeHttpMetadata(headers);
    headers.set('etag', object.httpEtag);
    return new Response(object.body, { headers });
  }

  return error(405, 'method not allowed');
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
      console.error('photo cleanup failed', prefix, e);
    }
  }
}
