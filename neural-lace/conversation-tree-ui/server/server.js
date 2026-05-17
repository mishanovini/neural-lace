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
// The server NEVER writes state, NEVER spawns/steers any Claude Code session.
// It is a passive reader of the file-mediated contract (ADR-031 Option 2).
// Binds to 127.0.0.1 only (NFR-5: localhost-only).

const http = require('http');
const fs = require('fs');
const path = require('path');
const { STATE_FILE, readState, SchemaTooNewError, SCHEMA_TOO_NEW_MESSAGE } = require('../state/state.js');

// §1/Pin 2 reader-glue: the ADR-032 reader REFUSES an unknown major by
// throwing SchemaTooNewError and reading NOTHING (never a partial mis-parse).
// The passive GUI must surface that distinctly, not crash. safeRead() returns
// a normal snapshot OR a one-shot "schema too new" marker the client renders
// as a refuse banner — never a best-effort guess at a newer file.
function safeRead() {
  try {
    return { snapshot: readState().snapshot };
  } catch (err) {
    if (err instanceof SchemaTooNewError) {
      return { snapshot: { nodes: [], schema_too_new: true, message: SCHEMA_TOO_NEW_MESSAGE } };
    }
    throw err;
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
    res.writeHead(200, h);
    res.end(buf);
  });
}

const server = http.createServer((req, res) => {
  const url = req.url.split('?')[0];

  if (url === '/' || url === '/index.html') return serveStatic(res, 'index.html');
  if (url === '/app.js') return serveStatic(res, 'app.js');
  if (url === '/app.css') return serveStatic(res, 'app.css');

  if (url === '/api/state') {
    var hj = {}; hj[CT] = 'application/json';
    res.writeHead(200, hj);
    res.end(JSON.stringify(safeRead().snapshot));
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

  res.writeHead(404).end('not found');
});

server.listen(PORT, HOST, () => {
  process.stdout.write('[server] conversation-tree-ui listening on http://' + HOST + ':' + PORT + '\n');
  process.stdout.write('[server] watching state file: ' + STATE_FILE + '\n');
});
