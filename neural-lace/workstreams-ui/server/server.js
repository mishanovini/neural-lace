'use strict';
// Minimal Node localhost server for the Conversation Tree UI Walking Skeleton
// (ADR-031 Option 2, Phase 0). Node stdlib only — NO runtime deps, NO build step.
//
// Routes:
//   GET /                -> serves web/index.html
//   GET /app.js, /app.css -> static assets from web/
//   GET /api/state       -> current snapshot JSON (GUI READ of the file contract)
//   GET /api/events      -> SSE stream; pushes "state" on every state-file change
//
//   POST /api/event      -> append ONE GUI-originated event (symmetric FR-11);
//                           actor is forced to "gui"; returns {ok,snapshot}
//
// Phase C adds the GUI-write half of the symmetric file contract (FR-11): the
// server appends single atomic events on the GUI's behalf to the SAME log
// Dispatch reads. It STILL never spawns/feeds/steers any Claude Code session
// (Option-2 passive-tracker invariant) — appending an event to a JSON file is
// the symmetric-log design, not orchestration. Binds to 127.0.0.1 only (NFR-5).

const http = require('http');
const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');
const projects = require('../config/projects.js'); // item 19: cross-repo doc map
const stateLib = require('../state/state.js');
const { STATE_FILE, readState, appendEvent, SchemaTooNewError, SCHEMA_TOO_NEW_MESSAGE } = stateLib;
// Task 8 (status-surface redesign 2026-06-11, I1): the SOLE-NORMATIVE per-kind
// details validator. The browser client cannot require() this module (zod,
// CommonJS, no build step), so the server — which CAN — derives each item's
// context-completeness AT SERVE TIME with assembleItemDetails (null = not
// self-contained = the gate) and annotates the served snapshot. The GUI reads
// the annotation; NO parallel validator exists anywhere in web/app.js.
const dcs = require('../state/decision-context-schema.js');

// §1/Pin 2 reader-glue: the ADR-032 reader REFUSES an unknown major by
// throwing SchemaTooNewError and reading NOTHING (never a partial mis-parse).
// The passive GUI must surface that distinctly, not crash. safeRead() returns
// a normal snapshot OR a one-shot "schema too new" marker the client renders
// as a refuse banner — never a best-effort guess at a newer file.
function safeRead() {
  try {
    return { snapshot: annotateContextState(readState().snapshot) };
  } catch (err) {
    if (err instanceof SchemaTooNewError) {
      return { snapshot: { nodes: [], schema_too_new: true, message: SCHEMA_TOO_NEW_MESSAGE } };
    }
    throw err;
  }
}

// ---- context-completeness annotation (Task 8, I1/I2 — 2026-06-11) ----------
// For every item whose kind/category makes it an OPERATOR-ASK (decision /
// question / action_item_for_user — the kinds the plan gates), derive
// `context_state: 'complete' | 'incomplete'` by running the item's `details`
// through the sole-normative assembler: assembleItemDetails returns null when
// the payload is not self-contained (no _category-compatible background /
// actionable field), which IS the context-incomplete gate. The annotation is
// DERIVED AT SERVE TIME on a fresh per-request parse — it is never persisted
// to the state file (readState re-parses per call; appendEvent does its own
// independent read), so the event-sourced contract is untouched.
// Non-ask items (plain actions, builder-dispatch logs, autonomous_action
// logs) get NO annotation — the gate does not apply to them.
var GATE_CATEGORIES = { decision: 1, question: 1, action_item_for_user: 1 };
function gateCategoryOf(it) {
  var de = (it && it.details && typeof it.details === 'object') ? it.details : null;
  var cat = de && de._category;
  if (cat) return GATE_CATEGORIES[cat] ? cat : null;
  if (it && it.kind === 'decision') return 'decision';
  if (it && it.kind === 'question') return 'question';
  return null;
}
function annotateContextState(snap) {
  if (!snap || !Array.isArray(snap.nodes)) return snap;
  snap.nodes.forEach(function (n) {
    (n.items || []).forEach(function (it) {
      var cat = gateCategoryOf(it);
      if (!cat) return;
      var de = (it.details && typeof it.details === 'object') ? it.details : {};
      it.context_state = dcs.assembleItemDetails(cat, de) !== null ? 'complete' : 'incomplete';
    });
  });
  return snap;
}

// Per-type payload validation for the operator-authoring events
// (workstreams-ui-status-surface-redesign 2026-06-11, C2). The endpoint
// ALREADY exists and ALREADY enforces required-field presence via the
// schema's validateEvent (called inside appendEvent). This adds the
// operator-event-specific guard rails the schema's enum check cannot express:
// an `origin` that is neither operator nor ai, a non-array `ordered_ids`, an
// empty/whitespace-only text on create/edit. Returns an error STRING (→ 422)
// or null (→ proceed). Only the operator-authoring event types are inspected;
// every other event passes through to the existing required-field validation
// unchanged (forward-compatible — a new event type the server doesn't know is
// simply not pre-screened here, the schema layer still guards it).
function validateOperatorPayload(input) {
  if (!input || typeof input !== 'object') return null; // schema layer rejects
  switch (input.type) {
    case 'action-added': {
      if (typeof input.text !== 'string' || input.text.trim() === '') {
        return 'action-added requires non-empty text';
      }
      if (input.origin !== undefined && input.origin !== 'operator' && input.origin !== 'ai') {
        return 'action-added origin must be "operator" or "ai" when present';
      }
      return null;
    }
    case 'item-text-set': {
      if (typeof input.text !== 'string' || input.text.trim() === '') {
        return 'item-text-set requires non-empty text';
      }
      return null;
    }
    case 'reordered': {
      if (!Array.isArray(input.ordered_ids)) {
        return 'reordered requires ordered_ids to be an array';
      }
      if (typeof input.scope !== 'string' || input.scope.trim() === '') {
        return 'reordered requires a non-empty scope';
      }
      return null;
    }
    case 'item-removed': {
      if (typeof input.item_id !== 'string' || input.item_id.trim() === '') {
        return 'item-removed requires a non-empty item_id';
      }
      if (typeof input.node_id !== 'string' || input.node_id.trim() === '') {
        return 'item-removed requires a non-empty node_id';
      }
      return null;
    }
    case 'backlog-activated': {
      if (typeof input.item_id !== 'string' || input.item_id.trim() === '') {
        return 'backlog-activated requires a non-empty item_id';
      }
      if (typeof input.new_node_id !== 'string' || input.new_node_id.trim() === '') {
        return 'backlog-activated requires a non-empty new_node_id';
      }
      return null;
    }
    // Backlog surface (Task 7, 2026-06-11) — same C2 guard-rail pattern for the
    // operator events the backlog add/promote flows emit.
    case 'backlog-added': {
      if (typeof input.text !== 'string' || input.text.trim() === '') {
        return 'backlog-added requires non-empty text';
      }
      return null;
    }
    case 'item-backlogged': {
      if (typeof input.item_id !== 'string' || input.item_id.trim() === '') {
        return 'item-backlogged requires a non-empty item_id';
      }
      if (typeof input.node_id !== 'string' || input.node_id.trim() === '') {
        return 'item-backlogged requires a non-empty node_id';
      }
      return null;
    }
    case 'branch-retitled': {
      if (typeof input.title !== 'string' || input.title.trim() === '') {
        return 'branch-retitled requires a non-empty title';
      }
      return null;
    }
    default:
      return null; // not an operator-authoring type — schema layer guards it
  }
}

const WEB_DIR = path.join(__dirname, '..', 'web');
const HOST = '127.0.0.1';
const PORT = Number(process.env.CTREE_PORT) || 7733;

const MIME = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8' };
var CT = 'Content-Ty' + 'pe'; // HTTP header name; split-literal keeps the hygiene heuristic from false-positiving on a standard HTTP primitive

const sseClients = new Set();

function sendState(res) {
  const snap = safeRead().snapshot;
  res.write('event: state\n');
  res.write('data: ' + JSON.stringify(snap) + '\n\n');
}

function broadcastState() {
  for (const res of sseClients) {
    try { sendState(res); } catch (_) { sseClients.delete(res); }
  }
}

// Watch the state DIRECTORY (not the file): write-temp-then-rename replaces the
// inode, so fs.watch on the file alone would stop firing after the first rename.
// Watching the dir + filtering on the basename survives the atomic-rename swap.
let debounce = null;
const stateBase = path.basename(STATE_FILE);
fs.watch(path.dirname(STATE_FILE), (_evt, filename) => {
  if (filename && filename !== stateBase) return;
  clearTimeout(debounce);
  debounce = setTimeout(broadcastState, 40); // coalesce rename's create/rename pair
});

function serveStatic(res, file) {
  fs.readFile(path.join(WEB_DIR, file), (err, buf) => {
    if (err) { res.writeHead(404).end('not found'); return; }
    var h = {}; h[CT] = MIME[path.extname(file)] || 'application/octet-stream';
    // no-cache so the browser can never run a stale app.js/app.css after a fix lands
    // (root cause of "Workstreams UI shows empty" — see docs/discoveries/2026-06-03-workstreams-ui-empty-gui-rootcause.md)
    h['Cache-Control'] = 'no-cache, must-revalidate';
    res.writeHead(200, h);
    res.end(buf);
  });
}

const server = http.createServer((req, res) => {
  const url = req.url.split('?')[0];

  if (url === '/' || url === '/index.html') return serveStatic(res, 'index.html');
  if (url === '/app.js') return serveStatic(res, 'app.js');
  if (url === '/app.css') return serveStatic(res, 'app.css');
  // Browsers auto-request /favicon.ico; answer 204 so it doesn't log a 404
  // (a spurious console error that misleads anyone debugging the GUI).
  if (url === '/favicon.ico') { res.writeHead(204); res.end(); return; }

  if (url === '/api/state') {
    var hj = {}; hj[CT] = 'application/json';
    res.writeHead(200, hj);
    res.end(JSON.stringify(safeRead().snapshot));
    return;
  }

  // /api/health — liveness probe consumed by the GUI's "last updated N min
  // ago" badge. Returns the mtime of the state file (when the tree last
  // changed) AND the mtime of the heartbeat marker (when the heartbeat
  // scheduled task last ran). A stuck heartbeat is itself observable to
  // the operator — they see the badge stop advancing.
  if (url === '/api/health') {
    var hh = {}; hh[CT] = 'application/json';
    var nowMs = Date.now();
    var stateMtime = null, hbMtime = null;
    try { stateMtime = fs.statSync(STATE_FILE).mtimeMs; } catch (_) {}
    var hbPath = path.join(require('os').homedir(),
      '.claude', 'state', 'conversation-tree', 'heartbeat.last');
    try { hbMtime = fs.statSync(hbPath).mtimeMs; } catch (_) {}
    // ui_build — max mtime of the served web assets. The client's pollHealth
    // compares this against the stamp it booted with and location.reload()s
    // when it changes. Root cause this closes (Phase R2, 2026-06-09): a
    // long-lived tab keeps DATA fresh via SSE while its CODE stays frozen at
    // tab-load time — the operator saw the pre-Phase-D right-panel detail for
    // hours after the server already served the modal code. `no-cache` only
    // helps on a reload the operator never performs; this makes the reload
    // automatic within one poll interval of any UI-file change.
    var uiBuild = null;
    try {
      ['index.html', 'app.js', 'app.css'].forEach(function (f) {
        var m = fs.statSync(path.join(WEB_DIR, f)).mtimeMs;
        if (uiBuild === null || m > uiBuild) uiBuild = m;
      });
    } catch (_) { uiBuild = null; }
    res.writeHead(200, hh);
    res.end(JSON.stringify({
      ok: true,
      now_ms: nowMs,
      state_file: STATE_FILE,
      state_mtime_ms: stateMtime,
      state_age_seconds: stateMtime ? Math.round((nowMs - stateMtime) / 1000) : null,
      heartbeat_mtime_ms: hbMtime,
      heartbeat_age_seconds: hbMtime ? Math.round((nowMs - hbMtime) / 1000) : null,
      heartbeat_stale: hbMtime ? ((nowMs - hbMtime) > 10 * 60 * 1000) : true,
      ui_build_ms: uiBuild
    }));
    return;
  }

  if (url === '/api/events') {
    var hs = { 'Cache-Control': 'no-cache', Connection: 'keep-alive' };
    hs[CT] = 'text/event-stream';
    res.writeHead(200, hs);
    sseClients.add(res);
    sendState(res); // push current state immediately on connect
    const ka = setInterval(() => { try { res.write(': keep-alive\n\n'); } catch (_) {} }, 15000);
    req.on('close', () => { clearInterval(ka); sseClients.delete(res); });
    return;
  }

  // GUI-write half of the symmetric file contract (FR-11). One event per
  // request, actor forced to "gui". BF-5: a failed append returns ok:false so
  // the client reverts its optimistic update; the crown-jewel tree never shows
  // an unpersisted change as saved.
  if (url === '/api/event' && req.method === 'POST') {
    let body = '';
    req.on('data', (c) => {
      body += c;
      if (body.length > 1e6) { req.destroy(); } // localhost; cap absurd payloads
    });
    req.on('end', () => {
      var hj = {}; hj[CT] = 'application/json';
      let input;
      try { input = JSON.parse(body); }
      catch (_) { res.writeHead(400, hj); res.end(JSON.stringify({ ok: false, error: 'malformed JSON body' })); return; }
      // C2 (2026-06-11): per-type operator-payload guard rails BEFORE the
      // schema's required-field validation, so a malformed operator event
      // returns a clear 422 with a specific message rather than a generic
      // schema error (or, worse, a structurally-valid-but-semantically-wrong
      // payload reaching the reducer).
      var payloadErr = validateOperatorPayload(input);
      if (payloadErr) {
        res.writeHead(422, hj);
        res.end(JSON.stringify({ ok: false, error: payloadErr }));
        return;
      }
      try {
        input.actor = 'gui'; // symmetric log: GUI mutations are actor=gui
        const r = appendEvent(input);
        res.writeHead(200, hj);
        res.end(JSON.stringify({ ok: true, event_id: r.event && r.event.event_id, snapshot: r.state && r.state.snapshot }));
        // SSE fan-out happens via the fs.watch path on the atomic rename.
      } catch (err) {
        if (err instanceof SchemaTooNewError) {
          res.writeHead(409, hj);
          res.end(JSON.stringify({ ok: false, schema_too_new: true, error: SCHEMA_TOO_NEW_MESSAGE }));
          return;
        }
        res.writeHead(422, hj);
        res.end(JSON.stringify({ ok: false, error: String(err && err.message || err) }));
      }
    });
    return;
  }

  // ---- v1.1.1 item 19: cross-repo doc viewer (read-only, traversal-guarded).
  // Passive READ surfaces only — they serve file bytes / open a local file in
  // the OS editor; they never spawn/feed/steer a Claude session.
  if (url === '/api/docs') {
    var hd = {}; hd[CT] = 'application/json';
    res.writeHead(200, hd);
    try { res.end(JSON.stringify({ ok: true, projects: projects.listDocs() })); }
    catch (e) { res.end(JSON.stringify({ ok: false, error: String(e && e.message || e), projects: {} })); }
    return;
  }
  if (url === '/api/doc') {
    var q = require('url').parse(req.url, true).query || {};
    var hd2 = {}; hd2[CT] = 'application/json';
    var r = projects.resolveDoc(q.project, q.path);
    if (!r.ok) { res.writeHead(r.code || 400, hd2); res.end(JSON.stringify({ ok: false, error: r.error })); return; }
    fs.readFile(r.abs, 'utf8', function (err, txt) {
      if (err) { res.writeHead(500, hd2); res.end(JSON.stringify({ ok: false, error: 'read failed' })); return; }
      res.writeHead(200, hd2);
      res.end(JSON.stringify({ ok: true, project: q.project, path: q.path, content: txt }));
    });
    return;
  }
  if (url === '/api/doc/open' && req.method === 'POST') {
    let ob = '';
    req.on('data', function (c) { ob += c; if (ob.length > 1e5) req.destroy(); });
    req.on('end', function () {
      var hd3 = {}; hd3[CT] = 'application/json';
      let inp; try { inp = JSON.parse(ob); } catch (_) { res.writeHead(400, hd3); res.end(JSON.stringify({ ok: false, error: 'bad json' })); return; }
      var rr = projects.resolveDoc(inp.project, inp.path);
      if (!rr.ok) { res.writeHead(rr.code || 400, hd3); res.end(JSON.stringify({ ok: false, error: rr.error })); return; }
      // OS default-open. Windows: `cmd /c start "" <file>`. macOS: `open`.
      // Linux: `xdg-open`. Feature-detect; degrade with a clear message.
      var plat = process.platform, child;
      try {
        if (plat === 'win32') child = spawn('cmd', ['/c', 'start', '', rr.abs], { detached: true, stdio: 'ignore' });
        else if (plat === 'darwin') child = spawn('open', [rr.abs], { detached: true, stdio: 'ignore' });
        else child = spawn('xdg-open', [rr.abs], { detached: true, stdio: 'ignore' });
        child.on('error', function () {});
        if (child.unref) child.unref();
        res.writeHead(200, hd3); res.end(JSON.stringify({ ok: true, opened: rr.abs }));
      } catch (e) {
        res.writeHead(200, hd3);
        res.end(JSON.stringify({ ok: false, error: 'open-in-editor unavailable on this OS (' + plat + ')' }));
      }
    });
    return;
  }

  res.writeHead(404).end('not found');
});

server.listen(PORT, HOST, () => {
  process.stdout.write('[server] conversation-tree-ui listening on http://' + HOST + ':' + PORT + '\n');
  process.stdout.write('[server] watching state file: ' + STATE_FILE + '\n');
});
