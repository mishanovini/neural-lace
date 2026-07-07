'use strict';
// derive-cache.js — the server-side derived-JSON cache (NL Observability
// Program Wave O, task O.4, specs-o §O.4 deliverable 1).
//
// WHY THIS EXISTS
// ============================================================
// Law 1 (DERIVE-DON'T-MAINTAIN, docs/reviews/2026-07-04-observability-design-
// sketch.md) says the cockpit must never render MAINTAINED state (the old
// tree-state.json event log) as truth. This module shells the real `nl <sub>
// --json` oracle (contract C5, adapters/claude-code/scripts/nl.sh) for every
// pane, caches each subcommand's last-good result, and refreshes on a timer.
// It is the ONLY place server.js reads derived truth from — every pane
// endpoint is a thin read of this cache, so "what the pane shows" and "what
// `nl <sub> --json` returns" are mechanically the same data path (the
// acceptance bar every one of the 10 runtime scenarios checks).
//
// CACHE ENTRY SHAPE (ux-review amendment 1 — error-masked-as-empty):
//   { data, rc, stderr_tail, derived_at }
// rc !== 0 means the LAST refresh attempt failed; `data` still holds the
// last-KNOWN-GOOD payload (or null if there has never been one) so a
// transient failure doesn't erase a pane that was working a moment ago —
// but the cache entry's rc/stderr_tail let the caller render an honest
// ERROR state instead of silently serving a stale success. The pane layer
// (server.js) decides how to render rc!=0; this module never lies about it.
//
// SANDBOXING: NL_BIN overrides the `nl` binary path (tests point this at a
// stub script); CTREE_PORT is server.js's own concern, not this module's.

const { spawn } = require('child_process');
const path = require('path');

// Resolve the real `nl` CLI location: adapters/claude-code/scripts/nl.sh.
// This checkout nests workstreams-ui under neural-lace/ (neural-lace/
// workstreams-ui/server/), while adapters/claude-code/ sits at the OUTER
// repo root (a sibling of neural-lace/, not of workstreams-ui/) — so the
// walk up from server/ is THREE levels (server -> workstreams-ui ->
// neural-lace -> repo root), not two. Verified live against this checkout's
// actual layout (see the O.4 livesmoke evidence in the task report-back).
// NL_BIN overrides this entirely — tests point it at a fixture stub
// asserting each pane endpoint returns derived JSON without needing the
// real estate.
function defaultNlBin() {
  return path.join(__dirname, '..', '..', '..', 'adapters', 'claude-code', 'scripts', 'nl.sh');
}

function nlBin() {
  return process.env.NL_BIN || defaultNlBin();
}

// defaultDeriveLib() — the C4 derivation lib (hooks/lib/observability-
// derive.sh), same three-level walk as defaultNlBin above. NL_DERIVE_LIB
// overrides (tests point this at a fixture lib exporting a stub
// od_harness_health so the health-gates fix is exercised without the real
// estate).
function defaultDeriveLib() {
  return path.join(__dirname, '..', '..', '..', 'adapters', 'claude-code', 'hooks', 'lib', 'observability-derive.sh');
}

function deriveLib() {
  return process.env.NL_DERIVE_LIB || defaultDeriveLib();
}

// The subcommands this cache refreshes. Each maps to one `nl` invocation.
// `args` are appended after the subcommand and before --json.
//
// `health` (Q4, O.4-fix1) is DELIBERATELY not routed through `nl status
// --json`: nl.sh's cmd_status composes {sessions, doctor} and DISCARDS the
// od_harness_health --json .gates[] array entirely (verified live —
// `bash nl.sh status --json` has no "gates" key while
// `source observability-derive.sh && od_harness_health --json` returns
// 15 gates with block/waiver/downgrade/dominant per gate, matching the
// acceptance oracle exactly). nl.sh (adapters/claude-code/scripts/nl.sh)
// is OUT OF O.4's declared scope (workstreams-ui/** only) and its owner
// (O.3) may add a `nl health --json` passthrough later — until then this
// module sources the C4 lib directly and calls the already-exported
// od_harness_health function (a read-only invocation of an existing
// contract function, NOT a modification of hooks/lib/observability-
// derive.sh). See runHealth() below.
const SUBCOMMANDS = {
  status: { args: [] },
  'needs-me': { args: [] },
  shipped: { args: [] }, // --since is appended per-call by refreshShipped
  costs: { args: [] },
  backlog: { args: [] },
  health: { args: [] },
};

// PER-SUBCOMMAND TIMEOUT OVERRIDE (O.4-fix1, item 6 — backlog pane
// permanent rc=124). The acceptance drill measured `nl backlog --json` at
// 80-162s on the real estate vs the OBS_NL_TIMEOUT_MS global default of
// 60000ms; a re-measurement during this fix's own livesmoke (2026-07-07)
// found it had grown further to ~258s (docs/backlog.md keeps growing —
// this is O.9's known, separate, open backlog-oracle performance issue,
// worsening over time, NOT something fixed here). OBS_NL_TIMEOUT_MS_<SUB>
// (subcommand name upper-cased, hyphens -> underscores, e.g.
// OBS_NL_TIMEOUT_MS_BACKLOG) overrides the global OBS_NL_TIMEOUT_MS for
// that one subcommand; falls back to the global, then the 60000ms
// default. `backlog` itself gets a higher built-in default (360000ms —
// comfortably above the measured ~258s with headroom for further growth
// before the next perf fix lands) since this is a client-side
// accommodation, not a fix to od_backlog_health's performance; operators
// on a smaller/faster estate can lower it via OBS_NL_TIMEOUT_MS_BACKLOG.
const SUBCOMMAND_TIMEOUT_DEFAULTS_MS = { backlog: 360000 };
function timeoutMsFor(sub) {
  const perSubKey = 'OBS_NL_TIMEOUT_MS_' + sub.toUpperCase().replace(/-/g, '_');
  if (process.env[perSubKey]) return Number(process.env[perSubKey]);
  if (process.env.OBS_NL_TIMEOUT_MS) return Number(process.env.OBS_NL_TIMEOUT_MS);
  return SUBCOMMAND_TIMEOUT_DEFAULTS_MS[sub] || 60000;
}

// spawnAsync(cmd, args, timeoutMs, timeoutLabel) -> Promise<{rc, stdout,
// stderr}> — the shared ASYNCHRONOUS (child_process `spawn`, never
// `spawnSync`) subprocess runner backing both runNl and runHealth. This is
// load-bearing, not a style choice: livesmoke against this checkout's real
// estate (O.4 report-back evidence) measured `nl backlog --json` at
// 80-162s wall time on a large/aged docs/backlog.md (a symptom of O.9's
// backlog-oracle performance on this specific estate — flagged as a
// follow-up, out of O.4's scope per the acceptance scenarios' own
// "nl/derivation correctness in isolation is an O.3/O.9 failure"
// carve-out). Node is single-threaded: a synchronous spawnSync call for
// ANY subcommand blocks the ENTIRE event loop, including the HTTP server's
// ability to accept new connections, for the full duration of that one
// call — so a slow `nl backlog` would make the WHOLE cockpit appear down
// (refuse every connection) for 50+ seconds on every refresh cycle on this
// real estate. `spawn` lets the event loop keep serving in-flight and new
// HTTP requests from the LAST-KNOWN-GOOD cache entries while a slow
// subcommand's child process runs in the background. Never throws: a
// spawn failure itself (ENOENT, no bash on PATH) resolves with rc=127 and
// the spawn error's message as stderr.
function spawnAsync(cmd, args, timeoutMs, timeoutLabel) {
  return new Promise((resolve) => {
    let child;
    try {
      child = spawn(cmd, args, { encoding: 'utf8' });
    } catch (err) {
      resolve({ rc: 127, stdout: '', stderr: String(err && err.message || err) });
      return;
    }
    let stdout = '', stderr = '', settled = false;
    const timer = setTimeout(() => {
      if (settled) return;
      settled = true;
      try { child.kill(); } catch (_) {}
      resolve({ rc: 124, stdout: '', stderr: (timeoutLabel || cmd) + ' timed out after ' + timeoutMs + 'ms' });
    }, timeoutMs);
    if (timer.unref) timer.unref();
    child.stdout.on('data', (d) => { stdout += d; });
    child.stderr.on('data', (d) => { stderr += d; });
    child.on('error', (err) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      resolve({ rc: 127, stdout: '', stderr: String(err && err.message || err) });
    });
    child.on('close', (code) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      resolve({ rc: code == null ? 1 : code, stdout: stdout, stderr: stderr });
    });
  });
}

// runNl(sub, extraArgs) -> Promise<{rc, stdout, stderr}> — spawns
// `bash <nl-bin> <sub> ...extraArgs --json` ASYNCHRONOUSLY. Per-subcommand
// timeout (O.4-fix1 item 6): OBS_NL_TIMEOUT_MS_<SUB> overrides
// OBS_NL_TIMEOUT_MS overrides the 60s (180s for backlog) default — see
// timeoutMsFor above.
function runNl(sub, extraArgs) {
  const bin = nlBin();
  const args = [bin, sub].concat(extraArgs || [], ['--json']);
  const timeoutMs = timeoutMsFor(sub);
  return spawnAsync('bash', args, timeoutMs, 'nl ' + sub);
}

// runHealth() -> Promise<{rc, stdout, stderr}> — Q4 fix (O.4-fix1 item 1).
// Sources the C4 derivation lib directly and calls the already-exported
// od_harness_health function, so the response carries .gates[] (15 gates
// with block_7d/waiver_7d/downgrade_7d/dominant on this estate) — data
// `nl status --json` never surfaces because nl.sh's cmd_status composes
// only {sessions, doctor} and discards .gates. This is a READ-ONLY
// invocation of an existing C4 contract function; it does not modify
// hooks/lib/observability-derive.sh. NL_DERIVE_LIB overrides for tests.
function runHealth() {
  const lib = deriveLib();
  const script = 'source "' + lib.replace(/"/g, '\\"') + '" && od_harness_health --json';
  const timeoutMs = timeoutMsFor('health');
  return spawnAsync('bash', ['-c', script], timeoutMs, 'nl health (od_harness_health)');
}

function tail(s, n) {
  if (!s) return '';
  const lines = String(s).split(/\r?\n/).filter(Boolean);
  return lines.slice(-n).join('\n');
}

function nowIso() {
  return new Date().toISOString();
}

// DeriveCache — one instance per server process. `refreshIntervalMs`
// defaults to 30s per specs-o §O.4 deliverable 1 ("batch-refreshed <= every
// 30s"). `since` is a function returning the ISO timestamp `nl shipped
// --since` should use; server.js supplies the Q3 last-look anchor (client-
// persisted, defaulting to 24h per ux-review amendment 3).
function DeriveCache(opts) {
  opts = opts || {};
  this.refreshIntervalMs = opts.refreshIntervalMs || (Number(process.env.OBS_REFRESH_MS) || 30000);
  this.getShippedSince = opts.getShippedSince || function () {
    return new Date(Date.now() - 24 * 3600 * 1000).toISOString();
  };
  this.entries = {}; // sub -> {data, rc, stderr_tail, derived_at}
  this.inFlight = {}; // sub -> boolean (refresh in progress)
  this.listeners = []; // called after every refresh cycle (for SSE push)
  Object.keys(SUBCOMMANDS).forEach((sub) => {
    this.entries[sub] = { data: null, rc: null, stderr_tail: '', derived_at: null };
  });
}

DeriveCache.prototype.onRefresh = function (fn) {
  this.listeners.push(fn);
};

DeriveCache.prototype._notify = function () {
  this.listeners.forEach((fn) => {
    try { fn(); } catch (_) { /* a listener's own failure must not break refresh */ }
  });
};

// refreshOne(sub) -> Promise<entry> — runs the CLI for one subcommand
// ASYNCHRONOUSLY (never blocks the event loop — see runNl's header), parses
// JSON on success, and ALWAYS writes a fresh cache entry (even on failure)
// so derived_at/rc/stderr_tail reflect the most recent attempt. On a parse
// failure (malformed JSON from an otherwise rc=0 CLI — should not happen
// but must never crash the server) the entry is treated as rc=1 with the
// raw stdout as the error detail, per the "never trust, verify" discipline.
// While a refresh is in-flight for a subcommand, callers get the CURRENT
// (possibly stale but still last-known-good) entry immediately rather than
// piling up duplicate child processes for the same subcommand.
DeriveCache.prototype.refreshOne = function (sub) {
  if (this.inFlight[sub]) return Promise.resolve(this.entries[sub]);
  this.inFlight[sub] = true;
  const extraArgs = sub === 'shipped' ? ['--since', this.getShippedSince()] : [];
  // health (Q4, O.4-fix1) is sourced directly (runHealth) rather than
  // through `nl status --json`'s lossy composition — see runHealth's
  // header. Every other subcommand goes through the normal `nl <sub>
  // --json` CLI path.
  const runner = sub === 'health' ? runHealth() : runNl(sub, extraArgs);
  return runner.then((r) => {
    let entry;
    if (r.rc === 0) {
      let parsed = null;
      let parseErr = null;
      try {
        parsed = JSON.parse(r.stdout);
      } catch (e) {
        parseErr = e;
      }
      if (parseErr) {
        entry = {
          data: this.entries[sub] && this.entries[sub].data, // keep last-known-good
          rc: 1,
          stderr_tail: tail('nl ' + sub + ' --json produced non-JSON output: ' + r.stdout, 20),
          derived_at: nowIso(),
        };
      } else {
        entry = { data: parsed, rc: 0, stderr_tail: '', derived_at: nowIso() };
      }
    } else {
      entry = {
        data: this.entries[sub] && this.entries[sub].data, // keep last-known-good for display
        rc: r.rc,
        stderr_tail: tail(r.stderr, 20),
        derived_at: nowIso(),
      };
    }
    this.entries[sub] = entry;
    this.inFlight[sub] = false;
    return entry;
  }, (err) => {
    this.inFlight[sub] = false;
    throw err;
  });
};

// refreshAll() -> Promise — kicks off every subcommand's refresh IN
// PARALLEL (Promise.all over concurrent `spawn` calls, not a serial await
// loop) so one slow subcommand (e.g. `nl backlog` on a large estate) does
// not delay the others. Notifies listeners (SSE push) once ALL panes have
// settled, matching the prior batch-refresh semantics from the caller's
// point of view.
DeriveCache.prototype.refreshAll = function () {
  const self = this;
  return Promise.all(Object.keys(SUBCOMMANDS).map((sub) => self.refreshOne(sub))).then(() => {
    self._notify();
  });
};

DeriveCache.prototype.get = function (sub) {
  return this.entries[sub] || { data: null, rc: 1, stderr_tail: 'unknown subcommand: ' + sub, derived_at: null };
};

// start() — kicks off the FIRST refresh in the background (fire-and-forget;
// deliberately NOT awaited) and returns immediately so server.listen() can
// bind and start accepting connections right away. Every pane read before
// the first refresh completes serves the initial {data:null, rc:null}
// entry, which server.js's paneResponse renders as the loading state
// client-side (rc === null, not rc !== 0 — see server.js's pane response
// shape) rather than a false error.
DeriveCache.prototype.start = function () {
  this.refreshAll().catch(() => {}); // fire-and-forget; refreshOne already captures failures per-entry
  this._timer = setInterval(() => { this.refreshAll().catch(() => {}); }, this.refreshIntervalMs);
  if (this._timer.unref) this._timer.unref();
};

DeriveCache.prototype.stop = function () {
  if (this._timer) clearInterval(this._timer);
};

// runWhy(sessionId, lastBlock) -> Promise<entry> — Q6 is on-demand (never
// part of the batch-refresh cycle: the sketch's non-goal list excludes
// per-gate custom polling, and a why-drawer is opened for ONE session at a
// time, not every session on every tick). Resolves to the SAME
// {data, rc, stderr_tail, derived_at} shape as a cache entry so the
// pane-rendering/error-state logic in server.js is uniform across every
// pane including this on-demand one. Asynchronous for the same reason as
// runNl generally (never block the event loop / other in-flight requests).
// VERDICT_LINE_RE — matches od_why's text-mode one-line verdict, e.g.
// "verdict: blocked by workstreams-state-gate (...); next: ... allow" or
// the no-block case "verdict: no block event found for this session".
var VERDICT_LINE_RE = /^verdict:.*$/m;

// fetchVerdictFromTextMode(sessionId, lastBlock) -> Promise<string|null> —
// O.4-fix1 item 3 (Q6 verdict line). `od_why --json` (contract C5) omits
// the `verdict` field that TEXT mode emits (LIB DEPENDENCY, NOT fixed
// here: hooks/lib/observability-derive.sh's od_why prints its one-line
// verdict via `printf` AFTER the `if json_mode: ... return 0` early-return,
// so JSON mode never sees it — verified by reading the function; another
// builder owns that file during this task). Until the lib lands a fix,
// this shells `nl why <sid> [--last-block]` in TEXT mode (no --json) and
// lifts the final "verdict: ..." line so the drawer satisfies the
// acceptance scenario regardless of lib landing order. Best-effort: any
// failure here resolves null (caller falls back to no verdict line rather
// than erroring the whole drawer over a missing nice-to-have).
function fetchVerdictFromTextMode(sessionId, lastBlock) {
  const bin = nlBin();
  const args = [bin, 'why', sessionId];
  if (lastBlock) args.push('--last-block');
  const timeoutMs = timeoutMsFor('why');
  return spawnAsync('bash', args, timeoutMs, 'nl why ' + sessionId).then((r) => {
    if (r.rc !== 0 || !r.stdout) return null;
    const m = VERDICT_LINE_RE.exec(r.stdout);
    return m ? m[0].trim() : null;
  }, () => null);
}

// runWhy(sessionId, lastBlock) -> Promise<entry> — Q6 is on-demand (never
// part of the batch-refresh cycle: the sketch's non-goal list excludes
// per-gate custom polling, and a why-drawer is opened for ONE session at a
// time, not every session on every tick). Resolves to the SAME
// {data, rc, stderr_tail, derived_at} shape as a cache entry so the
// pane-rendering/error-state logic in server.js is uniform across every
// pane including this on-demand one. Asynchronous for the same reason as
// runNl generally (never block the event loop / other in-flight requests).
//
// O.4-fix1 item 3: if the parsed JSON lacks a `verdict` field (the current,
// un-fixed lib behavior), a SECOND shell-out fetches the text-mode verdict
// line and attaches it as `data.verdict` before resolving — so the UI
// renders the mandated one-line verdict today, and transparently stops
// making the extra call the moment od_why --json starts emitting `verdict`
// itself (the `'verdict' in parsed` check below goes true and this branch
// is skipped).
function runWhy(sessionId, lastBlock) {
  const extraArgs = [sessionId];
  if (lastBlock) extraArgs.push('--last-block');
  return runNl('why', extraArgs).then((r) => {
    if (r.rc === 0) {
      let parsed = null, parseErr = null;
      try { parsed = JSON.parse(r.stdout); } catch (e) { parseErr = e; }
      if (parseErr) {
        return { data: null, rc: 1, stderr_tail: tail('nl why --json produced non-JSON output: ' + r.stdout, 20), derived_at: nowIso() };
      }
      if (parsed && !('verdict' in parsed) && Array.isArray(parsed.chain) && parsed.chain.length > 0) {
        return fetchVerdictFromTextMode(sessionId, lastBlock).then((verdict) => {
          if (verdict) parsed.verdict = verdict;
          return { data: parsed, rc: 0, stderr_tail: '', derived_at: nowIso() };
        });
      }
      return { data: parsed, rc: 0, stderr_tail: '', derived_at: nowIso() };
    }
    return { data: null, rc: r.rc, stderr_tail: tail(r.stderr, 20), derived_at: nowIso() };
  });
}

module.exports = { DeriveCache, runWhy, nlBin, SUBCOMMANDS, timeoutMsFor };
