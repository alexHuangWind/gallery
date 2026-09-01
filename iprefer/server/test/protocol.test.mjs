/// End-to-end protocol tests against a running `wrangler dev`.
///
///   npm run db:local     # once, to create the tables in the local D1
///   npm run dev          # in one terminal
///   npm test             # in another
///
/// Plain node, no test framework: this exercises the real Worker over real
/// HTTP with real D1 and R2 bindings, which is the part worth proving.

const BASE = process.env.SYNC_URL ?? 'http://127.0.0.1:8787';

let passed = 0;
const failures = [];

function check(name, condition, detail) {
  if (condition) {
    passed++;
    console.log(`  ok  ${name}`);
  } else {
    failures.push(name);
    console.log(`FAIL  ${name}${detail ? ` — ${detail}` : ''}`);
  }
}

const eq = (name, actual, expected) =>
  check(name, JSON.stringify(actual) === JSON.stringify(expected), `got ${JSON.stringify(actual)}, want ${JSON.stringify(expected)}`);

async function api(path, { token, method = 'GET', body, raw, contentType } = {}) {
  const headers = {};
  if (token) headers.Authorization = `Bearer ${token}`;
  if (body !== undefined) headers['content-type'] = 'application/json';
  if (contentType) headers['content-type'] = contentType;
  const res = await fetch(`${BASE}${path}`, {
    method,
    headers,
    body: raw ?? (body !== undefined ? JSON.stringify(body) : undefined),
  });
  const text = await res.text();
  let json = null;
  try { json = text ? JSON.parse(text) : null; } catch { /* binary or empty */ }
  return { status: res.status, json, text, res };
}

const entry = (id, over = {}) => ({
  id,
  text: 'ferns that uncurl like a slow question',
  createdAt: 1755000000000,
  latitude: -36.8485,
  longitude: 174.7633,
  placeLabel: 'fitzroy',
  tags: ['plants'],
  photoName: `${id}.jpg`,
  ...over,
});

async function main() {
  console.log(`sync protocol tests against ${BASE}\n`);

  // --- health -------------------------------------------------------------
  const health = await api('/v1/health');
  eq('health responds', health.json, { ok: true });

  // --- auth ---------------------------------------------------------------
  const anon = await api('/v1/sync/pull?since=0');
  eq('pull without a token is 401', anon.status, 401);

  const forged = await api('/v1/sync/pull?since=0', { token: 'not.atoken' });
  eq('pull with a forged token is 401', forged.status, 401);

  // Fresh identities each run so repeated runs stay independent.
  const aliceLocal = `alice-${crypto.randomUUID()}`;
  const bobLocal = `bob-${crypto.randomUUID()}`;
  const alice = (await api('/v1/auth/dev', { method: 'POST', body: { localId: aliceLocal } })).json;
  const bob = (await api('/v1/auth/dev', { method: 'POST', body: { localId: bobLocal } })).json;
  check('dev auth issues a token', typeof alice?.token === 'string' && alice.token.includes('.'));

  const stable = (await api('/v1/auth/dev', { method: 'POST', body: { localId: aliceLocal } })).json;
  eq('same localId maps to the same user', stable.userId, alice.userId);

  // --- push / pull --------------------------------------------------------
  const id1 = crypto.randomUUID();
  const id2 = crypto.randomUUID();

  const pushed = await api('/v1/sync/push', {
    token: alice.token,
    method: 'POST',
    body: { ops: [
      { type: 'create', entryId: id1, payload: entry(id1) },
      { type: 'create', entryId: id2, payload: entry(id2, { text: 'a flat white before the world wakes up', latitude: null, longitude: null, placeLabel: null, tags: [] }) },
    ] },
  });
  eq('push applies two creates', pushed.json?.applied, 2);

  const pulled = await api(`/v1/sync/pull?since=0`, { token: alice.token });
  eq('pull returns both ops', pulled.json?.ops?.length, 2);
  eq('pull preserves the entry text', pulled.json?.ops?.[0]?.payload?.text, entry(id1).text);
  eq('pull preserves a null fix', pulled.json?.ops?.[1]?.payload?.latitude, null);
  eq('pull reports no more pages', pulled.json?.hasMore, false);
  check('seq is monotonic', pulled.json.ops[1].seq > pulled.json.ops[0].seq);

  const cursor = pulled.json.seq;
  const empty = await api(`/v1/sync/pull?since=${cursor}`, { token: alice.token });
  eq('pulling from the cursor returns nothing new', empty.json?.ops?.length, 0);
  eq('an empty pull holds the cursor', empty.json?.seq, cursor);

  // --- idempotency --------------------------------------------------------
  const replay = await api('/v1/sync/push', {
    token: alice.token,
    method: 'POST',
    body: { ops: [{ type: 'create', entryId: id1, payload: entry(id1) }] },
  });
  eq('re-pushing an op applies nothing', replay.json?.applied, 0);
  const afterReplay = await api(`/v1/sync/pull?since=0`, { token: alice.token });
  eq('re-pushing creates no duplicate row', afterReplay.json?.ops?.length, 2);

  // --- photos -------------------------------------------------------------
  const bytes = new Uint8Array(2048).map((_, i) => i % 251);
  const put = await api(`/v1/photos/${id1}.jpg`, {
    token: alice.token, method: 'PUT', raw: bytes, contentType: 'image/jpeg',
  });
  eq('photo upload returns 204', put.status, 204);

  const head = await api(`/v1/photos/${id1}.jpg`, { token: alice.token, method: 'HEAD' });
  eq('HEAD finds the photo', head.status, 200);

  const got = await fetch(`${BASE}/v1/photos/${id1}.jpg`, {
    headers: { Authorization: `Bearer ${alice.token}` },
  });
  const back = new Uint8Array(await got.arrayBuffer());
  eq('photo download returns the same bytes', [back.length, back[0], back[1000]], [bytes.length, bytes[0], bytes[1000]]);

  const missing = await api(`/v1/photos/${id2}.jpg`, { token: alice.token });
  eq('an unuploaded photo is 404', missing.status, 404);

  // --- tenant isolation ---------------------------------------------------
  const bobPull = await api('/v1/sync/pull?since=0', { token: bob.token });
  eq("another user sees none of alice's ops", bobPull.json?.ops?.length, 0);

  const bobSteal = await api(`/v1/photos/${id1}.jpg`, { token: bob.token });
  eq("another user cannot read alice's photo", bobSteal.status, 404);

  // --- delete -------------------------------------------------------------
  const del = await api('/v1/sync/push', {
    token: alice.token, method: 'POST', body: { ops: [{ type: 'delete', entryId: id1 }] },
  });
  eq('delete applies', del.json?.applied, 1);

  const afterDelete = await api(`/v1/sync/pull?since=${cursor}`, { token: alice.token });
  eq('the delete arrives after the cursor', afterDelete.json?.ops?.length, 1);
  eq('the delete op has no payload', afterDelete.json?.ops?.[0]?.payload, null);
  check(
    'delete sorts after its create',
    afterDelete.json.ops[0].seq > pulled.json.ops[0].seq,
  );

  // Cleanup runs in waitUntil, so give it a moment.
  let cleaned = false;
  for (let i = 0; i < 20 && !cleaned; i++) {
    await new Promise((r) => setTimeout(r, 100));
    cleaned = (await api(`/v1/photos/${id1}.jpg`, { token: alice.token, method: 'HEAD' })).status === 404;
  }
  check('deleting an entry removes its photo', cleaned);

  // --- pagination ---------------------------------------------------------
  const page = await api('/v1/sync/pull?since=0&limit=1', { token: alice.token });
  eq('limit is honoured', page.json?.ops?.length, 1);
  eq('hasMore is set when truncated', page.json?.hasMore, true);
  eq('the cursor stops at the last returned op', page.json?.seq, page.json.ops[0].seq);

  // --- validation ---------------------------------------------------------
  const bad = [
    ['a non-uuid entry id', { ops: [{ type: 'create', entryId: 'nope', payload: entry(id1) }] }],
    ['a mismatched payload id', { ops: [{ type: 'create', entryId: id2, payload: entry(id1) }] }],
    ['an unknown op type', { ops: [{ type: 'update', entryId: id1 }] }],
    ['empty text', { ops: [{ type: 'create', entryId: id2, payload: entry(id2, { text: '' }) }] }],
    ['half a location', { ops: [{ type: 'create', entryId: id2, payload: entry(id2, { longitude: null }) }] }],
    ['a photo name for another entry', { ops: [{ type: 'create', entryId: id2, payload: entry(id2, { photoName: `${id1}.jpg` }) }] }],
    ['an out-of-range latitude', { ops: [{ type: 'create', entryId: id2, payload: entry(id2, { latitude: 120 }) }] }],
  ];
  for (const [name, body] of bad) {
    const res = await api('/v1/sync/push', { token: alice.token, method: 'POST', body });
    eq(`rejects ${name}`, res.status, 400);
  }

  const badPhoto = await api(`/v1/photos/${id1}.exe`, {
    token: alice.token, method: 'PUT', raw: new Uint8Array(4),
  });
  check('rejects a suspicious photo extension', badPhoto.status === 400, `got ${badPhoto.status}`);

  const traversal = await api('/v1/photos/..%2F..%2Fetc%2Fpasswd', { token: alice.token });
  check('rejects path traversal in a photo name', traversal.status === 400, `got ${traversal.status}`);

  // --- report -------------------------------------------------------------
  console.log(`\n${passed} passed, ${failures.length} failed`);
  if (failures.length) {
    console.log('failed:', failures.join(', '));
    process.exit(1);
  }
}

main().catch((e) => {
  console.error('\ntest run crashed:', e.message);
  console.error('is `npm run dev` running, and has `npm run db:local` been applied?');
  process.exit(1);
});
