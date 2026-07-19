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
//                               verb — see STATUS DERIVATION below).
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
//     unblock,                      // OPTIONAL {label, hash} for a stalled item whose
//                                   // reason has a known navigable target (e.g.
//                                   // waiting-on-you -> #inbox/<id>); absent when no
//                                   // real cross-reference exists yet (task 4's Inbox
//                                   // data — not derived by this task, renderer already
//                                   // treats it as optional).
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
// STATUS DERIVATION (wired to task 1's derive-lib.js — the seam this file
// used to ship as a mechanical stub between STUB-STATUS-BEGIN/END; see
// docs/plans/fragments/roadmap-t3-server-fragment.md §2 for the merge note)
// ============================================================
// Every per-item status below is computed by calling
// deriveLib.deriveItemStatus() (the ONE status function, C5's no-default-
// guess invariant lives there, not here) — this file supplies the INPUTS
// (ground-truth done/started booleans, session ids, the once-per-request
// heartbeat read) and stays responsible for the TREE-SHAPE concerns
// derive-lib deliberately does not own: `since` timestamps, the
// operator-facing `label` text, and the bottom-up roll-up counts
// (computeRollUps, below — unchanged by this wiring, since it already reads
// any child's status.value/reason_class generically).
//
// ONE naming translation: derive-lib's internal enum spells the merged-but-
// unverified state `merged-deploy-unverified`; this route's PINNED payload
// contract (above) spells it `merged-unverified` (the name pinned by
// web/roadmap.js + cockpit.selftest.js's T3-* block before this wiring
// landed). mapDerivedValue() below is the one place that translates.
//
//   - task:   checkbox done -> complete, UNCONDITIONALLY (never routed
//             through the completion-oracle — the oracle answers "has this
//             SHIPPED unit been deploy-verified", a question that applies at
//             plan/intent granularity, not to an individual checkbox inside
//             an unmerged plan; this matches the pinned contract's own
//             task-level rule, unchanged by this wiring). Not done ->
//             deriveItemStatus's not-done branch, real heartbeat-backed
//             in-progress/stalled/unknown (this is the seam that lights up
//             stalled + unknown at task granularity — the stub never emitted
//             either).
//   - plan:   plan file absent/unreadable -> unknown(reason) — NEVER a
//             confident bucket (C5), unchanged (plan-parse's own contract,
//             not task 1's). All tasks done -> deriveItemStatus's done
//             branch: the REAL per-project completion-oracle now decides
//             complete vs merged-unverified (a configured project can now
//             render true complete-PROVEN; an unconfigured one still renders
//             merged-unverified, OUTSIDE complete — A4). Else: in-progress /
//             not-started from child counts (tree-aggregation, unchanged —
//             the ROLL-UP LAW, not this seam, is what surfaces a stalled/
//             unknown descendant to a parent whose own status stays
//             in-progress).
//   - intent: registry status done/merged -> deriveItemStatus with
//             overrideComplete:true (ALWAYS complete per derive-lib's own
//             contract — A4's "manual done is always an override, labeled").
//             All children shipped -> same oracle-backed done branch as
//             plan-level. Else: rolled up from children (unchanged).
//   - added_mid_build has NO derive-lib export (task 1 did not ship an
//     insertion-marker data source) — stays `false` here, same as before
//     this wiring; a real source is a future task's honest gap, not this
//     one's (Chesterton's Fence: no mechanism invented for it here).

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
// Status derivation (task-1 seam — see the header block above)
// ----------------------------------------------------------------------

// mapDerivedValue(value) — the ONE enum-name translation (see header note):
// derive-lib spells the merged-but-unverified state `merged-deploy-
// unverified`; this route's pinned payload contract spells it
// `merged-unverified`. Every other enum value is spelled identically in
// both places (identity passthrough).
function mapDerivedValue(value) {
  return value === 'merged-deploy-unverified' ? 'merged-unverified' : value;
}

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

// statusFromDerived(derived, opts) — wraps a REAL deriveLib.deriveItemStatus()
// result ({status, reason, oracle_class?, overridden?}) into this route's
// statusObj shape. A stalled item's `reason` IS its reason_class already
// (deriveStalledReason's return value is always one of the four named
// classes — see derive-lib.js) so no separate lookup is needed. `since` is
// a view-only recency timestamp derive-lib does not carry — the caller
// supplies it from its own knowledge of the relevant event timestamp.
function statusFromDerived(derived, opts) {
  const o = opts || {};
  const value = mapDerivedValue(derived.status);
  const reasonClass = derived.status === 'stalled' ? derived.reason : '';
  const reason = derived.reason || (value === 'merged-unverified' ? 'no deploy signal for this project' : '');
  return statusObj(value, {
    reason: reason,
    reason_class: reasonClass,
    since: o.since || '',
    override: !!derived.overridden,
  });
}

function deriveTaskNode(askId, slug, t, startedTs, doneTs, sessionsByTask, fromRequests, hbCtx) {
  let status;
  let completedAt = '';
  if (t.done) {
    // Task-level completion is a plan-internal checkbox, never itself the
    // shippable unit the completion-oracle judges — stays a simple,
    // unconditional complete (see the header note).
    completedAt = doneTs[t.id] || '';
    status = statusObj('complete', { since: completedAt });
  } else {
    const derived = deriveLib.deriveItemStatus({
      done: false,
      startedEvent: !!startedTs[t.id],
      sessionIds: (sessionsByTask && sessionsByTask[t.id]) || [],
      heartbeats: hbCtx.heartbeats,
      heartbeatsStoreOk: hbCtx.heartbeatsStoreOk,
      nowMs: hbCtx.nowMs,
    });
    status = statusFromDerived(derived, { since: startedTs[t.id] || '' });
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

function derivePlanNode(reg, slug, events, fromRequests, hbCtx) {
  const absPath = deriveLib.resolvePlanAbsPath(reg.repo, slug);
  const loaded = planParse.loadPlanFile(absPath);
  const startedTs = {}, doneTs = {};
  const sessionsByTask = {};
  let latestActivity = '';
  events.forEach((e) => {
    if (!e || e.plan_slug !== slug || !e.task_id) return;
    if (e.type === 'task_started') {
      startedTs[e.task_id] = e.ts || '';
      if (e.session_id) {
        sessionsByTask[e.task_id] = sessionsByTask[e.task_id] || [];
        if (sessionsByTask[e.task_id].indexOf(e.session_id) === -1) sessionsByTask[e.task_id].push(e.session_id);
      }
    }
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
  node.children = tasks.map((t) => deriveTaskNode(reg.ask_id, slug, t, startedTs, doneTs, sessionsByTask, fromRequests, hbCtx));
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
    // All checked: the REAL per-project completion-oracle decides complete
    // vs merged-unverified (A4) — no live deploy-signal collector on a GET
    // path (A6), so deployReadyAtMs is always null here.
    const mergedAtMs = latestDone ? Date.parse(latestDone) : null;
    const derived = deriveLib.deriveItemStatus({
      done: true,
      projectKey: reg.project,
      mergedAtMs: isNaN(mergedAtMs) ? null : mergedAtMs,
      deployReadyAtMs: null,
      overrideComplete: false,
    });
    node.status = statusFromDerived(derived, { since: latestDone });
    node.completed_at = latestDone;
  } else if (anyInProgress || done > 0) {
    node.status = statusObj('in-progress', { since: latestActivity || latestDone });
  } else {
    node.status = statusObj('not-started', { since: reg.created_ts });
  }
  return node;
}

function deriveIntentNode(reg, events, hbCtx) {
  const prov = classifyProvenance(reg);
  const title = reg.operator_title || reg.auto_title || reg.summary || reg.ask_id;
  const fromRequests = [{ id: reg.ask_id, title: title }];
  const children = (reg.plan_slugs || []).map((slug) => derivePlanNode(reg, slug, events, fromRequests, hbCtx));
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
    // Manual done is ALWAYS an override, labeled (A4) — overrideComplete:true
    // guarantees derive-lib's done branch renders complete regardless of
    // this project's configured oracle class.
    const statusTsMs = reg.status_ts ? Date.parse(reg.status_ts) : null;
    const derived = deriveLib.deriveItemStatus({
      done: true,
      projectKey: reg.project,
      mergedAtMs: isNaN(statusTsMs) ? null : statusTsMs,
      overrideComplete: true,
    });
    node.status = statusFromDerived(derived, { since: reg.status_ts });
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
    const latestMs = latest ? Date.parse(latest) : null;
    const derived = deriveLib.deriveItemStatus({
      done: true,
      projectKey: reg.project,
      mergedAtMs: isNaN(latestMs) ? null : latestMs,
      deployReadyAtMs: null,
      overrideComplete: false,
    });
    node.status = statusFromDerived(derived, { since: latest });
    node.completed_at = latest || '';
  } else if (anyInProgress || done > 0) {
    const latestSince = children.map((c) => c.status.since || '').sort().pop() || '';
    node.status = statusObj('in-progress', { since: latestSince });
  } else {
    node.status = statusObj('not-started', { since: reg.created_ts });
  }
  return node;
}

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
  // Heartbeats read ONCE per request (derive-lib's own convention — see
  // derive-lib.js's heartbeat section header) and handed to every item's
  // derivation below; heartbeatsStoreOk distinguishes a genuinely-absent
  // store (benign) from one that exists but could not be read (a real
  // derivation-input failure — C5). Pure fs read, no spawn (A6).
  const hbResult = deriveLib.listRawHeartbeatsResult();
  const hbCtx = { heartbeats: hbResult.heartbeats, heartbeatsStoreOk: hbResult.ok, nowMs: Date.now() };
  const items = [];
  Object.keys(byAsk).forEach((askId) => {
    const reg = byAsk[askId];
    if (reg.status === 'dismissed') return; // off the roadmap entirely
    const events = deriveLib.readAskEvents(askId).slice()
      .sort((a, b) => String(a.ts).localeCompare(String(b.ts)));
    const node = deriveIntentNode(reg, events, hbCtx);
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
