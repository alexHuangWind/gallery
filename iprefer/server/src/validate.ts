/// Wire-format validation.
///
/// The client is the only writer today, but "the client is well behaved" is
/// not a security model: everything here is reachable with a valid token and
/// a curl. Reject anything that isn't exactly the shape we store.

import type { EntryPayload, Op, OpType } from './types';

export const MAX_OPS_PER_PUSH = 500;
export const MAX_TEXT_LENGTH = 2000;
export const MAX_TAGS = 32;
export const MAX_TAG_LENGTH = 40;
export const MAX_PHOTO_BYTES = 15 * 1024 * 1024;

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/// Allowlist, not a pattern: this names an object the service will hand back
/// to a client, so "anything alphanumeric" would happily store `.exe`.
/// image_picker only ever produces these.
const PHOTO_EXTENSIONS = new Set(['jpg', 'jpeg', 'png', 'heic', 'heif', 'webp']);

export class ValidationError extends Error {}

function fail(message: string): never {
  throw new ValidationError(message);
}

export function isEntryId(value: unknown): value is string {
  return typeof value === 'string' && UUID_RE.test(value);
}

/// The photo name is always "<entryId>.<ext>" — the client already names files
/// that way, and deriving the R2 key from it means no mapping table and no way
/// to point one entry at another entry's photo.
export function photoNameFor(entryId: string, name: unknown): string {
  if (typeof name !== 'string') fail('photoName must be a string');
  const dot = name.lastIndexOf('.');
  if (dot <= 0) fail('photoName must have an extension');
  if (name.slice(0, dot) !== entryId) fail('photoName must start with the entry id');
  if (!PHOTO_EXTENSIONS.has(name.slice(dot + 1).toLowerCase())) {
    fail('photoName has an unsupported extension');
  }
  return name;
}

function optionalCoordinate(value: unknown, label: string): number | null {
  if (value === null || value === undefined) return null;
  if (typeof value !== 'number' || !Number.isFinite(value)) fail(`${label} must be a finite number`);
  const limit = label === 'latitude' ? 90 : 180;
  if (Math.abs(value) > limit) fail(`${label} out of range`);
  return value;
}

export function parseEntry(raw: unknown, entryId: string): EntryPayload {
  if (typeof raw !== 'object' || raw === null) fail('payload must be an object');
  const o = raw as Record<string, unknown>;

  if (o.id !== entryId) fail('payload.id must match the op entry id');

  if (typeof o.text !== 'string') fail('text must be a string');
  const text = o.text;
  if (text.length === 0) fail('text must not be empty');
  if ([...text].length > MAX_TEXT_LENGTH) fail('text is too long');

  if (typeof o.createdAt !== 'number' || !Number.isFinite(o.createdAt)) {
    fail('createdAt must be a number');
  }
  const createdAt = Math.trunc(o.createdAt);

  const latitude = optionalCoordinate(o.latitude, 'latitude');
  const longitude = optionalCoordinate(o.longitude, 'longitude');
  // Half a fix is not a fix — the client stores both or neither.
  if ((latitude === null) !== (longitude === null)) fail('latitude and longitude must agree');

  let placeLabel: string | null = null;
  if (o.placeLabel !== null && o.placeLabel !== undefined) {
    if (typeof o.placeLabel !== 'string') fail('placeLabel must be a string or null');
    placeLabel = o.placeLabel.slice(0, 200);
  }

  let tags: string[] = [];
  if (o.tags !== null && o.tags !== undefined) {
    if (!Array.isArray(o.tags)) fail('tags must be an array');
    if (o.tags.length > MAX_TAGS) fail('too many tags');
    tags = o.tags.map((t) => {
      if (typeof t !== 'string') fail('tags must be strings');
      if ([...t].length > MAX_TAG_LENGTH) fail('tag is too long');
      return t;
    });
  }

  return {
    id: entryId,
    text,
    createdAt,
    latitude,
    longitude,
    placeLabel,
    tags,
    photoName: photoNameFor(entryId, o.photoName),
  };
}

export function parseOps(raw: unknown): Op[] {
  if (typeof raw !== 'object' || raw === null) fail('body must be an object');
  const ops = (raw as Record<string, unknown>).ops;
  if (!Array.isArray(ops)) fail('ops must be an array');
  if (ops.length > MAX_OPS_PER_PUSH) fail(`at most ${MAX_OPS_PER_PUSH} ops per push`);

  return ops.map((item) => {
    if (typeof item !== 'object' || item === null) fail('each op must be an object');
    const o = item as Record<string, unknown>;

    const type = o.type;
    if (type !== 'create' && type !== 'delete') fail('op type must be create or delete');

    if (!isEntryId(o.entryId)) fail('entryId must be a uuid');
    const entryId = o.entryId;

    if (type === 'create') {
      return { type: type as OpType, entryId, payload: parseEntry(o.payload, entryId) };
    }
    return { type: type as OpType, entryId, payload: null };
  });
}
