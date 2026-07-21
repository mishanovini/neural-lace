'use strict';
// roadmap-routes.js — the Roadmap view's server surface
// (cockpit-roadmap-redesign Task 3, RE-ROOTED per the 2026-07-21 design-input
// Round 8 operator decision — docs/reviews/2026-07-17-cockpit-ux-design-
// input.md, "Round 8"). Routes (handle() returns true when it consumed the
// request):
//   GET  /roadmap.js          — serves the client module.
//   GET  /api/roadmap         — the roadmap tree payload (contract below).
//   POST /api/roadmap/rank    — keyboard-operable move up/down (A7/R2).
//   POST /api/roadmap/title   — title edit, delegated to ask-registry.sh
//                               (A3 one-writer discipline) for the FIRST
//                               ask linked to the target plan.
//
// ============================================================
// ROUND 8 — THE RE-ROOTING (binding; supersedes the prior ask/intent-rooted
// design this file shipped with)
// ============================================================
// The operator's repeatedly-stated vision: "a series of plans being worked
// on, phases 1-4, each a branch with its tasks as leaves" (round 1/6), and
// two round-8 data-shape residuals found on the deployed round-6/7 fix:
// (a) junk conversational captures ("The computer rebooted.") rendered as
//     top-level roadmap items — noise with no build value.
// (b) the operator's ACTUAL active work (redesign, other in-flight plans)
//     did NOT appear, because the tree rooted on the ask-registry and those
//     plans have no linked ask.
// FIX (8A): the Roadmap tree ROOTS ON PLAN FILES (docs/plans/*.md), each a
// top-level phase-node with its tasks as leaves — asks are no longer the
// root; they only supply OPTIONAL provenance (from_requests, C6) when a
// plan happens to have one linked. Requests/asks live ENTIRELY in the
// Requests tab now (server/requests-routes.js, unchanged by this task).
// CONSEQUENCE (8B, free): an unlinked junk ask has no plan, so a plan-rooted
// Roadmap never shows it — no separate junk filter was built; re-rooting
// IS the fix.
//
// WHICH plan files root the tree (a documented scoping choice, not dictated
// verbatim by round 8's prose):
//   - every `docs/plans/*.md` (top-level only — NOT `fragments/`, NOT
//     `deferred/`, which are directory-scoped OUT by the non-recursive
//     scan) whose `Status:` header is non-empty and does not start with
//     REFERENCE or NORMATIVE (a whole-corpus check, 2026-07-21, found only
//     ACTIVE/NORMATIVE/REFERENCE headers among top-level plans, plus ~20
//     files with NO header at all — the `*-evidence*.md` dumps; REFERENCE/
//     NORMATIVE explicitly self-describe as "not an independent plan" and
//     a header-less file is indistinguishable from an evidence dump, so
//     both are excluded rather than guessed at).
//   - every `docs/plans/archive/*.md` file, but ONLY when its mtime is
//     within the SAME completed_age_days window used for the client's own
//     completed-collapse aging (I2 — one tunable) — "do NOT dump the entire
//     archive/ history ... ancient archived plans stay out" (round 8).
//     File mtime is used as a proxy for "when this was archived/completed"
//     (the archival mechanism moves/touches the file); this is an honest,
//     documented approximation, not a guess dressed as a real timestamp.
//   - every plan a REGISTERED ask still links to (`plan_linked`), resolved
//     against THAT ask's own repo (preserving the pre-existing cross-repo
//     plan-linking behavior), subject to the same status/aging filters —
//     EXCEPT a linked plan that cannot be read at all (absent/damaged)
//     still surfaces as an `unknown` root rather than silently vanishing
//     (an operator's tracked work going dark is exactly what C5 exists to
//     surface, never a silent omission).
//
// ============================================================
// PAYLOAD CONTRACT (pinned for the T1 status-derivation seam)
// ============================================================
// GET /api/roadmap -> {
//   ok, generated_at, completed_age_days,
//   items: [RoadmapItem]            // top-level PLANS, in BUILD ORDER
// }
// RoadmapItem = {
//   id,                             // plan: <slug>; task: <slug>/<task_id>
//   kind: 'plan'|'task',
//   title, title_source: 'operator'|'auto',
//   project, provenance: 'operator', provenance_reason: '',
//   rank,                           // effective build-order rank (number|null)
//   added_ts, added_mid_build,
//   status: {
//     value: 'not-started'|'in-progress'|'merged-unverified'|'complete'
//            |'stalled'|'unknown',  // the six-value enum (C5)
//     reason, reason_class, label, since,
//     unblock,                      // OPTIONAL {label, hash}
//   },
//   progress: {done,total} | null,
//   completed_at,                   // ISO ts | ''
//   from_requests: [{id,title}],    // C6 — the ask(s), if any, that link to
//                                   // this plan; empty for an unlinked plan
//                                   // (never fabricated, never required)
//   roll_up: { <class>: {count, exemplar} },
//   children: [RoadmapItem],        // task kind
//   // ---- task-kind-only fields (round-6 gap 1 + round-7 7A/7B/7B-i) ----
//   lead_points: [string],
//   subtasks: [{title, body_points: [string]}],
//   live_sessions: [{id, kind:'agent', title, status:{value,label,since}}],
// }
//
// ============================================================
// STATUS DERIVATION (unchanged from the T1 wiring — this file supplies the
// INPUTS to deriveLib.deriveItemStatus() and stays responsible for the
// TREE-SHAPE concerns derive-lib does not own: `since`, `label`, roll-ups).
// ============================================================
//   - task:   checkbox done -> complete, UNCONDITIONALLY. Not done ->
//             deriveItemStatus's not-done branch (real heartbeat-backed
//             in-progress/stalled/unknown).
//   - plan:   plan file absent/unreadable -> unknown(reason), never a
//             confident bucket (C5). A linked ask manually marked
//             done/merged is ALWAYS a labeled override (A4), same rule
//             that used to live at the intent level — moved here since
//             plans are now the root. All tasks done (no override) -> the
//             real per-project completion-oracle decides complete vs
//             merged-unverified (A4). Else: in-progress/not-started from
//             child counts.

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
// timestamps/emitters this view needs (created emitter, status_change ts,
// title records), so this reads the raw JSONL once and folds locally. Fold
// rules mirror ask-registry.sh's documented contract; the TITLE fold
// applies the A3 rule: operator-sourced ALWAYS outranks auto REGARDLESS of
// timestamp. This fold is STILL needed post-round-8: it is the source of
// (a) which plans an ask links to (provenance, C6) and (b) the ONE-WRITER
// title/rank delegation target — asks are no longer the tree ROOT, but
// they are still the store title/rank edits write through.
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
    ['repo', 'project'].forEach((f) => { if (rec[f]) cur[f] = rec[f]; });
    if (rec.summary && (rec.record_type === 'created' || rec.record_type === 'summary_updated')) {
      cur.summary = rec.summary;
    }
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
    // Title records — task 2's REAL write shape (D2 — BINDING): `set-title`
    // appends `summary_updated` + `title_source:"operator"`. Routing keys
    // off `title_source` on the SAME record, not record_type alone, so a
    // LATER auto summary_updated (distiller re-run) never clobbers an
    // operator edit in this reader (the F3 race).
    if (rec.record_type === 'summary_updated' && rec.summary) {
      if (rec.title_source === 'operator') cur.operator_title = rec.summary;
      else cur.auto_title = rec.summary;
    }
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

// buildPlanAskLinks(byAsk) -> { <slug>: [{ask_id,title,title_source,project,
// repo,created_ts,roadmap_rank,status,status_ts}, ...] } — the reverse index
// from plan slug to every (non-dismissed) ask that links it. A plan can be
// linked by more than one ask (rare); the FIRST entry (registry-fold order,
// i.e. earliest `created_ts`) is the one title/rank edits delegate through
// and the one whose title/project the plan node displays, by convention
// with the prior single-owner-per-item behavior.
function buildPlanAskLinks(byAsk) {
  const bySlug = {};
  Object.keys(byAsk).forEach((askId) => {
    const reg = byAsk[askId];
    if (reg.status === 'dismissed') return;
    const title = reg.operator_title || reg.auto_title || reg.summary || askId;
    (reg.plan_slugs || []).forEach((slug) => {
      if (!bySlug[slug]) bySlug[slug] = [];
      bySlug[slug].push({
        ask_id: askId,
        title: title,
        title_source: reg.operator_title ? 'operator' : 'auto',
        project: reg.project || '',
        repo: reg.repo || '',
        created_ts: reg.created_ts || '',
        roadmap_rank: (reg.roadmap_rank === null || reg.roadmap_rank === undefined) ? null : reg.roadmap_rank,
        status: reg.status || '',
        status_ts: reg.status_ts || '',
      });
    });
  });
  return bySlug;
}

// ----------------------------------------------------------------------
// Plan-file discovery (8A) — which files root the tree. See the header
// note for the full rationale of each filter.
// ----------------------------------------------------------------------
function planScanRoot() {
  // Sandboxable like every other state path in this codebase (ASK_REGISTRY_
  // STATE_DIR etc.) — a dedicated override so tests never touch the real
  // checkout's docs/plans/.
  return process.env.ROADMAP_PLAN_SCAN_ROOT || deriveLib.mainRepoRoot();
}

const PLAN_STATUS_EXCLUDE_RE = /^(REFERENCE|NORMATIVE)\b/i;
function isEligiblePlanStatus(statusText) {
  const t = String(statusText || '').trim();
  if (!t) return false; // no Status: header at all -> evidence dump / stub, not a plan
  return !PLAN_STATUS_EXCLUDE_RE.test(t);
}

// scanPlanDir(dir, opts) -> [{slug, absPath, archived, mtimeMs}] for every
// eligible top-level *.md file directly inside `dir` (non-recursive — a
// subdirectory like fragments/ or archive/ itself is never descended into
// by this call; archive/ is scanned via ITS OWN separate call).
function scanPlanDir(dir, opts) {
  const options = opts || {};
  const out = [];
  let ents;
  try { ents = fs.readdirSync(dir, { withFileTypes: true }); } catch (_) { return out; }
  ents.forEach((e) => {
    if (!e.isFile() || !/\.md$/i.test(e.name)) return;
    const abs = path.join(dir, e.name);
    let stat;
    try { stat = fs.statSync(abs); } catch (_) { return; }
    if (typeof options.cutoffMs === 'number' && stat.mtimeMs < options.cutoffMs) return;
    let text;
    try { text = fs.readFileSync(abs, 'utf8'); } catch (_) { return; }
    if (!isEligiblePlanStatus(planParse.parsePlanStatus(text))) return;
    out.push({ slug: e.name.replace(/\.md$/i, ''), absPath: abs, archived: !!options.archived, mtimeMs: stat.mtimeMs });
  });
  return out;
}

// discoverPlanFiles(scanRoot, planAskLinks) -> [{slug, absPath, archived, mtimeMs}]
// the UNION of (1) scanRoot's own docs/plans/*.md, (2) scanRoot's docs/
// plans/archive/*.md within the completed-aging window, and (3) every
// ask-linked plan slug resolved against ITS OWN ask's repo (cross-repo
// plan-linking, preserved) not already captured by (1)/(2). Deduped by
// SLUG, not absolute path: a slug is the roadmap node's own identity
// (`id: pf.slug`), and a registry `repo` field can be recorded in a
// different path STYLE than this process's own path.win32 resolution
// (e.g. a POSIX-style `/c/Users/...` string written by a git-bash session,
// vs this Node process's `C:\Users\...`) — deduping by the resolved
// absPath STRING let the same real plan slip through twice under two
// textually-different-but-filesystem-equivalent paths (found via a real-
// data live check, 2026-07-21: `ask-rooted-workstreams-p1` rendered
// twice). Deduping by slug is also simply the correct invariant regardless
// of that specific cause: two entries sharing one `id` would corrupt
// client-side expand-state keying (openSet[item.id]) and DOM lookups
// (data-item-id) even if the path-string mismatch above were fixed some
// other way.
function discoverPlanFiles(scanRoot, planAskLinks) {
  const seenSlugs = {};
  const out = [];
  const cutoffMs = Date.now() - COMPLETED_AGE_DAYS * 86400000;

  scanPlanDir(path.join(scanRoot, 'docs', 'plans'), { archived: false }).forEach((pf) => {
    seenSlugs[pf.slug] = true; out.push(pf);
  });
  scanPlanDir(path.join(scanRoot, 'docs', 'plans', 'archive'), { archived: true, cutoffMs: cutoffMs }).forEach((pf) => {
    if (seenSlugs[pf.slug]) return;
    seenSlugs[pf.slug] = true; out.push(pf);
  });

  Object.keys(planAskLinks).forEach((slug) => {
    if (seenSlugs[slug]) return;
    const links = planAskLinks[slug];
    let repo = scanRoot;
    for (let i = 0; i < links.length; i++) { if (links[i].repo) { repo = links[i].repo; break; } }
    // resolvePlanAbsPath returns null when the file exists at NEITHER
    // docs/plans/ NOR docs/plans/archive/ under this repo — a genuinely
    // missing linked plan (the "ghost-plan" case), not merely an unreadable
    // one. Synthesize the expected docs/plans/<slug>.md path in that case
    // so the read below honestly fails ENOENT and this still surfaces as an
    // `unknown` root (C5) rather than silently vanishing — an operator's
    // tracked work going dark must never look identical to "no such plan
    // was ever linked".
    const abs = planParse.resolvePlanAbsPath(repo, slug) || path.join(repo, 'docs', 'plans', slug + '.md');
    let stat, text;
    try { stat = fs.statSync(abs); text = fs.readFileSync(abs, 'utf8'); }
    catch (_) {
      // The linked plan file genuinely can't be read (missing/moved/
      // permission error) — still surface it as a root so it renders
      // unknown(reason) rather than an operator's tracked work silently
      // going dark (C5).
      seenSlugs[slug] = true;
      out.push({ slug: slug, absPath: abs, archived: /[\\/]archive[\\/]/.test(abs), mtimeMs: 0 });
      return;
    }
    const archived = /[\\/]archive[\\/]/.test(abs);
    if (archived && stat.mtimeMs < cutoffMs) return; // ancient archived linked plan stays out too
    if (!isEligiblePlanStatus(planParse.parsePlanStatus(text))) return;
    seenSlugs[slug] = true;
    out.push({ slug: slug, absPath: abs, archived: archived, mtimeMs: stat.mtimeMs });
  });
  return out;
}

// ----------------------------------------------------------------------
// Plan-rank overlay — the INTERIM per-PLAN build-order store (a UI-state
// file, NOT the registry). Keyed by plan SLUG (the roadmap item's own id,
// now that plans are the root) — deliberately a SEPARATE file from any
// prior ask-keyed overlay: the id-space changed with the re-rooting, and
// reusing the old file name under new key semantics would risk a stale
// on-disk file being silently misread under the new meaning.
// ----------------------------------------------------------------------
function planRankOverlayPath() {
  return path.join(path.dirname(deriveLib.askRegistryFile()), 'roadmap-plan-rank-overlay.json');
}
function readPlanRankOverlay() {
  try { return JSON.parse(fs.readFileSync(planRankOverlayPath(), 'utf8')) || {}; }
  catch (_) { return {}; }
}
function writePlanRankOverlay(map) {
  const p = planRankOverlayPath();
  const tmp = p + '.tmp-' + process.pid + '-' + Date.now();
  fs.writeFileSync(tmp, JSON.stringify(map, null, 2));
  fs.renameSync(tmp, p);
}

// ----------------------------------------------------------------------
// Status derivation (unchanged plumbing; see header note)
// ----------------------------------------------------------------------
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

// deriveLiveAgentLeaves(taskId, sessionIds, heartbeats, nowMs) -> [AgentLeaf]
// Round 7B-i: currently-running background agents/sessions render as live
// sub-task leaves under the task they serve. A session with NO matching
// heartbeat record renders 'unknown' (named-absence, C5) — never guessed.
function deriveLiveAgentLeaves(taskId, sessionIds, heartbeats, nowMs) {
  const th = deriveLib.activityThresholdsMs();
  const ids = (sessionIds || []).filter(Boolean);
  return ids.map((sid) => {
    const hb = (heartbeats || []).find((h) => h && h.session_id === sid);
    if (!hb) {
      return {
        id: taskId + '/agent/' + sid,
        kind: 'agent',
        title: 'session ' + sid,
        status: { value: 'unknown', label: 'status unknown — no heartbeat evidence', reason: 'no heartbeat file found for this session', since: '' },
      };
    }
    const ageMs = nowMs - Date.parse(hb.last_activity_ts);
    const ageCls = deriveLib.classifyHeartbeatAge(isNaN(ageMs) ? NaN : ageMs, th);
    const value = ageCls === 'crashed' ? 'stalled' : 'running';
    return {
      id: taskId + '/agent/' + sid,
      kind: 'agent',
      title: 'session ' + sid + (hb.branch ? ' (' + hb.branch + ')' : ''),
      status: {
        value: value,
        label: value === 'running' ? 'running' : 'stalled — no recent heartbeat',
        reason: '', since: hb.last_activity_ts || '',
      },
    };
  });
}

// deriveTaskNode(slug, t, ...) — id scheme is now `<slug>/<task_id>` (the
// ask_id segment is gone: plans, not asks, are the root, so a task's
// address is relative to its plan alone).
function deriveTaskNode(slug, t, startedTs, doneTs, sessionsByTask, fromRequests, hbCtx) {
  let status;
  let completedAt = '';
  const taskSessionIds = (sessionsByTask && sessionsByTask[t.id]) || [];
  if (t.done) {
    completedAt = doneTs[t.id] || '';
    status = statusObj('complete', { since: completedAt });
  } else {
    const derived = deriveLib.deriveItemStatus({
      done: false,
      startedEvent: !!startedTs[t.id],
      sessionIds: taskSessionIds,
      heartbeats: hbCtx.heartbeats,
      heartbeatsStoreOk: hbCtx.heartbeatsStoreOk,
      nowMs: hbCtx.nowMs,
    });
    status = statusFromDerived(derived, { since: startedTs[t.id] || '' });
  }

  const struct = deriveLib.splitTaskStructure(t.description);
  const distilled = deriveLib.distillTaskTitle(struct.lead);
  const leadPoints = deriveLib.splitIntoSentences(distilled.remainder);
  const subtasks = struct.subtasks.map((s) => ({
    title: s.title,
    body_points: deriveLib.splitIntoSentences(s.body),
  }));
  const liveSessions = (!t.done && taskSessionIds.length)
    ? deriveLiveAgentLeaves(slug + '/' + t.id, taskSessionIds, hbCtx.heartbeats, hbCtx.nowMs)
    : [];

  return {
    id: slug + '/' + t.id,
    kind: 'task',
    title: 'task ' + t.id + ': ' + distilled.title,
    title_source: 'auto',
    project: '', provenance: 'operator', provenance_reason: '',
    rank: null, added_ts: '', added_mid_build: false,
    status: status,
    progress: null,
    completed_at: completedAt,
    from_requests: fromRequests,
    lead_points: leadPoints,
    subtasks: subtasks,
    live_sessions: liveSessions,
    roll_up: {},
    children: [],
  };
}

// eventsForSlug(slug, linkedAsks) — plan-native events: every linked ask's
// own progress-log file, PLUS the shared "unlinked" orphan lane
// (progress-log-lib.sh's own documented fallback for events emitted with no
// ask_id) always consulted too and filtered down to this plan's own slug —
// this is how a plan with NO linked ask still gets real task_started/
// task_done derivation (no new event mechanism invented; this lane already
// exists and is where such events land today).
function eventsForSlug(slug, linkedAsks) {
  const seenAskIds = {};
  let all = [];
  (linkedAsks || []).forEach((a) => {
    if (seenAskIds[a.ask_id]) return;
    seenAskIds[a.ask_id] = true;
    all = all.concat(deriveLib.readAskEvents(a.ask_id));
  });
  all = all.concat(deriveLib.readAskEvents(''));
  return all.filter((e) => e && e.plan_slug === slug && e.task_id)
    .sort((a, b) => String(a.ts).localeCompare(String(b.ts)));
}

function planFallbackAddedTs(pf, linkedAsks) {
  const tss = (linkedAsks || []).map((a) => a.created_ts).filter(Boolean).sort();
  if (tss.length) return tss[0];
  return new Date(pf.mtimeMs || Date.now()).toISOString();
}

// planEffectiveRank — build order (A7 + round 8): a linked ask's own
// registry roadmap_rank record (any linked ask carrying one) takes
// precedence, then this plan's own rank-overlay entry, else null (falls to
// the fallback-timestamp tie-break in buildRoadmapPayload's sort).
function planEffectiveRank(pf, linkedAsks, planRankOverlay) {
  for (let i = 0; i < (linkedAsks || []).length; i++) {
    if (typeof linkedAsks[i].roadmap_rank === 'number') return linkedAsks[i].roadmap_rank;
  }
  if (typeof planRankOverlay[pf.slug] === 'number') return planRankOverlay[pf.slug];
  return null;
}

// derivePlanRootNode(pf, linkedAsks, hbCtx) — the plan-file's own ROOT node
// (was task-1's nested `derivePlanNode`; promoted to the tree's root by
// 8A). Manual-done override (A4) moves here too: it used to live at the
// intent level, which no longer exists — a linked ask marked done/merged is
// still a labeled, honest way for the operator to force-complete an item
// the oracle would otherwise render merged-unverified.
function derivePlanRootNode(pf, linkedAsks, hbCtx) {
  const fromRequests = (linkedAsks || []).map((a) => ({ id: a.ask_id, title: a.title }));
  const addedTs = planFallbackAddedTs(pf, linkedAsks);
  const node = {
    id: pf.slug,
    kind: 'plan',
    title: (linkedAsks[0] && linkedAsks[0].title) || pf.slug,
    title_source: (linkedAsks[0] && linkedAsks[0].title_source) || 'auto',
    project: (linkedAsks[0] && linkedAsks[0].project) || '',
    provenance: 'operator', provenance_reason: '',
    rank: null, added_ts: addedTs, added_mid_build: false,
    status: null, progress: null, completed_at: '',
    from_requests: fromRequests,
    roll_up: {}, children: [],
  };

  // A linked ask's manual done/merged is ALWAYS a labeled override (A4),
  // short-circuiting the task-count-based derivation below.
  const doneAsk = (linkedAsks || []).find((a) => a.status === 'done' || a.status === 'merged');
  if (doneAsk) {
    const statusTsMs = doneAsk.status_ts ? Date.parse(doneAsk.status_ts) : null;
    const derived = deriveLib.deriveItemStatus({
      done: true,
      projectKey: node.project,
      mergedAtMs: isNaN(statusTsMs) ? null : statusTsMs,
      overrideComplete: true,
    });
    node.status = statusFromDerived(derived, { since: doneAsk.status_ts });
    node.completed_at = doneAsk.status_ts || '';
    return node;
  }

  const loaded = planParse.loadPlanFile(pf.absPath);
  if (!loaded.ok) {
    const reason = loaded.reason === 'damaged'
      ? 'plan file unreadable (' + (loaded.error || 'read failed') + ')'
      : 'plan file not found (docs/plans/' + pf.slug + '.md)';
    node.status = statusObj('unknown', { reason: reason, since: '' });
    return node;
  }

  const events = eventsForSlug(pf.slug, linkedAsks);
  const startedTs = {}, doneTs = {};
  const sessionsByTask = {};
  let latestActivity = '';
  events.forEach((e) => {
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

  const tasks = loaded.tasks || [];
  node.children = tasks.map((t) => deriveTaskNode(pf.slug, t, startedTs, doneTs, sessionsByTask, fromRequests, hbCtx));
  const total = tasks.length;
  const done = tasks.filter((t) => t.done).length;
  const anyInProgress = node.children.some((c) => c.status.value === 'in-progress');
  if (total > 0) node.progress = { done: done, total: total };
  const latestDone = Object.keys(doneTs).map((k) => doneTs[k]).sort().pop() || '';

  if (total === 0) {
    node.status = anyInProgress || latestActivity
      ? statusObj('in-progress', { since: latestActivity })
      : statusObj('not-started', { since: addedTs });
  } else if (done === total) {
    // All checked: the real per-project completion-oracle decides complete
    // vs merged-unverified (A4); no live deploy-signal collector on a GET
    // path (A6). completed_at prefers a real task_done event; falls back to
    // the plan file's own mtime ONLY when every box is checked but no event
    // ever recorded it (an archived/historical plan with no progress-log
    // trail, or one with no linked ask at all) — an honest, documented
    // proxy for "when this became complete", never applied to an
    // unfinished plan.
    const completedTsSource = latestDone || new Date(pf.mtimeMs || Date.now()).toISOString();
    const mergedAtMs = Date.parse(completedTsSource);
    const derived = deriveLib.deriveItemStatus({
      done: true,
      projectKey: node.project,
      mergedAtMs: isNaN(mergedAtMs) ? null : mergedAtMs,
      deployReadyAtMs: null,
      overrideComplete: false,
    });
    node.status = statusFromDerived(derived, { since: completedTsSource });
    node.completed_at = completedTsSource;
  } else if (anyInProgress || done > 0) {
    node.status = statusObj('in-progress', { since: latestActivity || latestDone });
  } else {
    node.status = statusObj('not-started', { since: addedTs });
  }
  return node;
}

// computeRollUps(node) — bottom-up: one entry PER attention class present
// in the subtree (delta R4 — precedence never selects), each {count,
// exemplar} where exemplar is one item id a badge click can expand to.
// Unchanged by the re-rooting: it only ever reads a child's own
// status.value/reason_class, generically, regardless of kind.
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
  const planAskLinks = buildPlanAskLinks(byAsk);
  const scanRoot = planScanRoot();
  const planFiles = discoverPlanFiles(scanRoot, planAskLinks);
  const planRankOverlay = readPlanRankOverlay();
  // Heartbeats read ONCE per request (derive-lib's own convention) and
  // handed to every item's derivation below; heartbeatsStoreOk distinguishes
  // a genuinely-absent store (benign) from one that exists but could not be
  // read (a real derivation-input failure — C5). Pure fs read, no spawn (A6).
  const hbResult = deriveLib.listRawHeartbeatsResult();
  const hbCtx = { heartbeats: hbResult.heartbeats, heartbeatsStoreOk: hbResult.ok, nowMs: Date.now() };

  const items = planFiles.map((pf) => {
    const linkedAsks = planAskLinks[pf.slug] || [];
    const node = derivePlanRootNode(pf, linkedAsks, hbCtx);
    node.rank = planEffectiveRank(pf, linkedAsks, planRankOverlay);
    computeRollUps(node);
    return node;
  });

  // Build order (A7 + round 8): ranked items by rank, then everything else
  // by the fallback added_ts (earliest-created first) — the pinned DEFAULT.
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

// firstLinkedAskId(slug) — the ONE-writer delegation target for a title/
// rank edit on a plan-rooted item: the first ask (registry-fold order)
// that links this plan slug, or null when no ask links it at all (an
// honest gap, not a crash — the caller answers with a named error).
function firstLinkedAskId(slug) {
  const byAsk = foldRegistryForRoadmap();
  const links = buildPlanAskLinks(byAsk)[slug] || [];
  return links.length ? links[0].ask_id : null;
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
// handle(req, res) -> true when consumed. The ONE server.js mount line:
//   if (roadmapRoutes.handle(req, res)) return;
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
      const itemId = typeof input.id === 'string' ? input.id : '';
      const direction = input.direction === 'up' ? 'up' : (input.direction === 'down' ? 'down' : '');
      if (!itemId || !direction) return sendJson(res, 400, { ok: false, error: 'id and direction (up|down) are required' });
      let payload;
      try { payload = buildRoadmapPayload(); }
      catch (e) { return sendJson(res, 500, { ok: false, error: String(e && e.message || e) }); }
      const ids = payload.items.map((i) => i.id);
      const idx = ids.indexOf(itemId);
      if (idx === -1) return sendJson(res, 404, { ok: false, error: 'roadmap item not found: ' + itemId });
      const swapWith = direction === 'up' ? idx - 1 : idx + 1;
      if (swapWith < 0 || swapWith >= ids.length) {
        return sendJson(res, 200, { ok: true, unchanged: true, order: ids });
      }
      const newOrder = ids.slice();
      newOrder[idx] = ids[swapWith];
      newOrder[swapWith] = itemId;
      // Materialize the FULL order into the plan-rank overlay (instant,
      // works today regardless of ask linkage); additionally best-effort
      // record the moved plan's FIRST linked ask's rank in the registry
      // when one exists (preserving the pre-existing registry-writeback
      // for the common linked case) — a plan with no linked ask simply
      // skips that best-effort delegation (registry_recorded:false), an
      // honest degrade, never a crash.
      const overlay = {};
      newOrder.forEach((id, i) => { overlay[id] = (i + 1) * 10; });
      try { writePlanRankOverlay(overlay); }
      catch (e) { return sendJson(res, 500, { ok: false, error: 'could not save the new order' }); }
      const linkedAskId = firstLinkedAskId(itemId);
      if (!linkedAskId) {
        return sendJson(res, 200, { ok: true, order: newOrder, registry_recorded: false });
      }
      runAskRegistryCli(['set-rank', '--ask-id', linkedAskId, '--rank', String((newOrder.indexOf(itemId) + 1) * 10), '--emitter', 'operator-ui'])
        .then((r) => {
          sendJson(res, 200, { ok: true, order: newOrder, registry_recorded: !!r.ok });
        });
    });
    return true;
  }

  if (urlPath === '/api/roadmap/title' && req.method === 'POST') {
    readBody(req, (input) => {
      if (!input) return sendJson(res, 400, { ok: false, error: 'bad json' });
      const itemId = typeof input.id === 'string' ? input.id : '';
      const title = typeof input.title === 'string' ? input.title.trim() : '';
      if (!itemId || !title) return sendJson(res, 400, { ok: false, error: 'id and a non-empty title are required' });
      // One-writer discipline (A3): the title lives in the registry, keyed
      // by ask id — this endpoint resolves the plan's FIRST linked ask and
      // delegates there. A plan with no linked ask has no store to write a
      // title into yet; the honest answer is a named error, never a
      // silent success and never a second, plan-keyed title store invented
      // here (Chesterton's Fence — no mechanism for that exists).
      const linkedAskId = firstLinkedAskId(itemId);
      if (!linkedAskId) {
        return sendJson(res, 200, { ok: false, error: 'this plan has no linked request to attach a title edit to yet' });
      }
      runAskRegistryCli(['set-title', '--ask-id', linkedAskId, '--title', title, '--title-source', 'operator', '--emitter', 'operator-ui'])
        .then((r) => {
          if (r.ok) return sendJson(res, 200, { ok: true, id: itemId, title: title, title_source: 'operator' });
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
  foldRegistryForRoadmap,
  buildPlanAskLinks,
  discoverPlanFiles,
  isEligiblePlanStatus,
  ROLLUP_CLASSES,
  COMPLETED_AGE_DAYS,
};
