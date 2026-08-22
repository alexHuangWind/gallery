-- iPrefer sync schema.
--
-- The whole design rests on one property of the product: an entry is created
-- and deleted, never edited (CLAUDE.md excludes edit history). That makes the
-- server an append-only op log with no field-level merge and no conflicts.

CREATE TABLE IF NOT EXISTS users (
  id         TEXT PRIMARY KEY,   -- our own uid, handed to clients
  apple_sub  TEXT UNIQUE,        -- Apple's stable subject id; null for dev users
  created_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS ops (
  seq        INTEGER PRIMARY KEY AUTOINCREMENT,  -- the sync cursor
  user_id    TEXT NOT NULL,
  entry_id   TEXT NOT NULL,
  type       TEXT NOT NULL CHECK (type IN ('create', 'delete')),
  payload    TEXT,                                -- entry JSON on create, null on delete
  created_at INTEGER NOT NULL
);

-- Pull is always "my ops after this seq".
CREATE INDEX IF NOT EXISTS ops_by_user_seq ON ops (user_id, seq);

-- Idempotency, enforced by the database rather than by careful callers:
-- re-pushing the same op is an INSERT OR IGNORE no-op. Safe because entry ids
-- are client-generated UUIDv4 — a re-created entry is a different entry.
CREATE UNIQUE INDEX IF NOT EXISTS ops_unique_per_entry_type
  ON ops (user_id, entry_id, type);
