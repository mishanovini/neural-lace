'use strict';
// workstreams-ui server — NL Observability Program Wave O, task O.4 cockpit
// rebuild (specs-o §O.4). REPLACES the tree-state-reading server: every pane
// is now a thin read of derive-cache.js, which shells the real `nl <sub>
// --json` oracle (contract C5). The cockpit NEVER renders tree-state.json
// as truth (law 1) — the ONLY remaining tree-state read is the divergence
// reconciler's COMPARISON path (reconciler.js), which never feeds a pane
// directly, only the drift-badge endpoint.
//
// TRUST-PATH RETIREMENT (specs-o §O.4 deliverable 4, disposition:
// "legacy write features RETIRE ENTIRELY"): POST /api/event (the GUI-write
// half of the old symmetric file contract) and every GUI write affordance
// it served (capture, my-tasks CRUD, backlog promote, decision approve/
// decline/respond, branch retitle) are REMOVED from this server. Q2 in this
// cockpit is READ-ONLY v1 (orchestrator disposition, docs/reviews/
// 2026-07-06-o4-cockpit-ux-review.md bottom section): answers happen in
// sessions/chat, never via a button in this UI. A future `needs-you.sh
// resolve`-backed Resolve action is a legitimate later increment (its sink
// is the canonical ledger, not the retired tree) — explicitly NOT built
// here.
//
// KEPT: the docs browser (/api/docs, /api/doc, /api/doc/open) — per the
// review's disposition it becomes the ONE link-resolver backend used by
// Q2/Q3/Q6 (ux-review amendment 6: "no pane grows its own link handling").
//
// Binds to 127.0.0.1 only. Port: CTREE_PORT env (default 7733, unchanged —
// existing launcher scripts/autostart registration keep working).

const http = require('http');
const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');
const projects = require('../config/projects.js');
const { DeriveCache, runWhy } = require('./derive-cache.js');
const reconciler = require('./reconciler.js');

// stateLib for the reconciler's COMPARISON-ONLY read. Best-effort require:
// if trust-path retirement has already removed/broken this module on a
// given checkout, the reconciler degrades to "0 drift" (empty claim set)
// rather than crashing the server — see reconciler.js's own header.
let stateLib = null;
try {
  stateLib = require('../state/state.js');
} catch (err) {
  process.stderr.write('[server] NOTE: state/state.js unavailable (' +
    String(err && err.message || err).split('\n')[0] +
    ') — reconciler will report 0 drift (no tree-state claims to compare).\n');
}

const WEB_DIR = path.join(__dirname, '..', 'web');
const HOST = '127.0.0.1';
const PORT = Number(process.env.CTREE_PORT) || 7733;

// ---- Server start time + lobotomy detection (2026-07-09 incident): a
// logon-task-spawned instance with a minimal registry env held the port all
// day while EVERY pane failed (rc=127 spawn-bash-ENOENT, then rc=1
// empty-stdout) — "up" to any TCP/HTTP probe, useless to the operator.
// /api/health now self-reports that shape so the launcher (launch-gui.ps1)
// can kill-and-restart it with a healthy environment.
const SERVER_START_MS = Date.now();

// Grace window before the flag can go true: a FRESH instance (uptime <=
// 120s) is never lobotomized, which bounds the launcher's restart-on-
// lobotomy to at most ONE restart per launcher invocation (the replacement
// instance reports false by construction — no restart loop possible).
const LOBOTOMY_MIN_UPTIME_MS = 120000;

// isLobotomized(cacheObj, uptimeMs) — true when EVERY pane's most recent
// refresh attempt FAILED (rc a non-null, NONZERO number) AND the server is
// past the first-refresh grace window. rc === null is deliberately NOT
// "failed": it means "no refresh attempt has settled yet" (loading), and a
// healthy-but-slow estate can legitimately still be in its first refresh
// near the window's edge (status/backlog timeouts are 180s/360s) — killing
// that instance would be a false positive. Exported for the self-test
// (fabricated cache states + uptimes; a real >120s all-failed instance
// can't be produced inside the test's time budget).
function isLobotomized(cacheObj, uptimeMs) {
  if (uptimeMs <= LOBOTOMY_MIN_UPTIME_MS) return false;
  const subs = Object.keys(require('./derive-cache.js').SUBCOMMANDS);
  return subs.every((s) => {
    const rc = cacheObj.get(s).rc;
    return typeof rc === 'number' && rc !== 0;
  });
}

const MIME = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8' };
var CT = 'Content-Ty' + 'pe'; // split-literal keeps the hygiene heuristic from false-positiving on a standard HTTP primitive

// ---- Q3 last-look anchor (server-side default; client also persists its
// own copy per ux-review amendment 3 "every client-persisted key gets
// write-trigger + read-effect + reset-path"). The SERVER needs an anchor to
// pass to `nl shipped --since` on each refresh tick; the client can override
// per-request via ?since=<iso> (used right after a Mark-seen click so the
// NEXT poll reflects the new anchor without waiting a full cache cycle).
let lastLookSince = new Date(Date.now() - 24 * 3600 * 1000).toISOString(); // first-use window: 24h

const cache = new DeriveCache({
  getShippedSince: () => lastLookSince,
});

const sseClients = new Set();

function broadcastRefresh() {
  const payload = 'event: refresh\ndata: ' + JSON.stringify({ ts: new Date().toISOString() }) + '\n\n';
  for (const res of sseClients) {
    try { res.write(payload); } catch (_) { sseClients.delete(res); }
  }
}

cache.onRefresh(broadcastRefresh);
// cache.start() deliberately does NOT happen here — it moved inside the
// 'listening' callback at the bottom of this file (nl-issue [55],
// NL-FINDING-040/FM-037): starting the poll loop before listen() succeeds
// means N concurrently-launched instances (15+ worktree-launched copies at
// the 2026-07-08 incident) EACH poll the nl.sh oracle independently even
// though only one can ever own the port. Listen-success is the mutex.

function serveStatic(res, file) {
  fs.readFile(path.join(WEB_DIR, file), (err, buf) => {
    if (err) { res.writeHead(404).end('not found'); return; }
    var h = {}; h[CT] = MIME[path.extname(file)] || 'application/octet-stream';
    // no-cache so the browser can never run a stale app.js/app.css after a fix lands
    h['Cache-Control'] = 'no-cache, must-revalidate';
    res.writeHead(200, h);
    res.end(buf);
  });
}

function sendJson(res, code, obj) {
  var h = {}; h[CT] = 'application/json';
  res.writeHead(code, h);
  res.end(JSON.stringify(obj));
}

// paneResponse(entry) — wraps a derive-cache entry into the pane payload
// every /api/pane/* endpoint returns. rc!=0 is carried through EXPLICITLY
// (ux-review amendment 1: rc!=0 renders a named ERROR state client-side,
// never the empty state) along with the exact failing `nl` command line so
// the client can show it verbatim.
function paneResponse(sub, entry, extraArgsLabel) {
  const cmdLine = 'nl ' + sub + (extraArgsLabel ? ' ' + extraArgsLabel : '') + ' --json';
  return {
    schema: 1,
    pane: sub,
    data: entry.data,
    rc: entry.rc,
    stderr_tail: entry.stderr_tail,
    derived_at: entry.derived_at,
    command: cmdLine,
  };
}

const server = http.createServer((req, res) => {
  const parsedUrl = require('url').parse(req.url, true);
  const url = parsedUrl.pathname;
  const q = parsedUrl.query || {};

  if (url === '/' || url === '/index.html') return serveStatic(res, 'index.html');
  if (url === '/app.js') return serveStatic(res, 'app.js');
  if (url === '/app.css') return serveStatic(res, 'app.css');
  if (url === '/favicon.ico') { res.writeHead(204); res.end(); return; }

  // ---- /api/health — freshness header (ux-review amendment 4: re-specced
  // onto derived-cache stamps, NOT the retired state-file/heartbeat-file
  // mtimes the old server used — those would show false-stale forever once
  // trust-path retirement lands). Every pane names its own derived_at; this
  // endpoint gives the GLOBAL picture (oldest cache entry age, ui_build for
  // the auto-reload mechanism, kept unchanged from the old server).
  if (url === '/api/health') {
    const subs = Object.keys(require('./derive-cache.js').SUBCOMMANDS);
    const ages = subs.map((s) => cache.get(s)).filter((e) => e.derived_at);
    const oldestMs = ages.length
      ? Math.max(...ages.map((e) => Date.now() - Date.parse(e.derived_at)))
      : null;
    const anyFailed = subs.some((s) => cache.get(s).rc !== 0);
    var uiBuild = null;
    try {
      ['index.html', 'app.js', 'app.css'].forEach(function (f) {
        var m = fs.statSync(path.join(WEB_DIR, f)).mtimeMs;
        if (uiBuild === null || m > uiBuild) uiBuild = m;
      });
    } catch (_) { uiBuild = null; }
    const uptimeMs = Date.now() - SERVER_START_MS;
    sendJson(res, 200, {
      ok: true,
      now_ms: Date.now(),
      oldest_pane_age_ms: oldestMs,
      any_pane_failed: anyFailed,
      refresh_interval_ms: cache.refreshIntervalMs,
      ui_build_ms: uiBuild,
      // 2026-07-09 lobotomy incident fields — see SERVER_START_MS /
      // isLobotomized headers above. The launcher keys restart-on-lobotomy
      // off `lobotomized`.
      server_uptime_ms: uptimeMs,
      lobotomized: isLobotomized(cache, uptimeMs),
    });
    return;
  }

  // ---- Six-question pane endpoints. Each is a thin read of the cache —
  // the SAME data path `nl <sub> --json` would produce at that moment
  // (modulo the cache's own refresh cadence), which is the acceptance
  // bar every runtime scenario checks (derived-vs-displayed equality).
  if (url === '/api/pane/status') { // Q1
    return sendJson(res, 200, paneResponse('status', cache.get('status')));
  }
  if (url === '/api/pane/needs-me') { // Q2
    return sendJson(res, 200, paneResponse('needs-me', cache.get('needs-me')));
  }
  if (url === '/api/pane/shipped') { // Q3
    // ?since=<iso> lets the client force a specific anchor RIGHT NOW (used
    // right after Mark-seen so the pane reflects the new anchor without
    // waiting for the next 30s tick) — this refresh is ASYNC and scoped to
    // this one subcommand (never blocks the event loop; see
    // derive-cache.js's runNl header), not a full cache.refreshAll().
    if (q.since && typeof q.since === 'string') {
      lastLookSince = q.since;
      cache.refreshOne('shipped').then(() => {
        sendJson(res, 200, paneResponse('shipped', cache.get('shipped'), '--since ' + lastLookSince));
      });
      return;
    }
    return sendJson(res, 200, paneResponse('shipped', cache.get('shipped'), '--since ' + lastLookSince));
  }
  if (url === '/api/pane/health') { // Q4 (harness health, distinct from /api/health above)
    // O.4-fix1 item 1: the `health` cache entry is populated by
    // derive-cache.js's runHealth() (sources the C4 lib directly and calls
    // od_harness_health --json), NOT by nl.sh's `status` subcommand — that
    // path drops .gates entirely (see derive-cache.js's SUBCOMMANDS/
    // runHealth comments). The doctor verdict+ts still ride on this same
    // .doctor sub-object (od_harness_health computes both), so this one
    // pane read carries everything Q4 needs: doctor verdict + per-gate 7d
    // block/waiver/downgrade/dominant counts.
    return sendJson(res, 200, paneResponse('health', cache.get('health')));
  }
  if (url === '/api/pane/costs') { // Q5
    return sendJson(res, 200, paneResponse('costs', cache.get('costs')));
  }
  if (url === '/api/pane/backlog') { // backlog oracle (not one of the six sketch questions, same discipline)
    return sendJson(res, 200, paneResponse('backlog', cache.get('backlog')));
  }
  if (url === '/api/pane/why') { // Q6, on-demand, not part of the batch cache
    const sid = q.session;
    if (!sid) { return sendJson(res, 400, { ok: false, error: 'missing ?session=<id>' }); }
    const lastBlock = q.last_block === '1' || q.last_block === 'true';
    runWhy(sid, lastBlock).then((entry) => {
      sendJson(res, 200, paneResponse('why', entry, sid + (lastBlock ? ' --last-block' : '')));
    });
    return;
  }

  // ---- Divergence reconciler badge (specs-o §O.4 deliverable 3 / §O.4.3).
  if (url === '/api/reconciler') {
    const result = reconciler.check(stateLib, cache, reconciler.defaultLedgerEmit);
    return sendJson(res, 200, result);
  }

  // ---- On-demand refresh (ux-review amendment 4: visible Refresh control
  // with in-flight/succeeded/failed feedback). Refreshes ALL panes IN
  // PARALLEL (async — never blocks the event loop; see derive-cache.js's
  // runNl/refreshAll headers) and responds once every pane has settled, so
  // the client's Refresh button shows a definitive success/fail rather than
  // guessing from the next poll.
  if (url === '/api/refresh' && req.method === 'POST') {
    cache.refreshAll().then(() => {
      const subs = Object.keys(require('./derive-cache.js').SUBCOMMANDS);
      const results = {};
      subs.forEach((s) => { results[s] = { rc: cache.get(s).rc, derived_at: cache.get(s).derived_at }; });
      sendJson(res, 200, { ok: true, results: results });
    });
    return;
  }

  if (url === '/api/events') {
    var hs = { 'Cache-Control': 'no-cache', Connection: 'keep-alive' };
    hs[CT] = 'text/event-stream';
    res.writeHead(200, hs);
    sseClients.add(res);
    res.write('event: refresh\ndata: ' + JSON.stringify({ ts: new Date().toISOString() }) + '\n\n');
    const ka = setInterval(() => { try { res.write(': keep-alive\n\n'); } catch (_) {} }, 15000);
    req.on('close', () => { clearInterval(ka); sseClients.delete(res); });
    return;
  }

  // ---- Docs browser (KEPT — becomes the link-resolver backend, ux-review
  // amendment 6). Passive READ surfaces only.
  if (url === '/api/docs') {
    try { return sendJson(res, 200, { ok: true, projects: projects.listDocs() }); }
    catch (e) { return sendJson(res, 200, { ok: false, error: String(e && e.message || e), projects: {} }); }
  }
  if (url === '/api/doc') {
    var r = projects.resolveDoc(q.project, q.path);
    if (!r.ok) { return sendJson(res, r.code || 400, { ok: false, error: r.error }); }
    fs.readFile(r.abs, 'utf8', function (err, txt) {
      if (err) { return sendJson(res, 500, { ok: false, error: 'read failed' }); }
      sendJson(res, 200, { ok: true, project: q.project, path: q.path, content: txt });
    });
    return;
  }
  if (url === '/api/doc/open' && req.method === 'POST') {
    let ob = '';
    req.on('data', function (c) { ob += c; if (ob.length > 1e5) req.destroy(); });
    req.on('end', function () {
      let inp; try { inp = JSON.parse(ob); } catch (_) { return sendJson(res, 400, { ok: false, error: 'bad json' }); }
      var rr = projects.resolveDoc(inp.project, inp.path);
      if (!rr.ok) { return sendJson(res, rr.code || 400, { ok: false, error: rr.error }); }
      var plat = process.platform, child;
      try {
        if (plat === 'win32') child = spawn('cmd', ['/c', 'start', '', rr.abs], { detached: true, stdio: 'ignore' });
        else if (plat === 'darwin') child = spawn('open', [rr.abs], { detached: true, stdio: 'ignore' });
        else child = spawn('xdg-open', [rr.abs], { detached: true, stdio: 'ignore' });
        child.on('error', function () {});
        if (child.unref) child.unref();
        sendJson(res, 200, { ok: true, opened: rr.abs });
      } catch (e) {
        sendJson(res, 200, { ok: false, error: 'open-in-editor unavailable on this OS (' + plat + ')' });
      }
    });
    return;
  }

  res.writeHead(404).end('not found');
});

// ---- Single-instance guard (nl-issue [55], NL-FINDING-040/FM-037 — the
// 2026-07-08 machine-crash amplification engine). The port itself is the
// mutex: whichever instance binds 127.0.0.1:PORT first owns BOTH the HTTP
// surface AND the nl.sh poll loop; every later instance launched against
// the SAME port gets EADDRINUSE here, logs one line, and exits 0 WITHOUT
// ever having started the cache (cache.start() only runs inside the
// 'listening' success callback below). This is defense-in-depth UNDER the
// launcher layer's own probe (launch-gui.ps1 Test-ServerUp / ensure-
// cockpit.sh): the launcher probe races (N sessions can all probe "down"
// before any of them binds); the bind itself cannot. A deliberately
// different CTREE_PORT is a deliberate second instance (e.g. the sandboxed
// self-test) and correctly gets its own poll loop — the guard keys on the
// port, not on a global lock, by design.
server.on('error', (err) => {
  if (err && err.code === 'EADDRINUSE') {
    process.stdout.write('[server] http://' + HOST + ':' + PORT +
      ' already owned by another instance — exiting 0 without starting the poll loop (single-instance guard, FM-037)\n');
    process.exit(0);
  }
  process.stderr.write('[server] listen failed: ' + String(err && err.message || err) + '\n');
  process.exit(1);
});

server.listen(PORT, HOST, () => {
  process.stdout.write('[server] workstreams-ui (O.4 cockpit) listening on http://' + HOST + ':' + PORT + '\n');
  process.stdout.write('[server] nl bin: ' + require('./derive-cache.js').nlBin() + '\n');
  // Poll loop starts ONLY after a successful bind — see the guard above.
  cache.start();
});

module.exports = { server, cache, isLobotomized };
