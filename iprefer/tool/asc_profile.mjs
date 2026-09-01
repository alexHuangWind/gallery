// Ensures an iOS provisioning profile exists for the bundle id and installs it
// locally, then prints "PROFILE <name>" for the export step.
//
//   node tool/asc_profile.mjs                 # App Store profile (TestFlight)
//   node tool/asc_profile.mjs --development   # dev profile with every
//                                             # registered device, for a
//                                             # direct install over USB/Wi-Fi
//
// Uses the App Store Connect API key on this machine (key id + issuer + .p8
// under ~/.appstoreconnect). Auto-signing via `xcodebuild -allowProvisioning
// Updates` needs the key to have cloud-managed-certificate access, which this
// team's key does not — so we mint a profile against the existing certificate
// and sign manually instead.
import {
  existsSync,
  mkdirSync,
  readFileSync,
  readdirSync,
  unlinkSync,
  writeFileSync,
} from 'node:fs';
import { createSign } from 'node:crypto';
import { homedir } from 'node:os';

const KID = 'WUD39Q6XN3';
const BUNDLE_ID = 'com.iprefer.iprefer';

const DEVELOPMENT = process.argv.includes('--development');
const PROFILE_NAME = DEVELOPMENT ? 'iPrefer Development' : 'iPrefer App Store';
const PROFILE_TYPE = DEVELOPMENT ? 'IOS_APP_DEVELOPMENT' : 'IOS_APP_STORE';
const CERT_TYPE = DEVELOPMENT ? /^DEVELOPMENT$/i : /DISTRIBUTION/i;

const iss = readFileSync(`${homedir()}/.appstoreconnect/issuer_id`, 'utf8').trim();
const key = readFileSync(`${homedir()}/.appstoreconnect/private_keys/AuthKey_${KID}.p8`, 'utf8');

function jwt() {
  const b64 = (o) => Buffer.from(typeof o === 'string' ? o : JSON.stringify(o)).toString('base64url');
  const header = b64({ alg: 'ES256', kid: KID, typ: 'JWT' });
  const now = Math.floor(Date.now() / 1000);
  const payload = b64({ iss, iat: now, exp: now + 600, aud: 'appstoreconnect-v1' });
  const signer = createSign('SHA256'); signer.update(`${header}.${payload}`);
  const der = signer.sign(key);
  let o = 4, rl = der[3]; const r = der.slice(o, o + rl); o += rl + 1; const sl = der[o]; o += 1; const s = der.slice(o, o + sl);
  const fix = (b) => { b = Buffer.from(b); while (b.length > 32 && b[0] === 0) b = b.slice(1); const p = Buffer.alloc(32); b.copy(p, 32 - b.length); return p; };
  return `${header}.${payload}.${Buffer.concat([fix(r), fix(s)]).toString('base64url')}`;
}
const api = async (path, init = {}) => {
  const res = await fetch(`https://api.appstoreconnect.apple.com${path}`, {
    ...init, headers: { Authorization: `Bearer ${jwt()}`, 'Content-Type': 'application/json', ...(init.headers || {}) },
  });
  const j = await res.json().catch(() => ({}));
  if (j.errors) throw new Error(`${path} -> ${j.errors[0].title}: ${j.errors[0].detail || ''}`);
  return j;
};

const PROFILE_DIR = `${homedir()}/Library/MobileDevice/Provisioning Profiles`;

/// Deletes locally-installed profiles that share our name but not our uuid.
///
/// Deleting a profile through the API does not remove the copy already on
/// this Mac, and xcodebuild resolves PROVISIONING_PROFILE_SPECIFIER by *name*.
/// Leave a stale twin behind and the build may sign against it — which is
/// exactly how an export failed with "requires a provisioning profile with
/// the Sign In with Apple feature" while the freshly minted profile had it.
///
/// The embedded plist sits in the CMS blob as plaintext, so a regex over the
/// raw bytes is enough to read Name and UUID without decoding the signature.
function pruneLocalTwins(keepUuid) {
  if (!existsSync(PROFILE_DIR)) return;
  for (const file of readdirSync(PROFILE_DIR)) {
    if (!file.endsWith('.mobileprovision')) continue;
    const raw = readFileSync(`${PROFILE_DIR}/${file}`, 'latin1');
    const name = /<key>Name<\/key>\s*<string>([^<]*)<\/string>/.exec(raw)?.[1];
    const uuid = /<key>UUID<\/key>\s*<string>([^<]*)<\/string>/.exec(raw)?.[1];
    if (name === PROFILE_NAME && uuid !== keepUuid) {
      unlinkSync(`${PROFILE_DIR}/${file}`);
      process.stderr.write(`removed stale local profile ${uuid}\n`);
    }
  }
}

function install(attrs) {
  mkdirSync(PROFILE_DIR, { recursive: true });
  writeFileSync(
    `${PROFILE_DIR}/${attrs.uuid}.mobileprovision`,
    Buffer.from(attrs.profileContent, 'base64'),
  );
  pruneLocalTwins(attrs.uuid);
}

/// Every enabled iPhone/iPad on the account. A development profile is only
/// valid for the devices baked into it, so a phone registered after the
/// profile was minted needs the profile re-made — see the reuse check below.
async function enabledDevices() {
  const res = await api('/v1/devices?limit=200&filter[status]=ENABLED&filter[platform]=IOS');
  return res.data || [];
}

const devices = DEVELOPMENT ? await enabledDevices() : [];

// Reuse an existing valid profile of this name if present.
const existing = await api(`/v1/profiles?filter[name]=${encodeURIComponent(PROFILE_NAME)}&include=certificates`);
const found = existing.data || [];
const active = found.find((p) => p.attributes.profileState === 'ACTIVE');
let reusable = active;
if (active && DEVELOPMENT) {
  // Only reusable if it already covers every device we know about.
  const covered = await api(`/v1/profiles/${active.id}/devices?limit=200`);
  const ids = new Set((covered.data || []).map((d) => d.id));
  const missing = devices.filter((d) => !ids.has(d.id));
  if (missing.length) {
    process.stderr.write(`profile ${PROFILE_NAME} lacks ${missing.length} device(s); re-minting\n`);
    reusable = null;
  }
}
if (reusable) {
  const full = await api(`/v1/profiles/${reusable.id}?fields[profiles]=name,uuid,profileContent,profileState`);
  install(full.data.attributes);
  process.stderr.write(`reusing profile ${PROFILE_NAME}\n`);
  process.stdout.write(PROFILE_NAME);
  process.exit(0);
}

// Nothing usable, but same-named profiles may still exist. Changing an App
// ID's capabilities (adding Sign in with Apple, say) marks every profile for
// that App ID INVALID, and Apple rejects a create that duplicates a name — so
// the stale ones have to go before a fresh one can take their place. This is
// the recovery path for exactly that, and it is why re-running this script is
// enough to unbreak the release pipeline after a capability change.
for (const stale of found) {
  await api(`/v1/profiles/${stale.id}`, { method: 'DELETE' });
  process.stderr.write(
    `removed ${stale.attributes.profileState} profile ${PROFILE_NAME}\n`,
  );
}

// Otherwise mint one against the right cert + bundle id (+ devices).
const [certs, bundles] = await Promise.all([
  api('/v1/certificates?limit=200'),
  api(`/v1/bundleIds?filter[identifier]=${BUNDLE_ID}`),
]);
const cert = certs.data.find((c) => CERT_TYPE.test(c.attributes.certificateType));
if (!cert) throw new Error(`no ${DEVELOPMENT ? 'development' : 'distribution'} certificate on the account`);
const bundle = bundles.data[0];
if (!bundle) throw new Error(`bundle id ${BUNDLE_ID} is not registered`);
if (DEVELOPMENT && devices.length === 0) {
  throw new Error('no enabled iOS devices registered — a development profile needs at least one');
}

const relationships = {
  bundleId: { data: { type: 'bundleIds', id: bundle.id } },
  certificates: { data: [{ type: 'certificates', id: cert.id }] },
};
if (DEVELOPMENT) {
  relationships.devices = { data: devices.map((d) => ({ type: 'devices', id: d.id })) };
}

const created = await api('/v1/profiles', {
  method: 'POST',
  body: JSON.stringify({
    data: {
      type: 'profiles',
      attributes: { name: PROFILE_NAME, profileType: PROFILE_TYPE },
      relationships,
    },
  }),
});
install(created.data.attributes);
process.stderr.write(`created profile ${PROFILE_NAME}${DEVELOPMENT ? ` (${devices.length} device(s))` : ''}\n`);
process.stdout.write(PROFILE_NAME);
