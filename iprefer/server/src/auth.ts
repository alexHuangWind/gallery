/// Session tokens.
///
/// The verification path here is the real one from day one — an HMAC-signed
/// bearer token carrying a uid and an expiry. Only the *issuance* has a
/// dev shortcut (see `/v1/auth/dev` in index.ts), so nothing about the code
/// that guards every request changes when Sign in with Apple lands.
///
/// Sign in with Apple then becomes just another way to obtain the same token:
/// verify Apple's identity JWT against https://appleid.apple.com/auth/keys,
/// map `sub` -> users.apple_sub, and call `mintToken` with that user's id.

import type { Env } from './types';

const TOKEN_TTL_SECONDS = 60 * 60 * 24 * 30; // 30 days

const enc = new TextEncoder();

function b64urlEncode(bytes: Uint8Array): string {
  let s = '';
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function b64urlDecode(s: string): Uint8Array {
  const padded = s.replace(/-/g, '+').replace(/_/g, '/');
  const bin = atob(padded + '='.repeat((4 - (padded.length % 4)) % 4));
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

/// Local dev runs with no configured secret so `wrangler dev` works from a
/// fresh clone. In production DEV_AUTH is absent, so a missing secret is a
/// hard failure rather than a silently insecure default.
function sessionSecret(env: Env): string {
  if (env.SESSION_SECRET) return env.SESSION_SECRET;
  if (env.DEV_AUTH === '1') return 'dev-only-insecure-secret';
  throw new Error('SESSION_SECRET is not configured');
}

async function key(env: Env): Promise<CryptoKey> {
  return crypto.subtle.importKey(
    'raw',
    enc.encode(sessionSecret(env)),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign', 'verify'],
  );
}

/// `<base64url(payload)>.<base64url(hmac)>`
export async function mintToken(env: Env, userId: string): Promise<string> {
  const payload = JSON.stringify({
    uid: userId,
    exp: Math.floor(Date.now() / 1000) + TOKEN_TTL_SECONDS,
  });
  const body = b64urlEncode(enc.encode(payload));
  const sig = await crypto.subtle.sign('HMAC', await key(env), enc.encode(body));
  return `${body}.${b64urlEncode(new Uint8Array(sig))}`;
}

/// Returns the user id, or null if the token is missing, malformed, forged,
/// or expired. Never throws — a bad token is a 401, not a 500.
export async function verifyToken(env: Env, token: string | null): Promise<string | null> {
  if (!token) return null;
  const dot = token.indexOf('.');
  if (dot <= 0) return null;
  const body = token.slice(0, dot);
  const sig = token.slice(dot + 1);

  try {
    const ok = await crypto.subtle.verify(
      'HMAC',
      await key(env),
      b64urlDecode(sig),
      enc.encode(body),
    );
    if (!ok) return null;

    const claims = JSON.parse(new TextDecoder().decode(b64urlDecode(body)));
    if (typeof claims.uid !== 'string' || typeof claims.exp !== 'number') return null;
    if (claims.exp < Math.floor(Date.now() / 1000)) return null;
    return claims.uid;
  } catch {
    return null;
  }
}

/// Pulls the bearer token off a request and checks its signature and expiry —
/// and nothing else. Says nothing about whether the account still exists, so
/// only `DELETE /v1/account` uses it directly (see index.ts for why).
export async function authenticateToken(request: Request, env: Env): Promise<string | null> {
  const header = request.headers.get('Authorization');
  if (!header?.startsWith('Bearer ')) return null;
  return verifyToken(env, header.slice('Bearer '.length).trim());
}

/// What every guarded route uses: a valid token AND an account that still
/// exists.
///
/// The second half is what makes account deletion take effect at once. These
/// tokens are stateless HMACs with a thirty day life, so with the signature
/// check alone a deleted user's phone could go on pushing ops for a month
/// after the account was erased. A primary-key lookup per request is a real
/// cost, but this service serves one phone per account and the alternative is
/// a delete that does not actually stop anything.
///
/// A D1 failure here throws rather than returning null, on purpose: the client
/// reads 401 as "the session is over, stop syncing until someone signs in
/// again" (`SyncAuthExpiredException`), so a database blip must surface as a
/// retryable 5xx instead of quietly ending the session.
export async function authenticate(request: Request, env: Env): Promise<string | null> {
  const userId = await authenticateToken(request, env);
  if (!userId) return null;

  const row = await env.DB.prepare('SELECT 1 AS ok FROM users WHERE id = ?')
    .bind(userId)
    .first<{ ok: number }>();
  return row ? userId : null;
}
