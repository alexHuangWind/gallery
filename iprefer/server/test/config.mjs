/// Everything both test files and the dev-server launcher have to agree on.
///
/// It lives in one place because the agreement is easy to break silently: the
/// Worker learns the JWKS url from a `--var` passed at launch, while the test
/// that stands the JWKS double up learns the port from here. Two constants
/// drifting apart would look like a signature bug.

export const PORT = Number(process.env.SYNC_PORT ?? 8787);
export const BASE = process.env.SYNC_URL ?? `http://127.0.0.1:${PORT}`;

/// Where test/apple_auth.test.mjs serves its throwaway JWKS.
export const JWKS_PORT = 8788;
export const JWKS_URL = `http://127.0.0.1:${JWKS_PORT}/keys`;

/// Short enough to test both sides of the window in a few seconds, long
/// enough that a burst of five local requests comfortably fits inside it.
/// Production uses the 5 minute default in src/apple.ts.
export const REFETCH_COOLDOWN_MS = 3000;
