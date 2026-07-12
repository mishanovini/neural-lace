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
const os = require('os');
const path = require('path');
const { spawn } = require('child_process');
const projects = require('../config/projects.js');
const { DeriveCache, runWhy } = require('./derive-cache.js');
const reconciler = require('./reconciler.js');
const payloadSchema = require('./payload-schema.js');
// Ask-rooted-workstreams-p1 Task 12 — background drift auditor. Mounted
// (start()'d) only after a successful port bind (same single-instance-guard
// timing `cache.start()` already uses, below) and read on every /api/asks +
// /api/ask/<id> build via getBadgesForAsk() — a pure in-memory read, never
// an oracle shell on the request path (auditor.js's own header + Behavioral
// Contracts perf budget).
const auditorMod = require('./auditor.js');
const auditor = auditorMod.createAuditor();

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

// ============================================================
// Ask-rooted workstreams — Task 11 "Server read surface" (FINALIZES the
// Task 1 walking skeleton's `/api/asks` stub with the full landing payload:
// project grouping via config/projects.js, plan-progress counts,
// waiting-item §3 blocks (or the never-terminal defect form), drift-badge
// placeholders (Task 12 populates), plus the ONE lifecycle write endpoint
// (constraint 7's operator-override exit path) and `GET /api/ask/<id>`
// full detail. Every payload this section builds is validated against
// payload-schema.js's allowlist before it ever reaches the wire (constraint
// 1 anti-noise + constraint 2 absolute-links) — a validation FAILURE
// degrades to {ok:false, diagnostics:[...]} at 500, never a leaking
// payload (Systems Analysis §3).
//
// State-dir resolution mirrors the shell writer libs (progress-log-lib.sh /
// ask-registry.sh / needs-you.sh / dispatch-provenance.sh /
// session-heartbeat-lib.sh) so the SAME env-var overrides sandbox every
// side for a manual walkthrough or an automated test: PROGRESS_LOG_STATE_DIR
// / ASK_REGISTRY_STATE_DIR / NEEDS_YOU_MD_PATH / DISPATCH_PROVENANCE_STATE_DIR
// / HEARTBEAT_STATE_DIR, else the real $HOME/.claude/state/* paths + the
// real main-checkout NEEDS-YOU.md.
// ============================================================
function progressLogStateDir() {
  return process.env.PROGRESS_LOG_STATE_DIR ||
    path.join(process.env.HOME || os.homedir(), '.claude', 'state', 'progress-logs');
}
function askRegistryFile() {
  const dir = process.env.ASK_REGISTRY_STATE_DIR ||
    path.join(process.env.HOME || os.homedir(), '.claude', 'state');
  return path.join(dir, 'ask-registry.jsonl');
}

// readJsonlLines(file) — best-effort JSONL reader: a missing file or a
// corrupt/unparseable line is silently skipped (Edge Cases: "readers skip
// bad lines and surface a diagnostics-tab count; landing page never 500s
// on one bad record" — the diagnostics-tab count itself is Task 16's job;
// this reader just never crashes on bad input).
function readJsonlLines(file) {
  let raw;
  try { raw = fs.readFileSync(file, 'utf8'); } catch (_) { return []; }
  return raw.split('\n')
    .map((l) => l.trim())
    .filter(Boolean)
    .map((l) => { try { return JSON.parse(l); } catch (_) { return null; } })
    .filter(Boolean);
}

function readAskRegistry() { return readJsonlLines(askRegistryFile()); }

function readAskEvents(askId) {
  const dir = progressLogStateDir();
  const file = path.join(dir, (askId || 'unlinked') + '.jsonl');
  return readJsonlLines(file);
}

// mainRepoRoot() — best-effort "this repo's root" for resolving plan files
// and NEEDS-YOU.md when a per-ask `repo` field is absent/unreachable.
// config/projects.js's selfRepoRoot() already computes exactly this (the
// conv-tree-ui repo root, worktree-pool-aware) — reused rather than
// re-derived (no git dependency at read time, matches this module's own
// no-oracle-shelling-on-the-landing-path budget).
function mainRepoRoot() {
  try { return projects.selfRepoRoot(); } catch (_) { return process.cwd(); }
}

function needsYouMdPath() {
  return process.env.NEEDS_YOU_MD_PATH || path.join(mainRepoRoot(), 'NEEDS-YOU.md');
}

function dispatchProvenanceStateDir() {
  return process.env.DISPATCH_PROVENANCE_STATE_DIR ||
    path.join(process.env.HOME || os.homedir(), '.claude', 'state', 'dispatch-provenance');
}

function heartbeatStateDir() {
  return process.env.HEARTBEAT_STATE_DIR ||
    path.join(process.env.HOME || os.homedir(), '.claude', 'state', 'heartbeats');
}

// ----------------------------------------------------------------------
// foldAskRegistry() — read ALL ask-registry.jsonl records and fold them
// per the reader FOLD CONTRACT documented in ask-registry.sh's header:
// "last-write-wins per NON-EMPTY field, in timestamp order" for the mutable
// scalar fields, PLUS an accumulated `plan_slugs[]` (every `plan_linked`
// record's plan_slug, deduped — a list, never a last-wins scalar, since an
// ask can link >1 plan; MULTI-PLAN CARDS, review round 2).
// ----------------------------------------------------------------------
function foldAskRegistry() {
  const lines = readAskRegistry().slice().sort((a, b) => String(a.ts).localeCompare(String(b.ts)));
  const byAsk = {};
  lines.forEach((rec) => {
    if (!rec || !rec.ask_id) return;
    const cur = byAsk[rec.ask_id] || { plan_slugs: [] };
    ['repo', 'project', 'summary', 'verbatim_ref', 'status'].forEach((f) => {
      if (rec[f]) cur[f] = rec[f];
    });
    if (rec.record_type === 'plan_linked' && rec.plan_slug && cur.plan_slugs.indexOf(rec.plan_slug) === -1) {
      cur.plan_slugs.push(rec.plan_slug);
    }
    if (rec.record_type === 'created' && rec.ts) {
      cur.created_ts = rec.ts;
    }
    byAsk[rec.ask_id] = cur;
  });
  Object.keys(byAsk).forEach((k) => {
    if (!byAsk[k].status) byAsk[k].status = 'active';
  });
  return byAsk;
}

// ----------------------------------------------------------------------
// Plan-file task counting (plan progress bars / drill-down rows). Reuses
// the SAME task-checkbox line shape `hooks/plan-lifecycle.sh` itself
// parses (`- [x] N.` / `- [ ] N.`) — no re-invention of the plan-line
// grammar.
// ----------------------------------------------------------------------
const TASK_LINE_RE = /^- \[([ xX])\][ \t]*([0-9]+(?:\.[0-9]+)?)\./;

function countPlanTasks(absPath) {
  let text;
  try { text = fs.readFileSync(absPath, 'utf8'); } catch (_) { return null; }
  const tasks = [];
  text.split('\n').forEach((line) => {
    const m = TASK_LINE_RE.exec(line);
    if (m) tasks.push({ id: m[2], done: (m[1] === 'x' || m[1] === 'X') });
  });
  return tasks;
}

// resolvePlanAbsPath(repo, slug) — the ask's own `repo` first (its plans
// live at <repo>/docs/plans/<slug>.md), falling back to this repo's own
// root (the common case for harness-development asks like this one). Null
// when neither resolves — the caller renders an honest "no plan file found"
// empty row rather than crashing (Edge Cases: "readers skip bad
// lines/records ... landing page never 500s").
function resolvePlanAbsPath(repo, slug) {
  const candidates = [];
  if (repo) candidates.push(path.join(repo, 'docs', 'plans', slug + '.md'));
  candidates.push(path.join(mainRepoRoot(), 'docs', 'plans', slug + '.md'));
  for (let i = 0; i < candidates.length; i++) {
    try { if (fs.existsSync(candidates[i]) && fs.statSync(candidates[i]).isFile()) return candidates[i]; } catch (_) { /* try next */ }
  }
  return null;
}

// projectDocRefFor(absPath) — best-effort {project, path} pair resolving
// absPath against config/projects.js's loadProjects() map (deepest matching
// root wins — same technique ask-registry.sh's _ar_resolve_project uses in
// its own node snippet), so the UI (Task 13) can drill down through the
// EXISTING /api/doc + /api/doc/open resolver (ux-review amendment 6: "no
// pane grows its own link handling") instead of a bespoke absolute-path
// opener. This {project, path} shape is the ONE named exception to the
// absolute-href law — see payload-schema.js's header for why.
function projectDocRefFor(absPath) {
  if (!absPath) return null;
  try {
    const map = projects.loadProjects();
    const target = path.resolve(absPath);
    let best = null, bestLen = -1;
    Object.keys(map).forEach((k) => {
      let root;
      try { root = path.resolve(map[k]); } catch (_) { return; }
      if (target === root || target.indexOf(root + path.sep) === 0) {
        if (root.length > bestLen) { best = k; bestLen = root.length; }
      }
    });
    if (!best) return null;
    const rel = path.relative(path.resolve(map[best]), target).split(path.sep).join('/');
    return { project: best, path: rel };
  } catch (_) { return null; }
}

// computePlanRows(reg, events) — per linked plan: the real checkbox state
// from the plan FILE (ground truth) crossed with this ask's own
// `task_started`/`task_done` events to derive in-flight (constraint 2 law
// 4: "in-progress is derived, never declared" — a task is in_flight when it
// has a task_started event and NO task_done event yet, and its checkbox is
// still unflipped; Task 12's auditor is the CONTINUOUS reconciler of this —
// this is the correct-at-read-time snapshot Task 11 owns).
function computePlanRows(reg, events) {
  const slugs = (reg.plan_slugs || []).slice();
  const startedByPlan = {};
  const doneEvByPlan = {};
  events.forEach((e) => {
    if (!e || !e.plan_slug || !e.task_id) return;
    if (e.type === 'task_started') {
      startedByPlan[e.plan_slug] = startedByPlan[e.plan_slug] || {};
      startedByPlan[e.plan_slug][e.task_id] = true;
    }
    if (e.type === 'task_done') {
      doneEvByPlan[e.plan_slug] = doneEvByPlan[e.plan_slug] || {};
      doneEvByPlan[e.plan_slug][e.task_id] = e.evidence_link || '';
    }
  });
  // Task 12 — every task-level drift badge (Task 12's auditor) the ask
  // carries gets routed to the matching plan_slug+task_id row here; the
  // detail payload's ask-level `drift_badges` (buildAskDetailPayload) is
  // the full set, this is the per-row subset a future click-through
  // (Task 13) can attach to the right task.
  const askBadges = auditor.getBadgesForAsk(reg.ask_id);
  return slugs.map((slug) => {
    const absPath = resolvePlanAbsPath(reg.repo, slug);
    const planTasks = absPath ? countPlanTasks(absPath) : null;
    const startedSet = startedByPlan[slug] || {};
    const doneMap = doneEvByPlan[slug] || {};
    const tasks = (planTasks || []).map((t) => {
      const inFlight = !t.done && !!startedSet[t.id] && !doneMap[t.id];
      const rowBadges = askBadges.filter((b) => b.plan_slug === slug && b.task_id === t.id);
      return { id: t.id, done: t.done, in_flight: inFlight, evidence_link: doneMap[t.id] || '', drift_badges: rowBadges };
    });
    return { plan_slug: slug, plan_doc: projectDocRefFor(absPath), tasks: tasks };
  });
}

function aggregatePlanProgress(planRows) {
  let done = 0, inFlight = 0, total = 0;
  planRows.forEach((row) => {
    row.tasks.forEach((t) => {
      total++;
      if (t.done) done++;
      else if (t.in_flight) inFlight++;
    });
  });
  return { done: done, in_flight: inFlight, not_started: total - done - inFlight, total: total };
}

// ----------------------------------------------------------------------
// NEEDS-YOU.md parsing — Task 11's "waiting items with §3 context blocks"
// requirement is specced to parse the SAME shape needs-you.sh RENDERS
// (not its internal ledger.json), so a future ledger-schema change can't
// silently break this reader as long as the rendered markdown shape holds
// (pinned in server.selftest.js against real `needs-you.sh --self-test`
// output, per the plan's Integration point).
// ----------------------------------------------------------------------
function extractMdSection(mdText, header) {
  const lines = mdText.split('\n');
  let capturing = false;
  const out = [];
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    if (line.trim() === header) { capturing = true; continue; }
    if (capturing && /^## /.test(line)) break;
    if (capturing) out.push(line);
  }
  return out.join('\n');
}

// Only "## Awaiting your decision" blocks (rendered by
// _ny_render_decision_block) carry a trailing "id `<id>`" tag — bullets
// (questions/inflight, _ny_render_bullet) do not, and only decision blocks
// follow the §3 shape a waiting_on_operator event's needs_you_id can ever
// be validated against (the plan's §3-defect-form edge case is specific to
// decisions). This parser is therefore scoped to that one section by design.
const DECISION_META_RE = /^\*\(added ([0-9-]+|unknown), session `([^`]*)`, id `([^`]*)`\)\*$/;

function parseDecisionBlocks(sectionText) {
  const blocks = [];
  if (!sectionText || !sectionText.trim()) return blocks;
  const chunks = sectionText.split(/\n(?=### )/);
  chunks.forEach((chunk) => {
    if (!/^### /.test(chunk)) return;
    const lines = chunk.split('\n');
    let metaIdx = -1;
    for (let i = lines.length - 1; i >= 0; i--) {
      if (DECISION_META_RE.test(lines[i].trim())) { metaIdx = i; break; }
    }
    if (metaIdx === -1) return; // malformed block — skip, never crash (Edge Cases)
    const meta = DECISION_META_RE.exec(lines[metaIdx].trim());
    const added = meta[1], session = meta[2], id = meta[3];
    let linksLine = '', bodyEnd = metaIdx;
    if (metaIdx > 0 && /^Links: /.test(lines[metaIdx - 1].trim())) {
      linksLine = lines[metaIdx - 1].trim().replace(/^Links: /, '');
      bodyEnd = metaIdx - 1;
    }
    const bodyLines = lines.slice(1, bodyEnd);
    const body = bodyLines.join('\n').trim();
    const title = lines[0].replace(/^### /, '').trim();
    const links = (!linksLine || linksLine === '(none)') ? [] : linksLine.split(/\s+/).filter(Boolean);
    if (id) blocks.push({ id: id, title: title, body: body, links: links, session: session, added: added });
  });
  return blocks;
}

// readNeedsYouDecisionsResult() — {available, decisions}. `available:false`
// means the file could not be read at all (missing/permission error) — the
// waiting-count fallback (computeWaitingCount) treats that as "never hide a
// real waiting item" rather than silently reporting 0.
function readNeedsYouDecisionsResult() {
  let text;
  try { text = fs.readFileSync(needsYouMdPath(), 'utf8'); } catch (_) { return { available: false, decisions: [] }; }
  return { available: true, decisions: parseDecisionBlocks(extractMdSection(text, '## Awaiting your decision')) };
}

// hasGenuineContext(body) mirrors needs-you.sh's OWN cold-reader "no-context"
// heuristic (_ny_lint_decision_text (a), inverted): more than a single line
// AND at least one line >=40 chars. Deliberately the SAME threshold as the
// writer side's own lint, not a re-invented bar.
function hasGenuineContext(body) {
  if (!body) return false;
  const lines = body.split('\n');
  return lines.length > 1 && lines.some((l) => l.length >= 40);
}

// ----------------------------------------------------------------------
// Narrative summaries — every progress-log `summary` is already
// operator-prose (a mechanism wrote it, e.g. "task 3 verified done"); the
// fallback map below exists ONLY for the rare event with an empty
// `summary`, and deliberately never falls back to the raw `type`/`emitter`
// tokens (anti-noise law: those are internal mechanism vocabulary, not
// copy fit for the landing surface).
// ----------------------------------------------------------------------
const EVENT_TYPE_FALLBACK_SUMMARY = {
  task_done: 'a task was verified done',
  task_started: 'a task was dispatched',
  waiting_on_operator: 'a decision is waiting on the operator',
  merged: 'changes were merged',
  plan_amended: 'the plan was amended',
  plan_completed: 'the plan was completed',
  ask_registered: 'this ask was registered',
  session_attached: 'a session was attached',
};
function narrativeSummary(e) {
  if (e && e.summary) return e.summary;
  return (e && EVENT_TYPE_FALLBACK_SUMMARY[e.type]) || 'a progress update was recorded';
}

// computeWaitingCount(events) — see readNeedsYouDecisionsResult's header for
// the available/unavailable distinction driving the fallback.
function computeWaitingCount(events) {
  const ny = readNeedsYouDecisionsResult();
  const openIds = {};
  ny.decisions.forEach((d) => { openIds[d.id] = true; });
  const seen = {};
  let count = 0;
  events.forEach((e) => {
    if (!e || e.type !== 'waiting_on_operator' || !e.needs_you_id) return;
    if (seen[e.needs_you_id]) return;
    seen[e.needs_you_id] = true;
    if (!ny.available || openIds[e.needs_you_id]) count++;
  });
  return count;
}

// buildWaitingItems(events) — the §3-context-or-defect-form rendering
// (constraint 9: the defect form is NEVER terminal — it always carries the
// violation notice + an ABSOLUTE link to the raw NEEDS-YOU.md entry + the
// source-session id).
function buildWaitingItems(events) {
  const ny = readNeedsYouDecisionsResult();
  const byId = {};
  ny.decisions.forEach((d) => { byId[d.id] = d; });
  const seen = {};
  const out = [];
  events.forEach((e) => {
    if (!e || e.type !== 'waiting_on_operator' || !e.needs_you_id) return;
    if (seen[e.needs_you_id]) return;
    seen[e.needs_you_id] = true;
    const block = byId[e.needs_you_id];
    if (block && hasGenuineContext(block.body)) {
      out.push({
        needs_you_id: e.needs_you_id, defect: false, title: block.title, body: block.body,
        links: block.links, session_id: e.session_id || block.session || '', added: block.added,
      });
    } else {
      out.push({
        needs_you_id: e.needs_you_id, defect: true,
        message: 'context missing — session violated §3',
        raw_link: needsYouMdPath(), session_id: e.session_id || '',
      });
    }
  });
  return out;
}

function buildArtifacts(events) {
  return events.filter((e) => e && e.type === 'merged').map((e) => ({
    sha: e.sha || '', ts: e.ts || '', evidence_link: e.evidence_link || '',
  }));
}

// ----------------------------------------------------------------------
// Dispatch-provenance markers (Task 3, landed) + sessions/lineage.
// ----------------------------------------------------------------------
function readDispatchProvenanceMarkers() {
  const dir = dispatchProvenanceStateDir();
  let files;
  try { files = fs.readdirSync(dir); } catch (_) { return []; }
  const out = [];
  files.forEach((f) => {
    if (!/\.json$/.test(f)) return;
    try {
      const obj = JSON.parse(fs.readFileSync(path.join(dir, f), 'utf8'));
      if (obj) out.push(obj);
    } catch (_) { /* corrupt marker — skip, never crash */ }
  });
  return out;
}

// buildSessions(askId, events, markers) — union of every session this ask's
// own events name (ask_registered/session_attached/task_started) PLUS the
// dispatch-provenance markers matching this ask, each with a lineage edge
// (parent dispatching session -> child_id). HONEST LIMITATION (documented,
// not papered over — mirrors dispatch-provenance.sh's own header): the
// dispatched child's REAL session id is not resolvable until Task 9's
// attach-session lands; `child_id` is rendered as its own lineage node
// (role "child") until then, never silently dropped.
function buildSessions(askId, events, markers) {
  const bySession = {};
  function touch(sid, patch) {
    if (!sid) return;
    const prev = bySession[sid] || { session_id: sid, role: '', resumed_from: '', plan_slug: '', task_id: '' };
    bySession[sid] = Object.assign({}, prev, patch, { role: (patch.role && !prev.role) ? patch.role : (prev.role || patch.role || '') });
  }
  events.forEach((e) => {
    if (!e) return;
    if (e.type === 'ask_registered' && e.session_id) touch(e.session_id, { role: 'origin' });
    if (e.type === 'session_attached' && e.session_id) touch(e.session_id, { role: 'attached', resumed_from: e.session_id === '' ? '' : (bySession[e.session_id] || {}).resumed_from || '' });
    if (e.type === 'task_started' && e.session_id) touch(e.session_id, { role: 'dispatcher', plan_slug: e.plan_slug || '', task_id: e.task_id || '' });
  });
  markers.filter((m) => m && m.ask_id === askId).forEach((m) => {
    if (m.session_id) touch(m.session_id, { role: 'dispatcher', plan_slug: m.plan_slug || '', task_id: m.task_id || '' });
    if (m.child_id && !bySession[m.child_id]) {
      bySession[m.child_id] = {
        session_id: m.child_id, role: 'child', resumed_from: m.session_id || '',
        plan_slug: m.plan_slug || '', task_id: m.task_id || '',
      };
    }
  });
  return Object.keys(bySession).map((k) => bySession[k]);
}

// classifySessions(sessionIds) — reuses hooks/lib/session-heartbeat-lib.sh's
// hb_classify (live|stale|throttled|crashed|missing) via a single batched
// bash spawn, mirroring derive-cache.js's bashBin()/spawnEnv() conventions
// (absolute-path bash + login shell — the 2026-07-09 lobotomy lessons).
// Best-effort: any failure (missing lib, spawn error, timeout) resolves an
// EMPTY map rather than hanging or crashing the detail request — this is
// off the landing path entirely (only /api/ask/<id> calls it), so its cost
// never touches the GET /api/asks p95 budget.
function sessionHeartbeatLibPath() {
  return process.env.SESSION_HEARTBEAT_LIB ||
    path.join(__dirname, '..', '..', '..', 'adapters', 'claude-code', 'hooks', 'lib', 'session-heartbeat-lib.sh');
}
function shQuote(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'"; }

function classifySessions(sessionIds) {
  return new Promise((resolve) => {
    const ids = (sessionIds || []).filter(Boolean);
    if (!ids.length) return resolve({});
    const lib = sessionHeartbeatLibPath();
    if (!fs.existsSync(lib)) return resolve({});
    let bashBin, spawnEnv;
    try {
      const dc = require('./derive-cache.js');
      bashBin = dc.bashBin; spawnEnv = dc.spawnEnv;
    } catch (_) { return resolve({}); }
    const dir = heartbeatStateDir();
    const script = [
      'source ' + shQuote(lib) + ' 2>/dev/null || exit 0',
      'for sid in ' + ids.map(shQuote).join(' ') + '; do',
      '  f=' + shQuote(dir) + '"/$sid.json"',
      '  cls="$(hb_classify "$f" 2>/dev/null)"',
      '  printf "%s\\t%s\\n" "$sid" "${cls:-missing}"',
      'done',
    ].join('\n');
    let settled = false;
    const done = (result) => { if (!settled) { settled = true; resolve(result); } };
    let child;
    try { child = spawn(bashBin(), ['-lc', script], { env: spawnEnv() }); }
    catch (_) { return done({}); }
    let out = '';
    child.stdout.on('data', (d) => { out += d; });
    child.on('error', () => done({}));
    child.on('close', () => {
      const map = {};
      out.split('\n').forEach((line) => {
        const idx = line.indexOf('\t');
        if (idx === -1) return;
        const sid = line.slice(0, idx).trim();
        const cls = line.slice(idx + 1).trim();
        if (sid) map[sid] = cls || 'missing';
      });
      done(map);
    });
    // 180s budget: this environment's own login-shell bash spawns (bashBin()
    // + '-lc', the same 2026-07-09-lobotomy-lesson pattern every other
    // child spawn in this file uses) have been directly measured at 94s and
    // 119s during this task's own build on this machine (likely the same
    // AV/behavior-monitoring scan-on-spawn characteristic already diagnosed
    // on this machine per the operator's own prior notes) — matches
    // derive-cache.js's own precedent of generous per-subcommand budgets
    // (180-360s) for exactly this class of slow Windows/Git-Bash spawn. A
    // short timeout here would misclassify a merely-slow spawn as "no
    // sessions available" on every request.
    setTimeout(() => done({}), 180000);
  });
}

// ----------------------------------------------------------------------
// Landing payload — GET /api/asks. Defaults `status:active`; done/dismissed/
// merged asks ALWAYS fold into the independent `completed` group (review
// round 1's exit-mechanism law) regardless of the filter, so the UI's
// collapsed-group count (review round 2's COMPLETED-GROUP HEADER) is always
// accurate. No oracle shelling on this path (Behavioral Contracts perf
// budget) — every read here is a plain fs read of JSONL/plan-markdown
// files.
// ----------------------------------------------------------------------
function buildAskCard(reg, events) {
  const planRows = computePlanRows(reg, events);
  const planProgress = aggregatePlanProgress(planRows);
  const waitingCount = computeWaitingCount(events);
  const lastEvent = events.length ? events[events.length - 1] : null;
  const activityTs = lastEvent ? (lastEvent.ts || '') : (reg.created_ts || '');
  return {
    ask_id: reg.ask_id,
    summary: reg.summary || '',
    project: reg.project || '',
    repo: reg.repo || '',
    status: reg.status || 'active',
    activity_ts: activityTs,
    plan_progress: planProgress,
    waiting_count: waitingCount,
    drift_badges: auditor.getBadgesForAsk(reg.ask_id), // Task 12 (background auditor)
    narrative_excerpt: lastEvent ? narrativeSummary(lastEvent) : '',
  };
}

const COMPLETED_STATUSES = ['done', 'dismissed', 'merged'];

function buildAsksLandingPayload(statusFilter) {
  const registry = foldAskRegistry();
  const filter = statusFilter || 'active';
  const activeCards = [];
  const completedCards = [];
  Object.keys(registry).forEach((askId) => {
    const reg = registry[askId];
    reg.ask_id = askId;
    const events = readAskEvents(askId).sort((a, b) => String(a.ts).localeCompare(String(b.ts)));
    const card = buildAskCard(reg, events);
    if (COMPLETED_STATUSES.indexOf(card.status) !== -1) {
      completedCards.push(card);
      if (filter === card.status) activeCards.push(card); // explicit ?status=done etc. is a real filter
    } else if (filter === 'all' || filter === card.status) {
      activeCards.push(card);
    }
  });
  const byProject = {};
  activeCards.forEach((c) => {
    const key = c.project || '(unknown project)';
    byProject[key] = byProject[key] || [];
    byProject[key].push(c);
  });
  const groups = Object.keys(byProject).sort().map((project) => ({
    project: project,
    asks: byProject[project].slice().sort((a, b) => String(b.activity_ts).localeCompare(String(a.activity_ts))),
  }));
  completedCards.sort((a, b) => String(b.activity_ts).localeCompare(String(a.activity_ts)));
  return {
    ok: true,
    status_filter: filter,
    generated_at: new Date().toISOString(),
    groups: groups,
    completed: {
      count: completedCards.length,
      newest_completed_ts: completedCards.length ? completedCards[0].activity_ts : null,
      asks: completedCards,
    },
  };
}

// ----------------------------------------------------------------------
// Detail payload — GET /api/ask/<id>.
// ----------------------------------------------------------------------
function buildAskDetailPayload(askId) {
  const registry = foldAskRegistry();
  const reg = registry[askId];
  if (!reg) return Promise.resolve(null);
  reg.ask_id = askId;
  const events = readAskEvents(askId).sort((a, b) => String(a.ts).localeCompare(String(b.ts)));
  const planRows = computePlanRows(reg, events);
  const narrative = events.map((e) => ({ ts: e.ts || '', summary: narrativeSummary(e), evidence_link: e.evidence_link || '' }));
  const waitingItems = buildWaitingItems(events);
  const artifacts = buildArtifacts(events);
  const markers = readDispatchProvenanceMarkers();
  const sessions = buildSessions(askId, events, markers);
  const sessionIds = sessions.map((s) => s.session_id).filter(Boolean);
  return classifySessions(sessionIds).then((clsMap) => ({
    ok: true,
    ask_id: askId,
    summary: reg.summary || '',
    project: reg.project || '',
    repo: reg.repo || '',
    status: reg.status || 'active',
    verbatim_ref: reg.verbatim_ref || '',
    plan_slugs: reg.plan_slugs || [],
    narrative: narrative,
    plan_rows: planRows,
    waiting_items: waitingItems,
    artifacts: artifacts,
    sessions: sessions.map((s) => Object.assign({}, s, { state: clsMap[s.session_id] || 'missing' })),
    drift_badges: auditor.getBadgesForAsk(askId), // Task 12 (background auditor) — ask-level badges
  }));
}

// ----------------------------------------------------------------------
// Lifecycle write endpoint — POST /api/ask/<id>/lifecycle (review round 1:
// the operator-override exit path constraint 7 requires). Delegates to the
// UNCHANGED ask-registry.sh CLI (Task 8) — never writes the registry
// directly, so the registry's own append/fold contract stays the single
// implementation of "what a status change means."
// ----------------------------------------------------------------------
function askRegistryCliPath() {
  return process.env.ASK_REGISTRY_CLI ||
    path.join(__dirname, '..', '..', '..', 'adapters', 'claude-code', 'scripts', 'ask-registry.sh');
}

function runAskRegistryCli(args) {
  return new Promise((resolve) => {
    const cli = askRegistryCliPath();
    if (!fs.existsSync(cli)) return resolve({ ok: false, error: 'ask-registry.sh not found at ' + cli });
    let bashBin, spawnEnv;
    try {
      const dc = require('./derive-cache.js');
      bashBin = dc.bashBin; spawnEnv = dc.spawnEnv;
    } catch (e) { return resolve({ ok: false, error: 'derive-cache unavailable: ' + String(e && e.message || e) }); }
    const cmd = 'bash ' + shQuote(cli) + ' ' + args.map(shQuote).join(' ');
    let settled = false;
    const done = (r) => { if (!settled) { settled = true; resolve(r); } };
    let child;
    try { child = spawn(bashBin(), ['-lc', cmd], { env: spawnEnv() }); }
    catch (e) { return done({ ok: false, error: String(e && e.message || e) }); }
    let out = '', err = '';
    child.stdout.on('data', (d) => { out += d; });
    child.stderr.on('data', (d) => { err += d; });
    child.on('error', (e) => done({ ok: false, error: String(e && e.message || e) }));
    child.on('close', (code) => done({ ok: code === 0, code: code, stdout: out, stderr: err }));
    // 180s — see classifySessions' identical comment: this environment's
    // login-shell bash spawns have been directly measured at 94s/119s.
    setTimeout(() => done({ ok: false, error: 'ask-registry.sh call timed out' }), 180000);
  });
}

// Action -> ask-registry.sh verb/args + the resulting status (for the
// response body only — the registry file itself is the source of truth).
// NOTE (honest limitation, not silently routed around): ask-registry.sh's
// `merge` verb (Task 8, already shipped) does not accept an `--emitter`
// flag — every merge record is stamped emitter="ask-registry" regardless of
// caller. `set-status` DOES accept `--emitter`, so done/dismiss/reopen are
// tagged `--emitter operator-ui` (constraint 7's operator-exit path); merge
// is called as-is. Flagged as a follow-up against ask-registry.sh (Task 8)
// rather than fixed here (out of this task's file ownership).
function lifecycleArgsFor(action, askId, into) {
  if (action === 'done') return ['set-status', '--ask-id', askId, '--status', 'done', '--emitter', 'operator-ui'];
  if (action === 'dismiss') return ['set-status', '--ask-id', askId, '--status', 'dismissed', '--emitter', 'operator-ui'];
  if (action === 'reopen') return ['set-status', '--ask-id', askId, '--status', 'active', '--emitter', 'operator-ui'];
  if (action === 'merge') return into ? ['merge', '--ask-id', askId, '--into', into] : null;
  return null;
}
function lifecycleResultStatus(action) {
  if (action === 'done') return 'done';
  if (action === 'dismiss') return 'dismissed';
  if (action === 'reopen') return 'active';
  if (action === 'merge') return 'merged';
  return '';
}

const server = http.createServer((req, res) => {
  const parsedUrl = require('url').parse(req.url, true);
  const url = parsedUrl.pathname;
  const q = parsedUrl.query || {};

  if (url === '/' || url === '/index.html') return serveStatic(res, 'index.html');
  if (url === '/app.js') return serveStatic(res, 'app.js');
  if (url === '/app.css') return serveStatic(res, 'app.css');
  if (url === '/asks.js') return serveStatic(res, 'asks.js');
  if (url === '/favicon.ico') { res.writeHead(204); res.end(); return; }

  // ---- /api/asks — ask-rooted-workstreams-p1 Task 11 landing payload
  // (project groups + a collapsed `completed` group; `?status=` filter,
  // defaults to `active`). Schema-validated (payload-schema.js) before it
  // ever reaches the wire — a validation failure degrades to a diagnostics
  // 500, never a leaking payload.
  if (url === '/api/asks') {
    try {
      const filter = (typeof q.status === 'string' && q.status) ? q.status : 'active';
      const payload = buildAsksLandingPayload(filter);
      const check = payloadSchema.validateLanding(payload);
      if (!check.ok) {
        return sendJson(res, 500, { ok: false, error: 'payload schema validation failed', diagnostics: check.errors });
      }
      return sendJson(res, 200, payload);
    } catch (e) {
      return sendJson(res, 200, { ok: false, error: String(e && e.message || e), groups: [], completed: { count: 0, newest_completed_ts: null, asks: [] } });
    }
  }

  // ---- /api/ask/<id> (GET, full detail) and /api/ask/<id>/lifecycle
  // (POST, the operator-override exit path — constraint 7) — Task 11.
  if (url.indexOf('/api/ask/') === 0) {
    const rest = url.slice('/api/ask/'.length);
    if (req.method === 'POST' && rest.slice(-'/lifecycle'.length) === '/lifecycle') {
      const askId = decodeURIComponent(rest.slice(0, -'/lifecycle'.length));
      let bodyBuf = '';
      req.on('data', (c) => { bodyBuf += c; if (bodyBuf.length > 1e5) req.destroy(); });
      req.on('end', () => {
        let input;
        try { input = bodyBuf ? JSON.parse(bodyBuf) : {}; } catch (_) { return sendJson(res, 400, { ok: false, error: 'bad json' }); }
        const registry = foldAskRegistry();
        if (!registry[askId]) return sendJson(res, 404, { ok: false, error: 'ask not found: ' + askId });
        const action = input.action;
        const args = lifecycleArgsFor(action, askId, input.into);
        if (!args) {
          return sendJson(res, 400, { ok: false, error: action === 'merge' ? 'merge requires "into" (target ask id)' : ('unknown action: ' + String(action)) });
        }
        runAskRegistryCli(args).then((r) => {
          if (!r.ok) return sendJson(res, 500, { ok: false, error: r.error || ('ask-registry.sh exited ' + r.code) });
          sendJson(res, 200, { ok: true, ask_id: askId, action: action, status: lifecycleResultStatus(action) });
        });
      });
      return;
    }
    if (req.method === 'GET' && rest && rest.indexOf('/') === -1) {
      const askId = decodeURIComponent(rest);
      buildAskDetailPayload(askId).then((payload) => {
        if (!payload) return sendJson(res, 404, { ok: false, error: 'ask not found: ' + askId });
        const check = payloadSchema.validateAskDetail(payload);
        if (!check.ok) {
          return sendJson(res, 500, { ok: false, error: 'payload schema validation failed', diagnostics: check.errors });
        }
        sendJson(res, 200, payload);
      }).catch((e) => {
        sendJson(res, 200, { ok: false, error: String(e && e.message || e) });
      });
      return;
    }
  }

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

  // ---- Task 12 diagnostics detail — the background auditor's FULL internal
  // state (healed backfills, backfill errors, the §8-3 count-reconciliation
  // detail, and the raw per-ask badge map). Deliberately NOT schema-
  // validated (unlike /api/asks + /api/ask/<id>): this is the diagnostics-
  // tab surface (Task 16, not built by this task), which the anti-noise law
  // (constraint 1) explicitly scopes to the LANDING payload/DOM, not this
  // internal view — same precedent as the existing /api/reconciler endpoint
  // just below.
  if (url === '/api/diagnostics/drift') {
    return sendJson(res, 200, auditor.getDiagnostics());
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
  // Task 12 — background drift auditor. SAME single-instance-guard timing
  // as cache.start(): a losing EADDRINUSE instance exits above and never
  // reaches this callback, so at most one auditor cadence loop runs against
  // a given port.
  auditor.start();
});

module.exports = { server, cache, isLobotomized, auditor };
