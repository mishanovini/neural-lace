'use strict';
// Component B (orchestration-architecture-2026-05-30.md §3, step 4) — live
// session inventory + liveness, for stall/orphan detection.
//
// WHY transcript-mtime and NOT `claude agents --json`:
//   The orchestration-architecture brief proposed `claude agents --json` as the
//   "Agent View native source of truth" for running sessions. VERIFIED FALSE
//   (spike S-2, 2026-06-01): `claude agents` lists the 22 configured agent
//   *definitions* (task-verifier, code-reviewer, explorer, …) — NOT running
//   sessions. There is no CLI command that enumerates live sessions, and it is
//   blocked inside a session anyway (the CLAUDECODE nested-session guard).
//   The design doc named the correct fallback: the heartbeat's transcript-mtime
//   liveness scan, already proven in `conversation-tree-emit.sh --heartbeat`.
//   This module is the node port of that scan.
//
// The substrate: Claude Code writes one transcript JSONL per session under
//   ~/.claude/projects/<cwd-slug>/<session-uuid>.jsonl
// The file's mtime IS the liveness signal — a session actively producing turns
// touches its transcript. mtime within `freshMin` ⇒ live; older ⇒ idle/stalled.
// The emit hook's --heartbeat also writes per-session live-markers at
//   ~/.claude/state/conversation-tree-emit/live/<sid_safe>
// We read those as a secondary signal (a marker freshly touched by --heartbeat
// corroborates liveness even if the transcript path moved).

const fs = require('fs');
const path = require('path');
const os = require('os');

const DEFAULT_PROJECTS_DIR = path.join(os.homedir(), '.claude', 'projects');
const DEFAULT_LEDGER_LIVE_DIR = path.join(
  os.homedir(), '.claude', 'state', 'conversation-tree-emit', 'live'
);
const DEFAULT_FRESH_MIN = 15; // matches CONV_TREE_HEARTBEAT_FRESH_MIN default

// Mirror the emit hook's sid sanitizer (line ~651) so a session_id from a
// `session-bound` event can be matched against a live-marker filename.
function sidSafe(sid) {
  return String(sid)
    .replace(/[^A-Za-z0-9._-]/g, '-')
    .replace(/-+/g, '-')
    .replace(/^-/, '')
    .replace(/-$/, '');
}

// Recursively collect *.jsonl transcript files up to a small depth (Claude Code
// nests at projects/<slug>/<uuid>.jsonl, plus worktree sub-slugs one deeper).
function collectTranscripts(dir, depth, out) {
  let entries;
  try { entries = fs.readdirSync(dir, { withFileTypes: true }); }
  catch (_) { return out; }
  for (const ent of entries) {
    const full = path.join(dir, ent.name);
    if (ent.isDirectory()) {
      if (depth > 0) collectTranscripts(full, depth - 1, out);
    } else if (ent.isFile() && ent.name.endsWith('.jsonl')) {
      out.push(full);
    }
  }
  return out;
}

// Scan transcripts → live session records. Pure w.r.t. its inputs (point
// projectsDir/ledgerLiveDir at temp dirs to unit-test).
//   { projectsDir, ledgerLiveDir, freshMin, now }
// Returns: [{ session_id, sid_safe, last_active_ms, age_min, fresh, project,
//             transcript }]
function liveSessions(opts) {
  opts = opts || {};
  const projectsDir = opts.projectsDir || DEFAULT_PROJECTS_DIR;
  const ledgerLiveDir = opts.ledgerLiveDir || DEFAULT_LEDGER_LIVE_DIR;
  const freshMin = opts.freshMin != null ? Number(opts.freshMin) : DEFAULT_FRESH_MIN;
  const now = opts.now != null ? Number(opts.now) : Date.now();

  // Dedupe by session_id (the same uuid can appear via a worktree sub-slug);
  // keep the freshest mtime seen for it.
  const bySid = new Map();

  const transcripts = collectTranscripts(projectsDir, 3, []);
  for (const t of transcripts) {
    let st;
    try { st = fs.statSync(t); } catch (_) { continue; }
    const sid = path.basename(t, '.jsonl');
    const mtime = st.mtimeMs;
    const prev = bySid.get(sid);
    if (!prev || mtime > prev.last_active_ms) {
      bySid.set(sid, {
        session_id: sid,
        sid_safe: sidSafe(sid),
        last_active_ms: mtime,
        project: path.basename(path.dirname(t)),
        transcript: t,
      });
    }
  }

  // Secondary signal: a live-marker freshly touched by --heartbeat. If a marker
  // is fresher than the transcript we observed (or the transcript is absent),
  // fold it in. Marker filename is the sid_safe form, so we can only corroborate
  // sessions we already keyed by sid_safe; we also add marker-only sessions.
  let markers = [];
  try { markers = fs.readdirSync(ledgerLiveDir); } catch (_) { markers = []; }
  const markerMtime = new Map();
  for (const m of markers) {
    try { markerMtime.set(m, fs.statSync(path.join(ledgerLiveDir, m)).mtimeMs); }
    catch (_) { /* skip */ }
  }
  // Fold marker freshness into matching sessions (by sid_safe).
  for (const rec of bySid.values()) {
    const mm = markerMtime.get(rec.sid_safe);
    if (mm != null && mm > rec.last_active_ms) rec.last_active_ms = mm;
  }

  const out = [];
  for (const rec of bySid.values()) {
    const ageMin = (now - rec.last_active_ms) / 60000;
    out.push(Object.assign({}, rec, {
      age_min: ageMin,
      fresh: ageMin <= freshMin,
    }));
  }
  // Stable order: freshest first.
  out.sort(function (a, b) { return b.last_active_ms - a.last_active_ms; });
  return out;
}

// Convenience: a Map session_id → record, for O(1) lookup by the reconciler.
function liveSessionMap(opts) {
  const m = new Map();
  for (const rec of liveSessions(opts)) m.set(rec.session_id, rec);
  return m;
}

module.exports = {
  DEFAULT_PROJECTS_DIR,
  DEFAULT_LEDGER_LIVE_DIR,
  DEFAULT_FRESH_MIN,
  sidSafe,
  collectTranscripts,
  liveSessions,
  liveSessionMap,
};
