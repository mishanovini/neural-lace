'use strict';
// server/state-watch.js — PUSH fast path for DeriveCache (2026-08-02
// operator correction on the subprocess-storm fix: a TTL/timer poll,
// however infrequent, is still PULL — cost scales with clock ticks, not
// with change rate. This module watches the on-disk state that feeds every
// `nl <sub> --json` derivation (session heartbeats, signal-ledger.jsonl,
// the needs-you ledger, doctor-cache.json, obs-costs-cache.json,
// remote-ledgers, docs/backlog.md) with fs.watch and triggers ONE
// debounced cache.refreshAll() per burst of real changes, instead of on a
// fixed interval regardless of whether anything changed.
//
// DeriveCache's own timer (cache.start()'s setInterval, see
// derive-cache.js) becomes the ANTI-ENTROPY FLOOR only, at a low frequency
// — the safety net for the two ways a pure push design silently drifts:
// (a) fs.watch is not 100%-reliable cross-platform (missed events, e.g. a
// rename racing the watch setup), (b) a state producer this module doesn't
// know to watch. The floor heals both without being the primary path.
//
// HONEST SCOPE LIMIT (see this task's report): this watches the INPUT
// files/dirs and re-triggers the EXISTING shell-out (`nl <sub> --json` /
// `od_harness_health`) — it does NOT reimplement the derivation logic in
// Node. That logic lives in adapters/claude-code/hooks/lib/observability-
// derive.sh (owned by another builder; out of this task's declared scope,
// workstreams-ui/** only, and re-deriving it here would be exactly the
// "third grammar" derive-lib.js's own header warns against). So a real
// change still costs one subprocess spawn — but spawns now scale with
// CHANGE RATE (debounced), never with a fixed clock tick or the volume of
// unrelated HTTP requests hitting the cache's read side.
//
// ENV KNOBS:
//   OBS_WATCH_DIRS         - comma-separated list of directories that
//                            COMPLETELY replaces the computed default list
//                            (test sandboxing — points the watcher at a
//                            tmp dir instead of the real ~/.claude/state
//                            estate + this repo's real docs/).
//   OBS_WATCH_DISABLED=1   - disables the watcher entirely (mirrors
//                            AUDITOR_DISABLED's sandboxing convention);
//                            the anti-entropy floor timer remains the only
//                            trigger.
//   OBS_WATCH_DEBOUNCE_MS  - quiet-period before a burst of changes fires
//                            one refresh (default 2000).
//   OBS_WATCH_MAX_WAIT_MS  - hard cap on how long a CONTINUOUS burst of
//                            changes can defer a refresh (default 15000) —
//                            without this, a debounce alone could never
//                            fire under sustained sub-2s-apart churn
//                            (e.g. many concurrently-heartbeating sessions).
//
// Every path below is resolved the SAME way the underlying derivation
// reads it (same env-var override names: HEARTBEAT_STATE_DIR,
// SIGNAL_LEDGER_PATH, NEEDS_YOU_STATE_DIR, OBS_DOCTOR_CACHE_DIR /
// DOCTOR_CACHE_PATH, OBS_COSTS_CACHE, OBS_REMOTE_LEDGERS_DIR,
// OBS_BACKLOG_PATH) — see derive-cache.js's own header + observability-
// derive.sh's od_sessions/od_needs_me/od_harness_health/od_costs/
// od_backlog_health for the reads this mirrors.

const fs = require('fs');
const os = require('os');
const path = require('path');

function homeDir() {
  return process.env.HOME || os.homedir();
}

// defaultWatchDirs(mainRepoRootFn) -> string[] absolute, deduped directory
// paths — the computed production default when OBS_WATCH_DIRS is unset.
function defaultWatchDirs(mainRepoRootFn) {
  const home = homeDir();
  const stateDir = process.env.SIGNAL_LEDGER_PATH
    ? path.dirname(process.env.SIGNAL_LEDGER_PATH)
    : path.join(home, '.claude', 'state');
  const heartbeatDir = process.env.HEARTBEAT_STATE_DIR || path.join(home, '.claude', 'state', 'heartbeats');
  const needsYouDir = process.env.NEEDS_YOU_STATE_DIR || path.join(home, '.claude', 'state', 'needs-you');
  const doctorCacheDir = process.env.OBS_DOCTOR_CACHE_DIR ||
    (process.env.DOCTOR_CACHE_PATH ? path.dirname(process.env.DOCTOR_CACHE_PATH) : path.join(home, '.claude', 'state', 'digest'));
  const costsCacheDir = process.env.OBS_COSTS_CACHE ? path.dirname(process.env.OBS_COSTS_CACHE) : stateDir;
  const remoteLedgersDir = process.env.OBS_REMOTE_LEDGERS_DIR || path.join(home, '.claude', 'state', 'remote-ledgers');
  let repoRoot = process.cwd();
  if (typeof mainRepoRootFn === 'function') {
    try { repoRoot = mainRepoRootFn() || repoRoot; } catch (_) { /* fall back to cwd */ }
  }
  const backlogDir = process.env.OBS_BACKLOG_PATH ? path.dirname(process.env.OBS_BACKLOG_PATH) : path.join(repoRoot, 'docs');

  const candidates = [stateDir, heartbeatDir, needsYouDir, doctorCacheDir, costsCacheDir, remoteLedgersDir, backlogDir];
  const seen = {};
  const out = [];
  candidates.forEach((d) => {
    if (!d) return;
    let abs;
    try { abs = path.resolve(d); } catch (_) { return; }
    if (seen[abs]) return;
    seen[abs] = true;
    out.push(abs);
  });
  return out;
}

// resolveWatchDirs(mainRepoRootFn) -> string[] — OBS_WATCH_DIRS wins whole,
// else the computed default list above.
function resolveWatchDirs(mainRepoRootFn) {
  if (process.env.OBS_WATCH_DIRS) {
    return process.env.OBS_WATCH_DIRS.split(',')
      .map((s) => s.trim())
      .filter(Boolean)
      .map((d) => path.resolve(d));
  }
  return defaultWatchDirs(mainRepoRootFn);
}

// createDebouncedTrigger(fn, waitMs, maxWaitMs) -> {trigger, cancel}
//
// Trailing-edge debounce WITH a max-wait cap: each call to trigger()
// restarts a waitMs timer, so a burst of rapid changes collapses to ONE
// fn() call after the burst goes quiet for waitMs — but a burst that never
// goes quiet (continuous churn under waitMs apart) would otherwise defer
// fn() forever, so maxWaitMs bounds the total wait from the FIRST trigger()
// in the burst, guaranteeing fn() still fires periodically during sustained
// change. During genuine idle (no trigger() calls at all) NOTHING fires —
// this is the whole point: zero spawns/recomputes when nothing changed.
function createDebouncedTrigger(fn, waitMs, maxWaitMs) {
  let timer = null;
  let firstQueuedAt = null;
  function fire() {
    timer = null;
    firstQueuedAt = null;
    try { fn(); } catch (_) { /* caller's own responsibility to not throw */ }
  }
  function trigger() {
    const now = Date.now();
    if (firstQueuedAt == null) firstQueuedAt = now;
    if (timer) clearTimeout(timer);
    const remainingMax = maxWaitMs - (now - firstQueuedAt);
    const delay = Math.max(0, Math.min(waitMs, remainingMax));
    timer = setTimeout(fire, delay);
    if (timer.unref) timer.unref();
  }
  function cancel() {
    if (timer) clearTimeout(timer);
    timer = null;
    firstQueuedAt = null;
  }
  return { trigger: trigger, cancel: cancel };
}

// startStateWatch(opts) -> {stop, watchedDirs, stats, disabled}
//
// opts.mainRepoRoot  - fn returning the repo root (docs/backlog.md default).
//                       Ignored when opts.dirs is given.
// opts.dirs          - EXPLICIT directory list; when given, this bypasses
//                       OBS_WATCH_DIRS/the computed default entirely (used
//                       by server.js's second watch group — the
//                       nl-maintenance snapshot dir — which is a disjoint
//                       concern from the six nl-subcommand inputs and needs
//                       its own independent trigger; see server.js's two
//                       startStateWatch() call sites).
// opts.onTrigger     - REQUIRED: called (debounced) on a relevant fs event.
//                       server.js passes `() => cache.refreshAll().catch(()=>{})`
//                       for the nl-subcommand group and `broadcastRefresh`
//                       for the maintenance-snapshot group (a materialized
//                       file the server only re-reads, never re-derives —
//                       see buildMaintenancePane's header — so pushing a
//                       browser refresh is all that group needs; it must
//                       NOT also re-trigger the nl-subcommand spawns, which
//                       is exactly why it is a separate watch group with a
//                       separate onTrigger rather than sharing refreshAll).
// opts.waitMs/opts.maxWaitMs - override the debounce window (else env/default).
//
// Never throws: a missing watch directory (ENOENT — a fresh estate that has
// never written e.g. remote-ledgers/) or an unwatchable one (EPERM) is
// recorded in stats.watchErrors and skipped, exactly like every other
// best-effort reader in this codebase (derive-lib.js's readJsonlLines,
// listRawHeartbeatsResult, etc.) — a missing state dir must never crash the
// server or block the port bind.
function startStateWatch(opts) {
  opts = opts || {};
  const stats = { events: 0, triggers: 0, watchErrors: [] };
  if (process.env.OBS_WATCH_DISABLED === '1') {
    return { stop: function () {}, watchedDirs: [], stats: stats, disabled: true };
  }
  const onTrigger = typeof opts.onTrigger === 'function' ? opts.onTrigger : function () {};
  const waitMs = opts.waitMs || Number(process.env.OBS_WATCH_DEBOUNCE_MS) || 2000;
  const maxWaitMs = opts.maxWaitMs || Number(process.env.OBS_WATCH_MAX_WAIT_MS) || 15000;
  const debounced = createDebouncedTrigger(function () {
    stats.triggers++;
    onTrigger();
  }, waitMs, maxWaitMs);

  const dirs = Array.isArray(opts.dirs) && opts.dirs.length
    ? opts.dirs.map((d) => path.resolve(d))
    : resolveWatchDirs(opts.mainRepoRoot);
  const watchers = [];
  dirs.forEach((dir) => {
    try {
      const w = fs.watch(dir, { persistent: false }, function () {
        stats.events++;
        debounced.trigger();
      });
      w.on('error', function (err) {
        stats.watchErrors.push({ dir: dir, error: String(err && err.message || err) });
      });
      if (w.unref) w.unref();
      watchers.push(w);
    } catch (err) {
      stats.watchErrors.push({ dir: dir, error: String(err && err.message || err) });
    }
  });

  function stop() {
    debounced.cancel();
    watchers.forEach((w) => { try { w.close(); } catch (_) { /* already closed */ } });
  }

  return { stop: stop, watchedDirs: dirs, stats: stats, disabled: false };
}

module.exports = {
  startStateWatch: startStateWatch,
  resolveWatchDirs: resolveWatchDirs,
  defaultWatchDirs: defaultWatchDirs,
  createDebouncedTrigger: createDebouncedTrigger,
};
