/// Boots and stops the `wrangler dev` the tests run against.
///
///   node test/dev_server.mjs start   (npm pretest)
///   node test/dev_server.mjs stop    (npm posttest)
///
/// `npm test` used to mean "remember to start a server in another terminal,
/// and remember to apply the schema first, or watch every assertion fail for
/// reasons that have nothing to do with the code". This does both.
///
/// It also supplies APPLE_JWKS_URL, which no longer lives in .dev.vars: the
/// test double it points at only exists while the tests are running, so
/// pinning it there broke plain `wrangler dev`.
///
/// Two things it deliberately does NOT do: it will not kill a server it did
/// not start (a developer's own `npm run dev` is adopted, with a warning that
/// the Apple tests need the override), and it will not spawn a second one on
/// an occupied port.

import { spawn } from 'node:child_process';
import { existsSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, '..');
const PID_FILE = join(root, '.dev-server.pid');

const { PORT, BASE, JWKS_URL, REFETCH_COOLDOWN_MS } = await import('./config.mjs');

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function healthy() {
  try {
    const res = await fetch(`${BASE}/v1/health`, { signal: AbortSignal.timeout(1000) });
    return res.ok;
  } catch {
    return false;
  }
}

/// Kills whatever a previous run left behind. The safety net for `npm test`
/// failing: npm skips `posttest` when `test` exits non-zero, so a red run
/// leaks its server until the next start reclaims it.
function killTracked() {
  if (!existsSync(PID_FILE)) return false;
  const pid = Number(readFileSync(PID_FILE, 'utf8').trim());
  rmSync(PID_FILE, { force: true });
  if (!Number.isInteger(pid) || pid <= 0) return false;
  try {
    // Negative pid: the whole group. wrangler runs the Worker in a child, and
    // killing only the parent leaves the port held.
    process.kill(-pid, 'SIGTERM');
  } catch {
    try {
      process.kill(pid, 'SIGTERM');
    } catch {
      return false; // already gone
    }
  }
  return true;
}

function run(command, args) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, { cwd: root, stdio: 'inherit', shell: false });
    child.on('error', reject);
    child.on('exit', (code) => (code === 0 ? resolve() : reject(new Error(`${command} exited ${code}`))));
  });
}

async function start() {
  if (process.env.SYNC_URL) {
    console.log(`dev server: using SYNC_URL=${process.env.SYNC_URL}, not starting one`);
    return;
  }

  if (killTracked()) {
    // Give the socket a moment to come free before we try to bind it again.
    for (let i = 0; i < 50 && (await healthy()); i++) await sleep(100);
  }

  if (await healthy()) {
    console.log(
      `dev server: something is already serving ${BASE} — adopting it.\n` +
        '  NOTE: the Apple tests need APPLE_JWKS_URL pointed at the test double.\n' +
        '  If they fail, stop that server and let `npm test` start its own.',
    );
    return;
  }

  // CREATE TABLE IF NOT EXISTS throughout, so this is cheap to repeat — and it
  // is what makes `npm test` work from a fresh clone. Before `wrangler dev`
  // starts, so the two are never touching the local SQLite file at once.
  await run('npx', ['wrangler', 'd1', 'execute', 'iprefer-sync', '--local', '--file=./schema.sql']);

  const child = spawn(
    'npx',
    [
      'wrangler',
      'dev',
      '--port',
      String(PORT),
      '--var',
      `APPLE_JWKS_URL:${JWKS_URL}`,
      '--var',
      `APPLE_JWKS_REFETCH_COOLDOWN_MS:${REFETCH_COOLDOWN_MS}`,
    ],
    { cwd: root, stdio: 'ignore', detached: true },
  );
  child.unref();
  writeFileSync(PID_FILE, String(child.pid));

  for (let i = 0; i < 120; i++) {
    if (await healthy()) {
      console.log(`dev server: up on ${BASE} (pid ${child.pid})`);
      return;
    }
    await sleep(500);
  }

  killTracked();
  throw new Error(`dev server did not answer ${BASE}/v1/health within 60s`);
}

function stop() {
  console.log(killTracked() ? 'dev server: stopped' : 'dev server: nothing to stop');
}

const command = process.argv[2];
if (command === 'start') {
  await start();
} else if (command === 'stop') {
  stop();
} else {
  console.error('usage: node test/dev_server.mjs start|stop');
  process.exit(2);
}
