#!/usr/bin/env node
'use strict';
// Component B — the RUNNER. The I/O shell around the pure reconciler.
// orchestration-architecture-2026-05-30.md §3 (the reconciliation pass) + §8
// (surface-first; auto-spawn gated).
//
// One pass:
//   1. acquire a single-machine lock (atomic; steals a stale lock)
//   2. consume the wake queue (delete trigger files — they are NOT state)
//   3. read the Workstreams state (via state.js — the SAME tree-state.json the GUI uses)
//   4. scan live sessions (sessions.js transcript-mtime — NOT `claude agents`)
//   5. load local claims stub (Component C is OUT in v1 — usually {})
//   6. reconcile()  ← the pure brain
//   7. apply emitted events: schema-valid ones (item-committed) via appendEvent;
//      claim-released → the local claims stub
//   8. write the surface file (spawnable + pendingMisha + orphans + spawnPlan)
//      — the universal output Dispatch / the GUI read
//   9. if config.autoSpawn (DEFAULT OFF): launch the headless-local spawnPlan
//      entries via `claude -p`. Code/Cowork/Routine entries are NEVER launched
//      here (a subprocess cannot call the MCP spawn tools — ADR-031 r5); they
//      are surfaced for Dispatch's agent loop.
//
// Never throws fatally — a runner crash must not break the harness. Exit 0
// except on a usage error (exit 2).
//
// Usage:
//   node reconciler-run.js [--dry-run] [--no-spawn] [--json] [--state <path>]
//     --dry-run : compute + print only; NO event emission, NO surface write, NO spawn
//     --no-spawn: emit + surface, but never launch (force surface-only this pass)
//     --json    : print the full reconcile result as JSON (else a human report)
//     --state   : override the state file path (tests)

const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');

const stateLib = require('./state.js');
const sessions = require('./sessions.js');
const { reconcile } = require('./reconciler.js');
const { PATHS, loadConfig } = require('./reconciler-config.js');

// Only these emitted-event types are valid ADR-032 schema events the runner may
// appendEvent. Everything else (claim-released) is Component-C/local-stub only.
const SCHEMA_EMITTABLE = new Set(['item-committed']);

function parseArgs(argv) {
  const a = { dryRun: false, noSpawn: false, json: false, statePath: null };
  for (let i = 2; i < argv.length; i++) {
    const t = argv[i];
    if (t === '--dry-run') a.dryRun = true;
    else if (t === '--no-spawn') a.noSpawn = true;
    else if (t === '--json') a.json = true;
    else if (t === '--state') a.statePath = argv[++i];
    else if (t === '-h' || t === '--help') { a.help = true; }
  }
  return a;
}

// ── lock (atomic create; steal if stale) ────────────────────────────────────
function acquireLock(lockPath, staleMinutes) {
  try { fs.mkdirSync(path.dirname(lockPath), { recursive: true }); } catch (_) {}
  try {
    const fd = fs.openSync(lockPath, 'wx'); // exclusive create — fails if exists
    fs.writeSync(fd, String(process.pid) + ' ' + new Date().toISOString());
    fs.closeSync(fd);
    return true;
  } catch (err) {
    if (err && err.code === 'EEXIST') {
      // Steal if the existing lock is stale (crashed runner).
      try {
        const st = fs.statSync(lockPath);
        const ageMin = (Date.now() - st.mtimeMs) / 60000;
        if (ageMin > staleMinutes) {
          fs.unlinkSync(lockPath);
          return acquireLock(lockPath, staleMinutes);
        }
      } catch (_) {}
      return false;
    }
    return false; // any other error → treat as not-acquired (don't crash)
  }
}
function releaseLock(lockPath) { try { fs.unlinkSync(lockPath); } catch (_) {} }

// ── queue consumption (wake files are triggers, not state) ───────────────────
function consumeQueue(queueDir) {
  let files = [];
  try { files = fs.readdirSync(queueDir).filter(function (f) { return f.endsWith('.json'); }); }
  catch (_) { return 0; }
  let n = 0;
  for (const f of files) {
    try { fs.unlinkSync(path.join(queueDir, f)); n++; } catch (_) {}
  }
  return n;
}

// ── local claims stub (Component C is OUT in v1) ─────────────────────────────
function loadClaims(claimsPath) {
  try {
    if (fs.existsSync(claimsPath)) return JSON.parse(fs.readFileSync(claimsPath, 'utf8')) || {};
  } catch (_) {}
  return {};
}
function saveClaims(claimsPath, claims) {
  try {
    fs.mkdirSync(path.dirname(claimsPath), { recursive: true });
    fs.writeFileSync(claimsPath, JSON.stringify(claims, null, 2), 'utf8');
  } catch (_) {}
}

// Resolve the claude binary for headless-local spawns.
function resolveClaudeBin() {
  if (process.env.CLAUDE_BIN && fs.existsSync(process.env.CLAUDE_BIN)) return process.env.CLAUDE_BIN;
  const home = require('os').homedir();
  const candidates = [
    path.join(home, '.local', 'bin', 'claude.exe'),
    path.join(home, '.local', 'bin', 'claude'),
  ];
  for (const c of candidates) { if (fs.existsSync(c)) return c; }
  return 'claude'; // fall back to PATH
}

// Launch a headless-local session (detached; the runner does not block on it).
function launchHeadless(planEntry, config, spawnLogPath) {
  const bin = resolveClaudeBin();
  // The nested-session guard blocks `claude` when CLAUDECODE is set; unset it
  // for the child so an unattended headless spawn can run.
  const env = Object.assign({}, process.env);
  delete env.CLAUDECODE;
  delete env.CLAUDE_CODE_ENTRYPOINT;
  try {
    const child = spawn(bin, planEntry.argv, { detached: true, stdio: 'ignore', env: env });
    child.unref();
    appendSpawnLog(spawnLogPath, {
      ts: new Date().toISOString(), item_id: planEntry.item_id,
      runner_kind: planEntry.runner_kind, pid: child.pid, launched: true,
    });
    return { launched: true, pid: child.pid };
  } catch (err) {
    appendSpawnLog(spawnLogPath, {
      ts: new Date().toISOString(), item_id: planEntry.item_id,
      runner_kind: planEntry.runner_kind, launched: false, error: String(err && err.message),
    });
    return { launched: false, error: String(err && err.message) };
  }
}
function appendSpawnLog(spawnLogPath, rec) {
  try {
    fs.mkdirSync(path.dirname(spawnLogPath), { recursive: true });
    fs.appendFileSync(spawnLogPath, JSON.stringify(rec) + '\n', 'utf8');
  } catch (_) {}
}

function writeSurface(surfacePath, result, extra) {
  // Strip the big prompt blobs from the surfaced spawnPlan (keep metadata +
  // executability); the full prompt is rebuilt deterministically at spawn time.
  const surfacedPlan = result.spawnPlan.map(function (p) {
    return {
      item_id: p.item_id, node_id: p.node_id, title: p.title, kind: p.kind,
      runner_kind: p.runner_kind, executable: p.executable, priority: p.priority,
      prompt_preview: String(p.prompt || '').split('\n')[0].slice(0, 120),
    };
  });
  const surface = {
    generated_at: new Date().toISOString(),
    machine_id: result.config.machineId,
    auto_spawn: result.config.autoSpawn,
    live_count: result.liveCount,
    free_slots: result.freeSlots,
    cascades: result.cascades,
    orphans: result.orphans,
    spawnable: result.spawnable,
    spawn_plan: surfacedPlan,
    spawn_deferred_count: result.spawnDeferredCount,
    pending_misha: result.pendingMisha,
    note: extra && extra.note,
  };
  try {
    fs.mkdirSync(path.dirname(surfacePath), { recursive: true });
    const tmp = surfacePath + '.tmp.' + process.pid;
    fs.writeFileSync(tmp, JSON.stringify(surface, null, 2), 'utf8');
    fs.renameSync(tmp, surfacePath); // atomic publish
  } catch (_) {}
  return surface;
}

function humanReport(result, meta) {
  const L = [];
  L.push('── Orchestrator reconciliation ' + (meta.dryRun ? '(DRY-RUN) ' : '') + '──');
  L.push('machine=' + result.config.machineId + '  autoSpawn=' + result.config.autoSpawn
    + '  live=' + result.liveCount + '/' + result.config.maxConcurrent
    + '  freeSlots=' + result.freeSlots + '  queueConsumed=' + (meta.queueConsumed || 0));
  L.push('cascades(unblocked): ' + result.cascades.length
    + '  orphans(stalled): ' + result.orphans.length
    + '  spawnable: ' + result.spawnable.length
    + '  pendingMisha: ' + result.pendingMisha.length);
  for (const c of result.cascades) L.push('  ↳ cascade: ' + c.item_id + ' unblocked by ' + c.unblocked_by);
  for (const o of result.orphans) L.push('  ⚠ orphan: ' + o.item_id + ' stalled ' + Math.round(o.oldest_age_min) + 'min');
  for (const p of result.spawnPlan) {
    L.push('  ▸ ' + (p.executable ? 'LAUNCH' : 'SURFACE') + ' [' + p.runner_kind + '] ' + p.item_id
      + (meta.launched && meta.launched[p.item_id] ? ' (pid ' + meta.launched[p.item_id] + ')' : ''));
  }
  if (result.spawnDeferredCount > 0) L.push('  … ' + result.spawnDeferredCount + ' spawnable item(s) deferred (no free slot this pass)');
  for (const m of result.pendingMisha) L.push('  ? Misha: ' + m.item_id + ' — ' + m.reason);
  return L.join('\n');
}

function main() {
  const args = parseArgs(process.argv);
  if (args.help) {
    process.stdout.write('Usage: node reconciler-run.js [--dry-run] [--no-spawn] [--json] [--state <path>]\n');
    process.exit(0);
  }
  const config = loadConfig();
  const now = Date.now();

  // 1. lock
  let locked = false;
  if (!args.dryRun) {
    locked = acquireLock(PATHS.lock, config.lockStaleMinutes);
    if (!locked) {
      process.stdout.write('[orchestrator] another pass holds the lock — skipping (idempotent; next pass will reconcile)\n');
      process.exit(0);
    }
  }

  try {
    // 2. consume queue (only on a real pass; dry-run leaves triggers intact)
    const queueConsumed = args.dryRun ? 0 : consumeQueue(PATHS.queue);

    // 3. read state
    const readOpts = args.statePath ? { statePath: args.statePath } : {};
    let snapshot;
    try { snapshot = stateLib.readState(readOpts).snapshot; }
    catch (err) {
      process.stderr.write('[orchestrator] readState failed (' + String(err && err.message) + ') — aborting pass, exit 0\n');
      if (locked) releaseLock(PATHS.lock);
      process.exit(0);
    }

    // 4. liveness  5. claims
    const liveList = sessions.liveSessions({ freshMin: config.freshMinutes, now: now });
    const claims = loadClaims(PATHS.claims);

    // 6. reconcile (pure)
    const result = reconcile({ snapshot: snapshot, liveSessions: liveList, claims: claims, config: config, now: now });

    const meta = { dryRun: args.dryRun, queueConsumed: queueConsumed, launched: {} };

    if (!args.dryRun) {
      // 7a. apply schema-valid emitted events (item-committed cascades)
      for (const ev of result.emittedEvents) {
        if (!SCHEMA_EMITTABLE.has(ev.type)) continue;
        try { stateLib.appendEvent(ev, readOpts); }
        catch (e) { process.stderr.write('[orchestrator] appendEvent(' + ev.type + ') failed: ' + String(e && e.message) + '\n'); }
      }
      // 7b. apply claim-released to the local claims stub (Component C local)
      let claimsChanged = false;
      for (const ev of result.emittedEvents) {
        if (ev.type === 'claim-released' && claims[ev.item_id]) { delete claims[ev.item_id]; claimsChanged = true; }
      }
      if (claimsChanged) saveClaims(PATHS.claims, claims);

      // 8. surface
      writeSurface(PATHS.surface, result, { note: result.spawnDeferredCount > 0 ? 'some spawnable deferred (slots full)' : null });

      // 9. gated spawn — headless-local only, autoSpawn must be on AND not --no-spawn
      if (config.autoSpawn && !args.noSpawn) {
        for (const p of result.spawnPlan) {
          if (!p.executable) continue; // code-task/cowork/routine → surfaced for Dispatch, never launched here
          // claim locally before spawn (Component C dedup primitive; v1 local)
          claims[p.item_id] = { machine_id: config.machineId, claimed_at: now, lease_ttl_min: config.leaseTtlMin };
          saveClaims(PATHS.claims, claims);
          const r = launchHeadless(p, config, PATHS.spawnLog);
          if (r.launched) meta.launched[p.item_id] = r.pid;
          else { // spawn failed → release the claim so a retry can re-pick it
            delete claims[p.item_id]; saveClaims(PATHS.claims, claims);
          }
        }
      }
    } else {
      // dry-run: still compute the surface object for display, but DO NOT write it.
    }

    // report
    if (args.json) {
      process.stdout.write(JSON.stringify(Object.assign({}, result, { _meta: meta }), null, 2) + '\n');
    } else {
      process.stdout.write(humanReport(result, meta) + '\n');
    }
  } finally {
    if (locked) releaseLock(PATHS.lock);
  }
  process.exit(0);
}

if (require.main === module) main();
module.exports = { acquireLock, releaseLock, consumeQueue, loadClaims, saveClaims, writeSurface, resolveClaudeBin };
