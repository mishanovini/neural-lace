'use strict';
// roadmap-routes.js — the Roadmap view's server surface
// (cockpit-roadmap-redesign Task 3: "Roadmap tree view + the navigation
// shell"). A NEW file by design: Task 1 concurrently owns server.js +
// derive-lib.js, so this task adds its route handlers HERE and the ONE
// server.js mount line ships as a fragment
// (docs/plans/fragments/roadmap-t3-server-fragment.md) for the orchestrator
// to apply at merge — never a direct edit to a file another task owns.
//
// Routes (handle() returns true when it consumed the request):
//   GET  /roadmap.js          — serves the client module (keeps the fragment
//                               to ONE mount line instead of two).
//   GET  /api/roadmap         — the roadmap tree payload (contract below).
//   POST /api/roadmap/rank    — keyboard-operable move up/down (A7/R2).
//   POST /api/roadmap/title   — title edit, DELEGATED to ask-registry.sh
//                               (A3 one-writer discipline; task 2 owns the
//                               verb — see STATUS DERIVATION STUB below).
//
// ============================================================
// PAYLOAD CONTRACT (pinned for task-1 merge re-verification)
// ============================================================
// GET /api/roadmap -> {
//   ok, generated_at, completed_age_days,
//   items: [RoadmapItem]            // top-level intents, BUILD ORDER
// }
// RoadmapItem = {
//   id,                             // intent: <ask_id>; plan: <ask_id>/<slug>;
//                                   // task: <ask_id>/<slug>/<task_id>
//   kind: 'intent'|'plan'|'task',
//   title, title_source: 'operator'|'auto',
//   project, provenance: 'operator'|'machine', provenance_reason,
//   rank,                           // effective build-order rank (number|null)
//   added_ts, added_mid_build,      // insertion marker (task 1 populates the flag)
//   status: {
//     value: 'not-started'|'in-progress'|'merged-unverified'|'complete'
//            |'stalled'|'unknown',  // the six-value enum (C5) — nothing else
//     reason,                       // stalled/unknown: the derived reason text
//     reason_class,                 // stalled: waiting-on-you|crashed|blocked-on|limit-parked
//     label,                        // the operator-facing chip text (named-absence pattern)
//     since,                        // ISO ts of the transition (I1 recency)
//   },
//   progress: {done,total} | null,  // null = zero tracked children (no fake granularity)
//   completed_at,                   // ISO ts | '' (completed aging, one 7d knob)
//   from_requests: [{id,title}],    // C6 — inherited by every descendant
//   roll_up: { <class>: {count, exemplar} },  // C1/R4 — one entry PER attention
//                                   // class present in the subtree; classes:
//                                   // waiting-on-you|crashed|blocked-on|limit-parked|unknown
//   children: [RoadmapItem],
// }
//
// ============================================================
// STATUS DERIVATION STUB (the task-1 seam — clearly marked)
// ============================================================
// Task 1 owns the real per-item status derivation in derive-lib.js (the
// six-value enum incl. the three-class completion oracle, heartbeat-backed
// in-progress, and the stalled reasons). This file ships the plan's PINNED
// MECHANICAL subset so the view is functional and honest before that merge:
//   - task:   checkbox done -> complete; task_started event + unflipped ->
//             in-progress; else not-started.
//   - plan:   plan file absent/unreadable -> unknown(reason) — NEVER a
//             confident bucket (C5); all tasks done + NO deploy signal ->
//             merged-unverified OUTSIDE complete (A4 binding rule; this stub
//             has no oracle config, i.e. every project is `no-signal`);
//             else in-progress / not-started from child counts.
//   - intent: registry status done/merged -> complete (manual done is an
//             override, LABELED); else rolled up from children.
//   - stalled(reason) is NOT derived here (heartbeat + ledger inputs are
//             task 1's); the renderer + roll-up plumbing below carry it the
//             moment derive-lib emits it.
// At merge, the block between STUB-STATUS-BEGIN/END is replaced by calls
// into task 1's derive-lib exports (see the fragment file).

const fs = require('fs');
const path = require('path');
const deriveLib = require('./derive-lib.js');
const planParse = require('./plan-parse.js');

const WEB_DIR = path.join(__dirname, '..', 'web');
const COMPLETED_AGE_DAYS = Number(process.env.ROADMAP_COMPLETED_AGE_DAYS) || 7;

// The five roll-up attention classes, in the pinned precedence order
// (adjudication (b) + delta R4: precedence governs display ORDER only —
// one badge per class present, a higher class never masks a lower one).
const ROLLUP_CLASSES = ['waiting-on-you', 'crashed', 'blocked-on', 'limit-parked', 'unknown'];

function sendJson(res, code, obj) {
  res.writeHead(code, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify(obj));
}

// ----------------------------------------------------------------------
// Registry fold (roadmap flavor) — the derive-lib fold drops per-record
// timestamps/emitters this view needs (created emitter for provenance,
// status_change ts for completed aging, title records for A3 precedence),
// so this reads the raw JSONL once and folds locally. Fold rules mirror
// ask-registry.sh's documented contract; the TITLE fold applies the A3
// rule: operator-sourced ALWAYS outranks auto REGARDLESS of timestamp.
// ----------------------------------------------------------------------
function foldRegistryForRoadmap() {
  const lines = deriveLib.readAskRegistry().slice()
    .sort((a, b) => String(a.ts).localeCompare(String(b.ts)));
  const byAsk = {};
  lines.forEach((rec) => {
    if (!rec || !rec.ask_id) return;
    const cur = byAsk[rec.ask_id] || {
      ask_id: rec.ask_id, plan_slugs: [], status: 'active', status_ts: '', status_emitter: '',
      created_ts: '', created_emitter: '', origin_session: '', repo: '', project: '',
      summary: '', auto_title: '', operator_title: '', roadmap_rank: null,
    };
    ['repo', 'project', 'summary'].forEach((f) => { if (rec[f]) cur[f] = rec[f]; });
    if (rec.record_type === 'created') {
      cur.created_ts = rec.ts || '';
      cur.created_emitter = rec.emitter || '';
      cur.origin_session = rec.origin_session || rec.session_id || '';
      if (rec.summary) cur.auto_title = rec.summary;
    }
    if (rec.record_type === 'plan_linked' && rec.plan_slug && cur.plan_slugs.indexOf(rec.plan_slug) === -1) {
      cur.plan_slugs.push(rec.plan_slug);
    }
    if ((rec.record_type === 'status_change' || rec.record_type === 'merged') && rec.status) {
      cur.status = rec.status; cur.status_ts = rec.ts || ''; cur.status_emitter = rec.emitter || '';
    } else if (rec.record_type === 'created' && rec.status) {
      cur.status = rec.status; cur.status_ts = rec.ts || '';
    }
    // Title records — task 2's shapes, read-forward-compatibly (A3):
    // summary_updated {summary} = the async distiller (auto slot);
    // title_set {title, title_source} = the set-title verb this file's
    // /api/roadmap/title delegates to.
    if (rec.record_type === 'summary_updated' && rec.summary) cur.auto_title = rec.summary;
    if (rec.record_type === 'title_set' && rec.title) {
      if (rec.title_source === 'operator') cur.operator_title = rec.title;
      else cur.auto_title = rec.title;
    }
    if (rec.record_type === 'roadmap_rank' && rec.rank !== undefined && rec.rank !== null && !isNaN(Number(rec.rank))) {
      cur.roadmap_rank = Number(rec.rank);
    }
    byAsk[rec.ask_id] = cur;
  });
  return byAsk;
}

// ----------------------------------------------------------------------
// Rank overlay — the INTERIM build-order store (a UI-state file, NOT the
// registry: registry writes stay ask-registry.sh's alone). Registry
// roadmap_rank records, once task 2's verb lands, take precedence per ask;
// the overlay covers every ask the registry has no rank record for. The
// fragment file documents the migration.
// ----------------------------------------------------------------------
function rankOverlayPath() {
  return path.join(path.dirname(deriveLib.askRegistryFile()), 'roadmap-rank-overlay.json');
}
function readRankOverlay() {
  try { return JSON.parse(fs.readFileSync(rankOverlayPath(), 'utf8')) || {}; }
  catch (_) { return {}; }
}
function writeRankOverlay(map) {
  const p = rankOverlayPath();
  const tmp = p + '.tmp-' + process.pid + '-' + Date.now();
  fs.writeFileSync(tmp, JSON.stringify(map, null, 2));
  fs.renameSync(tmp, p);
}

// ----------------------------------------------------------------------
// Provenance classifier (A9, operator B) — PROVENANCE, never subject
// matter: machine-filed means a mechanical filer created the ask (nl-issue /
// findings / auto-sweep / auditor emitters, or a mechanism-stamped summary
// prefix). Derivation failure defaults to 'operator' (the safe side — A9's
// stated risk is operator-requested work vanishing, never the reverse).
// ----------------------------------------------------------------------
const MACHINE_EMITTER_RE = /(auditor|auto-sweep|auto_sweep|nl-issue|nl_issue|findings|triage-bot|scheduled)/i;
const MACHINE_SUMMARY_PREFIX_RE = /^\s*(nl-issue:|auto[-: ]|\[auto\]|finding[: ])/i;
function classifyProvenance(reg) {
  if (reg.created_emitter && reg.created_emitter !== 'ask-registry' && MACHINE_EMITTER_RE.test(reg.created_emitter)) {
    return { provenance: 'machine', provenance_reason: 'filed by the "' + reg.created_emitter + '" mechanism, not from a conversation with you' };
  }
  if (MACHINE_SUMMARY_PREFIX_RE.test(reg.summary || '')) {
    return { provenance: 'machine', provenance_reason: 'auto-filed (mechanism-stamped title prefix)' };
  }
  return { provenance: 'operator', provenance_reason: 'registered from a conversation with you' };
}

// ----------------------------------------------------------------------
// STUB-STATUS-BEGIN (task-1 seam — see the header block)
// ----------------------------------------------------------------------
function statusObj(value, opts) {
  const o = opts || {};
  let label;
  if (value === 'unknown') label = 'status unknown — ' + (o.reason || 'derivation failed');
  else if (value === 'merged-unverified') label = 'merged — deploy unverified';
  else if (value === 'stalled') label = 'stalled — ' + (o.reason || 'reason unavailable');
  else if (value === 'complete') label = 'complete' + (o.override ? ' (operator override)' : '');
  else if (value === 'in-progress') label = 'in progress';
  else label = 'not started';
  return { value: value, reason: o.reason || '', reason_class: o.reason_class || '', label: label, since: o.since || '' };
}

function deriveTaskNode(askId, slug, t, startedTs, doneTs, fromRequests) {
  let status;
  let completedAt = '';
  if (t.done) {
    completedAt = doneTs[t.id] || '';
    status = statusObj('complete', { since: completedAt });
  } else if (startedTs[t.id]) {
    status = statusObj('in-progress', { since: startedTs[t.id] });
  } else {
    status = statusObj('not-started', {});
  }
  return {
    id: askId + '/' + slug + '/' + t.id,
    kind: 'task',
    title: 'task ' + t.id + (t.description ? ' — ' + t.description : ''),
    title_source: 'auto',
    project: '', provenance: 'operator', provenance_reason: '',
    rank: null, added_ts: '', added_mid_build: false,
    status: status,
    progress: null,
    completed_at: completedAt,
    from_requests: fromRequests,
    roll_up: {},
    children: [],
  };
}

function derivePlanNode(reg, slug, events, fromRequests) {
  const absPath = deriveLib.resolvePlanAbsPath(reg.repo, slug);
  const loaded = planParse.loadPlanFile(absPath);
  const startedTs = {}, doneTs = {};
  let latestActivity = '';
  events.forEach((e) => {
    if (!e || e.plan_slug !== slug || !e.task_id) return;
    if (e.type === 'task_started') startedTs[e.task_id] = e.ts || '';
    if (e.type === 'task_done') doneTs[e.task_id] = e.ts || '';
    if (e.ts && e.ts > latestActivity) latestActivity = e.ts;
  });
  const node = {
    id: reg.ask_id + '/' + slug,
    kind: 'plan',
    title: slug,
    title_source: 'auto',
    project: reg.project || '', provenance: 'operator', provenance_reason: '',
    rank: null, added_ts: '', added_mid_build: false,
    status: null,
    progress: null,
    completed_at: '',
    from_requests: fromRequests,
    roll_up: {},
    children: [],
  };
  if (!loaded.ok) {
    const reason = loaded.reason === 'damaged'
      ? 'plan file unreadable (' + (loaded.error || 'read failed') + ')'
      : 'plan file not found (docs/plans/' + slug + '.md)';
    node.status = statusObj('unknown', { reason: reason, since: latestActivity });
    return node;
  }
  const tasks = loaded.tasks || [];
  node.children = tasks.map((t) => deriveTaskNode(reg.ask_id, slug, t, startedTs, doneTs, fromRequests));
  const total = tasks.length;
  const done = tasks.filter((t) => t.done).length;
  const anyInProgress = node.children.some((c) => c.status.value === 'in-progress');
  if (total > 0) node.progress = { done: done, total: total };
  const latestDone = Object.keys(doneTs).map((k) => doneTs[k]).sort().pop() || '';
  if (total === 0) {
    node.status = anyInProgress || latestActivity
      ? statusObj('in-progress', { since: latestActivity })
      : statusObj('not-started', { since: reg.created_ts });
  } else if (done === total) {
    // All checked, NO deploy signal (this stub has no oracle config —
    // every project is the `no-signal` class): OUTSIDE Complete (A4).
    node.status = statusObj('merged-unverified', { reason: 'no deploy signal for this project', since: latestDone });
    node.completed_at = latestDone;
  } else if (anyInProgress || done > 0) {
    node.status = statusObj('in-progress', { since: latestActivity || latestDone });
  } else {
    node.status = statusObj('not-started', { since: reg.created_ts });
  }
  return node;
}

function deriveIntentNode(reg, events) {
  const prov = classifyProvenance(reg);
  const title = reg.operator_title || reg.auto_title || reg.summary || reg.ask_id;
  const fromRequests = [{ id: reg.ask_id, title: title }];
  const children = (reg.plan_slugs || []).map((slug) => derivePlanNode(reg, slug, events, fromRequests));
  const node = {
    id: reg.ask_id,
    kind: 'intent',
    title: title,
    title_source: reg.operator_title ? 'operator' : 'auto',
    project: reg.project || '',
    provenance: prov.provenance, provenance_reason: prov.provenance_reason,
    rank: null,
    added_ts: reg.created_ts || '', added_mid_build: false,
    status: null,
    progress: null,
    completed_at: '',
    from_requests: fromRequests,
    roll_up: {},
    children: children,
  };
  // leaf-task counts across every plan
  let done = 0, total = 0;
  children.forEach((p) => { if (p.progress) { done += p.progress.done; total += p.progress.total; } });
  if (total > 0) node.progress = { done: done, total: total };

  if (reg.status === 'done' || reg.status === 'merged') {
    // Manual done is ALWAYS an override, labeled (A4). The stub cannot
    // consult a completion oracle; task 1's derive-lib refines this into
    // complete-PROVEN vs override at merge.
    node.status = statusObj('complete', { since: reg.status_ts, override: true });
    node.completed_at = reg.status_ts || '';
    return node;
  }
  const anyInProgress = children.some((c) => c.status.value === 'in-progress');
  const knownChildren = children.filter((c) => c.status.value !== 'unknown');
  const allShipped = knownChildren.length > 0 &&
    knownChildren.every((c) => c.status.value === 'merged-unverified' || c.status.value === 'complete');
  if (children.length === 0) {
    node.status = statusObj('not-started', { since: reg.created_ts });
  } else if (knownChildren.length === 0) {
    // EVERY child failed derivation: this item's own status is underivable —
    // unknown(reason), never a confident bucket (C5). The per-child reasons
    // stay one click away on the children; the roll-up badge counts them.
    node.status = statusObj('unknown', {
      reason: children.length === 1
        ? (children[0].status.reason || 'linked plan could not be derived')
        : 'none of the ' + children.length + ' linked plans could be derived',
      since: reg.created_ts,
    });
  } else if (allShipped) {
    const latest = knownChildren.map((c) => c.completed_at).sort().pop() || reg.status_ts;
    node.status = statusObj('merged-unverified', { reason: 'no deploy signal for this project', since: latest });
    node.completed_at = latest || '';
  } else if (anyInProgress || done > 0) {
    const latestSince = children.map((c) => c.status.since || '').sort().pop() || '';
    node.status = statusObj('in-progress', { since: latestSince });
  } else {
    node.status = statusObj('not-started', { since: reg.created_ts });
  }
  return node;
}
// ----------------------------------------------------------------------
// STUB-STATUS-END
// ----------------------------------------------------------------------

// computeRollUps(node) — bottom-up: one entry PER attention class present
// in the subtree (delta R4 — precedence never selects), each {count,
// exemplar} where exemplar is one item id a badge click can expand to.
function computeRollUps(node) {
  const agg = {};
  function absorb(cls, count, exemplar) {
    if (!agg[cls]) agg[cls] = { count: 0, exemplar: exemplar };
    agg[cls].count += count;
    if (!agg[cls].exemplar) agg[cls].exemplar = exemplar;
  }
  (node.children || []).forEach((child) => {
    computeRollUps(child);
    const st = child.status || {};
    if (st.value === 'stalled') {
      const cls = ROLLUP_CLASSES.indexOf(st.reason_class) !== -1 ? st.reason_class : 'blocked-on';
      absorb(cls, 1, child.id);
    }
    if (st.value === 'unknown') absorb('unknown', 1, child.id);
    Object.keys(child.roll_up || {}).forEach((cls) => {
      absorb(cls, child.roll_up[cls].count, child.roll_up[cls].exemplar);
    });
  });
  node.roll_up = agg;
}

function buildRoadmapPayload() {
  const byAsk = foldRegistryForRoadmap();
  const overlay = readRankOverlay();
  const items = [];
  Object.keys(byAsk).forEach((askId) => {
    const reg = byAsk[askId];
    if (reg.status === 'dismissed') return; // off the roadmap entirely
    const events = deriveLib.readAskEvents(askId).slice()
      .sort((a, b) => String(a.ts).localeCompare(String(b.ts)));
    const node = deriveIntentNode(reg, events);
    // effective rank: registry roadmap_rank record > overlay > none
    node.rank = (reg.roadmap_rank !== null && reg.roadmap_rank !== undefined) ? reg.roadmap_rank
      : (typeof overlay[askId] === 'number' ? overlay[askId] : null);
    computeRollUps(node);
    items.push(node);
  });
  // Build order (A7): ranked items by rank, then everything else in
  // registry-insertion (created_ts) order — the plan's pinned DEFAULT.
  items.sort((a, b) => {
    const ar = a.rank === null ? Infinity : a.rank;
    const br = b.rank === null ? Infinity : b.rank;
    if (ar !== br) return ar - br;
    return String(a.added_ts).localeCompare(String(b.added_ts));
  });
  return {
    ok: true,
    generated_at: new Date().toISOString(),
    completed_age_days: COMPLETED_AGE_DAYS,
    items: items,
  };
}

// ----------------------------------------------------------------------
// ask-registry.sh delegation (one-writer discipline — same shape as
// server.js's runAskRegistryCli; duplicated per this codebase's small-
// helper convention because server.js is task-1-owned right now).
// ----------------------------------------------------------------------
function askRegistryCliPath() {
  return process.env.ASK_REGISTRY_CLI ||
    path.join(__dirname, '..', '..', '..', 'adapters', 'claude-code', 'scripts', 'ask-registry.sh');
}

function runAskRegistryCli(args) {
  return new Promise((resolve) => {
    const cli = askRegistryCliPath();
    if (!fs.existsSync(cli)) return resolve({ ok: false, missing: true, error: 'registry CLI not found' });
    let bashBin, spawnEnv;
    try {
      const dc = require('./derive-cache.js');
      bashBin = dc.bashBin; spawnEnv = dc.spawnEnv;
    } catch (e) { return resolve({ ok: false, error: 'shell environment unavailable' }); }
    const { spawn } = require('child_process');
    const cmd = 'bash ' + deriveLib.shQuote(cli) + ' ' + args.map(deriveLib.shQuote).join(' ');
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
    // 180s — the measured worst case for login-shell bash spawns on this
    // machine (server.js's lifecycle endpoint uses the same budget).
    setTimeout(() => done({ ok: false, error: 'registry call timed out' }), 180000);
  });
}

function readBody(req, cb) {
  let buf = '';
  req.on('data', (c) => { buf += c; if (buf.length > 1e5) req.destroy(); });
  req.on('end', () => {
    let input;
    try { input = buf ? JSON.parse(buf) : {}; } catch (_) { input = null; }
    cb(input);
  });
}

// ----------------------------------------------------------------------
// handle(req, res) -> true when consumed. The ONE server.js mount line
// (see the fragment file):  if (roadmapRoutes.handle(req, res)) return;
// ----------------------------------------------------------------------
function handle(req, res) {
  const urlPath = String(req.url || '').split('?')[0];

  if (urlPath === '/roadmap.js' && req.method === 'GET') {
    fs.readFile(path.join(WEB_DIR, 'roadmap.js'), (err, buf) => {
      if (err) { res.writeHead(404); res.end('not found'); return; }
      res.writeHead(200, { 'Content-Type': 'text/javascript; charset=utf-8', 'Cache-Control': 'no-cache, must-revalidate' });
      res.end(buf);
    });
    return true;
  }

  if (urlPath === '/api/roadmap' && req.method === 'GET') {
    try {
      sendJson(res, 200, buildRoadmapPayload());
    } catch (e) {
      // rc-style honesty: the client renders pane-error + Retry from
      // ok:false — NEVER the empty state on failure (C4).
      sendJson(res, 200, { ok: false, error: String(e && e.message || e), items: [] });
    }
    return true;
  }

  if (urlPath === '/api/roadmap/rank' && req.method === 'POST') {
    readBody(req, (input) => {
      if (!input) return sendJson(res, 400, { ok: false, error: 'bad json' });
      const askId = typeof input.ask_id === 'string' ? input.ask_id : '';
      const direction = input.direction === 'up' ? 'up' : (input.direction === 'down' ? 'down' : '');
      if (!askId || !direction) return sendJson(res, 400, { ok: false, error: 'ask_id and direction (up|down) are required' });
      let payload;
      try { payload = buildRoadmapPayload(); }
      catch (e) { return sendJson(res, 500, { ok: false, error: String(e && e.message || e) }); }
      const ids = payload.items.map((i) => i.id);
      const idx = ids.indexOf(askId);
      if (idx === -1) return sendJson(res, 404, { ok: false, error: 'roadmap item not found: ' + askId });
      const swapWith = direction === 'up' ? idx - 1 : idx + 1;
      if (swapWith < 0 || swapWith >= ids.length) {
        return sendJson(res, 200, { ok: true, unchanged: true, order: ids });
      }
      const newOrder = ids.slice();
      newOrder[idx] = ids[swapWith];
      newOrder[swapWith] = askId;
      // Materialize the FULL order into the overlay (instant, works today);
      // additionally record the moved item's rank in the registry when the
      // set-rank verb exists (task 2's fold then takes precedence per ask).
      const overlay = {};
      newOrder.forEach((id, i) => { overlay[id] = (i + 1) * 10; });
      try { writeRankOverlay(overlay); }
      catch (e) { return sendJson(res, 500, { ok: false, error: 'could not save the new order' }); }
      runAskRegistryCli(['set-rank', '--ask-id', askId, '--rank', String((newOrder.indexOf(askId) + 1) * 10), '--emitter', 'operator-ui'])
        .then((r) => {
          // Registry delegation is best-effort until task 2's verb lands —
          // the overlay already carries the order either way.
          sendJson(res, 200, { ok: true, order: newOrder, registry_recorded: !!r.ok });
        });
    });
    return true;
  }

  if (urlPath === '/api/roadmap/title' && req.method === 'POST') {
    readBody(req, (input) => {
      if (!input) return sendJson(res, 400, { ok: false, error: 'bad json' });
      const askId = typeof input.ask_id === 'string' ? input.ask_id : '';
      const title = typeof input.title === 'string' ? input.title.trim() : '';
      if (!askId || !title) return sendJson(res, 400, { ok: false, error: 'ask_id and a non-empty title are required' });
      // One-writer discipline (A3): the title lives in the registry, so this
      // endpoint ONLY delegates — no overlay, no second title store. Until
      // the work-item layer's set-title verb lands, the honest answer is a
      // named error, never a silent success.
      runAskRegistryCli(['set-title', '--ask-id', askId, '--title', title, '--title-source', 'operator', '--emitter', 'operator-ui'])
        .then((r) => {
          if (r.ok) return sendJson(res, 200, { ok: true, ask_id: askId, title: title, title_source: 'operator' });
          const why = r.missing ? 'the title store is not available on this build yet'
            : ('the title store rejected the change' + (r.stderr ? ': ' + String(r.stderr).trim().split('\n').pop() : ''));
          sendJson(res, 200, { ok: false, error: 'could not save the title — ' + why });
        });
    });
    return true;
  }

  return false;
}

module.exports = {
  handle,
  buildRoadmapPayload,
  classifyProvenance,
  foldRegistryForRoadmap,
  ROLLUP_CLASSES,
  COMPLETED_AGE_DAYS,
};
