export interface Env {
  DB: D1Database;
  PHOTOS: R2Bucket;
  /// HMAC key for session tokens. Set with `wrangler secret put SESSION_SECRET`.
  /// Local dev falls back to a fixed dev value (see index.ts).
  SESSION_SECRET: string;
  /// "1" enables /v1/auth/dev. Absent in production.
  DEV_AUTH?: string;
  /// Overridable so tests can point at a local JWKS. Defaults to Apple's.
  /// Note it is NOT set in .dev.vars: a plain `wrangler dev` should talk to
  /// the real key server, not to a test double that may not be listening.
  APPLE_JWKS_URL?: string;
  /// The bundle id an identity token must be addressed to. Defaults to ours.
  APPLE_AUDIENCE?: string;
  /// How long an unknown `kid` is refused before another forced JWKS refetch
  /// is allowed. Exists so tests can shrink the window; defaults to 5 minutes.
  APPLE_JWKS_REFETCH_COOLDOWN_MS?: string;
}

/// The wire shape of an entry. Mirrors lib/models/entry.dart, except
/// `localPath` (a device-local file name) travels as `photoName`.
export interface EntryPayload {
  id: string;
  text: string;
  createdAt: number; // ms since epoch — same precision the client stores
  latitude: number | null;
  longitude: number | null;
  placeLabel: string | null;
  tags: string[];
  photoName: string; // "<entryId>.<ext>" — also the R2 object key suffix
}

export type OpType = 'create' | 'delete';

export interface Op {
  type: OpType;
  entryId: string;
  payload?: EntryPayload | null;
}

export interface StoredOp extends Op {
  seq: number;
}
