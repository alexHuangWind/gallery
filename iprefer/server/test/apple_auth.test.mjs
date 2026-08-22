/// Sign in with Apple verification, exercised against real crypto.
///
///   npm run dev            # wrangler dev, reading APPLE_JWKS_URL from .dev.vars
///   node test/apple_auth.test.mjs
///
/// Stands up a JWKS server on :8788 with a throwaway RSA keypair, then signs
/// identity tokens — valid ones and every forgery worth trying. Getting this
/// wrong means anyone can sign in as anyone, so it is tested with real
/// signatures rather than a mock that says "yes".

import { createServer } from 'node:http';
import { createHmac, createSign, generateKeyPairSync } from 'node:crypto';

const BASE = process.env.SYNC_URL ?? 'http://127.0.0.1:8787';
const JWKS_PORT = 8788;
// Unique per run: the Worker caches JWKS by key id, and a fresh keypair under
// a recycled kid would be checked against the previous run's public key.
const KID = `iprefer-test-key-${Date.now()}`;
const AUDIENCE = 'com.iprefer.iprefer';
const ISSUER = 'https://appleid.apple.com';

let passed = 0;
const failures = [];
const check = (name, ok, detail) => {
  if (ok) { passed++; console.log(`  ok  ${name}`); }
  else { failures.push(name); console.log(`FAIL  ${name}${detail ? ` — ${detail}` : ''}`); }
};

const { publicKey, privateKey } = generateKeyPairSync('rsa', { modulusLength: 2048 });
const jwk = { ...publicKey.export({ format: 'jwk' }), kid: KID, alg: 'RS256', use: 'sig' };

const b64 = (o) => Buffer.from(typeof o === 'string' ? o : JSON.stringify(o)).toString('base64url');

/// Builds an identity token. Every parameter has a correct default so each
/// test can break exactly one thing.
function makeToken({
  sub = 'apple-sub-000',
  aud = AUDIENCE,
  iss = ISSUER,
  exp = Math.floor(Date.now() / 1000) + 3600,
  alg = 'RS256',
  kid = KID,
  signWith = 'rsa',
  tamper = false,
  email,
} = {}) {
  const header = b64({ alg, kid, typ: 'JWT' });
  const payload = b64({ sub, aud, iss, exp, iat: Math.floor(Date.now() / 1000), ...(email ? { email } : {}) });
  const signingInput = `${header}.${payload}`;

  let signature;
  if (signWith === 'none') {
    signature = '';
  } else if (signWith === 'hmac') {
    // Algorithm confusion: sign with HMAC using the public key as the secret.
    signature = createHmac('sha256', JSON.stringify(jwk)).update(signingInput).digest('base64url');
  } else {
    signature = createSign('RSA-SHA256').update(signingInput).sign(privateKey).toString('base64url');
  }

  if (tamper) {
    // Keep the valid signature but swap the payload for a different subject.
    const evil = b64({ sub: 'apple-sub-VICTIM', aud, iss, exp, iat: Math.floor(Date.now() / 1000) });
    return `${header}.${evil}.${signature}`;
  }
  return `${signingInput}.${signature}`;
}

const post = async (path, body) => {
  const res = await fetch(`${BASE}${path}`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(body),
  });
  const text = await res.text();
  let json = null;
  try { json = text ? JSON.parse(text) : null; } catch {}
  return { status: res.status, json };
};

const signIn = (opts) => post('/v1/auth/apple', { identityToken: makeToken(opts) });

async function main() {
  const jwks = createServer((req, res) => {
    res.writeHead(200, { 'content-type': 'application/json' });
    res.end(JSON.stringify({ keys: [jwk] }));
  });
  await new Promise((r) => jwks.listen(JWKS_PORT, '127.0.0.1', r));
  console.log(`apple auth tests against ${BASE} (JWKS double on :${JWKS_PORT})\n`);

  try {
    // --- the happy path ---------------------------------------------------
    const sub = `apple-sub-${Date.now()}`;
    const ok = await signIn({ sub, email: 'someone@privaterelay.appleid.com' });
    check('a valid identity token signs in', ok.status === 200, `got ${ok.status} ${JSON.stringify(ok.json)}`);
    check('it returns a session token and a user id',
      typeof ok.json?.token === 'string' && typeof ok.json?.userId === 'string');
    check("the user id is ours, not Apple's sub", ok.json?.userId !== sub, ok.json?.userId);

    const again = await signIn({ sub });
    check('the same Apple subject maps to the same user',
      again.json?.userId === ok.json?.userId, `${again.json?.userId} vs ${ok.json?.userId}`);

    const other = await signIn({ sub: `apple-sub-other-${Date.now()}` });
    check('a different Apple subject is a different user',
      other.json?.userId !== ok.json?.userId);

    // --- the session token actually works ---------------------------------
    const pull = await fetch(`${BASE}/v1/sync/pull?since=0`, {
      headers: { Authorization: `Bearer ${ok.json.token}` },
    });
    check('the issued token authenticates a real request', pull.status === 200, `got ${pull.status}`);

    // --- forgeries --------------------------------------------------------
    const forgeries = [
      ['a token for another app (wrong aud)', { aud: 'com.someone.else' }],
      ['a token from another issuer', { iss: 'https://evil.example.com' }],
      ['an expired token', { exp: Math.floor(Date.now() / 1000) - 60 }],
      ['a tampered payload with a valid signature', { tamper: true }],
      ['an unsigned token (alg none)', { alg: 'none', signWith: 'none' }],
      ['algorithm confusion (HS256 with the public key)', { alg: 'HS256', signWith: 'hmac' }],
      ['a token signed by an unknown key', { kid: 'not-a-real-kid' }],
    ];
    for (const [name, opts] of forgeries) {
      const res = await signIn(opts);
      check(`rejects ${name}`, res.status === 401, `got ${res.status} ${JSON.stringify(res.json)}`);
    }

    for (const [name, body] of [
      ['a missing token', {}],
      ['a non-string token', { identityToken: 42 }],
      ['a token that is not a JWT', { identityToken: 'hello' }],
      ['a JWT with garbage segments', { identityToken: 'a.b.c' }],
    ]) {
      const res = await post('/v1/auth/apple', body);
      check(`rejects ${name}`, res.status === 401, `got ${res.status}`);
    }

    // --- the dev hatch still exists locally, and is separate ---------------
    const dev = await post('/v1/auth/dev', { localId: 'apple-test-dev' });
    check('the dev hatch is still available locally', dev.status === 200);
  } finally {
    jwks.close();
  }

  console.log(`\n${passed} passed, ${failures.length} failed`);
  if (failures.length) { console.log('failed:', failures.join(', ')); process.exit(1); }
}

main().catch((e) => {
  console.error('\ntest run crashed:', e.message);
  console.error('is `npm run dev` running?');
  process.exit(1);
});
