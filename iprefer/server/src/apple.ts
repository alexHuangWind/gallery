/// Verifying Apple's identity token.
///
/// This is the only thing standing between a stranger and someone else's
/// archive, so every check below is load-bearing and none of them are
/// optional:
///
///  - the signature, against Apple's published keys (not the token's own
///    claim about itself);
///  - `alg`, pinned to RS256 — a token asking to be verified with `none`, or
///    with HMAC using the public key as the secret, is the classic JWT
///    forgery and is rejected before any crypto runs;
///  - `iss`, so a token from anywhere else is not Apple's;
///  - `aud`, so an identity token Apple legitimately issued for a *different*
///    app cannot be replayed here — without this check, anyone with any
///    Sign in with Apple app could sign in as any of our users;
///  - `exp`, so an old token cannot be replayed forever.

import type { Env } from './types';

const APPLE_ISSUER = 'https://appleid.apple.com';
const DEFAULT_JWKS_URL = 'https://appleid.apple.com/auth/keys';
/// A native iOS app's identity token carries the bundle id as its audience.
const DEFAULT_AUDIENCE = 'com.iprefer.iprefer';

export class AppleAuthError extends Error {}

interface AppleJwk {
  kty: string;
  kid: string;
  n: string;
  e: string;
  alg?: string;
  use?: string;
}

/// Apple's keys, cached between requests so signing in isn't gated on an
/// outbound round trip.
///
/// Two independent ways to go stale, both covered: a `kid` we've never seen
/// forces an immediate refetch (that's how rotation normally appears), and
/// the whole cache expires on a timer so a long-lived isolate can't hold a
/// retired key forever. Note we deliberately do NOT refetch on a signature
/// mismatch — that would let anyone force an outbound request per bad token.
const KEY_CACHE_TTL_MS = 60 * 60 * 1000; // 1 hour
let cachedKeys: { url: string; keys: AppleJwk[]; fetchedAt: number } | null = null;

function b64urlToBytes(value: string): Uint8Array {
  const padded = value.replace(/-/g, '+').replace(/_/g, '/');
  const bin = atob(padded + '='.repeat((4 - (padded.length % 4)) % 4));
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

function decodeJson(segment: string): Record<string, unknown> {
  return JSON.parse(new TextDecoder().decode(b64urlToBytes(segment)));
}

async function fetchKeys(url: string, force: boolean): Promise<AppleJwk[]> {
  const fresh =
      cachedKeys?.url === url && Date.now() - cachedKeys.fetchedAt < KEY_CACHE_TTL_MS;
  if (!force && fresh) return cachedKeys!.keys;

  const res = await fetch(url);
  if (!res.ok) throw new AppleAuthError(`could not fetch Apple keys (${res.status})`);
  const body = (await res.json()) as { keys?: AppleJwk[] };
  const keys = body.keys ?? [];
  cachedKeys = { url, keys, fetchedAt: Date.now() };
  return keys;
}

export interface AppleIdentity {
  /// Apple's stable, per-developer-account user id. This is the join key.
  sub: string;
  email?: string;
}

export async function verifyAppleIdentityToken(
  env: Env,
  idToken: unknown,
): Promise<AppleIdentity> {
  if (typeof idToken !== 'string' || idToken.length === 0) {
    throw new AppleAuthError('identityToken is required');
  }

  const parts = idToken.split('.');
  if (parts.length !== 3) throw new AppleAuthError('malformed token');
  const [rawHeader, rawPayload, rawSignature] = parts;

  let header: Record<string, unknown>;
  let claims: Record<string, unknown>;
  try {
    header = decodeJson(rawHeader);
    claims = decodeJson(rawPayload);
  } catch {
    throw new AppleAuthError('malformed token');
  }

  // Pinned before we touch a key: never let the token choose its own
  // verification algorithm.
  if (header.alg !== 'RS256') throw new AppleAuthError('unexpected token algorithm');
  const kid = header.kid;
  if (typeof kid !== 'string') throw new AppleAuthError('token has no key id');

  const jwksUrl = env.APPLE_JWKS_URL || DEFAULT_JWKS_URL;
  let keys = await fetchKeys(jwksUrl, false);
  let jwk = keys.find((k) => k.kid === kid);
  if (!jwk) {
    // Unknown kid: Apple may have rotated. One forced refetch, then give up —
    // otherwise a bogus kid turns into an outbound request per attempt.
    keys = await fetchKeys(jwksUrl, true);
    jwk = keys.find((k) => k.kid === kid);
  }
  if (!jwk) throw new AppleAuthError('unknown signing key');

  const key = await crypto.subtle.importKey(
    'jwk',
    { kty: jwk.kty, n: jwk.n, e: jwk.e, alg: 'RS256', ext: true },
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['verify'],
  );

  const signed = new TextEncoder().encode(`${rawHeader}.${rawPayload}`);
  const valid = await crypto.subtle.verify(
    'RSASSA-PKCS1-v1_5',
    key,
    b64urlToBytes(rawSignature),
    signed,
  );
  if (!valid) throw new AppleAuthError('bad signature');

  if (claims.iss !== APPLE_ISSUER) throw new AppleAuthError('wrong issuer');

  // `aud` is a string for a native app, but the spec allows an array.
  const audience = env.APPLE_AUDIENCE || DEFAULT_AUDIENCE;
  const aud = claims.aud;
  const audienceMatches = Array.isArray(aud) ? aud.includes(audience) : aud === audience;
  if (!audienceMatches) throw new AppleAuthError('wrong audience');

  const exp = claims.exp;
  if (typeof exp !== 'number' || exp * 1000 <= Date.now()) {
    throw new AppleAuthError('token expired');
  }

  const sub = claims.sub;
  if (typeof sub !== 'string' || sub.length === 0) {
    throw new AppleAuthError('token has no subject');
  }

  return {
    sub,
    email: typeof claims.email === 'string' ? claims.email : undefined,
  };
}
