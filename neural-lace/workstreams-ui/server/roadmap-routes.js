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
//   - every `docs/plans/archive/*.md` file, but ONLY with REAL recency
//     EVIDENCE within the SAME completed_age_days window used for the
//     client's own completed-collapse aging (I2 — one tunable) — "do NOT
//     dump the entire archive/ history ... ancient archived plans stay
//     out" (round 8). Evidence = a linked ask's newest created_ts, OR a
//     progress-log task_started/task_done event for the slug, inside the
//     window (see recentSlugsFromAskLinks/recentSlugsFromEvents). File
//     mtime is DELIBERATELY NOT trusted for this: a git-worktree checkout
//     (this harness's own standard per-builder-session workflow) resets
//     EVERY file's mtime to checkout time regardless of true archival
//     history — a whole-corpus live-data check (2026-07-21) found this
//     made a naive mtime-based gate a total no-op (all 227 archived files
//     read as "0.5 days old"), producing ~154 stale roots. A plan with
//     zero evidence either way is excluded — the safer default given the
//     goal (bounded noise), not a guess dressed as a real timestamp.
//   - every plan a REGISTERED ask still links to (`plan_linked`), resolved
//     against THAT ask's own repo (preserving the pre-existing cross-repo
//     plan-linking behavior), subject to the same status/eligibility
//     filters (an archived linked plan needs the same recency evidence
//     above) — EXCEPT a linked plan that cannot be read at all (absent/
//     damaged): that surfaces as an `unknown` root ONLY when its OWN
//     newest linking ask is recent (ghost-bounding, 2026-07-21) — an
//     ancient ghost is excluded and counted in `stale_links_omitted`
//     instead of becoming a permanent dead root (never a silent drop —
//     C5's honesty requirement is met by the named aggregate, not by
//     resurrecting every plan_linked record the registry has ever
//     accumulated).
//
// ============================================================
// PAYLOAD CONTRACT (pinned for the T1 status-derivation seam; extended by
// the round-9 fix round — docs/reviews/2026-07-17-cockpit-ux-design-
// input.md "Round 9" — see the R9-* markers scattered through this file for
// each fix's own rationale)
// ============================================================
// GET /api/roadmap -> {
//   ok, generated_at, completed_age_days, stale_links_omitted,
//   items: [RoadmapItem],           // top-level PLANS, in BUILD ORDER
//   unbound_sessions: UnboundSessionsNode | null,  // R9-7b — see below
// }
// RoadmapItem = {
//   id,                             // plan: <slug>; task: <slug>/<task_id>
//   kind: 'plan'|'task',
//   title, title_source: 'operator'|'auto',
//   project, provenance: 'operator'|'machine', provenance_reason: '',
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
// UnboundSessionsNode (R9-7b, OPTIONAL — null when no such session exists,
// honest absence, never a fake/empty node) = {
//   id: '(unattributed)', kind: 'unbound-sessions', title,
//   status: {value:'in-progress', label, reason:'', since:''},
//   live_sessions: [{id, kind:'agent', title, status:{value,label,since}}],
// }
//
// R9-1 (title): the plan file's own H1 (`# Plan: <title>` / `# Plan —
// <title>`, HTML-comment-prefixed scaffolds tolerated) outranks a fallback
// ask-distilled title and the raw slug; an OPERATOR title edit
// (title_source:'operator', A3) still always outranks everything, the H1
// included — title_source precedence is UNCHANGED by this fix. Fallback is
// the slug when no plan carries a `# Plan: ...` H1 at all.
// R9-4 (provenance): a plan's `provenance` is no longer hardcoded
// 'operator' — see planProvenanceClass() below for the full precedence
// (explicit plan-header field > linked-ask presence > slug heuristic).
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

// The roll-up attention classes, in the pinned precedence order
// (adjudication (b) + delta R4: precedence governs display ORDER only —
// one badge per class present, a higher class never masks a lower one).
//
// DERIVED from derive-lib's ATTENTION_PRECEDENCE (2026-07-30), never
// re-typed. This used to be a hand-maintained duplicate of that list, and
// the duplication was actively harmful rather than merely redundant:
// absorbOneChildRollUp (below) falls back to 'blocked-on' for any
// reason_class it does not recognise, so the moment derive-lib gained a
// new reason the copy here did not know about, every affected task
// silently rolled up as "stalled — blocked on a predecessor" — a
// fabricated dependency claim. Caught by S20e-reason when 'idle-dispatch'
// was added. One source of truth means a new reason can never again be
// silently re-attributed to an unrelated class.
const ROLLUP_CLASSES = deriveLib.ATTENTION_PRECEDENCE.slice();

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

// ----------------------------------------------------------------------
// ROADMAP-CORRUPT-PLAN-CONFIDENT-BUCKET-01 / ROADMAP-SUPERSEDED-RENDERS-
// PENDING-01 (2026-07-29 round 14) shared vocabulary — the harness's own
// terminal-status enum (ADR 052 + plan-lifecycle.sh's extract_status:
// "ACTIVE / COMPLETED / DEFERRED / ABANDONED / SUPERSEDED / etc.") is the
// only set of Status: tokens this derivation trusts enough to run the
// normal task-count ladder on unconditionally. Anything else surviving
// past isEligiblePlanStatus (a real Status: line, just not one of these —
// e.g. binary corruption landing "Status: WHAT" in place of a real token)
// is NOT a confident bucket (C5) — see scanPlanDir's read-failure/unknown-
// status handling below.
// ----------------------------------------------------------------------
const KNOWN_PLAN_STATUS_TOKENS = { ACTIVE: true, COMPLETED: true, DEFERRED: true, ABANDONED: true, SUPERSEDED: true };
function planStatusToken(statusText) {
  const m = /^([A-Za-z][A-Za-z0-9_-]*)/.exec(String(statusText || '').trim());
  return m ? m[1].toUpperCase() : '';
}
// PLAN_BODY_CORRUPTION_RE — control/binary bytes (outside the common
// whitespace \t\n\r already handled by line-splitting) anywhere in a
// scanned plan's body are a strong corruption signal: a genuine markdown
// plan is prose + task lines, never raw binary/control bytes. Used ONLY
// as the second half of the "zero tasks AND unparseable structure" test
// in scanPlanDir — never applied when tasks parsed successfully (a normal
// plan's continuation-line text can legitimately contain unusual but
// PRINTABLE punctuation, which this never flags).
const PLAN_BODY_CORRUPTION_RE = /[\x00-\x08\x0E-\x1F\x7F]/;

// scanPlanDir(dir, opts) -> [{slug, absPath, archived, mtimeMs}] for every
// eligible top-level *.md file directly inside `dir` (non-recursive — a
// subdirectory like fragments/ or archive/ itself is never descended into
// by this call; archive/ is scanned via ITS OWN separate call).
//
// AGING GATE (opts.cutoffMs, archive/ only): file MTIME IS NOT a trustworthy
// recency signal here — a git-worktree checkout (this harness's own
// standard per-builder-session workflow, `~/.claude/doctrine/orchestrator-
// pattern.md`) resets EVERY file's mtime to checkout time regardless of
// when its content was actually authored/archived. A whole-corpus live-data
// check (2026-07-21) found this made a naive "mtime within window" gate a
// complete no-op in a fresh worktree: all 227 archived files read as "0.5
// days old" (the worktree's own checkout time), producing ~154 stale roots
// on a page meant to show "what I'm working on right now" — and an
// mtime-OR-evidence gate does not fix this either, since a falsely-fresh
// mtime ALREADY satisfies the gate on its own, so adding more ways to ALSO
// pass changes nothing. The actual fix: an archived plan is included ONLY
// on POSITIVE, worktree-independent recency EVIDENCE — `opts.recentSlugs
// [slug]` true (an ask-link or progress-log event genuinely timestamped
// inside the window; see recentSlugsFromAskLinks/recentSlugsFromEvents
// below). The one real caller (discoverPlanFiles) ALWAYS supplies
// recentSlugs when it supplies cutoffMs, so evidence is unconditionally
// required whenever aging is being gated at all — no mtime fallback path.
function scanPlanDir(dir, opts) {
  const options = opts || {};
  const out = [];
  let ents;
  try { ents = fs.readdirSync(dir, { withFileTypes: true }); } catch (_) { return out; }
  ents.forEach((e) => {
    if (!e.isFile() || !/\.md$/i.test(e.name)) return;
    const abs = path.join(dir, e.name);
    let stat;
    try { stat = fs.statSync(abs); } catch (_) { return; } // vanished mid-scan race — genuinely gone, not this file's fault
    const slug = e.name.replace(/\.md$/i, '');
    if (typeof options.cutoffMs === 'number' && !(options.recentSlugs && options.recentSlugs[slug])) {
      return; // aging is gated here and this slug has no recency evidence
    }
    let text;
    try {
      text = fs.readFileSync(abs, 'utf8');
    } catch (err) {
      // ROADMAP-CORRUPT-PLAN-CONFIDENT-BUCKET-01 (c): the file EXISTS
      // (readdirSync/statSync above both succeeded) but could not be
      // read — a genuine permission/race failure, never silently skipped
      // the way an ineligible-status file legitimately is below. Matches
      // the registry-linked path's own `damaged` handling (derivePlanRootNode
      // via planParse.loadPlanFile) — surfaced as an unknown root instead
      // of vanishing from the tree.
      out.push({ slug: slug, absPath: abs, archived: !!options.archived, mtimeMs: stat.mtimeMs,
        scanIssue: 'plan file unreadable (' + (err && err.code ? err.code : String(err)) + ')' });
      return;
    }
    const statusText = planParse.parsePlanStatus(text);
    if (!isEligiblePlanStatus(statusText)) {
      // ROADMAP-STATUSLESS-CORRUPT-VANISH-01 (advocate re-run S7 residual,
      // 2026-07-30): a file with NO Status: header is normally not an
      // independent plan — evidence stubs, fragments, reference docs — and
      // stays excluded; flagging every header-less .md would flood the tree
      // (Round 14's correct rationale). But ABSENT header + the
      // binary-corruption signature in the body is the one combination whose
      // likeliest story is "a plan whose header was destroyed", and C5
      // forbids exactly this rendering: vanishing. Recognized-but-ineligible
      // statuses (REFERENCE/NORMATIVE) keep their unconditional exclusion —
      // their header survived, so their author's intent is legible.
      if (!statusText && PLAN_BODY_CORRUPTION_RE.test(text)) {
        out.push({ slug: slug, absPath: abs, archived: !!options.archived, mtimeMs: stat.mtimeMs,
          scanIssue: 'plan parse failed (no Status header + corrupt content — header destroyed?)' });
      }
      return;
    }

    // ROADMAP-CORRUPT-PLAN-CONFIDENT-BUCKET-01 (a): the Status: header
    // survives but its value is outside the known enum (see
    // KNOWN_PLAN_STATUS_TOKENS above) — e.g. binary corruption landed
    // "Status: WHAT" where a real token belongs. The OLD code let this
    // through as an eligible plan and zero parseable tasks then defaulted
    // it to a confident "not-started" (live repro: fx-corrupt2). Never a
    // confident bucket for a status this derivation doesn't recognize.
    if (!KNOWN_PLAN_STATUS_TOKENS[planStatusToken(statusText)]) {
      out.push({ slug: slug, absPath: abs, archived: !!options.archived, mtimeMs: stat.mtimeMs,
        scanIssue: 'plan parse failed (unrecognized Status: "' + statusText.trim() + '")' });
      return;
    }

    // A KNOWN status token survives, but the body is BOTH taskless AND
    // shows the binary/control-byte corruption signature — never
    // legitimate markdown prose. A genuinely fresh plan stub (zero tasks,
    // ordinary prose, no `## Tasks` written yet) is NOT flagged here —
    // only the corruption signature, so this never guesses on a plan that
    // is merely new.
    if (planParse.parseTasks(text).length === 0 && PLAN_BODY_CORRUPTION_RE.test(text)) {
      out.push({ slug: slug, absPath: abs, archived: !!options.archived, mtimeMs: stat.mtimeMs,
        scanIssue: 'plan parse failed (unparseable body — zero tasks, corrupt content)' });
      return;
    }

    out.push({ slug: slug, absPath: abs, archived: !!options.archived, mtimeMs: stat.mtimeMs });
  });
  return out;
}

// recentSlugsFromAskLinks(planAskLinks, cutoffMs) -> {slug: true, ...} for
// every slug whose NEWEST linking ask is inside the aging window —
// registry-timestamp-based, so it holds regardless of file mtime/worktree
// checkout state.
function recentSlugsFromAskLinks(planAskLinks, cutoffMs) {
  const set = {};
  Object.keys(planAskLinks).forEach((slug) => {
    const newest = newestLinkTs(planAskLinks[slug]);
    const ms = newest ? Date.parse(newest) : NaN;
    if (!isNaN(ms) && ms >= cutoffMs) set[slug] = true;
  });
  return set;
}

// recentSlugsFromEvents(cutoffMs) -> {slug: true, ...} for every plan slug
// with a task_started/task_done event inside the window, sourced from the
// shared "unlinked" progress-log lane (progress-log-lib.sh's own
// documented orphan-lane fallback for events with no ask_id) — the SAME
// data source an unlinked plan's own status derivation already reads
// (eventsForSlug), so this is a real recency signal for genuinely-active
// archived/historical plans with no ask attached, not a new mechanism.
function recentSlugsFromEvents(cutoffMs) {
  const set = {};
  deriveLib.readAskEvents('').forEach((e) => {
    if (!e || !e.plan_slug || !e.ts) return;
    const ms = Date.parse(e.ts);
    if (!isNaN(ms) && ms >= cutoffMs) set[e.plan_slug] = true;
  });
  return set;
}

// newestLinkTs(links) — the MOST RECENT created_ts among every ask that
// links a slug (distinct from planFallbackAddedTs's EARLIEST, which is the
// right signal for build-order; recency-gating below needs "has ANYONE
// referenced this slug lately", so the newest link is the right signal —
// one old ask plus one fresh one still counts as "recent").
function newestLinkTs(links) {
  const tss = (links || []).map((a) => a.created_ts).filter(Boolean).sort();
  return tss.length ? tss[tss.length - 1] : '';
}

// discoverPlanFiles(scanRoot, planAskLinks) -> { files: [{slug, absPath,
// archived, mtimeMs}], ghostCount }
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
//
// GHOST BOUNDING (found via the SAME real-data live check, 2026-07-21): an
// ask-linked slug whose file cannot be resolved/read at all (moved,
// archived-and-pruned, renamed, or from years of registry history) used to
// surface UNCONDITIONALLY as an `unknown` root — every plan_linked record
// the registry has EVER accumulated, forever. Against the real
// ~/.claude/state/ask-registry.jsonl this produced ~154 stale ghost roots
// out of 164 total (only ~10 are genuine current plans). C5's "never
// silently drop a derivation failure" is right for a plan that goes dark
// WHILE IT IS STILL CURRENT WORK; it is wrong applied to years of history.
// The fix bounds a ghost by RECENCY, reusing the SAME completed_age_days
// window (one tunable, same knob as archive aging and I2 collapse): a
// ghost whose NEWEST linking ask is within the window still renders as an
// honest `unknown` root (the real C5 signal — "this active-looking work
// went dark"); an ancient ghost is EXCLUDED from the roots entirely but
// COUNTED (never a silent drop — the caller surfaces one honest aggregate
// line, never 150+ individual dead roots). The originating ask itself
// stays fully visible in the Requests tab regardless (unchanged).
// configuredRepoRoots() -> [{key, root}] — R9-8: EXPLICIT machine-local
// repo config only (config/projects.json, the SAME two-layer convention
// config/projects.js already established for the Docs browser: the
// tracked config/projects.example.json is a generic placeholder; the real,
// gitignored config/projects.json carries real absolute paths).
//
// Deliberately does NOT call config/projects.js's own loadProjects() here:
// that function's auto-discovery ALSO pulls in every sibling repo under
// ~/claude-projects with a docs/ dir, which would silently expand the
// Roadmap's repo scan far beyond "configured repos" (R9-8's own wording)
// the instant ANY sibling repo happens to exist on the machine — R9-8's
// own binding rule is "keep the single-repo behavior as the zero-config
// default", so this reads the raw JSON directly and stays scoped to repos
// the operator actually configured. A malformed/absent config file is an
// honest zero-length list (never a crash, never a silent guess).
// R17 (operator 2026-07-30, decision A — multi-project grouping): each
// entry supports TWO forms — the pre-existing flat string (`"Circuit":
// "/abs/path"`, no group — those plans land in the honest '(ungrouped)'
// display bucket, see projectGroupFor below) AND a new object form
// (`"Circuit": { "root": "...", "group": "Pocket Technician" }`) that
// additionally declares which top-level DISPLAY GROUP the repo's plans
// belong to. `group` is deliberately read straight from the config file,
// never defaulted/guessed here — the operator's own binding rule for this
// round ("default group... for Circuit is NOT hardcoded").
function configuredRepoRoots() {
  const cfgPath = process.env.ROADMAP_PROJECTS_CONFIG ||
    path.join(__dirname, '..', 'config', 'projects.json');
  let raw;
  try { raw = JSON.parse(fs.readFileSync(cfgPath, 'utf8')); } catch (_) { return []; }
  const out = [];
  Object.keys(raw || {}).forEach((key) => {
    if (key === '_comment') return;
    const val = raw[key];
    if (typeof val === 'string' && val) { out.push({ key: key, root: val, group: '' }); return; }
    if (val && typeof val === 'object' && typeof val.root === 'string' && val.root) {
      out.push({ key: key, root: val.root, group: (typeof val.group === 'string' ? val.group : '') });
    }
  });
  return out;
}

// projectGroupFor(projectKey) -> the top-level DISPLAY GROUP a plan's
// project belongs to. The self repo's group is intrinsic ('Neural Lace' —
// this app's own home repo; it has no config/projects.json entry to read
// a group from, since that file is for OTHER repos). "Self" is identified
// by comparing projectKey against path.basename(planScanRoot()) — the
// SAME derivation planProjectFromPath uses for the self repo's own plans
// (discoverPlanFiles's `{key:'self', root:scanRoot}` entry) — never a
// hardcoded literal like 'neural-lace', which would silently break under
// ROADMAP_PLAN_SCAN_ROOT overrides (this file's own test suite included).
// Every OTHER project key's group comes from the SAME configuredRepoRoots()
// the repo-scan already reads (object-form entries only); a flat-string
// entry (no group declared) or an entirely unrecognized project key both
// fall to the honest '(ungrouped)' catch-all — never a silently-guessed
// default.
const SELF_PROJECT_GROUP = 'Neural Lace';
const UNGROUPED_PROJECT_GROUP = '(ungrouped)';
function projectGroupFor(projectKey) {
  if (projectKey && projectKey === path.basename(planScanRoot())) return SELF_PROJECT_GROUP;
  // Matched by the REPO ROOT's own basename, not the config KEY: a plan's
  // `project` value is planProjectFromPath's path-derived repo dirname
  // (same as the `{key:'self', root:...}` convention discoverPlanFiles
  // uses), which the operator's chosen config KEY need not equal (a
  // config key is just a human label picked for the JSON file; the real
  // Circuit case happens to have key===basename==="Circuit", but that is
  // a coincidence, not a guarantee this lookup may rely on).
  const configured = configuredRepoRoots();
  for (let i = 0; i < configured.length; i++) {
    if (path.basename(configured[i].root) === projectKey) return configured[i].group || UNGROUPED_PROJECT_GROUP;
  }
  return UNGROUPED_PROJECT_GROUP;
}

function discoverPlanFiles(scanRoot, planAskLinks) {
  const seenSlugs = {};
  const out = [];
  const cutoffMs = Date.now() - COMPLETED_AGE_DAYS * 86400000;
  let ghostCount = 0;
  // Worktree-independent recency evidence (see scanPlanDir's header note) —
  // computed ONCE per request, threaded into the archive/ scan's aging gate
  // alongside (never instead of) mtime.
  const recentSlugs = Object.assign({}, recentSlugsFromAskLinks(planAskLinks, cutoffMs), recentSlugsFromEvents(cutoffMs));

  // R9-8: scan THIS repo first (self — preserves the exact prior
  // single-repo behavior/order when zero repos are configured), then every
  // EXPLICITLY-configured repo's own docs/plans + docs/plans/archive, same
  // aging/ghost rules, deduped by slug (first-seen wins — self takes
  // precedence on a same-slug collision across repos). A configured repo
  // with no docs/plans/ at all renders NOTHING for it (scanPlanDir already
  // degrades an unreadable directory to an empty array — honest absence,
  // never synthesized).
  const repoRoots = [{ key: 'self', root: scanRoot }].concat(configuredRepoRoots());
  repoRoots.forEach((r) => {
    scanPlanDir(path.join(r.root, 'docs', 'plans'), { archived: false }).forEach((pf) => {
      if (seenSlugs[pf.slug]) return;
      seenSlugs[pf.slug] = true; out.push(pf);
    });
    scanPlanDir(path.join(r.root, 'docs', 'plans', 'archive'), { archived: true, cutoffMs: cutoffMs, recentSlugs: recentSlugs }).forEach((pf) => {
      if (seenSlugs[pf.slug]) return;
      seenSlugs[pf.slug] = true; out.push(pf);
    });
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
    // so the read below honestly fails ENOENT.
    const abs = planParse.resolvePlanAbsPath(repo, slug) || path.join(repo, 'docs', 'plans', slug + '.md');
    let stat, text;
    try { stat = fs.statSync(abs); text = fs.readFileSync(abs, 'utf8'); }
    catch (_) {
      // The linked plan file genuinely can't be read (missing/moved/
      // permission error). RECENT (newest linking ask inside the aging
      // window, or an undated link — no evidence either way defaults to
      // the safer, less-noisy "ancient" bucket) -> still surface as an
      // `unknown` root (C5: current work going dark must never look
      // identical to "never linked"). ANCIENT -> excluded from roots,
      // counted in ghostCount (never rendered, never silently dropped).
      const newest = newestLinkTs(links);
      const newestMs = newest ? Date.parse(newest) : NaN;
      const isRecent = !isNaN(newestMs) && newestMs >= cutoffMs;
      if (!isRecent) { ghostCount++; return; }
      seenSlugs[slug] = true;
      out.push({ slug: slug, absPath: abs, archived: /[\\/]archive[\\/]/.test(abs), mtimeMs: 0 });
      return;
    }
    const archived = /[\\/]archive[\\/]/.test(abs);
    // Same evidence-gated aging rule as scanPlanDir (mtime is not
    // trustworthy — see that function's header note): a readable-but-
    // archived linked plan needs real recency evidence, not just a fresh
    // (possibly checkout-reset) mtime. `newest` (this slug's OWN newest
    // linking ask, already computed above) already covers the ask-link
    // half of recentSlugs; recentSlugsFromEvents covers the progress-log
    // half — checking the shared recentSlugs set gets both for free.
    if (archived && !recentSlugs[slug]) return; // no recency evidence -> ancient archived linked plan stays out
    if (!isEligiblePlanStatus(planParse.parsePlanStatus(text))) return;
    seenSlugs[slug] = true;
    out.push({ slug: slug, absPath: abs, archived: archived, mtimeMs: stat.mtimeMs });
  });
  return { files: out, ghostCount: ghostCount };
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

// STALLED_REASON_PHRASE — human text for reason codes whose bare machine
// name would MISLEAD in the badge. Only codes listed here are rewritten;
// every other code keeps its existing verbatim rendering (the label is
// 'stalled — ' + code), so this map adds meaning without disturbing any
// pre-existing label string. 'idle-dispatch' needs it precisely because the
// operator's complaint was being pointed at the wrong investigation: the
// badge must say the session is ALIVE and the task merely went quiet, not
// leave a terse code that reads like a synonym for 'crashed'.
const STALLED_REASON_PHRASE = {
  'idle-dispatch': 'no recent dispatch (the session that touched it is still alive)',
};

function statusObj(value, opts) {
  const o = opts || {};
  let label;
  // ROADMAP-SUPERSEDED-RENDERS-PENDING-01: an AUTHORED terminal label
  // (superseded/abandoned) always wins the display text — see the
  // derivePlanRootNode call site for who sets this and why value stays
  // 'complete' underneath (Shipped-group membership, no new enum value).
  if (o.terminal_label) label = o.terminal_label;
  else if (value === 'unknown') label = 'status unknown — ' + (o.reason || 'derivation failed');
  else if (value === 'merged-unverified') label = 'merged — deploy unverified';
  else if (value === 'stalled') label = 'stalled — ' + (STALLED_REASON_PHRASE[o.reason] || o.reason || 'reason unavailable');
  else if (value === 'complete') label = 'complete' + (o.override ? ' (operator override)' : '');
  else if (value === 'in-progress') label = 'in progress';
  else label = 'not started';
  return { value: value, reason: o.reason || '', reason_class: o.reason_class || '', label: label, since: o.since || '', terminal_label: o.terminal_label || '' };
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

// deriveLiveAgentLeaves(taskId, sessionIds, heartbeats, nowMs,
// startedIdleExpired) -> [AgentLeaf]
// Round 7B-i: currently-running background agents/sessions render as live
// sub-task leaves under the task they serve. A session with NO matching
// heartbeat record renders 'unknown' (named-absence, C5) — never guessed.
//
// `startedIdleExpired` (false-eternal-running fix, 2026-07-30) — the SAME
// flag deriveLib.deriveItemStatus already computed for this task (see its
// own header): the attached session's heartbeat can be genuinely live
// (that session — almost always the DISPATCHING orchestrator, not a
// per-task worker — really is alive) while STILL being worthless evidence
// that this specific task has any current activity, once its own
// task_started is older than the idle window. Without this, a session leaf
// would render 'running' by heartbeat alone even when the task-level
// status (deriveTaskNode, above) has already downgraded to 'stalled' for
// the identical reason — an inconsistency between the task's own badge and
// its child leaf that this parameter closes.
function deriveLiveAgentLeaves(taskId, sessionIds, heartbeats, nowMs, startedIdleExpired, taskStatusValue) {
  const th = deriveLib.activityThresholdsMs();
  const ids = (sessionIds || []).filter(Boolean);
  // A leaf may claim 'running' ONLY when the task's own derived status is
  // 'in-progress' (2026-07-30). Found by S20g/S20h: a task whose own
  // task_started evidence was unreadable derived 'unknown', yet its leaves
  // still rendered 'running' off the session heartbeat alone — and the
  // owning plan then rolled up a green "1 running" badge for a task the
  // server had just admitted it could not classify. The leaf, the task
  // badge and the plan roll-up must never contradict each other; the task
  // status is the authority, and a leaf can only ever narrow it.
  // `undefined` keeps the pre-existing behaviour for any caller that has
  // not been updated (it is passed explicitly by deriveTaskNode).
  const taskProvenRunning = taskStatusValue === undefined || taskStatusValue === 'in-progress';
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
    // The task's own status could not be established at all — say so on the
    // leaf rather than upgrading a live heartbeat into a running claim the
    // task badge itself does not make.
    if (!taskProvenRunning && taskStatusValue === 'unknown') {
      return {
        id: taskId + '/agent/' + sid,
        kind: 'agent',
        title: 'session ' + sid + (hb.branch ? ' (' + hb.branch + ')' : ''),
        status: {
          value: 'unknown',
          label: 'status unknown — this session is alive, but this task\'s own start evidence could not be read',
          reason: '', since: hb.last_activity_ts || '',
        },
      };
    }
    const value = (ageCls === 'crashed' || startedIdleExpired || !taskProvenRunning) ? 'stalled' : 'running';
    const label = value === 'running'
      ? 'running'
      : (ageCls !== 'crashed'
        ? 'stalled — this task has not been (re-)dispatched in a while, even though the session that touched it is still alive'
        : 'stalled — no recent heartbeat');
    return {
      id: taskId + '/agent/' + sid,
      kind: 'agent',
      title: 'session ' + sid + (hb.branch ? ' (' + hb.branch + ')' : ''),
      status: {
        value: value,
        label: label,
        reason: '', since: hb.last_activity_ts || '',
      },
    };
  });
}

// deriveUnboundSessionsNode(hbCtx) -> UnboundSessionsNode | null — R9-7b.
//
// DIAGNOSIS (2026-07-23, against the REAL live state, read-only):
// ~/.claude/state/heartbeats/ carries ~20 real session heartbeats, several
// genuinely fresh (this very build's own session among them). The
// task-BOUND leaf pipeline (deriveLiveAgentLeaves, wired since round-7B-i)
// DOES work — S18/S19 in this file's own selftest prove a bound session
// renders as a live leaf. The operator-visible gap is entirely on the
// OTHER half: ~/.claude/state/progress-logs/_id.jsonl carries 946 real
// task_started/task_done events (incl. several for THIS plan,
// cockpit-roadmap-redesign, task 9) filed under the literal ask_id string
// "<id" — an emitter bug (a shell template placeholder that was never
// substituted before being used as a filename) that is OUT OF SCOPE for
// this file (it lives in the dispatch/emit hook layer, not
// roadmap-routes.js) and is flagged separately (nl-issue), never
// silently patched here. Its practical consequence: every session whose
// dispatch event landed under that broken filename is invisible to
// eventsForSlug's per-ask lookup, so those sessions' heartbeats are
// currently-running but attributed to NOTHING the tree can find — exactly
// the class this node exists to surface, regardless of which specific
// root cause (this bug, a plan with no task-binding at all, or a future
// unrelated cause) puts a session in that state on any given day.
//
// HONEST ABSENCE (R9-7's own binding rule): zero unattributed-but-running
// sessions -> null, never a fake/empty node.
function deriveUnboundSessionsNode(hbCtx) {
  const heartbeats = hbCtx.heartbeats || [];
  const bound = hbCtx.boundSessionIds || {};
  const th = deriveLib.activityThresholdsMs();
  const running = heartbeats.filter((h) => {
    if (!h || !h.session_id || bound[h.session_id]) return false;
    const ageMs = hbCtx.nowMs - Date.parse(h.last_activity_ts);
    const cls = deriveLib.classifyHeartbeatAge(isNaN(ageMs) ? NaN : ageMs, th);
    return cls !== 'crashed'; // throttled/stale are NOT crashed (A6 disjunct) — still "running" for this purpose
  });
  if (!running.length) return null;
  const children = running.map((h) => {
    const ageMs = hbCtx.nowMs - Date.parse(h.last_activity_ts);
    const cls = deriveLib.classifyHeartbeatAge(isNaN(ageMs) ? NaN : ageMs, th);
    const shortId = String(h.session_id).slice(0, 8);
    // 2026-08-01 (harness-reviewer finding 4): was `cls === 'active'`, a
    // comparison that could NEVER match — classifyHeartbeatAge's whole
    // vocabulary is 'live' | 'quiet' | 'crashed' (derive-lib.js), so the
    // freshest possible session was labelled "running (live)" instead of
    // plain "running". A dead comparator on the one surface that says
    // "running" out loud; the correct token is 'live'.
    const label = cls === 'live' ? 'running' : ('running (' + cls + ')');
    return {
      id: 'unattributed/' + h.session_id,
      kind: 'agent',
      title: 'session ' + shortId + (h.branch ? ' (' + h.branch + ')' : ''),
      // RUNNING-VALUE SPLIT-BRAIN FIX (2026-08-01, operator: "I do not see
      // any items in the cockpit that state that they are actively
      // running"). These members were stamped value:'in-progress' while
      // their own LABEL said "running" — the one node in the whole tree
      // that is a pure live-heartbeat truth claim was the one node whose
      // machine-readable value denied it. Consequences the operator saw:
      // the client's AGENT_STATUS_GLYPH has no 'in-progress' key, so every
      // genuinely-live session rendered with the UNKNOWN glyph ('○'), and
      // .rm-agent-running's green never applied. The value now matches the
      // label. This is NOT a widening of the running claim: the filter
      // above (non-crashed heartbeat) is unchanged — only its name is.
      status: { value: 'running', label: label, reason: '', since: h.last_activity_ts || '' },
    };
  });
  return {
    id: '(unattributed)',
    kind: 'unbound-sessions',
    title: 'live sessions not yet attributed to a task (' + running.length + ')',
    status: {
      value: 'running',
      label: running.length + ' running, unattributed to a task',
      reason: '', since: '',
    },
    live_sessions: children,
  };
}

// ----------------------------------------------------------------------
// deriveUnbindableDispatchLeaves(slug, tasks, startedTs, sessionsByTask,
// hbCtx) -> [agent leaf, ...]  (2026-08-01)
//
// THE GAP THIS CLOSES. A dispatch's `NL-ATTRIBUTION: plan=<slug> task=<id>`
// header makes workstreams-emit.sh write a real `task_started` event. That
// event names a plan_slug AND a task_id. The plan side always resolves; the
// task side often does not, because `task=` is written by hand and the
// roadmap joins on the plan file's OWN leading id token (plan-parse.js
// TASK_ID_TOKEN_RE — `T6`, `9`, `12.3`; a token WITHOUT digits can never be
// one). Observed 2026-08-01: `task=cockpit-running-representation` against a
// plan whose real ids are T1..T14.
//
// Before this function, such an event was silently dropped:
// sessionsByTask[<slug-that-is-not-a-task-id>] matched no task node, and the
// session was ALSO absent from the unattributed node (that node lists only
// sessions no task claimed — and nothing claimed this one either, because
// the claim failed). A genuinely running, genuinely attributed agent was
// invisible in BOTH places. That is precisely the failure R9-7 forbids:
// "running work is NEVER invisible."
//
// WHAT IT DOES NOT DO. It does not guess which task was meant, and it does
// not repair the join — an unresolvable id stays unresolved and is printed
// verbatim on the leaf so the operator can see what was actually sent. The
// dispatch is surfaced at the level it COULD be attributed to (the plan),
// never promoted to a task row it was never bound to.
//
// GATES ARE THE TASK-LEVEL ONES, UNCHANGED. Leaves go through
// deriveLiveAgentLeaves, so a stale heartbeat still renders 'stalled' and an
// absent one still renders 'unknown'. The task-started idle window
// (th.taskStartedIdleMs) is applied to the dispatch's OWN timestamp, exactly
// as deriveItemStatus applies it to a task's — an attributed dispatch that
// went quiet an hour ago is NOT running, here or anywhere else.
// ----------------------------------------------------------------------
function deriveUnbindableDispatchLeaves(slug, tasks, startedTs, sessionsByTask, hbCtx) {
  const realIds = {};
  (tasks || []).forEach((t) => { if (t && t.id) realIds[t.id] = true; });
  const th = deriveLib.activityThresholdsMs();
  const out = [];
  Object.keys(sessionsByTask || {}).forEach((taskId) => {
    if (realIds[taskId]) return; // bound normally — deriveTaskNode owns it
    const sids = sessionsByTask[taskId] || [];
    if (!sids.length) return;
    const startedAtMs = startedTs[taskId] ? Date.parse(startedTs[taskId]) : null;
    // NaN (present-but-unparseable) counts as EXPIRED, not as absent — the
    // same "malformed is not absent" direction deriveItemStatus takes; a
    // timestamp we cannot read must never license a running claim.
    const startedIdleExpired = startedAtMs === null || isNaN(startedAtMs) ||
      (hbCtx.nowMs - startedAtMs > th.taskStartedIdleMs);
    const leaves = deriveLiveAgentLeaves(slug + '/(unbindable)', sids, hbCtx.heartbeats,
      hbCtx.nowMs, startedIdleExpired, 'in-progress');
    leaves.forEach((leaf) => {
      // The id the dispatch actually sent, verbatim and quoted — this is the
      // whole diagnostic value of the leaf.
      leaf.title += ' — dispatched for task "' + taskId + '", which is not a task id in this plan';
      out.push(leaf);
    });
    // R9-7b bookkeeping, same rule deriveTaskNode applies: a session
    // rendered SOMEWHERE in the tree is attributed, so the unattributed node
    // must not also claim it. Without this the same agent would appear twice
    // with two different explanations.
    sids.forEach((sid) => { if (hbCtx.boundSessionIds) hbCtx.boundSessionIds[sid] = true; });
  });
  return out;
}

// ----------------------------------------------------------------------
// stampRunningNow(node) — THE ONE DEFINITION of "someone is working on
// this RIGHT NOW", added 2026-08-01 (operator, repeated: "the purple items
// are not representing what they're supposed to be representing ... it's
// supposed to represent items that are currently being worked on. At the
// moment, I actually do not see any items in the cockpit that state that
// they are actively running").
//
// WHY A SEPARATE FIELD AND NOT A STATUS VALUE. `status.value` is DERIVED
// FROM ARTIFACTS — plan checkboxes, task_started/task_done events, commit
// state. 'in-progress' there means "started and not finished" (it fires on
// done>0 alone; see derivePlanRootNode's `anyInProgress || done > 0`
// branch), which says NOTHING about whether a session is attending it this
// minute. Overloading that value would destroy the distinction the
// operator is asking for. `running_now` is the orthogonal LIVE overlay.
//
// SOURCE OF TRUTH — live signals ONLY, never plan-file text: a leaf
// `live_sessions[].status.value === 'running'`. TWO functions in this file
// produce that value, and their gates DIFFER — name both, never imply one
// (harness-reviewer finding 1, 2026-08-01):
//
//   deriveLiveAgentLeaves (TASK-BOUND leaves) emits 'running' only when ALL
//   of these hold:
//     (1) a real heartbeat file exists for that session id (else 'unknown'),
//     (2) its last_activity_ts is not crashed-stale (else 'stalled'),
//     (3) the task's own task_started is not idle-expired (startedIdleExpired,
//         the 60-minute window),
//     (4) the task's derived status is itself running-capable (taskProvenRunning).
//
//   deriveUnboundSessionsNode (the top-of-tree UNATTRIBUTED node) emits
//   'running' on gate (1)+(2) ALONE — there is no task to apply (3)/(4) to,
//   which is the entire point of that node. Its freshness bar is therefore
//   WEAKER: any heartbeat inside activityWindowMs, i.e. up to ~24h, and
//   members past activeMs carry the word "(quiet)" in their own label. That
//   is a deliberate pre-existing threshold, not a widening introduced here —
//   but it means a green claim on that node is backed by less evidence than
//   a green claim on a task row, and any future tightening belongs THERE,
//   not in this function.
// An ancestor is running_now iff a descendant is — the same C1 roll-up law
// absorbOneChildRollUp already applies to the 'running' badge class, but
// computed here directly off the leaf values so it is independent of
// roll-up merge ORDER (a master's child-plan roll-ups are absorbed later,
// in applyMasterHierarchy).
//
// HONEST ABSENCE (R9-7's binding rule): no live evidence -> `false`, and the
// client renders NOTHING running. A comforting badge is worse than a blank.
// ----------------------------------------------------------------------
function stampRunningNow(node) {
  if (!node) return false;
  const own = (node.live_sessions || []).some((s) => s && s.status && s.status.value === 'running');
  let descendant = false;
  (node.children || []).forEach((c) => { if (stampRunningNow(c)) descendant = true; });
  (node.child_plans || []).forEach((c) => { if (stampRunningNow(c)) descendant = true; });
  node.running_now = own || descendant;
  return node.running_now;
}

// buildWaitingOnYouMap(scanRoot) -> { '<slug>/<task_id>': <needs-you ledger
// id>, ... } — ROADMAP-WAITING-ON-YOU-SIGNAL-01 (2026-07-29 round 14): the
// producer half of deriveStalledReason's `waitingOnYouId` input (task-1-
// owned consumer, unit-proven but never populated in production —
// inbox-routes.js:55-68's own honest-limit note this closes).
//
// Reuses GET /api/inbox's OWN derivation (inbox-routes.buildInboxPayload) —
// never a second ledger parse (a lazy require here, not a module-load-time
// one, since roadmap-routes.js is required BY server.js alongside
// inbox-routes.js — deferring the require avoids any load-order coupling
// between sibling route modules, matching this file's existing
// derive-cache.js lazy-require precedent above).
//
// MATCHING (conservative — "a false badge is worse than a missing one",
// this defect's own binding rule): plan-parse.js's extractPlanTaskReferences
// finds CANDIDATE (slug, taskId) pairs via two explicit shapes only (its own
// header has the full rule — the app's own `#roadmap/<slug>/<task-id>`
// address, or a `docs/plans/<slug>.md` anchor + an explicit "task <id>"
// mention in the SAME text) — no fuzzy title/keyword matching. Every
// candidate is then VERIFIED against the plan's REAL parsed task list
// before being trusted; an unverified candidate is silently dropped, never
// fabricated. Only status:'ok' (a TRUSTED ledger read) is consulted — an
// unavailable/not-yet-derived ledger contributes nothing (never a guess).
//
// A bare plan-slug reference (no specific task id) does NOT mark anything
// here — the six-value enum has no plan-ROOT 'stalled' state (only task
// nodes reach deriveItemStatus's stalled branch; a plan's own not-started/
// in-progress status is derived from child task counts, never from
// deriveItemStatus directly) — an honest, documented limit rather than an
// invented "first stalled task in this plan" heuristic.
function buildWaitingOnYouMap(scanRoot) {
  const map = {};
  let payload;
  try {
    payload = require('./inbox-routes.js').buildInboxPayload();
  } catch (_) {
    return map; // inbox derivation unavailable — honest no-op, never a crash here
  }
  if (!payload || payload.status !== 'ok') return map; // only a TRUSTED read is a signal source
  (payload.answerable || []).forEach((item) => {
    const haystack = String(item.raw_text || '') + ' ' + (Array.isArray(item.links) ? item.links.join(' ') : '');
    planParse.extractPlanTaskReferences(haystack).forEach((ref) => {
      const roadmapId = ref.slug + '/' + ref.taskId;
      if (map[roadmapId]) return; // first (oldest, per buildInboxPayload's own sort) match wins
      const abs = planParse.resolvePlanAbsPath(scanRoot, ref.slug);
      if (!abs) return;
      const loaded = planParse.loadPlanFile(abs);
      if (!loaded.ok) return;
      const isRealTask = (loaded.tasks || []).some((t) => t.id === ref.taskId);
      if (!isRealTask) return; // never a fabricated correlation
      map[roadmapId] = item.id;
    });
  });
  return map;
}

// deriveTaskNode(slug, t, ...) — id scheme is now `<slug>/<task_id>` (the
// ask_id segment is gone: plans, not asks, are the root, so a task's
// address is relative to its plan alone).
function deriveTaskNode(slug, t, startedTs, doneTs, sessionsByTask, fromRequests, hbCtx, batchLabel) {
  let status;
  let completedAt = '';
  let startedIdleExpired = false;
  const taskSessionIds = (sessionsByTask && sessionsByTask[t.id]) || [];
  if (t.done) {
    completedAt = doneTs[t.id] || '';
    status = statusObj('complete', { since: completedAt });
  } else {
    // ROADMAP-WAITING-ON-YOU-SIGNAL-01: this task's own roadmap id
    // ('<slug>/<task_id>') is the key buildWaitingOnYouMap's producer
    // above keys the map by — an EXACT match, never a substring/fuzzy one.
    const waitingOnYouId = (hbCtx.waitingOnYou && hbCtx.waitingOnYou[slug + '/' + t.id]) || null;
    // False-eternal-running fix (2026-07-30): startedAtMs is THIS task's
    // own most-recent task_started event age — see deriveLib.deriveItemStatus's
    // header for why the attached session's heartbeat alone (sessionIds/
    // heartbeats below) can never prove this SPECIFIC task has current
    // activity (that session is the DISPATCHING session, not a per-task
    // worker, and stays alive across many unrelated dispatches).
    // MALFORMED IS NOT ABSENT (fail-open fix, 2026-07-30): this used to
    // collapse an unparseable ts to `null` — indistinguishable from "no
    // task_started at all" — which silently disabled the idle gate and
    // restored the pre-fix green-forever behaviour on exactly the corrupt
    // input we least want to trust. NaN is now passed THROUGH so
    // deriveItemStatus can tell the two apart and render 'unknown' for
    // present-but-unreadable evidence (its own branch documents why),
    // mirroring how the heartbeat side already treats an unparseable
    // last_activity_ts. `null` remains reserved for genuine absence.
    const startedAtMs = startedTs[t.id] ? Date.parse(startedTs[t.id]) : null;
    const derived = deriveLib.deriveItemStatus({
      done: false,
      startedEvent: !!startedTs[t.id],
      startedAtMs: startedAtMs,
      sessionIds: taskSessionIds,
      heartbeats: hbCtx.heartbeats,
      heartbeatsStoreOk: hbCtx.heartbeatsStoreOk,
      nowMs: hbCtx.nowMs,
      stalledSignals: waitingOnYouId ? { waitingOnYouId: waitingOnYouId } : undefined,
    });
    status = statusFromDerived(derived, { since: startedTs[t.id] || '' });
    startedIdleExpired = !!derived.startedIdleExpired;
    // ROADMAP-WAITING-ON-YOU-SIGNAL-01 (S6's "clicking it expands the
    // path; the #inbox/<id> link lands focused + highlighted" leg): feeds
    // the PRE-EXISTING, previously-never-populated `status.unblock
    // {label, hash}` field (documented at this file's own header, line
    // ~96 — "OPTIONAL {label, hash}") that web/roadmap.js's reasonRow
    // already renders as a real navigate-on-click link (line ~866) — no
    // new client-side plumbing needed, the consumer was unit-built and
    // simply never fed. Only set when the signal actually won the
    // stalled-reason precedence (deriveStalledReason ranks waiting-on-you
    // first, so if it was supplied it always wins — this mirrors that
    // fact rather than re-deriving it).
    if (waitingOnYouId && status.value === 'stalled' && status.reason_class === 'waiting-on-you') {
      status.unblock = { label: 'open in Inbox', hash: '#inbox/' + encodeURIComponent(waitingOnYouId) };
    }
  }

  const struct = deriveLib.splitTaskStructure(t.description);
  const distilled = deriveLib.distillTaskTitle(struct.lead);
  const leadPoints = deriveLib.splitIntoSentences(distilled.remainder);
  const subtasks = struct.subtasks.map((s) => ({
    title: s.title,
    body_points: deriveLib.splitIntoSentences(s.body),
  }));
  const liveSessions = (!t.done && taskSessionIds.length)
    ? deriveLiveAgentLeaves(slug + '/' + t.id, taskSessionIds, hbCtx.heartbeats, hbCtx.nowMs, startedIdleExpired, status.value)
    : [];
  // R9-7b bookkeeping: a session id ATTACHED to a not-done task is
  // "attributed" regardless of whether a matching heartbeat file exists —
  // it already renders its own leaf above (running, or an honest "unknown,
  // no heartbeat evidence" leaf, S19). Marking it here is what lets
  // deriveUnboundSessionsNode tell "genuinely unattributed" apart from
  // "attributed to a task, just heartbeat-lookup-failed".
  if (!t.done && taskSessionIds.length && hbCtx.boundSessionIds) {
    taskSessionIds.forEach((sid) => { hbCtx.boundSessionIds[sid] = true; });
  }

  return {
    id: slug + '/' + t.id,
    kind: 'task',
    title: 'task ' + t.id + ': ' + distilled.title,
    title_source: 'auto',
    batch: batchLabel || '', // R11 Critical 1/2: '' when the plan carries no batch structure
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
// planProjectFromPath(absPath) -> the repo directory name that owns the plan.
// A plan's project is a property of the REPO IT LIVES IN, never of an optional
// linked ask. Pre-fix this read `linkedAsks[0].project || ''`, so every plan
// without a linked ask (most of them, post-round-8 re-rooting) got project:''
// and was silently hidden by ANY active project chip — operator-reported
// 2026-07-22: the roadmap rendered "PHASE 1 OF 1" because a persisted
// neural-lace chip filtered out 16 of 17 phases. Path shape:
// <...>/<repo>/docs/plans[/archive]/<slug>.md
function planProjectFromPath(absPath) {
  if (!absPath) return '';
  const m = String(absPath).replace(/\\/g, '/').match(/([^/]+)\/docs\/plans\//);
  return m ? m[1] : '';
}

// ----------------------------------------------------------------------
// R9-1 (title) + R9-4 (provenance) — plan-header extras.
//
// Deliberately kept LOCAL to this file rather than added to plan-parse.js:
// this fix round's scope is roadmap-routes.js + its own selftest only, and
// this codebase's own established convention is small, deliberately
// duplicated per-file glue (see plan-parse.js's own header note) rather
// than widening a shared module's surface for one caller. Both reads below
// share ONE fs.readFileSync — called once per plan, not per field.
// ----------------------------------------------------------------------

// H1_PLAN_TITLE_RE — matches "# Plan: <title>" AND the real corpus's
// "# Plan — <title>" em-dash variant (whole-corpus check, 2026-07-23:
// every currently-ACTIVE top-level plan uses one of these two shapes).
// A leading HTML scaffold comment (`<!-- scaffold-created: ... -->`, the
// real shape start-plan.sh emits) is stripped before scanning, so the H1
// is found even when it is not literally the file's first line.
const H1_PLAN_TITLE_RE = /^#\s*Plan\s*[:—-]\s*(.+?)\s*$/;
// PROVENANCE_HEADER_RE — an OPTIONAL, explicit plan-header field
// (`provenance: machine` / `provenance: operator`) that overrides the slug
// heuristic below in EITHER direction (R9-4's own binding requirement).
const PROVENANCE_HEADER_RE = /^provenance:\s*(machine|operator)\s*$/im;
// R11-A (operator round 11): the master-plan hierarchy made MECHANICAL.
// `parent-plan: <slug>` in a plan's header block declares this plan a CHILD
// of the named master plan. Practice-verified (child plans spawned from
// oversized tasks, e.g. the A2P C2 family); previously prose-only, which is
// why the tree couldn't render the grouping. Optional — absent means
// standalone; NEVER inferred from prose (round-9 disease rule).
const PARENT_PLAN_HEADER_RE = /^parent-plan:\s*([a-z0-9._-]+)\s*$/im;

function planFileHeaderExtras(absPath) {
  let text;
  try { text = fs.readFileSync(absPath, 'utf8'); } catch (_) { return { h1Title: '', provenanceField: '', parentPlan: '' }; }
  const stripped = text.replace(/<!--[\s\S]*?-->/g, '');
  const lines = stripped.split('\n');
  let h1Title = '';
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i].replace(/\r$/, '').trim();
    if (!line) continue;
    const m = H1_PLAN_TITLE_RE.exec(line);
    if (m) h1Title = m[1].trim();
    break; // the first non-blank line (post comment-strip) is the H1 or it
           // isn't — either way, stop scanning here (bounded, honest: no
           // deeper heuristic hunts for a title buried mid-file).
  }
  const pm = PROVENANCE_HEADER_RE.exec(text);
  const pp = PARENT_PLAN_HEADER_RE.exec(text);
  return {
    h1Title: h1Title,
    provenanceField: pm ? pm[1].toLowerCase() : '',
    parentPlan: pp ? pp[1] : '',
  };
}

// R11 Critical 1/2 batch derivation — REPLACES the R11-A single-letter
// `taskBatchLetter` (that shape rendered a bare "A"/"B", which the binding
// ux-review (docs/reviews/2026-07-28-roadmap-hierarchy-ux-review.md)
// rejected: every derived label must quote a string that exists in the
// source artifact — a bare letter quotes nothing).
//
// The ONLY two batch sources, in priority order, NEVER title/description
// text (the PROVEN trap: conversation-quality-phase2's letters are title
// cross-references over plain 0-9 ids — title-derivation would invert its
// real P0->P5 priority order; this function never reads title/description,
// only the task's own `.id` token and plan-parse.js's new `.section`
// field, so that trap cannot reach it structurally):
//   (a) `###` sub-headings inside `## Tasks` — plan-parse.js's `.section`
//       field, VERBATIM, grouped into contiguous runs (never re-sorted).
//   (b) a single-uppercase-letter id PREFIX (`A1`, `B2`) — grouped into
//       contiguous SAME-LETTER runs in file order; label = the mechanical
//       span "Tasks <first>-<last>" (or "Task <id>" for a length-1 run) —
//       the "foundations->engine->..." GLOSS never renders (practice, not
//       data).
// Returns {<taskId>: <batch label>, ...} — '' for a task in neither shape
// (honest absence; the renderer shows it directly, no batch wrapper).
function deriveTaskBatches(tasks) {
  const list = tasks || [];
  const labels = {};
  const hasHeadings = list.some((t) => t.section);
  if (hasHeadings) {
    list.forEach((t) => { labels[t.id] = t.section || ''; });
    return labels;
  }
  const LETTER_PREFIX_RE = /^([A-Z])[0-9]/;
  let runIds = [], runLetter = '';
  function closeRun() {
    if (!runIds.length) return;
    const label = runIds.length > 1
      ? ('Tasks ' + runIds[0] + '–' + runIds[runIds.length - 1])
      : ('Task ' + runIds[0]);
    runIds.forEach((id) => { labels[id] = label; });
    runIds = []; runLetter = '';
  }
  list.forEach((t) => {
    const m = LETTER_PREFIX_RE.exec(String(t.id || ''));
    const letter = m ? m[1] : '';
    if (!letter) { closeRun(); labels[t.id] = ''; return; }
    if (runLetter && runLetter !== letter) closeRun();
    runLetter = letter;
    runIds.push(t.id);
  });
  closeRun();
  return labels;
}

// R9-4 — slug-prefix/word heuristics, scanned against the REAL live plan
// corpus (2026-07-23: docs/plans + docs/plans/archive) for every prefix the
// operator named plus what that scan turned up. PREFIXES (anchored at the
// start of the slug): nl-issue(s)-, nl-finding-, harness-, evidence-bar-.
// WORDS (may appear anywhere, hyphen-bounded so "sweeper"/"watchdogged"
// never false-positive): sweep, watchdog.
const MACHINE_SLUG_PREFIX_RE = /^(nl-issues?-|nl-finding-|harness-|evidence-bar-)/;
const MACHINE_SLUG_WORD_RE = /(^|-)(sweep|watchdog)(-|$)/;
function slugLooksMachineFiled(slug) {
  const s = String(slug || '');
  return MACHINE_SLUG_PREFIX_RE.test(s) || MACHINE_SLUG_WORD_RE.test(s);
}

// planProvenanceClass(slug, headerField, hasLinkedAsk) -> {provenance,
// provenance_reason} — R9-4's binding precedence:
//   1. An explicit `provenance: machine|operator` plan-header field ALWAYS
//      wins, in EITHER direction (the operator's own correction path for
//      whatever the heuristic below gets wrong).
//   2. A plan linked to a real, non-dismissed ask (an operator REQUEST) is
//      never hidden by subject-matter/slug shape — A9's own binding rule
//      ("classifier = PROVENANCE, NOT subject matter — else operator-
//      requested harness work vanishes").
//   3. Otherwise, the slug heuristic decides; absent any signal, the
//      default stays 'operator' (never hide on silence — A9).
function planProvenanceClass(slug, headerField, hasLinkedAsk) {
  if (headerField === 'operator' || headerField === 'machine') {
    return { provenance: headerField, provenance_reason: 'plan header: provenance: ' + headerField };
  }
  if (hasLinkedAsk) {
    return { provenance: 'operator', provenance_reason: 'linked to an operator request' };
  }
  if (slugLooksMachineFiled(slug)) {
    return { provenance: 'machine', provenance_reason: 'slug matches a machine-filed naming pattern' };
  }
  return { provenance: 'operator', provenance_reason: '' };
}

function derivePlanRootNode(pf, linkedAsks, hbCtx) {
  const fromRequests = (linkedAsks || []).map((a) => ({ id: a.ask_id, title: a.title }));
  const addedTs = planFallbackAddedTs(pf, linkedAsks);
  const headerExtras = planFileHeaderExtras(pf.absPath);
  const firstLink = linkedAsks[0];
  // R9-1: operator title (title_source:'operator' on the FIRST linked ask,
  // the same delegation target title edits already write through) always
  // wins; else the plan's own H1 outranks an auto-distilled ask title (an
  // ask summary is a best-effort distillation of a prompt — round 1's own
  // "not a good reference for what my actual ask was" — while the plan's
  // H1 is a deliberately-authored name); else the ask auto-title; else the
  // raw slug (now truly the last resort, not the common case).
  const operatorTitle = (firstLink && firstLink.title_source === 'operator') ? firstLink.title : '';
  const askAutoTitle = (firstLink && firstLink.title_source !== 'operator') ? (firstLink.title || '') : '';
  const provClass = planProvenanceClass(pf.slug, headerExtras.provenanceField, !!(linkedAsks && linkedAsks.length));
  const projectKey = (linkedAsks[0] && linkedAsks[0].project) || planProjectFromPath(pf.absPath);
  const node = {
    id: pf.slug,
    kind: 'plan',
    title: operatorTitle || headerExtras.h1Title || askAutoTitle || pf.slug,
    title_source: operatorTitle ? 'operator' : 'auto',
    project: projectKey,
    // R17 deliverable 4: the top-level DISPLAY GROUP this plan's project
    // belongs to (see projectGroupFor above) — a NEW field, additive to
    // the existing `project` (per-repo) grouping the client already uses;
    // never replaces it.
    project_group: projectGroupFor(projectKey),
    plan_path: pf.absPath, // R9 follow-up (operator 2026-07-24): every phase IS a plan file — link it
    // Round 15 (operator, verified live): the client's ONLY prior rendering
    // of plan_path was a raw `file:///` href — a dead link from an http-
    // served page (no navigation, no network activity, confirmed live at
    // :7733). `plan_doc` reuses the EXISTING /api/doc {project,path}
    // resolver (asks.js's plan-drilldown already does this — same
    // deriveLib.projectDocRefFor helper, "no new link handling", ux-review
    // amendment 6) so roadmap.js can open the SAME in-page docs viewer
    // instead of growing a second one. null when the plan lives outside
    // every configured/discovered project root (config/projects.json
    // absent an entry, or the root not on this machine) — the client falls
    // back to plain text + copy, never a fabricated link.
    plan_doc: deriveLib.projectDocRefFor(pf.absPath),
    parent_plan: headerExtras.parentPlan, // R11-A: '' = standalone; slug = child of that master
    provenance: provClass.provenance, provenance_reason: provClass.provenance_reason,
    rank: null, added_ts: addedTs, added_mid_build: false,
    status: null, progress: null, completed_at: '',
    from_requests: fromRequests,
    // Plan-level live sessions (2026-08-01): populated ONLY by
    // deriveUnbindableDispatchLeaves — an attributed dispatch whose task=
    // id resolves to no task in this plan. Default [] so the field's SHAPE
    // is uniform across every node kind (a client can read live_sessions
    // without a kind check), including the terminal-status early return
    // above, which never reaches the events pass.
    live_sessions: [],
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

  // ROADMAP-CORRUPT-PLAN-CONFIDENT-BUCKET-01: a SCAN-path corruption
  // signal (unreadable file, unrecognized Status: token, or a taskless
  // body with binary/control bytes — see scanPlanDir's own header) renders
  // unknown(reason) here, matching the registry-linked path's own
  // loadPlanFile-failure handling directly below. Never a confident
  // not-started/in-progress bucket for a plan whose derivation input has
  // already failed. Checked AFTER doneAsk (an ask-registry override never
  // depends on the plan FILE being readable at all — same precedent as
  // the loadPlanFile-failure check below).
  if (pf.scanIssue) {
    node.status = statusObj('unknown', { reason: pf.scanIssue, since: '' });
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

  // ROADMAP-SUPERSEDED-RENDERS-PENDING-01: an AUTHORED terminal status
  // (SUPERSEDED/ABANDONED) on an otherwise-readable, otherwise-eligible
  // plan never runs through the task-count-derived not-started/in-
  // progress/complete ladder below — it renders `status.value: 'complete'`
  // (so the EXISTING Shipped grouping, web/roadmap.js's status.value===
  // 'complete' check, picks it up with zero new client-side plumbing —
  // never the pending/live list) with a distinct `terminal_label` so the
  // operator can still tell it apart from real shipped work (live case:
  // cockpit-ui-polish, superseded by THIS plan's own closure contract).
  // COMPLETED is deliberately NOT special-cased here — an all-done
  // COMPLETED plan already derives 'complete' correctly via the normal
  // ladder below.
  const authoredToken = planStatusToken(loaded.status);
  if (authoredToken === 'SUPERSEDED' || authoredToken === 'ABANDONED') {
    node.status = statusObj('complete', { terminal_label: authoredToken === 'SUPERSEDED' ? 'superseded' : 'abandoned' });
    node.completed_at = new Date(pf.mtimeMs || Date.now()).toISOString();
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
  const batchLabels = deriveTaskBatches(tasks); // R11 Critical 1/2
  node.children = tasks.map((t) => deriveTaskNode(pf.slug, t, startedTs, doneTs, sessionsByTask, fromRequests, hbCtx, batchLabels[t.id]));
  node.live_sessions = deriveUnbindableDispatchLeaves(pf.slug, tasks, startedTs, sessionsByTask, hbCtx);
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
function absorbIntoRollUp(agg, cls, count, exemplar) {
  if (!agg[cls]) agg[cls] = { count: 0, exemplar: exemplar };
  agg[cls].count += count;
  if (!agg[cls].exemplar) agg[cls].exemplar = exemplar;
}

// absorbOneChildRollUp(agg, child) — the one rule shared by computeRollUps
// (own-task children) and absorbChildPlanRollUps (R11 master/child-plan
// nesting, below): a stalled/unknown child contributes ONE count under its
// class, PLUS whatever the child already rolled up from its own subtree.
function absorbOneChildRollUp(agg, child) {
  const st = child.status || {};
  if (st.value === 'stalled') {
    // Unrecognised reason -> 'unknown', NOT 'blocked-on' (2026-07-30).
    // The old fallback invented a specific, wrong, actionable claim ("this
    // is blocked on a predecessor") out of what is really an absence of
    // classification, and it fired silently for every reason code this
    // file had not been taught. 'unknown' is the honest bucket for "we
    // could not classify this" and already exists for exactly that.
    const cls = ROLLUP_CLASSES.indexOf(st.reason_class) !== -1 ? st.reason_class : 'unknown';
    absorbIntoRollUp(agg, cls, 1, child.id);
  }
  if (st.value === 'unknown') absorbIntoRollUp(agg, 'unknown', 1, child.id);
  // Round 15 (operator, repeated across rounds): "if I expand a plan I can
  // see the tasks that are in progress, but the plan itself doesn't show
  // there's anything in progress." A child genuinely carrying a live
  // session (the SAME live_sessions signal the leaf task row already
  // renders as "running") rolls up exactly like stalled/unknown do — C1's
  // roll-up law applied to the running state, not just attention states:
  // every collapsed ancestor gets a counted "N running" badge, one click
  // from the active row. Independent of status.value === 'in-progress'
  // (which also fires on mere recent-activity with no session currently
  // attached, or on a done>0-but-idle plan — see derivePlanRootNode's own
  // `anyInProgress || done > 0` branch) — only an ACTUALLY attached live
  // session counts as "running" here, so a merely-partial plan is never
  // mislabeled as actively worked on.
  //
  // FALSE-ETERNAL-RUNNING FIX (2026-07-30, operator-reported: green roadmap
  // chips for tasks nobody was actively working): the ORIGINAL check here
  // was `child.live_sessions.length` alone — merely NON-EMPTY, independent
  // of whether those sessions are alive, stalled, or crashed. live_sessions
  // can (and, on the real deployed roadmap, routinely does) hold entries
  // whose OWN status.value is 'stalled' or 'unknown' (deriveLiveAgentLeaves
  // renders those explicitly, right above) — counting the array's mere
  // presence rolled up "running" for a task whose only evidence was a
  // session that had gone quiet or was never heartbeat-confirmed at all.
  // Require an ACTUALLY-running leaf: at least one live_sessions entry
  // whose own status.value is 'running' (deriveLiveAgentLeaves already
  // folds the task_started idle-expiry into that value — see its header —
  // so this one check also inherits that fix, with no separate age math
  // needed here).
  const hasRunningLeaf = (child.live_sessions || []).some((s) => s && s.status && s.status.value === 'running');
  if (hasRunningLeaf) absorbIntoRollUp(agg, 'running', 1, child.id);
  Object.keys(child.roll_up || {}).forEach((cls) => {
    absorbIntoRollUp(agg, cls, child.roll_up[cls].count, child.roll_up[cls].exemplar);
  });
}

function computeRollUps(node) {
  const agg = {};
  (node.children || []).forEach((child) => {
    computeRollUps(child);
    absorbOneChildRollUp(agg, child);
  });
  node.roll_up = agg;
}

// absorbChildPlanRollUps(node) — R11 Critical 1 generalization: a master's
// roll-up badges must ALSO reflect its resolved CHILD PLANS (node.child_plans,
// applyMasterHierarchy below), not just its own direct tasks — "applies to
// EVERY leaf-derived attention signal ... audited against the law, not just
// stalled." Mutates node.roll_up (already seeded by computeRollUps above,
// from the master's own tasks) rather than replacing it — both sources
// count toward the SAME per-class badge.
function absorbChildPlanRollUps(node) {
  (node.child_plans || []).forEach((child) => { absorbOneChildRollUp(node.roll_up, child); });
}

// ----------------------------------------------------------------------
// R11 Critical 3/4/5 — the master-plan hierarchy: reference lifecycle +
// master aggregation. Ships in the SAME round as the renderer rebuild per
// Critical 3 ("acceptance oracle = master nodes visibly group their REAL
// children on the live tree, never 'renderer supports parent-plan'").
// ----------------------------------------------------------------------

// repoRootFromAbsPath(absPath) -> the repo root a plan file lives under
// (the part of its path before `/docs/plans/...`), used to re-resolve a
// SAME-PROJECT parent-plan reference directly, bypassing discovery filters
// entirely (the pinning case below).
function repoRootFromAbsPath(absPath) {
  if (!absPath) return '';
  const m = String(absPath).replace(/\\/g, '/').match(/^(.*)\/docs\/plans\//);
  return m ? m[1] : '';
}

// pinDanglingActiveMasters(items, ...) — Critical 4(1): "a master with ANY
// non-terminal child is PINNED on the tree regardless of its own
// aging/archive status." A master can be excluded from `items` by the
// normal archive-aging gate (discoverPlanFiles) even though a still-active
// child plan names it as `parent-plan:` — this direct-loads that master
// file (same repo root as the child, SAME-PROJECT ONLY — decide-and-go (b):
// cross-repo parent-plan out of scope until configured) bypassing the aging
// cutoff (never bypassing plan-status eligibility — a REFERENCE/NORMATIVE
// master still does not belong on the tree). A genuinely-absent parent file
// is left alone here — it stays dangling, handled by applyMasterHierarchy.
function pinDanglingActiveMasters(items, planAskLinks, planRankOverlay, hbCtx) {
  const bySlug = {};
  items.forEach((n) => { bySlug[n.id] = n; });
  const attempted = {};
  items.slice().forEach((child) => {
    const parentSlug = child.parent_plan;
    if (!parentSlug || bySlug[parentSlug] || attempted[parentSlug]) return;
    attempted[parentSlug] = true;
    if (child.status && child.status.value === 'complete') return; // pin rule is for a NON-TERMINAL child only
    const childRepoRoot = repoRootFromAbsPath(child.plan_path);
    if (!childRepoRoot) return;
    const abs = planParse.resolvePlanAbsPath(childRepoRoot, parentSlug);
    if (!abs) return; // genuinely absent -> stays dangling
    let text;
    try { text = fs.readFileSync(abs, 'utf8'); } catch (_) { return; }
    if (!isEligiblePlanStatus(planParse.parsePlanStatus(text))) return;
    if (planProjectFromPath(abs) !== child.project) return; // same-project resolution ONLY
    const pf = { slug: parentSlug, absPath: abs, archived: /[\\/]archive[\\/]/.test(abs), mtimeMs: 0 };
    const linkedAsks = planAskLinks[parentSlug] || [];
    const node = derivePlanRootNode(pf, linkedAsks, hbCtx);
    node.rank = planEffectiveRank(pf, linkedAsks, planRankOverlay);
    node.pinned = true;
    node.pinned_reason = "kept on the tree: a non-terminal child plan ('" + child.id + "') still references it";
    computeRollUps(node);
    bySlug[parentSlug] = node;
    items.push(node);
  });
  return items;
}

// applyMasterHierarchy(items) -> {topLevel} — Critical 4(2)(3)(4) + Critical
// 5, in one pass over the already-built, already-sorted flat item list:
//   (2) dangling parent -> child stays standalone, `dangling_parent: true`
//       (client renders the "parent '<slug>' not found" badge from the
//       already-present `parent_plan` string — no extra field needed).
//   (3) resolution is SAME-PROJECT-SCOPED — a same-slug match in a
//       DIFFERENT project is treated as unresolved (never cross-repo this
//       round).
//   (4) a cycle (A's resolved parent is B, B's is ... A) is broken at the
//       BACK EDGE (the revisiting node's own resolved-parent link is
//       dropped, so it renders standalone) and BOTH endpoints are flagged.
// Critical 5: a master's TWO labeled counts (`master_summary.plans` = child
// plan completion fraction, `master_summary.own_tasks` = the master's own
// direct-task fraction) are computed here, NEVER blended into one number.
// The `[master]` tag (client-side) is driven ONLY by `child_plans.length`,
// i.e. only from RESOLVED children — never merely from a declared
// `parent_plan` string on some other plan.
function applyMasterHierarchy(items) {
  const bySlug = {};
  items.forEach((n) => {
    n.dangling_parent = false;
    n.cycle_flag = false;
    n.cycle_with = '';
    n.resolved_parent = '';
    n.child_plans = [];
    n.master_summary = null;
    bySlug[n.id] = n;
  });

  items.forEach((n) => {
    if (!n.parent_plan) return;
    const cand = bySlug[n.parent_plan];
    if (cand && cand.project === n.project) n.resolved_parent = n.parent_plan;
    else n.dangling_parent = true; // not found, or a cross-project match (out of scope this round)
  });

  // Cycle detection: DFS over resolved_parent edges with a recursion stack;
  // a back-edge to a node CURRENTLY on the stack is the cycle. Break it by
  // clearing the REVISITING node's own resolved_parent (that one edge never
  // renders); flag BOTH endpoints so the operator sees the whole cycle.
  const state = {};
  function visit(id, stack) {
    if (state[id] === 'done' || state[id] === 'visiting') return;
    const node = bySlug[id];
    if (!node) return;
    state[id] = 'visiting';
    stack.push(id);
    const p = node.resolved_parent;
    if (p) {
      if (stack.indexOf(p) !== -1) {
        node.cycle_flag = true; node.cycle_with = p;
        const other = bySlug[p];
        if (other) { other.cycle_flag = true; if (!other.cycle_with) other.cycle_with = id; }
        node.resolved_parent = ''; // break the back-edge -> this node renders standalone
      } else {
        visit(p, stack);
      }
    }
    stack.pop();
    state[id] = 'done';
  }
  items.forEach((n) => visit(n.id, []));

  // Nest: every surviving resolved_parent edge makes this node a
  // `child_plans` entry of its master.
  items.forEach((n) => {
    if (n.resolved_parent && bySlug[n.resolved_parent]) {
      bySlug[n.resolved_parent].child_plans.push(n);
    }
  });

  // Master aggregation (Critical 5) + roll-up absorption (C1 generalization
  // — a master's badges must reflect its child plans too), processed
  // children-before-parents so a multi-level master's own absorption
  // already sees its children's FINALIZED roll-ups (the tree is acyclic
  // post cycle-breaking, so this recursion always terminates).
  const finalized = {};
  function finalize(id) {
    if (finalized[id]) return;
    finalized[id] = true;
    const node = bySlug[id];
    if (!node) return;
    node.child_plans.forEach((c) => finalize(c.id));
    if (node.child_plans.length) {
      const done = node.child_plans.filter((c) => c.status && c.status.value === 'complete').length;
      node.master_summary = {
        plans: { done: done, total: node.child_plans.length },
        own_tasks: node.progress ? { done: node.progress.done, total: node.progress.total } : { done: 0, total: 0 },
      };
      absorbChildPlanRollUps(node);
    }
  }
  items.forEach((n) => finalize(n.id));

  return { topLevel: items.filter((n) => !n.resolved_parent) };
}

// buildRoadmapTree() -> {flatItems, topLevel, ghostCount} — the shared
// derivation core: EVERY plan node (masters, standalones, and every
// resolved child plan) in ONE flat array (flatItems — the id-addressable
// set the rank/title endpoints below resolve against, since a nested child
// plan keeps its own `id` and must stay reachable for edits/reorder), plus
// `topLevel` (Critical 3/4: child plans nested under their master are
// REMOVED from the top-level list — they render only once, under their
// master's "Plans — build order" subsection).
function buildRoadmapTree() {
  const byAsk = foldRegistryForRoadmap();
  const planAskLinks = buildPlanAskLinks(byAsk);
  const scanRoot = planScanRoot();
  const discovered = discoverPlanFiles(scanRoot, planAskLinks);
  const planFiles = discovered.files;
  const planRankOverlay = readPlanRankOverlay();
  // Heartbeats read ONCE per request (derive-lib's own convention) and
  // handed to every item's derivation below; heartbeatsStoreOk distinguishes
  // a genuinely-absent store (benign) from one that exists but could not be
  // read (a real derivation-input failure — C5). Pure fs read, no spawn (A6).
  const hbResult = deriveLib.listRawHeartbeatsResult();
  // R9-7b: boundSessionIds is populated AS A SIDE EFFECT of every task's own
  // derivation below (deriveTaskNode marks each session id attached to a
  // not-done task) — mutated-through-hbCtx is the same threading pattern
  // heartbeats/nowMs already use for this exact request-scoped object.
  const hbCtx = { heartbeats: hbResult.heartbeats, heartbeatsStoreOk: hbResult.ok, nowMs: Date.now(), boundSessionIds: {} };
  // ROADMAP-WAITING-ON-YOU-SIGNAL-01 (2026-07-29 round 14): read ONCE per
  // request (same convention as heartbeats above), handed to every task's
  // own derivation below via hbCtx — see buildWaitingOnYouMap's header for
  // the full matching contract.
  hbCtx.waitingOnYou = buildWaitingOnYouMap(scanRoot);

  let items = planFiles.map((pf) => {
    const linkedAsks = planAskLinks[pf.slug] || [];
    const node = derivePlanRootNode(pf, linkedAsks, hbCtx);
    node.rank = planEffectiveRank(pf, linkedAsks, planRankOverlay);
    computeRollUps(node);
    return node;
  });

  // R11 Critical 4(1): pin a master excluded by aging when a non-terminal
  // child still references it — BEFORE the build-order sort, so a pinned
  // master participates in ordering like any other item.
  items = pinDanglingActiveMasters(items, planAskLinks, planRankOverlay, hbCtx);

  // Build order (A7 + round 8): ranked items by rank, then everything else
  // by the fallback added_ts (earliest-created first) — the pinned DEFAULT.
  items.sort((a, b) => {
    const ar = a.rank === null ? Infinity : a.rank;
    const br = b.rank === null ? Infinity : b.rank;
    if (ar !== br) return ar - br;
    return String(a.added_ts).localeCompare(String(b.added_ts));
  });

  // R9-7b: computed AFTER every plan/task has been derived, so
  // boundSessionIds reflects the WHOLE tree, not just one plan.
  const unboundSessionsNode = deriveUnboundSessionsNode(hbCtx);

  // R11 Critical 3/4/5: resolve parent-plan -> nest verified children under
  // their master, break+flag cycles, aggregate the two labeled counts.
  const hierarchy = applyMasterHierarchy(items);

  // RUNNING-NOW pass: LAST, after nesting, so a master sees its resolved
  // child plans' leaves too (see stampRunningNow's header). Walks the
  // top-level roots; `items` shares the same node objects, so flatItems
  // carries the stamp as well.
  hierarchy.topLevel.forEach(stampRunningNow);
  if (unboundSessionsNode) stampRunningNow(unboundSessionsNode);

  return {
    flatItems: items, // every node, id-addressable, incl. nested child plans
    topLevel: hierarchy.topLevel,
    ghostCount: discovered.ghostCount,
    unboundSessionsNode: unboundSessionsNode,
  };
}

function buildRoadmapPayload() {
  const tree = buildRoadmapTree();
  return {
    ok: true,
    generated_at: new Date().toISOString(),
    completed_age_days: COMPLETED_AGE_DAYS,
    unbound_sessions: tree.unboundSessionsNode,
    // stale_links_omitted (2026-07-21 ghost-bounding fix): the count of
    // ask-linked plan slugs whose file could not be resolved AND whose
    // newest linking ask is older than completed_age_days — excluded from
    // `items` entirely (never 150+ dead roots), but named here as ONE
    // honest aggregate rather than a silent drop (C5).
    stale_links_omitted: tree.ghostCount,
    items: tree.topLevel,
  };
}

// computeSiblingIds(tree, itemId) -> [id, ...] | null — R11 Important I3:
// "reorder scoped WITHIN the current sibling list." A nested child plan's
// siblings are its master's OTHER resolved child plans (`child_plans`,
// already in build order); everything else (masters + standalone plans)
// shares the top-level list, exactly as before nesting existed.
function computeSiblingIds(tree, itemId) {
  const node = tree.flatItems.find((n) => n.id === itemId);
  if (!node) return null;
  if (node.resolved_parent) {
    const parent = tree.flatItems.find((n) => n.id === node.resolved_parent);
    if (parent) return (parent.child_plans || []).map((c) => c.id);
  }
  return tree.topLevel.map((n) => n.id);
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
      let tree;
      try { tree = buildRoadmapTree(); }
      catch (e) { return sendJson(res, 500, { ok: false, error: String(e && e.message || e) }); }
      // R11 I3: reorder is scoped WITHIN the current sibling list — a nested
      // child plan reorders among its master's other child plans, never the
      // whole tree.
      const ids = computeSiblingIds(tree, itemId);
      if (!ids) return sendJson(res, 404, { ok: false, error: 'roadmap item not found: ' + itemId });
      const idx = ids.indexOf(itemId);
      if (idx === -1) return sendJson(res, 404, { ok: false, error: 'roadmap item not found: ' + itemId });
      const swapWith = direction === 'up' ? idx - 1 : idx + 1;
      if (swapWith < 0 || swapWith >= ids.length) {
        return sendJson(res, 200, { ok: true, unchanged: true, order: ids });
      }
      const newOrder = ids.slice();
      newOrder[idx] = ids[swapWith];
      newOrder[swapWith] = itemId;
      // Merge into the EXISTING overlay (read, not replace): only THIS
      // sibling group's ranks change — a different master's children (or
      // the top-level list, when this reorder is itself nested) must keep
      // their own stored ranks untouched (I3 scoping applies to the WRITE
      // too, not just the computed order).
      const overlay = readPlanRankOverlay();
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
  // round-14 fix exports (test/reuse hooks — ROADMAP-CORRUPT-PLAN-CONFIDENT-
  // BUCKET-01 / ROADMAP-SUPERSEDED-RENDERS-PENDING-01)
  scanPlanDir,
  planStatusToken,
  KNOWN_PLAN_STATUS_TOKENS,
  derivePlanRootNode,
  // round-9 fix-round exports (test/reuse hooks)
  planFileHeaderExtras,
  planProvenanceClass,
  slugLooksMachineFiled,
  configuredRepoRoots,
  deriveUnboundSessionsNode,
  // R11 (round 11) exports — batch derivation + master hierarchy (test/reuse hooks)
  deriveTaskBatches,
  buildRoadmapTree,
  applyMasterHierarchy,
  pinDanglingActiveMasters,
  repoRootFromAbsPath,
};
