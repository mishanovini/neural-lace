'use strict';
// measure-seed.js — the design-time measurement script behind
// docs/designs/cockpit-read-through-2026-08-04.md's Inputs figures, persisted
// per harness review (2026-08-04) as the seed for the implementing plan's
// `server/read-bench.js` (REQ-A6). Run: `node measure-seed.js [repoRoot]`.
// All paths are homedir/argument-derived — no machine-identifying strings.
//
// 2026-08-04 output on the authoring machine (design Inputs, re-verifiable):
//   live plans: 31 files 1056815 bytes 12.1 ms
//   dispatch-ledger: 3076 rows 5.4 ms
//   archive: 266 files 5103324 bytes 68.8 ms; task lines 2109
//   heartbeats: 17 files
//   signal-ledger: 17735505 bytes 63327 rows 101.5 ms (read+split)

const fs = require('fs'), path = require('path'), os = require('os');
const home = os.homedir().replace(/\\/g, '/');

// Repo root: argv[2], else the install-written canonical pin (the same file
// DEC-3 consumes), else cwd. POSIX->win32 normalization mirrors DEC-3 step 2.
function canonicalRootGuess() {
  if (process.argv[2]) return process.argv[2];
  try {
    let line = String(fs.readFileSync(path.join(home, '.claude', 'local', 'nl-repo-path'), 'utf8'))
      .split('\n')[0].replace(/\r$/, '').trim();
    if (process.platform === 'win32') line = line.replace(/^\/([a-zA-Z])\//, '$1:/');
    if (line && fs.existsSync(line)) return line;
  } catch (_) { /* fall through */ }
  return process.cwd();
}
const root = canonicalRootGuess();
console.log('repo root:', root);

function msSince(t0) { return (Number(process.hrtime.bigint() - t0) / 1e6).toFixed(1); }

let t0 = process.hrtime.bigint();
const pd = path.join(root, 'docs', 'plans');
let files = [];
try { files = fs.readdirSync(pd).filter((f) => f.endsWith('.md')); } catch (e) { console.log('plans dir err', e.code); }
let bytes = 0;
files.forEach((f) => { bytes += Buffer.byteLength(fs.readFileSync(path.join(pd, f), 'utf8')); });
console.log('live plans:', files.length, 'files', bytes, 'bytes', msSince(t0), 'ms');

t0 = process.hrtime.bigint();
let rows = 0;
try {
  const raw = fs.readFileSync(home + '/.claude/state/dispatch-ledger.jsonl', 'utf8');
  raw.split('\n').forEach((l) => { if (!l.trim()) return; try { JSON.parse(l); rows++; } catch (_) {} });
} catch (e) { console.log('dispatch-ledger err', e.code); }
console.log('dispatch-ledger:', rows, 'rows', msSince(t0), 'ms');

t0 = process.hrtime.bigint();
const ad = path.join(pd, 'archive');
let afiles = [];
try { afiles = fs.readdirSync(ad).filter((f) => f.endsWith('.md')); } catch (_) {}
let abytes = 0, taskLines = 0;
afiles.forEach((f) => {
  const s = fs.readFileSync(path.join(ad, f), 'utf8');
  abytes += Buffer.byteLength(s);
  s.split('\n').forEach((l) => { if (/^- \[[ xX]\]/.test(l)) taskLines++; });
});
console.log('archive:', afiles.length, 'files', abytes, 'bytes', msSince(t0), 'ms; task lines', taskLines);

try { console.log('heartbeats:', fs.readdirSync(home + '/.claude/state/heartbeats').length, 'files'); }
catch (e) { console.log('heartbeats err', e.code); }

try {
  const sl = home + '/.claude/state/signal-ledger.jsonl';
  const size = fs.statSync(sl).size;
  t0 = process.hrtime.bigint();
  let n = 0;
  fs.readFileSync(sl, 'utf8').split('\n').forEach((l) => { if (l.trim()) n++; });
  console.log('signal-ledger:', size, 'bytes', n, 'rows', msSince(t0), 'ms (read+split)');
} catch (e) { console.log('signal-ledger err', e.code); }
