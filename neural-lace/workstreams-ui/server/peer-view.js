'use strict';
// server/peer-view.js — cockpit-v2-push-materialized-store Task 4: the
// server's READ of the LOCAL coord clone, producing the "Peers" section
// rendered on the ask-tree landing (GET /api/asks -> server.js's
// buildAsksLandingPayload).
//
// REQUEST PATH DISCIPLINE (binding): NO fork, NO network, ever, from this
// module. Every function below is a plain fs.readdirSync/statSync/
// readFileSync — the coord clone is just a directory that coord-sync.sh
// (Task 3) keeps fresh out-of-band, on its own 600s cadence; this module
// only ever reads whatever is ALREADY on disk at request time. (Contrast
// with server/export-state.js, which DOES shell out to `git` — but only at
// EXPORT time, on the WRITE side, never here.)
//
// A7 (binding) — skip-bad-record tolerance: `coord-pull.sh`'s `git reset
// --hard` is not atomic across multiple files in the clone's working tree,
// so a read landing mid-refresh can see a file that has vanished or is
// truncated. Every read below is wrapped so ONE bad/vanished file is
// silently skipped — never a thrown exception, never a 500 for the whole
// landing payload over one peer's bad luck.
//
// F2 (binding) — age is computed from RECEIVE-time, never the peer's own
// wall clock alone. "Receive-time" here IS the exported file's OS mtime ON
// THIS MACHINE: `coord-pull.sh`'s `git reset --hard` only rewrites a
// tracked file's bytes (and therefore its mtime) when the file's git blob
// actually changed, so a file's mtime is exactly "the last time THIS
// machine's disk got a genuinely new copy of this peer's export" —
// immune to any clock skew on the peer, because both ends of the
// subtraction (mtime, Date.now()) are this machine's own clock.
//
// A3 (binding) — named states, real mechanisms, not vibes:
//   fresh-ish        — receive_age <= FRESH_MS (default 20min): we got
//                       something (real progress OR a keepalive) recently.
//   estate-unchanged  — FRESH_MS < receive_age <= (KEEPALIVE_MS + MARGIN_MS)
//                       (default 60min + 20min = 80min): export-state.js's
//                       own A3ii bounded keepalive GUARANTEES a write (real
//                       content change OR a keepalive-only rewrite) at
//                       least every KEEPALIVE_MS on a healthy peer, plus the
//                       plan's own worst-case transport margin (~20min) to
//                       land here — so an age inside this window is fully
//                       explained by "nothing NEW happened, but the
//                       exporter is still alive", not by "the peer is
//                       gone".
//   peer-unreachable  — receive_age beyond that window: no keepalive would
//                       explain a gap this size on a healthy peer, so the
//                       exporter (or its coord-sync cadence) is presumed
//                       dead. Distinguishes "idle" from "dead" by
//                       MECHANISM (the keepalive's own guarantee), not by
//                       guessing.
//   no-data (has_data:false at the section level) — zero peer files ever
//                       seen (no coord clone, no plan-export/ dir, or the
//                       dir contains only this machine's own file).
//
// A5 (binding) — every threshold above is env-injectable (see
// thresholds() below) so the task-8 acceptance drill's degradation leg
// (kill the export loop -> "peer unreachable") is runnable on a compressed
// timescale rather than needing to wait 80 real minutes.
//
// F4 (binding) — a peer's UNMERGED state never renders as plain done: every
// peer plan row always carries a `provenance_label` ("as of Xm ago on
// <host> (<branch>, merged|unmerged)") alongside its tasks, so the reader
// is a labeled provenance row, never a bare checkbox indistinguishable from
// local truth (requirement 8: peer copies are ALWAYS labeled, NEVER
// substituted for the local card).
//
// A3c (binding) — sessions classify by AGE from the RAW `last_heartbeat_at`
// export-state.js ships (never a baked classification — see that module's
// own header); classifySessionAge() below is the reader-side classifier,
// independent of (and simpler than) the server's LOCAL
// derive-lib.js#classifySessions (which shells out to hb_classify for a
// pid-liveness check that is meaningless for a machine we cannot signal).
//
// "My coord view last refreshed" — the reader's OWN transport health.
// PRIMARY SOURCE (documented choice, not a hedge): the coord clone's own
// `.git/FETCH_HEAD` mtime. `git fetch` writes this file on every
// SUCCESSFUL fetch (even a genuine no-op fetch touches it) and does NOT
// touch it on failure — so its mtime is a direct, git-native answer to
// "when did this machine last successfully talk to the coord origin",
// independent of which script (the coord-sync cadence, or a manual
// `coord-pull.sh pull`) triggered the fetch, and needs zero parsing (one
// fs.statSync). coord-sync.sh's own `cycles.log` is used ONLY as a
// fallback when FETCH_HEAD is entirely absent (e.g. a clone that has never
// completed one fetch) — that log is cadence-script-specific
// instrumentation (a STATE_DIR path this module would otherwise have no
// reason to know), a strictly weaker signal than the git-native one.
'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');

// ----------------------------------------------------------------------
// Config resolution — mirrors coord-push.sh/coord-pull.sh/coord-sync.sh's
// own COORD_CLONE_DIR convention exactly (same default path) so this
// module reads the SAME clone those scripts maintain, with zero extra
// configuration.
// ----------------------------------------------------------------------
function coordCloneDir() {
  return process.env.COORD_CLONE_DIR ||
    path.join(process.env.HOME || os.homedir(), 'claude-projects', 'workstreams-coordination');
}

// selfHostname() — the SAME override var server/export-state.js honors
// (requirement #2 / A5): lets one machine simulate two peers (task 8's
// acceptance drill) while this machine's OWN peer view still correctly
// filters "self" out, using the identical identity the exporter would have
// stamped had it run under the same override.
function selfHostname() {
  return process.env.EXPORT_HOSTNAME || os.hostname();
}

// thresholds() — A5 (binding): every named-state boundary is env-
// injectable. Minutes, not ms, in the env vars (operator-friendly); the
// module works internally in ms.
function thresholds() {
  return {
    freshMs: Number(process.env.COCKPIT_PEER_FRESH_MIN || 20) * 60 * 1000,
    keepaliveMs: Number(process.env.COCKPIT_PEER_KEEPALIVE_MIN || 60) * 60 * 1000,
    marginMs: Number(process.env.COCKPIT_PEER_TRANSPORT_MARGIN_MIN || 20) * 60 * 1000,
    sessionStaleMin: Number(process.env.OBS_STALE_MIN || 30),
  };
}

function planExportDir(cloneDir) { return path.join(cloneDir, 'plan-export'); }

// ----------------------------------------------------------------------
// readPeerExportFiles(cloneDir) — A7 (binding): enumerate every
// `<host>.json` under `<cloneDir>/plan-export/`; a file that vanishes
// between readdir and stat/read (a `reset --hard` racing this read), or
// that fails to JSON.parse (a partial/corrupt file), is SILENTLY SKIPPED —
// never thrown, never a 500 for the whole landing payload. `receivedAt` is
// the file's own mtime (F2's receive-time anchor).
// ----------------------------------------------------------------------
function readPeerExportFiles(cloneDir) {
  const dir = planExportDir(cloneDir);
  let names;
  try { names = fs.readdirSync(dir); } catch (_) { return []; }
  const out = [];
  names.filter((n) => /\.json$/.test(n)).forEach((name) => {
    const file = path.join(dir, name);
    const host = name.slice(0, -'.json'.length);
    let stat;
    try { stat = fs.statSync(file); } catch (_) { return; } // vanished mid-read — skip (A7)
    let payload;
    try { payload = JSON.parse(fs.readFileSync(file, 'utf8')); } catch (_) { return; } // corrupt/partial — skip (A7)
    if (!payload || typeof payload !== 'object') return;
    out.push({ host: host, file: file, receivedAt: stat.mtime, payload: payload });
  });
  return out;
}

function minutesAgo(ms) { return Math.max(0, Math.round(ms / 60000)); }

// classifyPeerState(ageMs, th) — A3's three-way split, see header.
function classifyPeerState(ageMs, th) {
  if (ageMs <= th.freshMs) return 'fresh-ish';
  if (ageMs <= th.keepaliveMs + th.marginMs) return 'estate-unchanged';
  return 'peer-unreachable';
}

// stateLabel(state, ageMs, receivedAtIso) — the literal named-state copy
// the plan's User-facing Outcome quotes. fresh-ish shows a relative age
// (short-lived, so "Xm ago" reads naturally); the other two states show
// the absolute receive-time instant ("since <ts>") — deliberately NOT a
// relative age here, because what matters for those two states is the
// FIXED point since which nothing new has arrived, not how that gap is
// currently growing.
function stateLabel(state, ageMs, receivedAtIso) {
  if (state === 'fresh-ish') return 'fresh-ish (' + minutesAgo(ageMs) + 'm ago)';
  if (state === 'estate-unchanged') return 'estate unchanged since ' + receivedAtIso;
  return 'peer unreachable since ' + receivedAtIso;
}

// isUnmerged(provenance) — F4/Edge Cases: "master" is this codebase's own
// main-branch convention (see CLAUDE.md git conventions); any other branch,
// or a dirty tree even ON master, counts as unmerged. Missing/blank branch
// is treated as unmerged too (an honest "we don't know this is merged" is
// safer than defaulting to "merged").
function isUnmerged(provenance) {
  const branch = (provenance && provenance.branch) || '';
  const dirty = !!(provenance && provenance.dirty);
  return dirty || branch !== 'master';
}

// provenanceLabel(ageMs, host, provenance) — the literal per-plan-row copy
// the plan's User-facing Outcome quotes: "as of Xm ago on <host> (<branch>,
// unmerged/merged)".
function provenanceLabel(ageMs, host, provenance) {
  const branch = (provenance && provenance.branch) || 'unknown';
  const word = isUnmerged(provenance) ? 'unmerged' : 'merged';
  return 'as of ' + minutesAgo(ageMs) + 'm ago on ' + host + ' (' + branch + ', ' + word + ')';
}

// classifySessionAge(lastHeartbeatAt, staleMin) — A3c (binding): the
// READER classifies a peer session by AGE against ITS OWN clock, using the
// RAW last_heartbeat_at export-state.js ships — never a value trusted from
// the export itself. Deliberately a coarser two-state (fresh|stale) than
// derive-lib.js's LOCAL classifySessions() (live/stale/throttled/crashed/
// missing): pid-liveness (what distinguishes crashed from throttled) is
// unobservable for a session on a different machine, so this reader never
// claims a distinction it cannot prove.
function classifySessionAge(lastHeartbeatAt, staleMin) {
  if (!lastHeartbeatAt) return 'unknown';
  const ms = Date.now() - Date.parse(lastHeartbeatAt);
  if (isNaN(ms)) return 'unknown';
  return (ms / 60000) <= staleMin ? 'fresh' : 'stale';
}

// coordSyncCycleLogPath() — fallback-only path for myCoordRefresh() below;
// deliberately a DEDICATED env var (not coord-sync.sh's own generic
// `STATE_DIR`, which is too easily collided with by accident) — same
// default real path coord-sync.sh itself defaults to, so an operator who
// never overrides either still gets the fallback pointed at the real file.
function coordSyncCycleLogPath() {
  return process.env.COCKPIT_COORD_SYNC_STATE_DIR
    ? path.join(process.env.COCKPIT_COORD_SYNC_STATE_DIR, 'cycles.log')
    : path.join(process.env.HOME || os.homedir(), '.claude', 'state', 'coord-sync', 'cycles.log');
}

// myCoordRefresh(cloneDir) — the reader's OWN transport health: "my coord
// view last refreshed Xm ago". See header for the FETCH_HEAD-primary /
// cycles.log-fallback design choice.
function myCoordRefresh(cloneDir) {
  const fetchHead = path.join(cloneDir, '.git', 'FETCH_HEAD');
  try {
    const st = fs.statSync(fetchHead);
    const ageMs = Date.now() - st.mtime.getTime();
    return {
      last_refreshed_at: st.mtime.toISOString(),
      age_minutes: minutesAgo(ageMs),
      label: 'my coord view last refreshed ' + minutesAgo(ageMs) + 'm ago',
      source: 'fetch_head_mtime',
    };
  } catch (_) { /* fall through to the cycles.log fallback below */ }
  try {
    const log = coordSyncCycleLogPath();
    const lines = fs.readFileSync(log, 'utf8').trim().split('\n').filter(Boolean);
    const last = lines[lines.length - 1] || '';
    const m = /ts=(\S+)/.exec(last);
    if (m) {
      const ageMs = Date.now() - Date.parse(m[1]);
      if (!isNaN(ageMs)) {
        return {
          last_refreshed_at: m[1],
          age_minutes: minutesAgo(ageMs),
          label: 'my coord view last refreshed ' + minutesAgo(ageMs) + 'm ago',
          source: 'cycle_log',
        };
      }
    }
  } catch (_) { /* no cycle log either — genuinely never refreshed */ }
  return { last_refreshed_at: null, age_minutes: null, label: 'my coord view has never refreshed', source: 'none' };
}

// ----------------------------------------------------------------------
// computePeerView(opts) — the ONE entry point server.js calls. Never
// throws (every sub-step above is already fail-open); returns a payload
// shape server/payload-schema.js's LANDING_ALLOWED_KEYS validates.
// ----------------------------------------------------------------------
function computePeerView(opts) {
  opts = opts || {};
  const cloneDir = opts.cloneDir || coordCloneDir();
  const self = opts.selfHost || selfHostname();
  const th = opts.thresholds || thresholds();
  const now = Date.now();

  const files = readPeerExportFiles(cloneDir);
  const peerFiles = files.filter((f) => f.host !== self); // requirement #2: filter out self

  const entries = peerFiles.map((f) => {
    const ageMs = now - f.receivedAt.getTime();
    const state = classifyPeerState(ageMs, th);
    const receivedIso = f.receivedAt.toISOString();
    const provenance = (f.payload && f.payload.provenance) || {};
    const plans = Array.isArray(f.payload.plans) ? f.payload.plans : [];
    const sessions = Array.isArray(f.payload.sessions) ? f.payload.sessions : [];
    return {
      host: f.host,
      state: state,
      state_label: stateLabel(state, ageMs, receivedIso),
      age_minutes: minutesAgo(ageMs),
      received_at: receivedIso,
      branch: provenance.branch || '',
      dirty: !!provenance.dirty,
      head_sha: provenance.head_sha || '',
      unmerged: isUnmerged(provenance),
      plans: plans.map((p) => ({
        plan_slug: p.plan_slug || '',
        plan_doc: p.plan_doc || null,
        repo: p.repo || '',
        plan_progress: p.progress || { done: 0, in_flight: 0, not_started: 0, total: 0 },
        tasks: Array.isArray(p.tasks) ? p.tasks.map((t) => ({ id: t.id, done: !!t.done, in_flight: !!t.in_flight })) : [],
        // F4/requirement 8: EVERY peer plan row always carries this label —
        // never a bare checkbox that could read as local truth.
        provenance_label: provenanceLabel(ageMs, f.host, provenance),
      })),
      sessions: sessions.map((s) => ({
        session_id: s.session_id || '',
        role: s.role || '',
        plan_slug: s.plan_slug || '',
        task_id: s.task_id || '',
        last_heartbeat_at: s.last_heartbeat_at || '',
        state: classifySessionAge(s.last_heartbeat_at, th.sessionStaleMin),
      })),
    };
  }).sort((a, b) => a.host.localeCompare(b.host));

  return {
    has_data: entries.length > 0,
    my_coord_refresh: myCoordRefresh(cloneDir),
    entries: entries,
  };
}

module.exports = {
  computePeerView,
  coordCloneDir,
  selfHostname,
  thresholds,
  readPeerExportFiles,
  classifyPeerState,
  classifySessionAge,
  isUnmerged,
  provenanceLabel,
  stateLabel,
  myCoordRefresh,
  minutesAgo,
};

// ============================================================
// --self-test — sandboxed fixture suite (unit-level; the WIRING proof over
// real HTTP is server.selftest.js's job — see that file's S64+).
// ============================================================
async function selfTest() {
  let passed = 0, failed = 0;
  function ok(name, cond, detail) {
    if (cond) { passed++; console.log('  PASS: ' + name); }
    else { failed++; console.log('  FAIL: ' + name + (detail ? ' (' + detail + ')' : '')); }
  }

  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'peer-view-st-'));
  const savedEnv = {};
  const ENV_KEYS = [
    'COORD_CLONE_DIR', 'EXPORT_HOSTNAME', 'COCKPIT_PEER_FRESH_MIN',
    'COCKPIT_PEER_KEEPALIVE_MIN', 'COCKPIT_PEER_TRANSPORT_MARGIN_MIN',
    'OBS_STALE_MIN', 'COCKPIT_COORD_SYNC_STATE_DIR',
  ];
  ENV_KEYS.forEach((k) => { savedEnv[k] = process.env[k]; });

  try {
    // ---- Scenario 1: classifyPeerState boundary conditions (default
    // thresholds: fresh<=20min, estate-unchanged<=80min, else unreachable).
    const th = thresholds();
    ok('1. classifyPeerState: exactly at the fresh boundary is still fresh-ish',
      classifyPeerState(20 * 60 * 1000, th) === 'fresh-ish');
    ok('1b. classifyPeerState: just past the fresh boundary is estate-unchanged',
      classifyPeerState(20 * 60 * 1000 + 1, th) === 'estate-unchanged');
    ok('1c. classifyPeerState: exactly at the unreachable boundary (80min) is still estate-unchanged',
      classifyPeerState(80 * 60 * 1000, th) === 'estate-unchanged');
    ok('1d. classifyPeerState: just past 80min is peer-unreachable',
      classifyPeerState(80 * 60 * 1000 + 1, th) === 'peer-unreachable');

    // ---- Scenario 2: A5 — thresholds are env-injectable (a compressed
    // timescale, per task 8's acceptance-drill need).
    process.env.COCKPIT_PEER_FRESH_MIN = '1';
    process.env.COCKPIT_PEER_KEEPALIVE_MIN = '2';
    process.env.COCKPIT_PEER_TRANSPORT_MARGIN_MIN = '1';
    const thCustom = thresholds();
    ok('2. A5 thresholds honor env overrides (fresh=1min, keepalive=2min, margin=1min)',
      thCustom.freshMs === 60000 && thCustom.keepaliveMs === 120000 && thCustom.marginMs === 60000);
    ok('2b. classifyPeerState with the compressed thresholds: 90s is estate-unchanged (past 1min fresh, within 3min unreachable bound)',
      classifyPeerState(90 * 1000, thCustom) === 'estate-unchanged');
    delete process.env.COCKPIT_PEER_FRESH_MIN;
    delete process.env.COCKPIT_PEER_KEEPALIVE_MIN;
    delete process.env.COCKPIT_PEER_TRANSPORT_MARGIN_MIN;

    // ---- Scenario 3: stateLabel copy matches the plan's literal quotes.
    ok('3. stateLabel fresh-ish shows a relative age',
      stateLabel('fresh-ish', 4 * 60 * 1000, '2026-01-01T00:00:00.000Z') === 'fresh-ish (4m ago)');
    ok('3b. stateLabel estate-unchanged shows "since <ts>"',
      stateLabel('estate-unchanged', 0, '2026-01-01T00:00:00.000Z') === 'estate unchanged since 2026-01-01T00:00:00.000Z');
    ok('3c. stateLabel peer-unreachable shows "since <ts>"',
      stateLabel('peer-unreachable', 0, '2026-01-01T00:00:00.000Z') === 'peer unreachable since 2026-01-01T00:00:00.000Z');

    // ---- Scenario 4: isUnmerged / provenanceLabel — F4.
    ok('4. isUnmerged: master + clean -> merged (false)', isUnmerged({ branch: 'master', dirty: false }) === false);
    ok('4b. isUnmerged: non-master branch -> unmerged (true)', isUnmerged({ branch: 'build/x', dirty: false }) === true);
    ok('4c. isUnmerged: master but dirty -> unmerged (true)', isUnmerged({ branch: 'master', dirty: true }) === true);
    ok('4d. isUnmerged: missing branch -> unmerged (honest unknown, not defaulted to merged)', isUnmerged({}) === true);
    ok('4e. provenanceLabel matches the plan\'s literal quote shape',
      provenanceLabel(4 * 60 * 1000, 'host-b', { branch: 'build/foo', dirty: false }) ===
      'as of 4m ago on host-b (build/foo, unmerged)');

    // ---- Scenario 5: classifySessionAge — A3c, reader-side, age-only.
    ok('5. classifySessionAge: recent heartbeat -> fresh', classifySessionAge(new Date().toISOString(), 30) === 'fresh');
    ok('5b. classifySessionAge: 45min-old heartbeat with a 30min threshold -> stale',
      classifySessionAge(new Date(Date.now() - 45 * 60 * 1000).toISOString(), 30) === 'stale');
    ok('5c. classifySessionAge: missing timestamp -> unknown (never a crash/guess)', classifySessionAge('', 30) === 'unknown');

    // ---- Scenario 6: readPeerExportFiles — A7 skip-bad-record tolerance.
    const s6 = path.join(tmp, 's6-clone');
    const s6dir = planExportDir(s6);
    fs.mkdirSync(s6dir, { recursive: true });
    fs.writeFileSync(path.join(s6dir, 'good-host.json'), JSON.stringify({ schema_version: 1, provenance: { hostname: 'good-host' }, plans: [], sessions: [] }));
    fs.writeFileSync(path.join(s6dir, 'corrupt-host.json'), '{"schema_version":1, "provenance": TRUNCATED');
    fs.writeFileSync(path.join(s6dir, 'not-json.txt'), 'ignored — not even a .json file');
    const s6files = readPeerExportFiles(s6);
    ok('6. A7: exactly one well-formed peer file is read; the corrupt one is skipped WITHOUT throwing; non-.json ignored',
      s6files.length === 1 && s6files[0].host === 'good-host', JSON.stringify(s6files.map((f) => f.host)));

    // ---- Scenario 7: no coord clone at all / no plan-export dir -> empty,
    // never a throw.
    const s7 = path.join(tmp, 's7-nope');
    ok('7. readPeerExportFiles on a non-existent clone dir returns [] (never throws)',
      JSON.stringify(readPeerExportFiles(s7)) === '[]');

    // ---- Scenario 8: computePeerView end-to-end — self-filter, has_data,
    // provenance_label wiring, session age classification.
    const s8 = path.join(tmp, 's8-clone');
    const s8dir = planExportDir(s8);
    fs.mkdirSync(s8dir, { recursive: true });
    fs.writeFileSync(path.join(s8dir, 'self-host.json'), JSON.stringify({
      schema_version: 1, provenance: { hostname: 'self-host', branch: 'master', dirty: false },
      plans: [], sessions: [],
    }));
    fs.writeFileSync(path.join(s8dir, 'peer-host.json'), JSON.stringify({
      schema_version: 1, provenance: { hostname: 'peer-host', branch: 'build/y', head_sha: 'aaa111', dirty: true },
      plans: [{ plan_slug: 'demo-plan', plan_doc: null, repo: '/peer/repo', tasks: [{ id: '1', done: true, in_flight: false }], progress: { done: 1, in_flight: 0, not_started: 0, total: 1 } }],
      sessions: [{ session_id: 'peer-sess-1', role: 'dispatcher', plan_slug: 'demo-plan', task_id: '1', last_heartbeat_at: new Date().toISOString() }],
    }));
    const view8 = computePeerView({ cloneDir: s8, selfHost: 'self-host' });
    ok('8. computePeerView: self filtered out, exactly one peer entry, has_data:true',
      view8.has_data === true && view8.entries.length === 1 && view8.entries[0].host === 'peer-host',
      JSON.stringify(view8.entries.map((e) => e.host)));
    ok('8b. peer entry carries branch/dirty/unmerged from provenance',
      view8.entries[0].branch === 'build/y' && view8.entries[0].dirty === true && view8.entries[0].unmerged === true);
    ok('8c. peer plan row carries a provenance_label naming the host + unmerged',
      /on peer-host/.test(view8.entries[0].plans[0].provenance_label) && /unmerged/.test(view8.entries[0].plans[0].provenance_label),
      view8.entries[0].plans[0].provenance_label);
    ok('8d. peer session classified fresh by age (just-now heartbeat)',
      view8.entries[0].sessions[0].state === 'fresh');
    ok('8e. a fresh receive (just wrote the fixture) classifies fresh-ish',
      view8.entries[0].state === 'fresh-ish');

    // ---- Scenario 9: computePeerView on an entirely empty/absent clone ->
    // has_data:false (the "no data yet" collapse state), never a crash.
    const view9 = computePeerView({ cloneDir: path.join(tmp, 's9-nope'), selfHost: 'self-host' });
    ok('9. computePeerView on a non-existent clone -> has_data:false, entries:[] (no data yet)',
      view9.has_data === false && view9.entries.length === 0);

    // ---- Scenario 10: computePeerView when only self's file exists ->
    // still has_data:false (nothing for a PEER to show).
    const s10 = path.join(tmp, 's10-clone');
    const s10dir = planExportDir(s10);
    fs.mkdirSync(s10dir, { recursive: true });
    fs.writeFileSync(path.join(s10dir, 'self-host.json'), JSON.stringify({ schema_version: 1, provenance: { hostname: 'self-host' }, plans: [], sessions: [] }));
    const view10 = computePeerView({ cloneDir: s10, selfHost: 'self-host' });
    ok('10. computePeerView with ONLY self\'s own file present -> has_data:false (nothing for a peer to show)',
      view10.has_data === false && view10.entries.length === 0);

    // ---- Scenario 11: an aged (2h-old) receive classifies peer-unreachable.
    const s11 = path.join(tmp, 's11-clone');
    const s11dir = planExportDir(s11);
    fs.mkdirSync(s11dir, { recursive: true });
    const s11file = path.join(s11dir, 'stale-peer.json');
    fs.writeFileSync(s11file, JSON.stringify({ schema_version: 1, provenance: { hostname: 'stale-peer', branch: 'master', dirty: false }, plans: [], sessions: [] }));
    const twoHoursAgo = new Date(Date.now() - 2 * 60 * 60 * 1000);
    fs.utimesSync(s11file, twoHoursAgo, twoHoursAgo);
    const view11 = computePeerView({ cloneDir: s11, selfHost: 'self-host' });
    ok('11. a 2h-stale receive classifies peer-unreachable, named as such in state_label',
      view11.entries.length === 1 && view11.entries[0].state === 'peer-unreachable' &&
      /^peer unreachable since /.test(view11.entries[0].state_label),
      JSON.stringify(view11.entries[0] && view11.entries[0].state_label));

    // ---- Scenario 12: myCoordRefresh — FETCH_HEAD primary source.
    const s12 = path.join(tmp, 's12-clone');
    fs.mkdirSync(path.join(s12, '.git'), { recursive: true });
    const fetchHeadFile = path.join(s12, '.git', 'FETCH_HEAD');
    fs.writeFileSync(fetchHeadFile, 'deadbeef\t\tbranch \'main\' of ssh://example.test/coord\n');
    const fiveMinAgo = new Date(Date.now() - 5 * 60 * 1000);
    fs.utimesSync(fetchHeadFile, fiveMinAgo, fiveMinAgo);
    const refresh12 = myCoordRefresh(s12);
    ok('12. myCoordRefresh reads FETCH_HEAD mtime as the primary source (~5m ago)',
      refresh12.source === 'fetch_head_mtime' && refresh12.age_minutes >= 4 && refresh12.age_minutes <= 6,
      JSON.stringify(refresh12));

    // ---- Scenario 13: myCoordRefresh — cycles.log fallback when FETCH_HEAD
    // is absent.
    const s13 = path.join(tmp, 's13-clone'); // no .git dir at all
    const s13StateDir = path.join(tmp, 's13-coord-sync-state');
    fs.mkdirSync(s13StateDir, { recursive: true });
    const tenMinAgoIso = new Date(Date.now() - 10 * 60 * 1000).toISOString();
    fs.writeFileSync(path.join(s13StateDir, 'cycles.log'),
      'ts=2026-01-01T00:00:00Z host=x outcome=pushed export_rc=0 push_rc=0 pull_rc=0 pull_result=synced duration_ms=100\n' +
      'ts=' + tenMinAgoIso + ' host=x outcome=pushed export_rc=0 push_rc=0 pull_rc=0 pull_result=synced duration_ms=120\n');
    process.env.COCKPIT_COORD_SYNC_STATE_DIR = s13StateDir;
    const refresh13 = myCoordRefresh(s13);
    ok('13. myCoordRefresh falls back to cycles.log\'s last line when FETCH_HEAD is absent (~10m ago)',
      refresh13.source === 'cycle_log' && refresh13.age_minutes >= 9 && refresh13.age_minutes <= 11,
      JSON.stringify(refresh13));
    delete process.env.COCKPIT_COORD_SYNC_STATE_DIR;

    // ---- Scenario 14: myCoordRefresh — neither source available -> honest
    // "never refreshed", never a crash/guess.
    const refresh14 = myCoordRefresh(path.join(tmp, 's14-nope'));
    ok('14. myCoordRefresh with neither FETCH_HEAD nor a cycle log -> source:none, "never refreshed"',
      refresh14.source === 'none' && refresh14.last_refreshed_at === null && /never refreshed/.test(refresh14.label));

    // ---- Scenario 15: EXPORT_HOSTNAME override drives selfHostname() (and
    // therefore self-filtering), requirement #2.
    process.env.EXPORT_HOSTNAME = 'sim-peer-b';
    ok('15. selfHostname() honors EXPORT_HOSTNAME override', selfHostname() === 'sim-peer-b');
    const s15 = path.join(tmp, 's15-clone');
    const s15dir = planExportDir(s15);
    fs.mkdirSync(s15dir, { recursive: true });
    fs.writeFileSync(path.join(s15dir, 'sim-peer-b.json'), JSON.stringify({ schema_version: 1, provenance: { hostname: 'sim-peer-b' }, plans: [], sessions: [] }));
    fs.writeFileSync(path.join(s15dir, 'sim-peer-a.json'), JSON.stringify({ schema_version: 1, provenance: { hostname: 'sim-peer-a', branch: 'master', dirty: false }, plans: [], sessions: [] }));
    const view15 = computePeerView({ cloneDir: s15 }); // no explicit selfHost — must read the env override itself
    ok('15b. computePeerView (no explicit selfHost arg) filters using EXPORT_HOSTNAME, leaving only the other simulated peer',
      view15.entries.length === 1 && view15.entries[0].host === 'sim-peer-a',
      JSON.stringify(view15.entries.map((e) => e.host)));
    delete process.env.EXPORT_HOSTNAME;
  } finally {
    ENV_KEYS.forEach((k) => {
      if (savedEnv[k] === undefined) delete process.env[k];
      else process.env[k] = savedEnv[k];
    });
    try { fs.rmSync(tmp, { recursive: true, force: true }); } catch (_) { /* best-effort cleanup */ }
  }

  console.log('\n' + passed + ' passed, ' + failed + ' failed');
  return failed === 0 ? 0 : 1;
}

if (require.main === module) {
  if (process.argv.indexOf('--self-test') !== -1) {
    selfTest().then((code) => process.exit(code));
  } else {
    process.stdout.write(JSON.stringify(computePeerView(), null, 2) + '\n');
  }
}
