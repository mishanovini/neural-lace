'use strict';
// auditor.js — background drift auditor (ask-rooted-workstreams-p1 Task 12:
// "Background auditor + drift badges").
//
// ============================================================
// WHY THIS EXISTS
// ============================================================
//
// The log-first law (sketch §2) says progress is a MECHANISM-EMITTED log,
// never model memory — but every mechanism splice is explicitly
// best-effort/never-blocks (constraint 5), so a splice CAN legitimately miss
// an event (a crashed hook, a squash-merge that bypassed a local git hook, a
// process that died mid-write). This module is the safety net: it runs on a
// RELAXED cadence (never on the `GET /api/asks` request path — Behavioral
// Contracts' perf budget: "no oracle shelling on the landing path"),
// compares the log against several independent ground-truth sources, and
// either HEALS the gap (backfills a missing event, silently, no permanent
// badge) or BADGES it (when the log claims something ground truth does not
// support — the log can never be un-emitted or auto-corrected per
// constraint 6: "nothing here flips `- [x]` or adds a second done-bit").
//
// ============================================================
// DIVERGENCE-CLASS TABLE (plan Task 12, review round 1 — binding; the
// authoritative side is named PER CLASS, never direction-blind)
// ============================================================
//
//   Divergence                                          | Authoritative | Action
//   -----------------------------------------------------|---------------|----------------------------
//   checkbox [x], no task_done event (truth ahead)       | plan file     | BACKFILL task_done, emitter=auditor -- HEALS, no permanent badge
//   master SHA, no merged event (truth ahead)             | git           | BACKFILL merged via merge-scan-lib.sh's GUARANTEED lane (Task 5b)
//   NEEDS-YOU item resolved, pointer unchecked (truth ahead) | ledger     | derive resolution -> auto-check the operator-todo.md pointer
//   all linked plans terminal, ask still active (truth ahead) | plan Status | ask-registry.sh set-status done, emitter=auditor -- the mechanical ask exit (constraint 7)
//   task_done event, checkbox unflipped (log ahead)       | plan file     | BADGE -- never un-emit, never flip (constraint 6)
//   task_started with no matching dispatch record (log ahead) | dispatch records | BADGE -- ONLY when the event is within the marker retention horizon (see EVIDENCE HORIZON below); older events are SKIPPED, not badged
//   waiting_on_operator with no ground truth anywhere (log ahead) | ledger  | BADGE
//   event with provenance:unknown emitter (no oracle)     | --            | BADGE + UI de-emphasis (constraint 10)
//
// ============================================================
// EVIDENCE HORIZON (production incident, 2026-07-18 -- badge-storm nl-issue):
// dispatch-provenance markers are pruned by dispatch-provenance.sh's
// `_dp_prune` (TTL default 14d, then a newest-N cap, default 200 -- the
// pl_classify_session hot-path fix) EVERY time a marker is written. The
// `unmatched_dispatch` oracle above compares a task_started event against
// `ctx.dispatchMarkers`, which is only ever the CURRENTLY SURVIVING marker
// set -- so a task_started event old enough that its marker (if one was
// ever written) has since been pruned looks IDENTICAL to a task_started
// event that never had a marker at all. Judging the former as drift is
// wrong: absence of evidence past the retention horizon is not evidence of
// absence. PROVEN in production (2026-07-18): the operator's real
// ~/.claude/state/dispatch-provenance held exactly 200 markers (the cap),
// spanning roughly the last 2.3 HOURS of dispatch activity -- far tighter
// than the nominal 14-day TTL -- while task_started events for an archived
// 18-task build (weeks old) had no chance of a surviving marker, producing
// ~718 false unmatched_dispatch badges every 120s cycle.
//
// THE FIX: dispatchMarkerEvidenceHorizonMs() computes the point in time
// before which "no marker" can no longer be trusted as "never dispatched"
// -- the LATER (more recent, i.e. more restrictive) of (a) the static TTL
// cutoff (now - DISPATCH_PROVENANCE_TTL_DAYS) and (b) the empirical cutoff
// implied by the cap, when the cap is actually binding (marker count >=
// DISPATCH_PROVENANCE_MAX_MARKERS): the oldest marker CURRENTLY PRESENT,
// since the cap has by construction already evicted anything older than
// that regardless of TTL. auditAsk() skips (never badges, never heals) any
// task_started event older than this horizon. Recent events (within the
// horizon) are judged exactly as before -- a missing marker for a RECENT
// event is still real signal.
//
// unknown_provenance (Class H) does NOT share this exposure and needed no
// change: it badges on `event.provenance === 'unknown'`, a field stamped
// ONCE at write time by progress-log-lib.sh's pl_emit (`_pl_in_list
// "$emitter" "${_PL_KNOWN_EMITTERS[@]}"`, progress-log-lib.sh:398-401) and
// persisted permanently on the event itself -- it is not compared against
// any external, prunable ground-truth source at audit time, so an old event
// is judged on the exact same fact it was judged on the day it was emitted.
// orphaned_waiting_item (Class G) was also checked: its ground truth
// (`allKnownNeedsYouIds`, folded from NEEDS-YOU.md's open section UNION
// every id ever seen in an operator-todo.md pointer bullet) has no
// automatic TTL/cap prune anywhere in this codebase -- pointer bullets are
// only ever checkbox-flipped, never deleted -- so it is not retention-
// bounded the way dispatch-provenance markers are.
//
// PLUS the sketch §8-3 COUNT RECONCILIATION: ledger-parsed open NEEDS-YOU
// items vs the count actually reflected across every ask's waiting_count
// must be equal, else a diagnostics-tab detail (NEVER a landing-page banner
// -- anti-noise, constraint 1/2). See countReconciliation() below for the
// exact computation and the documented decision on where this surfaces
// (diagnostics only, since a systemic mismatch may not trace to any single
// ask card -- "attach to exactly the divergent item" has no single item
// when the divergence is "an open decision no ask's log references at all").
//
// Every drift badge carries a `detail_ref` (constraint 9: "clicking a badge
// opens its divergence detail") -- Task 13 (not built by this task) owns the
// actual click-through UI; this module only guarantees every badge is
// addressable by a stable, idempotent id.
//
// ============================================================
// CADENCE (constraint: "never on the landing request path")
// ============================================================
//
// Default 120000ms (2 minutes), env-tunable via AUDITOR_CADENCE_MS -- a
// RELAXED cadence relative to derive-cache.js's 30s pane refresh, since
// nothing on the read path depends on the auditor's freshness (the log is
// primary; the auditor is a background healer/badger, matching Behavioral
// Contracts: "auditor down -> landing still serves"). Mirrors
// derive-cache.js's DeriveCache.start()/stop() shape (fire the first cycle
// immediately, fire-and-forget, then setInterval) and its single-flight
// guard (`_cycleInFlight` -- a slow cycle SKIPS the next tick rather than
// stacking, exactly like DeriveCache's own `_cycleInFlight`/skippedCycles).
//
// ============================================================
// REUSE OF derive-cache.js's PLUMBING (Wire check)
// ============================================================
//
// This module shells to THREE existing mechanism CLIs (never re-implements
// their logic): `scripts/progress-log.sh emit` (backfill task_done),
// `scripts/ask-registry.sh set-status` (the mechanical ask-done exit), and
// `hooks/lib/merge-scan-lib.sh scan-repo` (the GUARANTEED merged-backfill
// lane -- Task 5b's header literally names this module as its caller: "Task
// 12's Node auditor shells out to THIS FILE directly"). Every spawn reuses
// derive-cache.js's `bashBin()`/`spawnEnv()` (absolute-path bash + the
// 2026-07-09 lobotomy-lesson env hardening) -- the SAME convention
// server.js's own `runAskRegistryCli`/`classifySessions` already use, so a
// THIRD independent re-derivation of "how do we spawn bash safely on this
// box" never exists.
//
// ============================================================
// WHY THE READERS BELOW ARE DUPLICATED, NOT REQUIRED FROM server.js
// ============================================================
//
// server.js REQUIRES this file (to mount + start the auditor and read its
// published badge state) -- so this file requiring server.js BACK would be
// a circular require, and Node resolves a circular require by handing back
// whatever the OTHER module's `module.exports` object holds AT THE MOMENT
// OF the require call, which for server.js (whose own `require('./auditor.js')`
// happens before its `module.exports` assignment at the bottom of the file)
// would be an incomplete/empty object -- fragile by construction, not a
// deliberate design. The small readers below (JSONL fold, plan-checkbox
// parse, NEEDS-YOU.md section parse) are therefore independently
// implemented here, mirroring this codebase's own established convention of
// small, deliberately duplicated per-file readers (e.g. merge-scan-lib.sh's
// own `_ms_resolve_ask_id` duplicates plan-lifecycle.sh's ask-id-header awk
// pattern rather than sourcing across hook/script boundaries -- "every
// splice stays independently best-effort, never sources another hook").
//
// ============================================================
// SANDBOXING (constraint 4)
// ============================================================
//
// Every stateful path this module touches resolves through the SAME env-var
// overrides the rest of this plan already established (PROGRESS_LOG_STATE_DIR,
// ASK_REGISTRY_STATE_DIR, NEEDS_YOU_MD_PATH, OPERATOR_TODO_PATH,
// DISPATCH_PROVENANCE_STATE_DIR), resolved FRESH on every cycle (never
// memoized at construction time) -- exactly like server.js's own
// `progressLogStateDir()`/`askRegistryFile()` functions, which are called
// per-request rather than cached, so a self-test that sets these env vars
// AFTER `createAuditor()` is constructed (as server.selftest.js's own
// ask-fixture setup does, ahead of `require('./server.js')`) still gets
// honored the next time `runCycle()` runs.

const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawn } = require('child_process');
const { bashBin, spawnEnv } = require('./derive-cache.js');
const projects = require('../config/projects.js');
const planParse = require('./plan-parse.js');

const DEFAULT_CADENCE_MS = 120000;
const DEFAULT_MERGE_SCAN_LIMIT = 200;
const DEFAULT_CLI_TIMEOUT_MS = 60000;
// Mirrors dispatch-provenance.sh's own `_dp_prune` defaults EXACTLY (same
// env var names too: DISPATCH_PROVENANCE_TTL_DAYS / _MAX_MARKERS) -- see the
// "EVIDENCE HORIZON" header block above for why this file needs to know them.
const DEFAULT_DISPATCH_PROVENANCE_TTL_DAYS = 14;
const DEFAULT_DISPATCH_PROVENANCE_MAX_MARKERS = 200;

function nowIso() { return new Date().toISOString(); }

// ----------------------------------------------------------------------
// Path resolution -- mirrors server.js's own resolver functions exactly
// (same env vars, same fallback shape) so one sandbox setup covers both
// the server's readers AND this module's.
// ----------------------------------------------------------------------
function mainRepoRoot() {
  try { return projects.selfRepoRoot(); } catch (_) { return process.cwd(); }
}
function progressLogStateDir() {
  return process.env.PROGRESS_LOG_STATE_DIR ||
    path.join(process.env.HOME || os.homedir(), '.claude', 'state', 'progress-logs');
}
function askRegistryFile() {
  const dir = process.env.ASK_REGISTRY_STATE_DIR ||
    path.join(process.env.HOME || os.homedir(), '.claude', 'state');
  return path.join(dir, 'ask-registry.jsonl');
}
function needsYouMdPath() {
  return process.env.NEEDS_YOU_MD_PATH || path.join(mainRepoRoot(), 'NEEDS-YOU.md');
}
// needsYouStateDir/needsYouLedgerFile — the STRUCTURED-JSON oracle (cockpit-
// roadmap-redesign Task 4, A8), distinct from needsYouMdPath() above (the
// rendered .md this module already reads for Class C/G). Quarantine
// classification needs `lint_warnings` — a field the rendered .md never
// carries — so this reads `<state dir>/ledger.json` directly, mirroring
// needs-you.sh's own `_ny_state_dir` resolution order (NEEDS_YOU_STATE_DIR
// env override, else $HOME/.claude/state/needs-you) and od_needs_me's own
// "THE oracle; never re-derives from the rendered NEEDS-YOU.md" precedent.
// Small, deliberately duplicated reader (server/inbox-routes.js carries an
// identical copy) — see file header "WHY THE READERS BELOW ARE DUPLICATED".
function needsYouStateDir() {
  return process.env.NEEDS_YOU_STATE_DIR ||
    path.join(process.env.HOME || os.homedir(), '.claude', 'state', 'needs-you');
}
function needsYouLedgerFile() { return path.join(needsYouStateDir(), 'ledger.json'); }
function readNeedsYouLedgerItems() {
  let raw;
  try { raw = fs.readFileSync(needsYouLedgerFile(), 'utf8'); } catch (_) { return []; }
  let parsed;
  try { parsed = JSON.parse(raw); } catch (_) { return []; }
  return (parsed && Array.isArray(parsed.items)) ? parsed.items : [];
}
// operator-todo.md -- mirrors needs-you.sh's `_ny_operator_todo_path` shape
// (OPERATOR_TODO_PATH env override, else the main-checkout root), but
// resolved in pure JS (no bash shell-out) the SAME way server.js resolves
// NEEDS_YOU_MD_PATH's fallback -- via config/projects.js's selfRepoRoot(),
// not `nl_main_checkout_root` (a bash-only function); this server process
// is always started from the main checkout in production (never a builder
// worktree), so the two resolvers agree in practice.
function operatorTodoPath() {
  return process.env.OPERATOR_TODO_PATH || path.join(mainRepoRoot(), 'docs', 'operator-todo.md');
}
function dispatchProvenanceStateDir() {
  return process.env.DISPATCH_PROVENANCE_STATE_DIR ||
    path.join(process.env.HOME || os.homedir(), '.claude', 'state', 'dispatch-provenance');
}
// dispatchProvenanceTtlDays / dispatchProvenanceMaxMarkers -- read FRESH on
// every call (never memoized, same convention as every other resolver in
// this file), honoring the SAME env var names dispatch-provenance.sh's own
// `_dp_prune` reads, so a single override tunes both the writer's actual
// prune behavior and this file's judgment of it in lockstep.
function dispatchProvenanceTtlDays() {
  const v = Number(process.env.DISPATCH_PROVENANCE_TTL_DAYS);
  return v > 0 ? v : DEFAULT_DISPATCH_PROVENANCE_TTL_DAYS;
}
function dispatchProvenanceMaxMarkers() {
  const v = Number(process.env.DISPATCH_PROVENANCE_MAX_MARKERS);
  return v > 0 ? v : DEFAULT_DISPATCH_PROVENANCE_MAX_MARKERS;
}
function mergeScanLibPath() {
  return process.env.MERGE_SCAN_LIB ||
    path.join(__dirname, '..', '..', '..', 'adapters', 'claude-code', 'hooks', 'lib', 'merge-scan-lib.sh');
}
function progressLogCliPath() {
  return process.env.PROGRESS_LOG_CLI ||
    path.join(__dirname, '..', '..', '..', 'adapters', 'claude-code', 'scripts', 'progress-log.sh');
}
function askRegistryCliPath() {
  return process.env.ASK_REGISTRY_CLI ||
    path.join(__dirname, '..', '..', '..', 'adapters', 'claude-code', 'scripts', 'ask-registry.sh');
}
// nl-issue.sh -- C3b (cockpit-v2-push-materialized-store Task 7). Resolved
// the SAME way as the three CLI paths above: repo-relative to the CANONICAL
// source in THIS repo (adapters/claude-code/scripts/), not the installed
// $HOME/.claude/scripts/ copy -- mirrors progressLogCliPath()/
// askRegistryCliPath() exactly.
function nlIssueCliPath() {
  return process.env.NL_ISSUE_CLI ||
    path.join(__dirname, '..', '..', '..', 'adapters', 'claude-code', 'scripts', 'nl-issue.sh');
}
// The auditor's OWN dedup/recurrence state (distinct from nl-issue.sh's own
// internal 24h text-dedup ledger) -- "already-filed divergence ids", so a
// still-open divergence badge (which persists every cycle until resolved,
// per constraint 6) is filed exactly ONCE per divergence lifetime, never
// once per cycle.
function auditorNlIssueStatePath() {
  return process.env.AUDITOR_NL_ISSUE_STATE_PATH ||
    path.join(process.env.HOME || os.homedir(), '.claude', 'state', 'auditor-nl-issue-state.json');
}

// ----------------------------------------------------------------------
// readJsonlLines / foldAskRegistry / readAskEvents -- small, deliberately
// duplicated readers (see header "WHY DUPLICATED" note). Identical
// semantics to server.js's own versions: a missing file or a corrupt line
// is silently skipped (Edge Cases: "readers skip bad lines ... never 500s
// on one bad record").
// ----------------------------------------------------------------------
function readJsonlLines(file) {
  let raw;
  try { raw = fs.readFileSync(file, 'utf8'); } catch (_) { return []; }
  return raw.split('\n')
    .map((l) => l.trim())
    .filter(Boolean)
    .map((l) => { try { return JSON.parse(l); } catch (_) { return null; } })
    .filter(Boolean);
}

function foldAskRegistry(registryFile) {
  const lines = readJsonlLines(registryFile).slice().sort((a, b) => String(a.ts).localeCompare(String(b.ts)));
  const byAsk = {};
  lines.forEach((rec) => {
    if (!rec || !rec.ask_id) return;
    const cur = byAsk[rec.ask_id] || { plan_slugs: [] };
    ['repo', 'project', 'verbatim_ref', 'status'].forEach((f) => {
      if (rec[f]) cur[f] = rec[f];
    });
    // TITLE FOLD PRECEDENCE PARITY (cockpit-roadmap-redesign Task 2's A3 rule,
    // spliced here at Task 4 per docs/plans/fragments/roadmap-t2-derive-lib-
    // fragment.md's "Second seam, task-4-owned" note): server.js's own
    // foldAskRegistry (derive-lib.js) stopped folding `summary` via plain
    // last-non-empty-wins — operator-sourced titles (title_source:"operator")
    // now ALWAYS outrank auto-sourced ones regardless of timestamp. This
    // duplicate reader (see file header "WHY DUPLICATED") must honor the
    // SAME precedence or its `summary`/`title_source` labels silently
    // diverge from the canonical reader's. This module's own decision
    // logic (auditAsk) only consumes `status`/`plan_slugs`, never `summary`
    // — the practical exposure was label-level, not correctness-level, but
    // parity is still the honest contract for any future consumer of this
    // duplicate's summary/title_source fields.
    if (rec.summary) {
      const src = rec.title_source === 'operator' ? 'operator' : 'auto';
      if (src === 'operator' || cur.title_source !== 'operator') {
        cur.summary = rec.summary;
        cur.title_source = src;
      }
    }
    if (rec.record_type === 'plan_linked' && rec.plan_slug && cur.plan_slugs.indexOf(rec.plan_slug) === -1) {
      cur.plan_slugs.push(rec.plan_slug);
    }
    byAsk[rec.ask_id] = cur;
  });
  Object.keys(byAsk).forEach((k) => { if (!byAsk[k].status) byAsk[k].status = 'active'; });
  return byAsk;
}

function readAskEvents(progressLogDir, askId) {
  const file = path.join(progressLogDir, (askId || 'unlinked') + '.jsonl');
  return readJsonlLines(file).sort((a, b) => String(a.ts).localeCompare(String(b.ts)));
}

// ----------------------------------------------------------------------
// Plan-file parsing + resolution -- now the ONE shared module
// (./plan-parse.js, cockpit-v2-push-materialized-store Task 1), replacing
// this file's own private (numeric-id-only) grammar. `parsePlanFile` below
// is a thin wrapper that preserves this file's EXACT prior signature/shape
// (`{tasks, status, absPath}` | `null`) so every call site below is
// unchanged; see plan-parse.js's header for the full "why" + the exact
// corpus delta. "Terminal" is still scoped STRICTLY to the literal value
// COMPLETED (the exact target close-plan.sh flips to on a successful
// close, and the state plan_completed events name) -- deliberately NOT any
// of the other terminal-ish values this estate's plans also use
// (ABANDONED, DEFERRED, SUPERSEDED): those mean "this plan stopped", not
// "the ask this plan served is done" -- an abandoned plan should never
// silently mark its ask done.
// ----------------------------------------------------------------------
function parsePlanFile(absPath) {
  return planParse.parsePlanFile(absPath);
}

// resolvePlanAbsPath -- mirrors merge-scan-lib.sh's own resolution order
// (current plan file, then the archived-on-close location) crossed with
// server.js's own repo-then-main-root fallback. planParse.resolvePlanAbsPath
// owns the per-root "docs/plans/ then docs/plans/archive/" check (M5); this
// wrapper preserves the EXACT prior repo-then-mainRoot priority order and
// 3-argument signature every call site below already uses.
function resolvePlanAbsPath(repo, mainRoot, slug) {
  if (repo) {
    const p = planParse.resolvePlanAbsPath(repo, slug);
    if (p) return p;
  }
  return planParse.resolvePlanAbsPath(mainRoot, slug);
}

// ----------------------------------------------------------------------
// NEEDS-YOU.md — reads the SAME "## Awaiting your decision" section
// server.js's readNeedsYouDecisionsResult parses (Task 11 Integration
// point: "parse the SAME shape needs-you.sh renders"). This module only
// needs the SET of currently-open ids, not the full §3 block.
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
const DECISION_META_RE = /^\*\(added ([0-9-]+|unknown), session `([^`]*)`, id `([^`]*)`\)\*$/;

function readOpenNeedsYouIds(mdPath) {
  let text;
  try { text = fs.readFileSync(mdPath, 'utf8'); } catch (_) { return { available: false, ids: new Set() }; }
  const section = extractMdSection(text, '## Awaiting your decision');
  const ids = new Set();
  section.split('\n').forEach((line) => {
    const m = DECISION_META_RE.exec(line.trim());
    if (m && m[3]) ids.add(m[3]);
  });
  return { available: true, ids: ids };
}

// ----------------------------------------------------------------------
// operator-todo.md — parses the AUTO-section pointer bullets
// `_ny_operator_todo_append_pointer` (needs-you.sh, Task 4) writes:
//   - [ ] AUTO: <section> waiting on operator — "<title>" (needs-you `<id>`, tier <t>, session `<sid>`) — see NEEDS-YOU.md
// and can flip an unchecked bullet's `[ ]` to `[x]` in place -- this is the
// ONLY mutation this module ever performs on operator-todo.md, and it is
// scoped to exactly the checkbox character on a matched AUTO line; every
// other byte (including operator-authored content above `<!-- AUTO:START -->`)
// is rewritten unchanged.
// ----------------------------------------------------------------------
const AUTO_START = '<!-- AUTO:START -->';
const AUTO_END = '<!-- AUTO:END -->';
const POINTER_RE = /^- \[( |x|X)\] AUTO: .*\(needs-you `([^`]+)`,/;

function readOperatorTodoPointers(todoPath) {
  let text;
  try { text = fs.readFileSync(todoPath, 'utf8'); } catch (_) { return { available: false, text: '', pointers: [] }; }
  const lines = text.split('\n');
  let inside = false;
  const pointers = [];
  lines.forEach((line, idx) => {
    const trimmed = line.trim();
    if (trimmed === AUTO_START) { inside = true; return; }
    if (trimmed === AUTO_END) { inside = false; return; }
    if (!inside) return;
    const m = POINTER_RE.exec(line);
    if (m) pointers.push({ lineIndex: idx, checked: (m[1].toLowerCase() === 'x'), needsYouId: m[2] });
  });
  return { available: true, text: text, pointers: pointers };
}

// autoCheckOperatorTodo(todoPath, resolvedIds) -> {changed, checkedCount}.
// resolvedIds: a Set of needs_you_id values that are NO LONGER open (i.e.
// the ledger-authoritative side, per the divergence table's third row) --
// every UNCHECKED pointer bullet naming one of these ids gets its `[ ]`
// flipped to `[x]`. Idempotent (an already-checked bullet is left alone)
// and atomic (tmp-file + rename, matching this codebase's other
// marker-safe rewrites).
function autoCheckOperatorTodo(todoPath, resolvedIds) {
  const r = readOperatorTodoPointers(todoPath);
  if (!r.available || !r.pointers.length) return { changed: false, checkedCount: 0 };
  const lines = r.text.split('\n');
  let changed = false, checkedCount = 0;
  r.pointers.forEach((p) => {
    if (p.checked) return;
    if (!resolvedIds.has(p.needsYouId)) return;
    const line = lines[p.lineIndex];
    const newLine = line.replace('- [ ] AUTO:', '- [x] AUTO:');
    if (newLine !== line) {
      lines[p.lineIndex] = newLine;
      changed = true;
      checkedCount++;
    }
  });
  if (!changed) return { changed: false, checkedCount: 0 };
  try {
    const tmp = todoPath + '.auditor-tmp-' + process.pid + '-' + Date.now();
    fs.writeFileSync(tmp, lines.join('\n'));
    fs.renameSync(tmp, todoPath);
  } catch (_) {
    return { changed: false, checkedCount: 0 };
  }
  return { changed: true, checkedCount: checkedCount };
}

// ----------------------------------------------------------------------
// Dispatch-provenance markers -- same reader shape as server.js's
// readDispatchProvenanceMarkers.
// ----------------------------------------------------------------------
function readDispatchMarkers(dir) {
  let files;
  try { files = fs.readdirSync(dir); } catch (_) { return []; }
  const out = [];
  files.forEach((f) => {
    if (!/\.json$/.test(f)) return;
    try {
      const obj = JSON.parse(fs.readFileSync(path.join(dir, f), 'utf8'));
      if (obj) out.push(obj);
    } catch (_) { /* corrupt marker -- skip, never crash */ }
  });
  return out;
}

// dispatchMarkerEvidenceHorizonMs(dispatchMarkers, nowMs) -- see the
// "EVIDENCE HORIZON" header block for the full incident + reasoning. Pure
// (given its inputs; only reads env for the TTL/cap config, same as every
// other resolver here). Returns an epoch-ms cutoff: a task_started event
// older than this cannot be trusted to still have a survivable marker, so
// auditAsk() must skip (not badge) it.
//
//   - ttlCutoffMs = nowMs - ttlDays worth of ms (the static floor: the TTL
//     pass alone would never keep anything older than this).
//   - When the cap is NOT currently binding (fewer markers present than
//     DISPATCH_PROVENANCE_MAX_MARKERS), the cap adds no further
//     restriction -- ttlCutoffMs is the answer.
//   - When the cap IS binding (marker count >= the max), the cap pass has
//     already evicted anything older than the OLDEST marker currently
//     present, REGARDLESS of the TTL -- that empirical bound can be
//     (and in production, 2026-07-18, WAS) far tighter than the TTL alone.
//     The horizon is then the LATER (more recent/restrictive) of the two.
function dispatchMarkerEvidenceHorizonMs(dispatchMarkers, nowMs) {
  const ttlDays = dispatchProvenanceTtlDays();
  const maxMarkers = dispatchProvenanceMaxMarkers();
  const ttlCutoffMs = nowMs - (ttlDays * 24 * 60 * 60 * 1000);

  const markers = Array.isArray(dispatchMarkers) ? dispatchMarkers : [];
  if (markers.length < maxMarkers) return ttlCutoffMs;

  let oldestMs = null;
  markers.forEach((m) => {
    if (!m || !m.ts) return;
    const t = Date.parse(m.ts);
    if (!isFinite(t)) return;
    if (oldestMs === null || t < oldestMs) oldestMs = t;
  });
  if (oldestMs === null) return ttlCutoffMs;
  return Math.max(ttlCutoffMs, oldestMs);
}

// ----------------------------------------------------------------------
// shQuote / runCli — the ONE bash-spawn primitive every backfill call uses,
// mirroring server.js's runAskRegistryCli/classifySessions (bashBin() +
// spawnEnv() + `-lc`, the 2026-07-09 lobotomy-lesson hardening).
// ----------------------------------------------------------------------
function shQuote(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'"; }

// killTree() -- kill a spawned child AND its descendants.
//
// NL-FINDING (2026-07-14, PROVEN in production): runCli()'s timeout used to
// merely resolve() the promise and walk away, leaving the child ALIVE. Every
// auditor cycle whose merge-scan exceeded the timeout leaked an entire process
// tree, forever. Measured on the operator's machine: 781 live bash.exe (435
// merge-scan-lib.sh + 194 progress-log.sh), accumulating ~1 tree / 120s cadence
// over hours, until a bare `date` took 4.6s and the box had to be rebooted --
// three times. The single-flight guard did NOT help: the auditor BELIEVED the
// cycle had finished (the timeout told it so) and happily started the next one.
//
// On Windows child.kill() reaps ONLY the `bash -lc` shell, not the inner
// `bash script.sh` / git / progress-log.sh grandchildren -- so a bare kill()
// leaks the exact processes that matter. taskkill /T (tree) /F is required.
function killTree(child) {
  if (!child || child.pid == null) return;
  try {
    if (process.platform === 'win32') {
      spawn('taskkill', ['/T', '/F', '/PID', String(child.pid)], { stdio: 'ignore', windowsHide: true })
        .on('error', () => { try { child.kill('SIGKILL'); } catch (_) {} });
    } else {
      try { process.kill(-child.pid, 'SIGKILL'); } catch (_) { try { child.kill('SIGKILL'); } catch (_) {} }
    }
  } catch (_) { /* best-effort: never throw out of a reaper */ }
}

function runCli(scriptPath, args, timeoutMs) {
  return new Promise((resolve) => {
    if (!fs.existsSync(scriptPath)) {
      return resolve({ ok: false, rc: 127, stdout: '', stderr: 'not found: ' + scriptPath });
    }
    const cmd = 'bash ' + shQuote(scriptPath) + ' ' + args.map(shQuote).join(' ');
    let settled = false;
    let t = null;
    // Clearing the timer on settle also stops the timer itself from leaking per call.
    const done = (r) => {
      if (settled) return;
      settled = true;
      if (t) { clearTimeout(t); t = null; }
      resolve(r);
    };
    let child;
    try { child = spawn(bashBin(), ['-lc', cmd], { env: spawnEnv() }); }
    catch (e) { return done({ ok: false, rc: 127, stdout: '', stderr: String(e && e.message || e) }); }
    let out = '', err = '';
    child.stdout.on('data', (d) => { out += d; });
    child.stderr.on('data', (d) => { err += d; });
    child.on('error', (e) => done({ ok: false, rc: 127, stdout: out, stderr: String(e && e.message || e) }));
    child.on('close', (code) => done({ ok: code === 0, rc: code == null ? 1 : code, stdout: out, stderr: err }));
    t = setTimeout(() => {
      // THE FIX: kill the tree BEFORE resolving. Resolving alone orphans it.
      killTree(child);
      done({ ok: false, rc: 124, stdout: out, stderr: 'auditor CLI call timed out after ' + timeoutMs + 'ms (child tree killed)' });
    }, timeoutMs || DEFAULT_CLI_TIMEOUT_MS);
    if (t.unref) t.unref();
  });
}

function backfillTaskDone(cliPath, askId, planSlug, taskId, evidenceAbsPath, timeoutMs) {
  return runCli(cliPath, [
    'emit', '--type', 'task_done', '--ask', askId, '--plan-slug', planSlug,
    '--task-id', String(taskId), '--sha', '',
    '--summary', 'task ' + taskId + ' verified done (auditor-derived backfill)',
    '--evidence-link', evidenceAbsPath || '', '--emitter', 'auditor',
  ], timeoutMs);
}

function backfillAskDone(cliPath, askId, timeoutMs) {
  return runCli(cliPath, ['set-status', '--ask-id', askId, '--status', 'done', '--emitter', 'auditor'], timeoutMs);
}

// scanRepoForMerges -- the Class B (merged-backfill) side effect. Shells to
// merge-scan-lib.sh's `scan-repo` verb, which walks `git log origin/master`
// (the GUARANTEED lane: local `git-hooks/post-commit` alone can never see a
// remote squash-merge) and, for every resolvable-plan-slug commit, delegates
// to the STABLE, UNCHANGED `scripts/progress-log.sh emit --type merged ...`
// CLI (Task 5b's own header: "Task 12's Node auditor shells out to THIS
// FILE directly" -- mirrors derive-cache.js's own spawnSync-a-bash-tool
// convention).
function scanRepoForMerges(cliPath, repoRoot, limit, timeoutMs) {
  return runCli(cliPath, ['scan-repo', repoRoot, '--emitter', 'auditor', '--limit', String(limit)], timeoutMs);
}

// ========================================================================
// auditAsk(askId, reg, events, ctx) -- the PURE per-ask divergence
// computation (no I/O, no side effects -- everything it needs is handed in
// via `ctx`), so it is independently unit-testable without spawning bash or
// touching the filesystem. Returns:
//   { badges: [...schema-safe badge objects],
//     backfillTaskDoneList: [{planSlug, taskId, evidenceAbsPath}],
//     healed: [...diagnostics-only notes],
//     setStatusDoneNeeded: bool }
// `ctx`:
//   planLookup(slug) -> {tasks, status, absPath} | null
//   dispatchMarkers  -> [...marker objects]
//   allKnownNeedsYouIds -> Set (union of currently-open ids + every id ever
//                          seen in an operator-todo.md pointer bullet --
//                          the "has SOME real-world trace" ground-truth set
//                          class F/G checks against)
//   dispatchEvidenceHorizonMs -> epoch ms | undefined/null. Class F's
//                          "no marker" verdict is only trusted for
//                          task_started events at/after this cutoff (see
//                          "EVIDENCE HORIZON" header block) -- an event
//                          older than this is SKIPPED, not badged. Omitting
//                          this field (pre-existing callers, e.g. the pure
//                          Scenario 7 self-test fixture) preserves the OLD
//                          unconditional-judge behavior.
// ========================================================================
function auditAsk(askId, reg, events, ctx) {
  const badges = [];
  const backfillTaskDoneList = [];
  const healed = [];

  const doneEventKeys = new Set(); // "<plan_slug>|<task_id>" for any task_done event, any sha
  const startedEvents = [];
  const waitingEvents = [];
  const unknownProvenanceEvents = [];
  events.forEach((e) => {
    if (!e) return;
    if (e.type === 'task_done' && e.plan_slug && e.task_id) doneEventKeys.add(e.plan_slug + '|' + e.task_id);
    if (e.type === 'task_started') startedEvents.push(e);
    if (e.type === 'waiting_on_operator') waitingEvents.push(e);
    if (e.provenance === 'unknown') unknownProvenanceEvents.push(e);
  });

  const slugs = (reg.plan_slugs || []).slice();
  let allTerminal = slugs.length > 0;

  slugs.forEach((slug) => {
    const plan = ctx.planLookup(slug);
    if (!plan) { allTerminal = false; return; }
    if (plan.status !== 'COMPLETED') allTerminal = false;

    plan.tasks.forEach((t) => {
      const key = slug + '|' + t.id;
      if (t.done && !doneEventKeys.has(key)) {
        // Class A: truth (checkbox) ahead of the log -> BACKFILL, heals,
        // NO permanent badge.
        backfillTaskDoneList.push({ planSlug: slug, taskId: t.id, evidenceAbsPath: plan.absPath });
        healed.push({ kind: 'task_done_backfilled', ask_id: askId, plan_slug: slug, task_id: t.id });
      } else if (!t.done && doneEventKeys.has(key)) {
        // Class E: the log is ahead of the plan file -> BADGE, never flip
        // the checkbox and never un-emit the event (constraint 6).
        badges.push({
          divergence_class: 'log_ahead_task_not_flipped',
          message: 'the progress log shows task ' + t.id + ' verified done, but the plan file still shows it open',
          detail_ref: 'drift-' + askId + '-log-ahead-' + slug + '-' + t.id,
          plan_slug: slug,
          task_id: t.id,
        });
      }
    });
  });

  const setStatusDoneNeeded = (reg.status === 'active') && allTerminal;
  if (setStatusDoneNeeded) {
    healed.push({ kind: 'ask_set_done_needed', ask_id: askId });
  }

  // Class F: task_started with no matching dispatch-provenance marker.
  // Precise match on (ask_id, plan_slug, task_id, session_id) -- these four
  // fields are stamped from the SAME dispatching-session variables at the
  // SAME call site (workstreams-emit.sh's `_emit_dispatch_provenance`), so a
  // missing marker for an identical tuple is a genuine gap, not a
  // false-positive from independently-derived data.
  startedEvents.forEach((e) => {
    const found = ctx.dispatchMarkers.some((m) => m && m.ask_id === askId &&
      m.plan_slug === e.plan_slug && m.task_id === e.task_id && m.session_id === e.session_id);
    if (found) return;

    // EVIDENCE HORIZON (see header block): a missing marker for an event
    // OLDER than the marker-retention horizon proves nothing -- the marker
    // may well have existed and simply aged out via TTL/cap pruning. Only
    // skip when we can actually determine the event is old (a missing/
    // unparseable ts is NOT proof of age -- default to judging it, same as
    // before, rather than silently swallowing a genuine badge).
    const eventMs = e && e.ts ? Date.parse(e.ts) : NaN;
    if (isFinite(eventMs) && ctx.dispatchEvidenceHorizonMs != null && eventMs < ctx.dispatchEvidenceHorizonMs) {
      return; // too old for "no marker" to mean anything -- not drift
    }

    badges.push({
      divergence_class: 'unmatched_dispatch',
      message: 'a task-started update for task ' + (e.task_id || '?') + ' has no matching dispatch record',
      detail_ref: 'drift-' + askId + '-unmatched-dispatch-' + (e.plan_slug || '') + '-' + (e.task_id || '') + '-' + (e.session_id || ''),
      plan_slug: e.plan_slug || '',
      task_id: e.task_id || '',
    });
  });

  // Class G: waiting_on_operator with no ground truth anywhere (neither a
  // currently-open decision NOR ever seen in an operator-todo.md pointer).
  const seenNeedsYouIds = new Set();
  waitingEvents.forEach((e) => {
    if (!e.needs_you_id || seenNeedsYouIds.has(e.needs_you_id)) return;
    seenNeedsYouIds.add(e.needs_you_id);
    if (!ctx.allKnownNeedsYouIds.has(e.needs_you_id)) {
      badges.push({
        divergence_class: 'orphaned_waiting_item',
        message: 'a waiting-on-you update references a decision that could not be found',
        detail_ref: 'drift-' + askId + '-orphaned-waiting-' + e.needs_you_id,
      });
    }
  });

  // Class H (constraint 10): provenance:unknown -> badge + de-emphasis.
  const seenUnknown = new Set();
  unknownProvenanceEvents.forEach((e) => {
    const key = (e.event_id || (e.emitter + '|' + e.ts));
    if (seenUnknown.has(key)) return;
    seenUnknown.add(key);
    badges.push({
      divergence_class: 'unknown_provenance',
      message: 'an update came from an unrecognized source and is shown for review only',
      detail_ref: 'drift-' + askId + '-unknown-provenance-' + key,
      de_emphasize: true,
    });
  });

  return { badges: badges, backfillTaskDoneList: backfillTaskDoneList, healed: healed, setStatusDoneNeeded: setStatusDoneNeeded };
}

// ========================================================================
// C3b (cockpit-v2-push-materialized-store Task 7) -- wire the auditor's
// REAL log-ahead divergences into nl-issue.sh.
//
// WHICH CLASSES: exactly the four LOG-AHEAD rows of the divergence-class
// table at the top of this file (the ones that BADGE rather than heal --
// truth can never catch up to an un-emittable log entry, so these are the
// genuine, permanent "the mechanism disagrees with itself" cases the
// operator's actual auto-healing intent is about). Read off the table by
// its OWN divergence_class STRING CONSTANTS (not the plan task's prose
// names, which paraphrase the table row descriptions rather than quoting
// the literal badge.divergence_class values this file actually pushes):
//   'log_ahead_task_not_flipped' -- "task_done event, checkbox unflipped"
//   'unmatched_dispatch'         -- "task_started, no matching dispatch record"
//   'orphaned_waiting_item'      -- "waiting_on_operator, no ground truth anywhere"
//   'unknown_provenance'         -- "event with provenance:unknown emitter"
// 'unknown_provenance' additionally carries de_emphasize:true on the UI
// side (constraint 10) -- that governs RENDERING only; it is still a real
// divergence worth an operator's attention via nl-issue, so it is filed
// exactly like the other three.
//
// DEDUP: a persisted state file (auditorNlIssueStatePath()) records every
// badge.detail_ref ever filed -- detail_ref is already a stable, globally-
// unique id per divergence (each construction site above embeds askId +
// plan_slug/task_id/needs_you_id/event key), so "already filed" is a
// single Set-membership check. This is a SEPARATE dedup layer from
// nl-issue.sh's own internal 24h byte-identical-text dedup: that one
// exists to stop an unrelated CALLER from spamming near-duplicate free-text
// notes; this one exists because a STILL-OPEN divergence badge is
// re-computed and re-pushed into newBadgesByAsk on EVERY cycle for as long
// as it remains unresolved (constraint 6: never un-emit, never auto-flip)
// -- without this layer, one stuck divergence would file a new nl-issue
// note every single cadence tick forever.
//
// RECURRENCE ESCALATION: per divergence_class, once 3 DISTINCT ids have
// been filed within a rolling 7-day window, file ONE additional escalated
// summary note (never repeated for that class again -- "ONE escalated
// summary filing" is read literally: once per class, ever, not a
// re-escalation on every subsequent new id). Computed from the PERSISTED
// filed-state's timestamps, not just the current cycle's badge set, since
// an older id can still count toward the window even after its own badge
// has since resolved and stopped appearing in newBadgesByAsk.
//
// SPAWN CONVENTION: reuses runCli() verbatim (bashBin()/spawnEnv() +ve
// killTree-on-timeout reaping, exactly like backfillTaskDone/
// backfillAskDone/scanRepoForMerges above) rather than a fire-and-forget
// unawaited spawn -- this file's own header already documents "sequential,
// never parallel-fan-out" as the house convention for cycle side effects,
// and awaiting (bounded by the SAME timeout+killTree safety net runCli
// already provides) keeps the auditor's own self-test deterministic
// without a polling race, while still never letting a hung nl-issue.sh
// wedge the cycle indefinitely. "Fire-and-forget" in the operational sense
// the plan text means: the auditor never retries, never propagates a
// failure into backfill_errors/diagnostics, and never lets nl-issue's
// outcome affect the cycle's own success.
//
// SANDBOX-AWARENESS: gates on env vars ALREADY set by every self-test
// entry point in this codebase that can produce a real badge --
// HARNESS_SELFTEST=1 (set by this file's OWN --self-test) and
// AUDITOR_DISABLED=1 (set for the ENTIRE duration of server.selftest.js's
// run, including its Scenario 28 direct `auditor.runCycle()` call --
// "Production never sets this", per start()'s own comment above). Checked
// FRESH on every call (never memoized), matching this file's existing
// sandboxing convention for every other stateful path.
// ========================================================================
const NL_ISSUE_BADGE_CLASSES = new Set([
  'log_ahead_task_not_flipped',
  'unmatched_dispatch',
  'orphaned_waiting_item',
  'unknown_provenance',
]);
const NL_ISSUE_RECURRENCE_THRESHOLD = 3;
const NL_ISSUE_RECURRENCE_WINDOW_MS = 7 * 24 * 60 * 60 * 1000;

function isNlIssueSandboxed() {
  return process.env.HARNESS_SELFTEST === '1' || process.env.AUDITOR_DISABLED === '1';
}

function loadNlIssueState(statePath) {
  try {
    const parsed = JSON.parse(fs.readFileSync(statePath, 'utf8'));
    return {
      filed: (parsed && typeof parsed.filed === 'object' && parsed.filed) || {},
      escalated: (parsed && typeof parsed.escalated === 'object' && parsed.escalated) || {},
    };
  } catch (_) {
    return { filed: {}, escalated: {} };
  }
}

function saveNlIssueState(statePath, st) {
  try {
    fs.mkdirSync(path.dirname(statePath), { recursive: true });
    fs.writeFileSync(statePath, JSON.stringify(st));
  } catch (_) { /* best-effort -- a lost write just re-files next cycle */ }
}

// nlIssueMessageForBadge -- the one-line text handed to nl-issue.sh. Plain
// operator prose (no JSON); nl-issue.sh's own _nli_json_escape handles the
// on-disk encoding.
function nlIssueMessageForBadge(askId, badge) {
  const where = badge.plan_slug ? (' (plan ' + badge.plan_slug + (badge.task_id ? ', task ' + badge.task_id : '') + ')') : '';
  return 'auditor drift [' + badge.divergence_class + ']' + where + ' ask ' + askId + ': ' + badge.message + ' (ref ' + badge.detail_ref + ')';
}

// fileNlIssueDivergences(newBadgesByAsk, opts) -- the C3b entry point.
// `opts`: { cliPath, statePath, cliTimeoutMs }. Async (sequential awaits,
// per the SPAWN CONVENTION note above); every failure is swallowed --
// never lets an nl-issue problem affect the cycle's own outcome.
async function fileNlIssueDivergences(newBadgesByAsk, opts) {
  if (process.env.AUDITOR_NL_ISSUE_DISABLED === '1') return;
  if (isNlIssueSandboxed()) return;

  const cliPath = opts.cliPath;
  const statePath = opts.statePath;
  const timeoutMs = opts.cliTimeoutMs;
  const st = loadNlIssueState(statePath);
  const nowTs = nowIso();
  let changed = false;

  const askIds = Object.keys(newBadgesByAsk);
  for (let i = 0; i < askIds.length; i++) {
    const askId = askIds[i];
    const badges = newBadgesByAsk[askId] || [];
    for (let j = 0; j < badges.length; j++) {
      const badge = badges[j];
      if (!badge || !NL_ISSUE_BADGE_CLASSES.has(badge.divergence_class)) continue;
      const id = badge.detail_ref;
      if (!id || st.filed[id]) continue; // no stable id, or already filed -- once per divergence lifetime

      const text = nlIssueMessageForBadge(askId, badge);
      try { await runCli(cliPath, [text], timeoutMs); } catch (_) { /* best-effort */ }
      st.filed[id] = { ts: nowTs, divergence_class: badge.divergence_class };
      changed = true;
    }
  }

  // Recurrence escalation -- computed from the PERSISTED filed-state (not
  // just this cycle's badges), grouped by divergence_class, counting
  // DISTINCT ids whose filed-ts falls within the rolling window.
  const nowMs = Date.now();
  const byClass = {};
  Object.keys(st.filed).forEach((id) => {
    const rec = st.filed[id];
    if (!rec || !rec.ts) return;
    const ageMs = nowMs - Date.parse(rec.ts);
    if (!(ageMs >= 0) || ageMs > NL_ISSUE_RECURRENCE_WINDOW_MS) return;
    const cls = rec.divergence_class;
    if (!byClass[cls]) byClass[cls] = [];
    byClass[cls].push(id);
  });

  const classes = Object.keys(byClass);
  for (let k = 0; k < classes.length; k++) {
    const cls = classes[k];
    const ids = byClass[cls];
    if (ids.length < NL_ISSUE_RECURRENCE_THRESHOLD) continue;
    if (st.escalated[cls]) continue; // ONE escalated summary filing per class, EVER

    const sortedIds = ids.slice().sort();
    const text = 'auditor RECURRENCE [' + cls + ']: ' + ids.length +
      ' distinct occurrences filed in the last 7 days (' + sortedIds.join(', ') +
      ') -- investigate the root cause, not just the individual instances.';
    try { await runCli(cliPath, [text], timeoutMs); } catch (_) { /* best-effort */ }
    st.escalated[cls] = { ts: nowTs, count: ids.length, ids: sortedIds };
    changed = true;
  }

  if (changed) saveNlIssueState(statePath, st);
}

// ========================================================================
// QUARANTINE AUTO-DEFECT (cockpit-roadmap-redesign Task 4, A8) -- files ONE
// nl-issue defect per context-less needs-you ledger item, ONCE per item
// lifetime, in the AUDITOR CYCLE ONLY (never on render -- the Inbox view,
// server/inbox-routes.js, only ever READS whether a defect has already been
// filed via readAuditorFiledIds(); it never files one itself). Reuses the
// SAME filed-once + recurrence-escalation state (auditorNlIssueStatePath())
// fileNlIssueDivergences() already maintains above -- a quarantine's
// detail_ref ('quarantine-<ledger id>') is namespaced distinctly from every
// ask-drift detail_ref ('drift-<askId>-...'), so the two classes share one
// state file with zero collision risk.
//
// KEYING (A8): "keyed by ledger item id" -- ALWAYS `item.id` (the needs-you
// NY-... id), regardless of whether the item carries a `session` (a
// producing session) or not. A "legacy no-producer item" (no session field,
// or a session that no longer resolves to anything) files against the
// SAME ledger id -- there is no separate "unknown producer" bucket, per the
// plan's own "legacy no-producer items file against the ledger id" clause.
//
// RECURRENCE: identical shape to fileNlIssueDivergences's own recurrence
// block (3+ distinct ids within a rolling 7-day window -> ONE escalated
// summary note, ever, per class) -- scoped to this ONE class
// ('quarantined_no_context') since quarantine ids never mix with ask-drift
// classes in the SAME class-bucket scan.
// ========================================================================
const NEEDS_YOU_QUARANTINE_CLASS = 'quarantined_no_context';

// quarantinedLedgerItems(items) -- the SAME context-contract test
// server/inbox-routes.js applies (I4/A8): an OPEN 'decision' item whose
// lint_warnings (stamped by needs-you.sh's cold-reader lint AT ADD TIME) is
// non-empty. 'question' items are never quarantined (the lint is scoped to
// --section decision only).
function quarantinedLedgerItems(items) {
  return (items || []).filter((it) => it && it.state === 'open' && it.section === 'decision' &&
    Array.isArray(it.lint_warnings) && it.lint_warnings.length > 0);
}

function nlIssueMessageForQuarantine(item) {
  const who = item.session ? ('session ' + item.session) : 'an unknown/legacy producer (no session recorded)';
  const warn = (item.lint_warnings || []).join(', ');
  return 'needs-you quarantine [' + NEEDS_YOU_QUARANTINE_CLASS + ']: item ' + item.id + ' (from ' + who +
    ') arrived without full context (' + warn + ') and is quarantined in the cockpit Inbox, excluded from its ' +
    'answerable count -- see NEEDS-YOU ledger id ' + item.id + '.';
}

// fileNeedsYouQuarantineDefects(ledgerItems, opts) -- mirrors
// fileNlIssueDivergences's exact shape/guards (sandbox-awareness, dedup,
// recurrence) but is intentionally a SEPARATE function rather than a
// refactor of that one: fileNlIssueDivergences is keyed by askId (its
// per-ask badge message names "ask <askId>"), while a quarantined item has
// no ask at all -- reusing it as-is would force an awkward synthetic askId
// into every quarantine message. Zero behavioral change to the
// already-tested fileNlIssueDivergences path.
async function fileNeedsYouQuarantineDefects(ledgerItems, opts) {
  if (process.env.AUDITOR_NL_ISSUE_DISABLED === '1') return;
  if (isNlIssueSandboxed()) return;

  const cliPath = opts.cliPath;
  const statePath = opts.statePath;
  const timeoutMs = opts.cliTimeoutMs;
  const st = loadNlIssueState(statePath);
  const nowTs = nowIso();
  let changed = false;

  const items = quarantinedLedgerItems(ledgerItems);
  for (let i = 0; i < items.length; i++) {
    const item = items[i];
    const id = 'quarantine-' + item.id; // keyed by ledger item id (A8) -- legacy no-producer items key the SAME way
    if (!item.id || st.filed[id]) continue; // no id to key on, or already filed -- ONCE per item lifetime
    const text = nlIssueMessageForQuarantine(item);
    try { await runCli(cliPath, [text], timeoutMs); } catch (_) { /* best-effort */ }
    st.filed[id] = { ts: nowTs, divergence_class: NEEDS_YOU_QUARANTINE_CLASS };
    changed = true;
  }

  // Recurrence escalation -- same rolling-window/threshold shape as
  // fileNlIssueDivergences, scoped to this one class.
  const nowMs = Date.now();
  const ids = [];
  Object.keys(st.filed).forEach((fid) => {
    const rec = st.filed[fid];
    if (!rec || rec.divergence_class !== NEEDS_YOU_QUARANTINE_CLASS || !rec.ts) return;
    const ageMs = nowMs - Date.parse(rec.ts);
    if (!(ageMs >= 0) || ageMs > NL_ISSUE_RECURRENCE_WINDOW_MS) return;
    ids.push(fid);
  });
  if (ids.length >= NL_ISSUE_RECURRENCE_THRESHOLD && !st.escalated[NEEDS_YOU_QUARANTINE_CLASS]) {
    const sortedIds = ids.slice().sort();
    const text = 'auditor RECURRENCE [' + NEEDS_YOU_QUARANTINE_CLASS + ']: ' + ids.length +
      ' distinct occurrences filed in the last 7 days (' + sortedIds.join(', ') +
      ') -- investigate the root cause (likely a specific producer emitting context-less decisions), not just the individual instances.';
    try { await runCli(cliPath, [text], timeoutMs); } catch (_) { /* best-effort */ }
    st.escalated[NEEDS_YOU_QUARANTINE_CLASS] = { ts: nowTs, count: ids.length, ids: sortedIds };
    changed = true;
  }

  if (changed) saveNlIssueState(statePath, st);
}

// ========================================================================
// createAuditor(userOpts) -- the auditor instance server.js mounts.
// ========================================================================
function createAuditor(userOpts) {
  userOpts = userOpts || {};

  const staticOpts = {
    cadenceMs: userOpts.cadenceMs || Number(process.env.AUDITOR_CADENCE_MS) || DEFAULT_CADENCE_MS,
    mergeScanLimit: userOpts.mergeScanLimit || Number(process.env.AUDITOR_MERGE_SCAN_LIMIT) || DEFAULT_MERGE_SCAN_LIMIT,
    cliTimeoutMs: userOpts.cliTimeoutMs || Number(process.env.AUDITOR_CLI_TIMEOUT_MS) || DEFAULT_CLI_TIMEOUT_MS,
    repoRoots: Array.isArray(userOpts.repoRoots) ? userOpts.repoRoots : null,
    progressLogCli: userOpts.progressLogCli || progressLogCliPath(),
    askRegistryCli: userOpts.askRegistryCli || askRegistryCliPath(),
    mergeScanLib: userOpts.mergeScanLib || mergeScanLibPath(),
    nlIssueCli: userOpts.nlIssueCli || nlIssueCliPath(),
  };

  // Dynamic resolvers -- re-read env/opts EVERY cycle, never memoized (see
  // header "SANDBOXING" note): a caller that sets PROGRESS_LOG_STATE_DIR /
  // ASK_REGISTRY_STATE_DIR / etc. AFTER createAuditor() was constructed
  // (server.selftest.js's own fixture setup does exactly this, ahead of its
  // first manual runCycle() call) is still honored.
  function rProgressLogStateDir() { return userOpts.progressLogStateDir || progressLogStateDir(); }
  function rAskRegistryFile() { return userOpts.askRegistryFile || askRegistryFile(); }
  function rNeedsYouMdPath() { return userOpts.needsYouMdPath || needsYouMdPath(); }
  function rOperatorTodoPath() { return userOpts.operatorTodoPath || operatorTodoPath(); }
  function rDispatchProvenanceDir() { return userOpts.dispatchProvenanceDir || dispatchProvenanceStateDir(); }
  function rMainRepoRoot() { return userOpts.mainRepoRoot || mainRepoRoot(); }
  function rAuditorNlIssueStatePath() { return userOpts.auditorNlIssueStatePath || auditorNlIssueStatePath(); }

  // repoRootsForCycle -- resolution order: (1) explicit `repoRoots` opt
  // (construction-time), (2) AUDITOR_REPO_ROOTS env var (path.delimiter-
  // separated — same idiom as PATH itself), checked FRESH each cycle so a
  // sandboxed caller (e.g. a self-test that wants to scan ONE small fixture
  // repo instead of every project config/projects.js's discovery walk would
  // otherwise find on the real machine) never pays that cost, (3) every
  // distinct root config/projects.js's loadProjects() map resolves to
  // (constraint: "the auditor iterates the repo roots from
  // config/projects.js's loadProjects() map ... not just this repo").
  function repoRootsForCycle() {
    if (staticOpts.repoRoots) return staticOpts.repoRoots.slice();
    if (process.env.AUDITOR_REPO_ROOTS) {
      const fromEnv = process.env.AUDITOR_REPO_ROOTS.split(path.delimiter).map((s) => s.trim()).filter(Boolean);
      if (fromEnv.length) return fromEnv;
    }
    try {
      const map = projects.loadProjects();
      const seen = new Set();
      const roots = [];
      Object.keys(map).forEach((k) => {
        let r;
        try { r = path.resolve(map[k]); } catch (_) { return; }
        if (!seen.has(r)) { seen.add(r); roots.push(r); }
      });
      return roots.length ? roots : [rMainRepoRoot()];
    } catch (_) { return [rMainRepoRoot()]; }
  }

  const state = {
    badgesByAsk: {},
    diagnostics: {
      last_cycle_ts: null,
      cycle_count: 0,
      last_cycle_duration_ms: null,
      healed_recent: [],
      backfill_errors: [],
      count_reconciliation: null,
    },
    _cycleInFlight: false,
    _timer: null,
  };

  function pushHealed(entry) {
    state.diagnostics.healed_recent.unshift(Object.assign({ ts: nowIso() }, entry));
    if (state.diagnostics.healed_recent.length > 200) state.diagnostics.healed_recent.length = 200;
  }
  function pushBackfillError(entry) {
    state.diagnostics.backfill_errors.unshift(Object.assign({ ts: nowIso() }, entry));
    if (state.diagnostics.backfill_errors.length > 100) state.diagnostics.backfill_errors.length = 100;
  }

  // runCycle() -- ONE full audit pass. Single-flight guarded (mirrors
  // derive-cache.js's DeriveCache._cycleInFlight): if a previous cycle is
  // still running (slow bash spawns, a large git-scan), this call is a
  // silent no-op rather than piling a second cycle on top -- the NEXT timer
  // tick simply runs once the current one finishes.
  async function runCycle() {
    if (state._cycleInFlight) return;
    state._cycleInFlight = true;
    const startedAt = Date.now();
    try {
      const progressLogDir = rProgressLogStateDir();
      const registryFile = rAskRegistryFile();
      const needsYouPath = rNeedsYouMdPath();
      const todoPath = rOperatorTodoPath();
      const dpDir = rDispatchProvenanceDir();
      const mainRoot = rMainRepoRoot();

      const registry = foldAskRegistry(registryFile);
      const planCache = {};
      function planLookup(repo, slug) {
        const key = (repo || '') + '::' + slug;
        if (Object.prototype.hasOwnProperty.call(planCache, key)) return planCache[key];
        const abs = resolvePlanAbsPath(repo, mainRoot, slug);
        const parsed = abs ? parsePlanFile(abs) : null;
        planCache[key] = parsed;
        return parsed;
      }

      const dispatchMarkers = readDispatchMarkers(dpDir);
      const dispatchEvidenceHorizonMs = dispatchMarkerEvidenceHorizonMs(dispatchMarkers, Date.now());
      const ny = readOpenNeedsYouIds(needsYouPath);
      const todo = readOperatorTodoPointers(todoPath);
      const allKnownNeedsYouIds = new Set(ny.ids);
      todo.pointers.forEach((p) => allKnownNeedsYouIds.add(p.needsYouId));

      const newBadgesByAsk = {};
      const backfillCalls = [];
      const setStatusAsks = [];
      const renderedWaitingIdSet = new Set();

      Object.keys(registry).forEach((askId) => {
        try {
          const reg = registry[askId];
          reg.ask_id = askId;
          const events = readAskEvents(progressLogDir, askId);
          const result = auditAsk(askId, reg, events, {
            planLookup: (slug) => planLookup(reg.repo || '', slug),
            dispatchMarkers: dispatchMarkers,
            allKnownNeedsYouIds: allKnownNeedsYouIds,
            dispatchEvidenceHorizonMs: dispatchEvidenceHorizonMs,
          });
          newBadgesByAsk[askId] = result.badges;
          result.backfillTaskDoneList.forEach((b) => backfillCalls.push(Object.assign({ askId: askId }, b)));
          result.healed.forEach(pushHealed);
          if (result.setStatusDoneNeeded) setStatusAsks.push(askId);

          events.forEach((e) => {
            if (e && e.type === 'waiting_on_operator' && e.needs_you_id && ny.ids.has(e.needs_you_id)) {
              renderedWaitingIdSet.add(e.needs_you_id);
            }
          });
        } catch (_) { /* one bad ask must never wedge the whole cycle */ }
      });

      // Side effects: sequential (never parallel-fan-out bash spawns --
      // keeps peak concurrency low, the same lesson derive-cache.js's
      // refreshAll lane-split already encodes for this codebase).
      for (let i = 0; i < backfillCalls.length; i++) {
        const b = backfillCalls[i];
        try {
          const r = await backfillTaskDone(staticOpts.progressLogCli, b.askId, b.planSlug, b.taskId, b.evidenceAbsPath, staticOpts.cliTimeoutMs);
          if (!r.ok) pushBackfillError({ kind: 'task_done', ask_id: b.askId, plan_slug: b.planSlug, task_id: b.taskId, stderr: r.stderr });
        } catch (e) { pushBackfillError({ kind: 'task_done', ask_id: b.askId, plan_slug: b.planSlug, task_id: b.taskId, stderr: String(e && e.message || e) }); }
      }
      for (let i = 0; i < setStatusAsks.length; i++) {
        const askId = setStatusAsks[i];
        try {
          const r = await backfillAskDone(staticOpts.askRegistryCli, askId, staticOpts.cliTimeoutMs);
          if (!r.ok) pushBackfillError({ kind: 'set_status_done', ask_id: askId, stderr: r.stderr });
          else pushHealed({ kind: 'ask_set_done_applied', ask_id: askId });
        } catch (e) { pushBackfillError({ kind: 'set_status_done', ask_id: askId, stderr: String(e && e.message || e) }); }
      }

      // Class C: NEEDS-YOU-resolved pointer auto-check. "Resolved" = a
      // pointer id that is NOT (any longer) in the currently-open set.
      try {
        const resolvedIds = new Set();
        todo.pointers.forEach((p) => { if (!ny.ids.has(p.needsYouId)) resolvedIds.add(p.needsYouId); });
        if (resolvedIds.size) {
          const r = autoCheckOperatorTodo(todoPath, resolvedIds);
          if (r.changed) pushHealed({ kind: 'operator_todo_pointer_autochecked', count: r.checkedCount });
        }
      } catch (_) { /* best-effort; never wedges the cycle */ }

      // Class B: merged backfill via the GUARANTEED lane (Task 5b),
      // sequential across every distinct repo root config/projects.js
      // knows about.
      const roots = repoRootsForCycle();
      for (let i = 0; i < roots.length; i++) {
        try { await scanRepoForMerges(staticOpts.mergeScanLib, roots[i], staticOpts.mergeScanLimit, staticOpts.cliTimeoutMs); }
        catch (_) { /* best-effort */ }
      }

      // C3b (Task 7): file this cycle's REAL log-ahead badges into
      // nl-issue.sh (dedup + recurrence escalation) -- see the block
      // comment at fileNlIssueDivergences() above for the full contract.
      // Runs LAST, once every badge for this cycle is final in
      // newBadgesByAsk; never wedges the cycle on a failure.
      try {
        await fileNlIssueDivergences(newBadgesByAsk, {
          cliPath: staticOpts.nlIssueCli,
          statePath: rAuditorNlIssueStatePath(),
          cliTimeoutMs: staticOpts.cliTimeoutMs,
        });
      } catch (_) { /* best-effort; never wedges the cycle */ }

      // A8 (Task 4): file the auto-defect for every context-less
      // ("quarantined") needs-you decision item, in THIS cycle only (never
      // on render — server/inbox-routes.js only ever READS whether a
      // defect has been filed, via the same state file). Reuses the exact
      // filed-once + recurrence-escalation state fileNlIssueDivergences
      // just wrote to above — see fileNeedsYouQuarantineDefects's own
      // header for why this is a sibling function rather than a reuse of
      // that one's per-ask shape.
      try {
        const ledgerItems = readNeedsYouLedgerItems();
        await fileNeedsYouQuarantineDefects(ledgerItems, {
          cliPath: staticOpts.nlIssueCli,
          statePath: rAuditorNlIssueStatePath(),
          cliTimeoutMs: staticOpts.cliTimeoutMs,
        });
      } catch (_) { /* best-effort; never wedges the cycle */ }

      // §8-3 count reconciliation -- see header for why this is
      // diagnostics-only (never a per-card badge, never a landing banner).
      // HONEST LIMITATION: this metric intersects `renderedWaitingIdSet`
      // against `ny.ids` (the parsed open-decision set), so a total parse
      // regression (e.g. the "## Awaiting your decision" header string is
      // renamed and `extractMdSection` never captures anything) would make
      // BOTH sides collapse to 0 and read as a trivial "match" rather than
      // a visible mismatch. In practice this is still caught INDIRECTLY:
      // Class G's `allKnownNeedsYouIds` ground-truth set also includes
      // every id ever seen in an operator-todo.md pointer bullet (written
      // by needs-you.sh's `add` at the SAME moment as the ledger entry,
      // independent of NEEDS-YOU.md's later renderability), so a genuinely
      // open decision that predates the parse breakage still resolves via
      // Class G's `orphaned_waiting_item` badge instead of vanishing
      // silently -- but a decision added AFTER the breakage, with no other
      // ask ever referencing it, would not be caught by either mechanism.
      // Flagged here rather than silently assumed complete.
      const unaccounted = [];
      ny.ids.forEach((id) => { if (!renderedWaitingIdSet.has(id)) unaccounted.push(id); });
      state.diagnostics.count_reconciliation = {
        checked_at: nowIso(),
        ledger_open_count: ny.available ? ny.ids.size : null,
        rendered_waiting_count: renderedWaitingIdSet.size,
        mismatch: ny.available ? (ny.ids.size !== renderedWaitingIdSet.size) : false,
        unaccounted_needs_you_ids: unaccounted,
      };

      state.badgesByAsk = newBadgesByAsk;
      state.diagnostics.cycle_count += 1;
      state.diagnostics.last_cycle_ts = nowIso();
      state.diagnostics.last_cycle_duration_ms = Date.now() - startedAt;
    } finally {
      state._cycleInFlight = false;
    }
  }

  function start() {
    // AUDITOR_DISABLED=1 — the ONE opt-out gate, checked at start()-call
    // time (not at createAuditor() construction time), so a caller can set
    // it any time before start() is reached and have it honored. Exists
    // because server.js constructs + starts the auditor at require/listen
    // time, BEFORE a harness like server.selftest.js gets a chance to point
    // every state path at its own sandbox (that env-var setup happens deep
    // inside main(), well after `require('./server.js')` already triggered
    // 'listening' -> auditor.start()) -- without this gate, running the
    // existing server self-test would fire a REAL auditor cycle against
    // production ~/.claude/state and real git repos before any sandboxing
    // env var is set (constraint 4 / "self-test pollution is a defect").
    // Production never sets this.
    if (process.env.AUDITOR_DISABLED === '1') return;
    runCycle().catch(() => {});
    state._timer = setInterval(() => { runCycle().catch(() => {}); }, staticOpts.cadenceMs);
    if (state._timer.unref) state._timer.unref();
  }
  function stop() {
    if (state._timer) clearInterval(state._timer);
    state._timer = null;
  }

  // getBadgesForAsk(askId) -- the ONLY thing server.js's payload-schema-
  // validated routes read: a flat, schema-safe array (no gate/hook
  // identifiers, no internal script/emitter names beyond what the badge
  // shape already allows) scoped to exactly this ask (constraint 1/9).
  function getBadgesForAsk(askId) { return (state.badgesByAsk[askId] || []).slice(); }

  // getDiagnostics() -- the UNRESTRICTED internal state, for a future
  // Harness-Health/diagnostics-tab consumer (Task 16) -- deliberately NOT
  // schema-validated (like the existing /api/reconciler endpoint), since
  // the diagnostics surface is explicitly exempt from the landing anti-
  // noise law (constraint 1 governs the LANDING payload/DOM only).
  function getDiagnostics() {
    return {
      ok: true,
      cadence_ms: staticOpts.cadenceMs,
      last_cycle_ts: state.diagnostics.last_cycle_ts,
      cycle_count: state.diagnostics.cycle_count,
      last_cycle_duration_ms: state.diagnostics.last_cycle_duration_ms,
      healed_recent: state.diagnostics.healed_recent,
      backfill_errors: state.diagnostics.backfill_errors,
      count_reconciliation: state.diagnostics.count_reconciliation,
      badges_by_ask: state.badgesByAsk,
    };
  }

  return {
    start: start,
    stop: stop,
    runCycle: runCycle,
    getBadgesForAsk: getBadgesForAsk,
    getDiagnostics: getDiagnostics,
    _state: state,
    _opts: staticOpts,
  };
}

module.exports = {
  createAuditor: createAuditor,
  auditAsk: auditAsk,
  parsePlanFile: parsePlanFile,
  resolvePlanAbsPath: resolvePlanAbsPath,
  readOpenNeedsYouIds: readOpenNeedsYouIds,
  readOperatorTodoPointers: readOperatorTodoPointers,
  autoCheckOperatorTodo: autoCheckOperatorTodo,
  foldAskRegistry: foldAskRegistry,
  readAskEvents: readAskEvents,
  readDispatchMarkers: readDispatchMarkers,
  dispatchMarkerEvidenceHorizonMs: dispatchMarkerEvidenceHorizonMs,
  dispatchProvenanceTtlDays: dispatchProvenanceTtlDays,
  dispatchProvenanceMaxMarkers: dispatchProvenanceMaxMarkers,
  DEFAULT_CADENCE_MS: DEFAULT_CADENCE_MS,
  // path resolvers exported for the self-test / a future diagnostics reader
  progressLogStateDir: progressLogStateDir,
  askRegistryFile: askRegistryFile,
  needsYouMdPath: needsYouMdPath,
  operatorTodoPath: operatorTodoPath,
  dispatchProvenanceStateDir: dispatchProvenanceStateDir,
  mergeScanLibPath: mergeScanLibPath,
  progressLogCliPath: progressLogCliPath,
  askRegistryCliPath: askRegistryCliPath,
  // C3b (Task 7) exports -- for the self-test / a future diagnostics reader.
  nlIssueCliPath: nlIssueCliPath,
  auditorNlIssueStatePath: auditorNlIssueStatePath,
  fileNlIssueDivergences: fileNlIssueDivergences,
  NL_ISSUE_BADGE_CLASSES: NL_ISSUE_BADGE_CLASSES,
  isNlIssueSandboxed: isNlIssueSandboxed,
  // A8 (Task 4) exports -- for the self-test / server/inbox-routes.js's
  // read-only "has a defect been filed yet" check.
  needsYouStateDir: needsYouStateDir,
  needsYouLedgerFile: needsYouLedgerFile,
  readNeedsYouLedgerItems: readNeedsYouLedgerItems,
  quarantinedLedgerItems: quarantinedLedgerItems,
  nlIssueMessageForQuarantine: nlIssueMessageForQuarantine,
  fileNeedsYouQuarantineDefects: fileNeedsYouQuarantineDefects,
  NEEDS_YOU_QUARANTINE_CLASS: NEEDS_YOU_QUARANTINE_CLASS,
};

// ============================================================
// --self-test (only runs when this file is EXECUTED directly, e.g.
// `node auditor.js --self-test`) -- sandboxed under its own mktemp dir;
// never touches real ~/.claude/state or a real repo's docs/. Exercises
// every divergence-class row against REAL mechanism CLIs (progress-log.sh,
// ask-registry.sh, merge-scan-lib.sh) shelled exactly as production does,
// plus the pure auditAsk() unit-level cases and the latency-unaffected
// assertion (Prove-it-works #4).
// ============================================================
if (require.main === module) {
  const arg = process.argv[2];
  if (arg === '--self-test' || arg === '--selftest') {
    selfTest().then((failed) => process.exit(failed ? 1 : 0)).catch((err) => {
      console.error('self-test crashed:', err);
      process.exit(1);
    });
  } else if (arg === '--run-once') {
    const a = createAuditor();
    a.runCycle().then(() => {
      console.log(JSON.stringify(a.getDiagnostics(), null, 2));
      process.exit(0);
    }).catch((err) => { console.error(err); process.exit(1); });
  }
}

async function selfTest() {
  let PASSED = 0, FAILED = 0;
  function ok(name, cond, detail) {
    if (cond) { PASSED++; console.log('  PASS: ' + name); }
    else { FAILED++; console.log('  FAIL: ' + name + (detail ? ' (' + detail + ')' : '')); }
  }

  const { spawnSync } = require('child_process');
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'auditor-selftest-'));
  const plDir = path.join(tmp, 'progress-logs');
  const arDir = path.join(tmp, 'ar-state');
  const dpDir = path.join(tmp, 'dispatch-provenance');
  const repoDir = path.join(tmp, 'main-repo');
  fs.mkdirSync(plDir, { recursive: true });
  fs.mkdirSync(arDir, { recursive: true });
  fs.mkdirSync(dpDir, { recursive: true });
  fs.mkdirSync(path.join(repoDir, 'docs', 'plans'), { recursive: true });
  const needsYouPath = path.join(repoDir, 'NEEDS-YOU.md');
  const todoPath = path.join(repoDir, 'docs', 'operator-todo.md');
  // Task 4 (A8): the auditor's runCycle() now ALSO reads NEEDS_YOU_STATE_DIR's
  // ledger.json every cycle (fileNeedsYouQuarantineDefects) -- sandboxed to an
  // EMPTY dir here from the very start of this self-test (no ledger.json ->
  // readNeedsYouLedgerItems() returns [], a no-op) so every PRE-EXISTING
  // scenario below (S1-S8, none of which know or care about needs-you
  // quarantine) never accidentally reads the REAL machine's
  // $HOME/.claude/state/needs-you/ledger.json. Scenario 9 below points this
  // at its OWN fixture ledger for the duration of that scenario only, then
  // restores it back to this same empty default.
  const nyStateDirDefault = path.join(tmp, 'ny-state-default');
  fs.mkdirSync(nyStateDirDefault, { recursive: true });

  process.env.HARNESS_SELFTEST = '1';
  process.env.PROGRESS_LOG_STATE_DIR = plDir;
  process.env.ASK_REGISTRY_STATE_DIR = arDir;
  process.env.ASK_REGISTRY_MIRROR_PATH = path.join(tmp, 'mirror-unused', 'ask-registry.jsonl');
  process.env.DISPATCH_PROVENANCE_STATE_DIR = dpDir;
  process.env.NEEDS_YOU_MD_PATH = needsYouPath;
  process.env.OPERATOR_TODO_PATH = todoPath;
  process.env.NEEDS_YOU_STATE_DIR = nyStateDirDefault;

  function writeRegistry(lines) {
    fs.writeFileSync(path.join(arDir, 'ask-registry.jsonl'), lines.map((o) => JSON.stringify(o)).join('\n') + '\n');
  }
  function regLine(fields) {
    return Object.assign({
      ask_id: '', record_type: '', ts: '', user: 't', machine: 'm', repo: '', project: '',
      summary: '', verbatim_ref: '', origin_session: '', status: '', plan_slug: '',
      session_id: '', resumed_from: '', merged_into: '', emitter: 'ask-registry',
    }, fields);
  }

  const auditor = createAuditor({
    progressLogStateDir: plDir,
    askRegistryFile: path.join(arDir, 'ask-registry.jsonl'),
    needsYouMdPath: needsYouPath,
    operatorTodoPath: todoPath,
    dispatchProvenanceDir: dpDir,
    mainRepoRoot: repoDir,
    repoRoots: [repoDir],
    cliTimeoutMs: 90000,
  });

  // ======================================================================
  // Scenario 1 (Class A -- truth ahead of log): a sandbox plan task is
  // flipped `- [x]` but its task_done event was deleted -- within one
  // cycle the auditor BACKFILLS task_done with emitter=auditor (heals, no
  // permanent badge).
  // ======================================================================
  const slugA = 'auditor-fixture-a';
  const planAPath = path.join(repoDir, 'docs', 'plans', slugA + '.md');
  fs.writeFileSync(planAPath, [
    '# Plan: Fixture A',
    'Status: ACTIVE',
    '',
    '- [x] 1. task one, done in the file.',
    '- [ ] 2. task two, not started.',
    '',
  ].join('\n'));
  writeRegistry([
    regLine({ ask_id: 'ask-a', record_type: 'created', ts: '2026-01-01T00:00:00Z', repo: repoDir, project: 'demo', summary: 'fixture a', status: 'active' }),
    regLine({ ask_id: 'ask-a', record_type: 'plan_linked', ts: '2026-01-01T00:01:00Z', plan_slug: slugA }),
  ]);
  // No task_done event exists yet for ask-a at all.
  await auditor.runCycle();
  const askAFile = path.join(plDir, 'ask-a.jsonl');
  const askAEvents = fs.existsSync(askAFile) ? readJsonlLines(askAFile) : [];
  ok('S1 truth-ahead-of-log (checkbox done, no event) BACKFILLS task_done with emitter=auditor',
    askAEvents.some((e) => e.type === 'task_done' && e.task_id === '1' && e.plan_slug === slugA && e.emitter === 'auditor'),
    JSON.stringify(askAEvents));
  ok('S1b the backfilled task is HEALED -- no permanent badge for it',
    !auditor.getBadgesForAsk('ask-a').some((b) => b.task_id === '1'),
    JSON.stringify(auditor.getBadgesForAsk('ask-a')));
  const diag1 = auditor.getDiagnostics();
  ok('S1c the backfill is recorded in diagnostics.healed_recent',
    diag1.healed_recent.some((h) => h.kind === 'task_done_backfilled' && h.ask_id === 'ask-a' && h.task_id === '1'));

  // Re-run: idempotent, no duplicate backfill line, still no badge.
  await auditor.runCycle();
  const askAEvents2 = readJsonlLines(askAFile);
  ok('S1d re-running the cycle does not duplicate the backfilled event (natural-key dedup holds)',
    askAEvents2.filter((e) => e.type === 'task_done' && e.task_id === '1').length === 1,
    JSON.stringify(askAEvents2));

  // ======================================================================
  // Scenario 2 (Class E -- log ahead of truth): inject a task_done event
  // for task 2 whose checkbox is still unflipped -> a permanent drift
  // badge, and the checkbox is NEVER auto-flipped (constraint 6).
  // ======================================================================
  const emitCli = progressLogCliPath();
  const emitRes = spawnSync(bashBin(), [emitCli, 'emit', '--type', 'task_done', '--ask', 'ask-a',
    '--plan-slug', slugA, '--task-id', '2', '--sha', 'deadbeef', '--summary', 'task 2 verified done',
    '--evidence-link', planAPath, '--emitter', 'plan-lifecycle'], { env: spawnEnv(), encoding: 'utf8' });
  ok('S2 (setup) real progress-log.sh emit for task 2 succeeded', emitRes.status === 0, emitRes.stderr);

  await auditor.runCycle();
  ok('S2b log-ahead-of-truth (event exists, checkbox unflipped) produces a drift badge for task 2',
    auditor.getBadgesForAsk('ask-a').some((b) => b.divergence_class === 'log_ahead_task_not_flipped' && b.task_id === '2' && !!b.detail_ref),
    JSON.stringify(auditor.getBadgesForAsk('ask-a')));
  const planAAfter = fs.readFileSync(planAPath, 'utf8');
  ok('S2c the auditor NEVER flips the checkbox itself (constraint 6) -- task 2 still reads `- [ ]`',
    /- \[ \] 2\./.test(planAAfter), planAAfter);

  await auditor.runCycle();
  ok('S2d the badge persists (never un-emitted, never one-shot) across a second cycle',
    auditor.getBadgesForAsk('ask-a').some((b) => b.divergence_class === 'log_ahead_task_not_flipped' && b.task_id === '2'));

  // ======================================================================
  // Scenario 2e-2i (C3b, Task 7): the auditor's REAL log-ahead divergences
  // wired into nl-issue.sh -- dedup, sandbox-awareness, and recurrence
  // escalation. Reuses the S2 fixture's already-persistent
  // log_ahead_task_not_flipped badge for ask-a task 2 (still present --
  // S2d just proved it survives a second cycle) as the "one real badge" to
  // file.
  //
  // This self-test itself runs with HARNESS_SELFTEST=1 set globally (see
  // the top of this function) -- which is EXACTLY one of the two sandbox
  // signals isNlIssueSandboxed() checks. S2e/S2f/S2h/S2i below temporarily
  // clear it (and confirm AUDITOR_DISABLED is not set, which it never is
  // in this file's own self-test) to exercise the REAL, un-sandboxed
  // filing path -- restored to '1' immediately after, before Scenario 3
  // resumes, so every OTHER cycle in this self-test stays exactly as
  // sandboxed as before this task existed.
  // ======================================================================
  const nlLedger1 = path.join(tmp, 'nl-issues-s2e.jsonl');
  const nlState1 = path.join(tmp, 'nl-issue-state-s2e.json');
  delete process.env.HARNESS_SELFTEST;
  process.env.NL_ISSUES_PATH = nlLedger1;
  process.env.AUDITOR_NL_ISSUE_STATE_PATH = nlState1;

  await auditor.runCycle();
  const ledger1Lines = fs.existsSync(nlLedger1) ? readJsonlLines(nlLedger1) : [];
  ok('S2e un-sandboxed: the persistent log-ahead badge for ask-a task 2 files EXACTLY ONE real nl-issue.sh entry',
    ledger1Lines.length === 1 && /log_ahead_task_not_flipped/.test(ledger1Lines[0].text || '') && /ask-a/.test(ledger1Lines[0].text || ''),
    JSON.stringify(ledger1Lines));
  ok('S2e2 the auditor\'s OWN dedup state file recorded the divergence id as filed',
    fs.existsSync(nlState1) && Object.keys(JSON.parse(fs.readFileSync(nlState1, 'utf8')).filed || {}).some((id) => /log-ahead-auditor-fixture-a-2/.test(id)),
    fs.existsSync(nlState1) ? fs.readFileSync(nlState1, 'utf8') : '(missing)');

  await auditor.runCycle();
  const ledger1LinesAfter = fs.existsSync(nlLedger1) ? readJsonlLines(nlLedger1) : [];
  ok('S2f a SECOND cycle over the SAME still-open badge does NOT re-file (one filing per divergence lifetime, not per cycle)',
    ledger1LinesAfter.length === 1, JSON.stringify(ledger1LinesAfter));

  // ---- S2g: sandbox mode (HARNESS_SELFTEST=1 restored) -> NO filing at
  // all, even though the exact same badge is still present.
  const nlLedger2 = path.join(tmp, 'nl-issues-s2g.jsonl');
  const nlState2 = path.join(tmp, 'nl-issue-state-s2g.json');
  process.env.HARNESS_SELFTEST = '1';
  process.env.NL_ISSUES_PATH = nlLedger2;
  process.env.AUDITOR_NL_ISSUE_STATE_PATH = nlState2;
  await auditor.runCycle();
  ok('S2g sandbox mode (HARNESS_SELFTEST=1) files NOTHING, even with a real eligible badge present',
    !fs.existsSync(nlLedger2), fs.existsSync(nlLedger2) ? fs.readFileSync(nlLedger2, 'utf8') : '(absent, as expected)');

  // ---- S2h: recurrence escalation. Un-sandbox again, fresh ledger/state,
  // and give the SAME divergence class a 3rd distinct id (tasks 3 and 4
  // added to plan A, real progress-log.sh emit each, checkbox left
  // unflipped) -- combined with the pre-existing task-2 badge, this cycle
  // sees 3 DISTINCT log_ahead_task_not_flipped ids for the FIRST time under
  // this fresh state file, which must fire exactly one extra escalation
  // filing alongside the 3 individual ones (4 ledger lines total).
  fs.appendFileSync(planAPath, '- [ ] 3. task three, not started.\n- [ ] 4. task four, not started.\n');
  ['3', '4'].forEach((taskId) => {
    const r = spawnSync(bashBin(), [emitCli, 'emit', '--type', 'task_done', '--ask', 'ask-a',
      '--plan-slug', slugA, '--task-id', taskId, '--sha', 'deadbeef' + taskId,
      '--summary', 'task ' + taskId + ' verified done', '--evidence-link', planAPath,
      '--emitter', 'plan-lifecycle'], { env: spawnEnv(), encoding: 'utf8' });
    ok('S2h (setup) real progress-log.sh emit for task ' + taskId + ' succeeded', r.status === 0, r.stderr);
  });
  const nlLedger3 = path.join(tmp, 'nl-issues-s2h.jsonl');
  const nlState3 = path.join(tmp, 'nl-issue-state-s2h.json');
  delete process.env.HARNESS_SELFTEST;
  process.env.NL_ISSUES_PATH = nlLedger3;
  process.env.AUDITOR_NL_ISSUE_STATE_PATH = nlState3;

  await auditor.runCycle();
  ok('S2h2 3 distinct badges now exist for ask-a (tasks 2, 3, 4) under log_ahead_task_not_flipped',
    ['2', '3', '4'].every((tid) => auditor.getBadgesForAsk('ask-a').some((b) => b.divergence_class === 'log_ahead_task_not_flipped' && b.task_id === tid)));
  const ledger3Lines = fs.existsSync(nlLedger3) ? readJsonlLines(nlLedger3) : [];
  ok('S2h3 escalation at 3: exactly 4 ledger lines (3 individual filings + 1 escalation summary)',
    ledger3Lines.length === 4, JSON.stringify(ledger3Lines.map((l) => l.text)));
  ok('S2h4 exactly one of the 4 lines is the RECURRENCE escalation summary, naming the divergence class + a count of 3',
    ledger3Lines.filter((l) => /RECURRENCE/.test(l.text || '') && /log_ahead_task_not_flipped/.test(l.text || '') && /\b3\b/.test(l.text || '')).length === 1,
    JSON.stringify(ledger3Lines.map((l) => l.text)));
  const state3 = JSON.parse(fs.readFileSync(nlState3, 'utf8'));
  ok('S2h5 the state file marks the class permanently escalated', !!(state3.escalated && state3.escalated.log_ahead_task_not_flipped));

  await auditor.runCycle();
  const ledger3LinesAfter = fs.existsSync(nlLedger3) ? readJsonlLines(nlLedger3) : [];
  ok('S2i a SECOND cycle over the SAME 3 badges does NOT re-escalate (still exactly 4 lines, not 5) -- ONE escalated summary filing, ever, per class',
    ledger3LinesAfter.length === 4, JSON.stringify(ledger3LinesAfter.map((l) => l.text)));

  // ---- S2j: the env kill-switch suppresses filing even when NOT sandboxed
  // (a fresh ledger/state, un-sandboxed, but AUDITOR_NL_ISSUE_DISABLED=1).
  const nlLedger4 = path.join(tmp, 'nl-issues-s2j.jsonl');
  const nlState4 = path.join(tmp, 'nl-issue-state-s2j.json');
  process.env.NL_ISSUES_PATH = nlLedger4;
  process.env.AUDITOR_NL_ISSUE_STATE_PATH = nlState4;
  process.env.AUDITOR_NL_ISSUE_DISABLED = '1';
  await auditor.runCycle();
  ok('S2j AUDITOR_NL_ISSUE_DISABLED=1 kill-switch files NOTHING even when un-sandboxed with real eligible badges present',
    !fs.existsSync(nlLedger4), fs.existsSync(nlLedger4) ? fs.readFileSync(nlLedger4, 'utf8') : '(absent, as expected)');
  delete process.env.AUDITOR_NL_ISSUE_DISABLED;

  // Restore the default sandbox posture for every scenario after this point.
  process.env.HARNESS_SELFTEST = '1';
  delete process.env.NL_ISSUES_PATH;
  delete process.env.AUDITOR_NL_ISSUE_STATE_PATH;

  // ======================================================================
  // Scenario 3 (Class C -- NEEDS-YOU resolved, pointer unchecked): a
  // pointer bullet in operator-todo.md whose needs-you id is OPEN stays
  // unchecked; once the id is no longer open, the pointer auto-checks.
  // ======================================================================
  fs.writeFileSync(needsYouPath, [
    '# NEEDS-YOU',
    '',
    '## Awaiting your decision',
    '',
    '### Ship tonight?',
    'Some context body line that is reasonably long for the §3 lint.',
    'Links: (none)',
    '*(added 2026-01-01, session `sess-x`, id `NY-100`)*',
    '',
  ].join('\n'));
  fs.writeFileSync(todoPath, [
    '# Operator To-Do',
    '',
    '## Operator items',
    '',
    '_(add your own free-form to-do items in this section — never overwritten)_',
    '',
    AUTO_START,
    '- [ ] AUTO: decision waiting on operator — "Ship tonight?" (needs-you `NY-100`, tier untiered, session `sess-x`) — see NEEDS-YOU.md',
    AUTO_END,
    '',
  ].join('\n'));

  await auditor.runCycle();
  const todoAfterOpen = fs.readFileSync(todoPath, 'utf8');
  ok('S3 pointer stays UNCHECKED while its needs-you id is still open',
    /- \[ \] AUTO: .*NY-100/.test(todoAfterOpen), todoAfterOpen);

  // Resolve NY-100 (remove it from the open section, simulating cmd_resolve).
  fs.writeFileSync(needsYouPath, [
    '# NEEDS-YOU',
    '',
    '## Awaiting your decision',
    '',
    '',
  ].join('\n'));
  await auditor.runCycle();
  const todoAfterResolve = fs.readFileSync(todoPath, 'utf8');
  ok('S3b pointer AUTO-CHECKS once its needs-you id is no longer open (derived resolution, ledger authoritative)',
    /- \[x\] AUTO: .*NY-100/.test(todoAfterResolve), todoAfterResolve);
  ok('S3c the operator-authored section above the AUTO markers is untouched',
    /## Operator items/.test(todoAfterResolve) && /never overwritten/.test(todoAfterResolve));

  // ======================================================================
  // Scenario 3d (§8-3 count reconciliation): an open NEEDS-YOU decision
  // with NO waiting_on_operator event referencing it anywhere (never
  // attached to any ask's log) is a mismatch -- surfaced ONLY in
  // diagnostics.count_reconciliation, never as a per-ask badge and never a
  // landing-page banner (anti-noise).
  // ======================================================================
  fs.writeFileSync(needsYouPath, [
    '# NEEDS-YOU', '', '## Awaiting your decision', '',
    '### Orphaned decision', 'A body line long enough for the §3 lint to consider it real context.',
    'Links: (none)', '*(added 2026-01-02, session `sess-orphan`, id `NY-200`)*', '',
  ].join('\n'));
  await auditor.runCycle();
  const diag3d = auditor.getDiagnostics();
  ok('S3d an open decision with no matching waiting_on_operator event ANYWHERE produces a count mismatch',
    diag3d.count_reconciliation && diag3d.count_reconciliation.mismatch === true &&
    diag3d.count_reconciliation.unaccounted_needs_you_ids.indexOf('NY-200') !== -1,
    JSON.stringify(diag3d.count_reconciliation));
  ok('S3e the mismatch is NOT rendered as a per-ask badge (diagnostics-only, never a landing banner)',
    Object.keys(auditor._state.badgesByAsk).every((askId) => !auditor.getBadgesForAsk(askId).some((b) => /NY-200/.test(b.detail_ref || ''))));

  // ======================================================================
  // Scenario 4 (Class B -- merged backfill via the GUARANTEED lane): a real
  // git fixture repo with a `plan: <slug>` trailer commit and a faked
  // origin/master ref -- mirrors merge-scan-lib.sh's own self-test fixture.
  // ======================================================================
  const slugM = 'auditor-fixture-merge';
  fs.mkdirSync(path.join(repoDir, 'docs', 'plans'), { recursive: true });
  fs.writeFileSync(path.join(repoDir, 'docs', 'plans', slugM + '.md'), [
    '# Plan: Merge fixture', 'Status: ACTIVE', 'ask-id: ask-merge-fixture', '',
    '## Tasks', '- [ ] 1. first task', '',
  ].join('\n'));
  spawnSync('git', ['init', '-q'], { cwd: repoDir });
  spawnSync('git', ['config', 'core.hooksPath', ''], { cwd: repoDir });
  spawnSync('git', ['config', 'user.email', 't@example.test'], { cwd: repoDir });
  spawnSync('git', ['config', 'user.name', 'T'], { cwd: repoDir });
  spawnSync('git', ['add', '.'], { cwd: repoDir });
  spawnSync('git', ['commit', '-q', '-m', 'init fixture repo'], { cwd: repoDir });
  fs.appendFileSync(path.join(repoDir, 'docs', 'plans', slugM + '.md'), '\nchange\n');
  spawnSync('git', ['commit', '-q', '-am', 'fix(auditor-fixture-merge): flip task 1\n\nplan: ' + slugM], { cwd: repoDir });
  const headSha = spawnSync('git', ['rev-parse', 'HEAD'], { cwd: repoDir, encoding: 'utf8' }).stdout.trim();
  spawnSync('git', ['update-ref', 'refs/remotes/origin/master', headSha], { cwd: repoDir });

  await auditor.runCycle();
  const mergeAskFile = path.join(plDir, 'ask-merge-fixture.jsonl');
  const mergeEvents = fs.existsSync(mergeAskFile) ? readJsonlLines(mergeAskFile) : [];
  ok('S4 the GUARANTEED merge-scan lane backfilled a merged event with the real HEAD sha',
    mergeEvents.some((e) => e.type === 'merged' && e.sha === headSha && e.emitter === 'auditor'),
    JSON.stringify(mergeEvents) + ' expectedSha=' + headSha);

  // ======================================================================
  // Scenario 5 (Class D -- mechanical ask exit): all linked plans terminal
  // (Status: COMPLETED), ask still active -> ask-registry.sh set-status
  // done, emitter=auditor.
  // ======================================================================
  const slugD = 'auditor-fixture-done';
  fs.writeFileSync(path.join(repoDir, 'docs', 'plans', slugD + '.md'), [
    '# Plan: Done fixture', 'Status: COMPLETED', '',
    '- [x] 1. only task, done.', '',
  ].join('\n'));
  const regBefore = readJsonlLines(path.join(arDir, 'ask-registry.jsonl'));
  writeRegistry(regBefore.concat([
    regLine({ ask_id: 'ask-d', record_type: 'created', ts: '2026-01-01T00:00:00Z', repo: repoDir, project: 'demo', summary: 'fixture d', status: 'active' }),
    regLine({ ask_id: 'ask-d', record_type: 'plan_linked', ts: '2026-01-01T00:01:00Z', plan_slug: slugD }),
  ]));
  await auditor.runCycle();
  const regAfterDone = fs.readFileSync(path.join(arDir, 'ask-registry.jsonl'), 'utf8');
  ok('S5 all-linked-plans-terminal (Status: COMPLETED) drives a REAL ask-registry.sh set-status done call, emitter=auditor',
    /"ask_id":"ask-d".*"record_type":"status_change".*"status":"done".*"emitter":"auditor"/.test(regAfterDone),
    regAfterDone);

  // ======================================================================
  // Scenario 6: latency unaffected -- /api/asks-equivalent read
  // (getBadgesForAsk, a pure in-memory read) stays fast even while a cycle
  // with several real bash spawns is in flight (auditor is off-path).
  // ======================================================================
  const cyclePromise = auditor.runCycle();
  const t0 = Date.now();
  auditor.getBadgesForAsk('ask-a');
  const readMs = Date.now() - t0;
  ok('S6 a badge read while a cycle is in flight completes in under 50ms (auditor is off the request path)',
    readMs < 50, 'readMs=' + readMs);
  await cyclePromise;

  // ======================================================================
  // Scenario 7 (pure unit, no I/O): auditAsk() classifies an unknown-
  // emitter event as unknown_provenance + de_emphasize, without touching
  // the filesystem.
  // ======================================================================
  const pureResult = auditAsk('ask-pure', { status: 'active', plan_slugs: [] }, [
    { type: 'task_started', plan_slug: '', task_id: '', emitter: 'some-random-cli', provenance: 'unknown', event_id: 'ev-1', ts: '2026-01-01T00:00:00Z' },
  ], { planLookup: () => null, dispatchMarkers: [], allKnownNeedsYouIds: new Set() });
  ok('S7 a provenance:unknown event badges unknown_provenance with de_emphasize:true',
    pureResult.badges.some((b) => b.divergence_class === 'unknown_provenance' && b.de_emphasize === true),
    JSON.stringify(pureResult.badges));

  // ======================================================================
  // Scenario 7b/7c (EVIDENCE HORIZON, production incident 2026-07-18):
  // pure unit tests for dispatchMarkerEvidenceHorizonMs() -- the TTL-only
  // case and the cap-binding empirical case (the exact mechanism that
  // produced ~718 false unmatched_dispatch badges in production: the real
  // dispatch-provenance dir held exactly 200 markers spanning only ~2.3
  // hours, far tighter than the nominal 14-day TTL).
  // ======================================================================
  const DAY_MS = 24 * 60 * 60 * 1000;
  const nowMsFixed = Date.now();
  const ttlOnlyHorizon = dispatchMarkerEvidenceHorizonMs([], nowMsFixed);
  ok('S7b with zero markers (cap never binding), the horizon is exactly the TTL cutoff (default 14 days back)',
    Math.abs(ttlOnlyHorizon - (nowMsFixed - 14 * DAY_MS)) < 5000,
    'ttlOnlyHorizon=' + ttlOnlyHorizon + ' expected~=' + (nowMsFixed - 14 * DAY_MS));

  const capMarkers = [];
  for (let i = 0; i < 200; i++) {
    capMarkers.push({ ts: new Date(nowMsFixed - (200 - i) * 60 * 1000).toISOString() }); // spans only the last ~200 minutes
  }
  const capBoundHorizon = dispatchMarkerEvidenceHorizonMs(capMarkers, nowMsFixed);
  const oldestCapMarkerMs = Date.parse(capMarkers[0].ts);
  ok('S7c when the marker count is AT the cap (200), the horizon is the oldest SURVIVING marker\'s ts, not the (much looser) 14-day TTL -- reproduces the production incident\'s actual retention window',
    Math.abs(capBoundHorizon - oldestCapMarkerMs) < 5000 && capBoundHorizon > (nowMsFixed - 14 * DAY_MS),
    'capBoundHorizon=' + capBoundHorizon + ' oldestCapMarkerMs=' + oldestCapMarkerMs);

  // ======================================================================
  // Scenario 7d/7e (the "Prove it works" scenarios): auditAsk() honors the
  // horizon for Class F (unmatched_dispatch) -- an OLD task_started event
  // with no matching marker is SKIPPED (evidence aged out, not drift); a
  // RECENT one with no matching marker still badges exactly as before.
  // ======================================================================
  const oldTs = new Date(nowMsFixed - 20 * DAY_MS).toISOString(); // 20d old, past the 14d default TTL
  const recentTs = new Date(nowMsFixed - 1 * DAY_MS).toISOString(); // 1d old, well within horizon
  const horizonCtx = {
    planLookup: () => null, dispatchMarkers: [], allKnownNeedsYouIds: new Set(),
    dispatchEvidenceHorizonMs: dispatchMarkerEvidenceHorizonMs([], nowMsFixed),
  };

  const oldResult = auditAsk('ask-horizon', { status: 'active', plan_slugs: [] }, [
    { type: 'task_started', plan_slug: 'some-plan', task_id: '9', emitter: 'workstreams-emit', provenance: 'known', event_id: 'ev-old', ts: oldTs, session_id: 'sess-old' },
  ], horizonCtx);
  ok('S7d an OLD task_started (beyond the retention horizon) with NO matching marker produces NO unmatched_dispatch badge',
    !oldResult.badges.some((b) => b.divergence_class === 'unmatched_dispatch'),
    JSON.stringify(oldResult.badges));

  const recentResult = auditAsk('ask-horizon', { status: 'active', plan_slugs: [] }, [
    { type: 'task_started', plan_slug: 'some-plan', task_id: '9', emitter: 'workstreams-emit', provenance: 'known', event_id: 'ev-recent', ts: recentTs, session_id: 'sess-recent' },
  ], horizonCtx);
  ok('S7e a RECENT task_started (within the retention horizon) with NO matching marker still badges unmatched_dispatch, exactly as before',
    recentResult.badges.some((b) => b.divergence_class === 'unmatched_dispatch' && b.task_id === '9'),
    JSON.stringify(recentResult.badges));

  // ======================================================================
  // Scenario 8: sandbox-only writes -- nothing landed outside this
  // self-test's own tempdir (T10-style assertion).
  // ======================================================================
  ok('S8 self-test wrote only under its own sandboxed tempdir (no real ~/.claude/state pollution)',
    fs.existsSync(plDir) && fs.existsSync(arDir), 'plDir/arDir should exist under tmp');

  // ======================================================================
  // Scenario 9 (cockpit-roadmap-redesign Task 4, A8): the quarantine
  // auto-defect. A fixture needs-you ledger.json with a clean answerable
  // item, TWO quarantined decision items (one with a producing session,
  // one legacy no-producer), a lint-flagged QUESTION item (must never
  // quarantine -- the lint is decision-only), and an already-RESOLVED
  // quarantined-shaped item (must never file -- it already left the
  // Inbox). Reuses the exact filed-once + recurrence-escalation machinery
  // fileNlIssueDivergences exercises above (Scenario 2e-2j), applied to
  // fileNeedsYouQuarantineDefects instead.
  // ======================================================================
  const nyStateDir9 = path.join(tmp, 'ny-state-s9');
  fs.mkdirSync(nyStateDir9, { recursive: true });
  const ledgerItems9 = [
    { id: 'NY-clean-1', section: 'decision', state: 'open', session: 'sess-clean', lint_warnings: [] },
    { id: 'NY-q1', section: 'decision', state: 'open', session: 'sess-q1', lint_warnings: ['no-anchor', 'no-context'] },
    { id: 'NY-q2-legacy', section: 'decision', state: 'open', lint_warnings: ['no-anchor'] }, // no `session` -- legacy no-producer
    { id: 'NY-question-1', section: 'question', state: 'open', session: 'sess-q3', lint_warnings: ['no-anchor'] }, // must NEVER quarantine (question, not decision)
    { id: 'NY-resolved-1', section: 'decision', state: 'resolved', session: 'sess-r1', lint_warnings: ['no-anchor'] }, // already left the Inbox -- must never file
  ];
  fs.writeFileSync(path.join(nyStateDir9, 'ledger.json'), JSON.stringify({ schema_version: 1, items: ledgerItems9 }));

  ok('S9a (pure unit) quarantinedLedgerItems() selects exactly the open+decision+lint-flagged items (NY-q1, NY-q2-legacy), excluding the clean/question/resolved fixtures',
    (() => {
      const q = quarantinedLedgerItems(ledgerItems9).map((it) => it.id).sort();
      return q.length === 2 && q[0] === 'NY-q1' && q[1] === 'NY-q2-legacy';
    })());

  const nlLedger9 = path.join(tmp, 'nl-issues-s9.jsonl');
  const nlState9 = path.join(tmp, 'nl-issue-state-s9.json');
  delete process.env.HARNESS_SELFTEST;
  process.env.NEEDS_YOU_STATE_DIR = nyStateDir9;
  process.env.NL_ISSUES_PATH = nlLedger9;
  process.env.AUDITOR_NL_ISSUE_STATE_PATH = nlState9;

  await auditor.runCycle();
  const ledger9Lines = fs.existsSync(nlLedger9) ? readJsonlLines(nlLedger9) : [];
  const quarantineLines9 = ledger9Lines.filter((l) => /quarantined_no_context/.test(l.text || ''));
  ok('S9b the auditor cycle files EXACTLY 2 quarantine defects (NY-q1 + NY-q2-legacy), never the clean/question/resolved fixtures',
    quarantineLines9.length === 2, JSON.stringify(quarantineLines9.map((l) => l.text)));
  ok('S9c the session-backed item\'s message names its producing session',
    quarantineLines9.some((l) => /NY-q1/.test(l.text) && /session sess-q1/.test(l.text)),
    JSON.stringify(quarantineLines9.map((l) => l.text)));
  ok('S9d the legacy no-producer item keys and messages against the LEDGER id, honestly naming the absent producer',
    quarantineLines9.some((l) => /NY-q2-legacy/.test(l.text) && /unknown\/legacy producer/.test(l.text)),
    JSON.stringify(quarantineLines9.map((l) => l.text)));
  const state9 = fs.existsSync(nlState9) ? JSON.parse(fs.readFileSync(nlState9, 'utf8')) : { filed: {} };
  ok('S9e the auditor\'s dedup state records BOTH quarantine ids as filed, keyed by ledger id',
    !!(state9.filed && state9.filed['quarantine-NY-q1'] && state9.filed['quarantine-NY-q2-legacy']),
    JSON.stringify(state9.filed));

  await auditor.runCycle();
  const ledger9LinesAfter = fs.existsSync(nlLedger9) ? readJsonlLines(nlLedger9) : [];
  const quarantineLines9After = ledger9LinesAfter.filter((l) => /quarantined_no_context/.test(l.text || ''));
  ok('S9f a SECOND cycle over the SAME 2 still-open quarantined items does NOT re-file (once per item lifetime, not per cycle)',
    quarantineLines9After.length === 2, JSON.stringify(quarantineLines9After.map((l) => l.text)));

  // ---- S9g: recurrence escalation -- a 3rd distinct quarantined id fires
  // ONE additional escalated summary, exactly like fileNlIssueDivergences's
  // own S2h/S2i pattern, scoped to the quarantined_no_context class.
  ledgerItems9.push({ id: 'NY-q3', section: 'decision', state: 'open', session: 'sess-q3b', lint_warnings: ['no-outcomes'] });
  fs.writeFileSync(path.join(nyStateDir9, 'ledger.json'), JSON.stringify({ schema_version: 1, items: ledgerItems9 }));
  await auditor.runCycle();
  const ledger9LinesG = fs.existsSync(nlLedger9) ? readJsonlLines(nlLedger9) : [];
  const quarantineLines9G = ledger9LinesG.filter((l) => /quarantined_no_context/.test(l.text || ''));
  ok('S9g escalation at 3 distinct quarantine ids: exactly 4 quarantine-class lines (3 individual filings + 1 escalation summary)',
    quarantineLines9G.length === 4, JSON.stringify(quarantineLines9G.map((l) => l.text)));
  ok('S9h exactly one of those lines is the RECURRENCE escalation summary, naming the class + a count of 3',
    quarantineLines9G.filter((l) => /RECURRENCE/.test(l.text) && /quarantined_no_context/.test(l.text) && /\b3\b/.test(l.text)).length === 1,
    JSON.stringify(quarantineLines9G.map((l) => l.text)));

  await auditor.runCycle();
  const ledger9LinesGAfter = fs.existsSync(nlLedger9) ? readJsonlLines(nlLedger9) : [];
  ok('S9i a repeat cycle over the same 3 escalated ids does NOT re-escalate (still exactly 4 quarantine-class lines)',
    ledger9LinesGAfter.filter((l) => /quarantined_no_context/.test(l.text || '')).length === 4);

  // Restore the default sandbox posture -- NEEDS_YOU_STATE_DIR back to the
  // EMPTY default dir (never deleted/unset), so any scenario after this one
  // can't fall through to the real machine's ledger.json.
  process.env.HARNESS_SELFTEST = '1';
  process.env.NEEDS_YOU_STATE_DIR = nyStateDirDefault;
  delete process.env.NL_ISSUES_PATH;
  delete process.env.AUDITOR_NL_ISSUE_STATE_PATH;

  // ======================================================================
  // Scenario 10 (Task 2 A3 fold-precedence PARITY -- see
  // docs/plans/fragments/roadmap-t2-derive-lib-fragment.md's "Second seam,
  // task-4-owned" note): THIS module's own foldAskRegistry duplicate must
  // honor the identical operator-beats-auto-regardless-of-timestamp rule
  // server.js's canonical derive-lib.js reader already enforces (task 2).
  // ======================================================================
  {
    const t10Dir = fs.mkdtempSync(path.join(os.tmpdir(), 'auditor-t10-fold-'));
    const t10Line = (o) => JSON.stringify(Object.assign({ ask_id: 'ask-t10', record_type: '', ts: '', repo: '', project: '', summary: '', status: '', plan_slug: '', title_source: '' }, o));
    fs.writeFileSync(path.join(t10Dir, 'ask-registry.jsonl'), [
      t10Line({ record_type: 'created', ts: '2026-07-19T10:00:00Z', summary: 'auto captured title', title_source: 'auto', status: 'active' }),
      t10Line({ record_type: 'summary_updated', ts: '2026-07-19T10:05:00Z', summary: 'Operator renamed this', title_source: 'operator' }),
      t10Line({ record_type: 'summary_updated', ts: '2026-07-19T10:10:00Z', summary: 'distiller re-run title', title_source: 'auto' }),
    ].join('\n') + '\n');
    const folded10 = foldAskRegistry(path.join(t10Dir, 'ask-registry.jsonl'));
    ok('S10 auditor.js\'s own foldAskRegistry duplicate ALSO keeps the operator title against a newer auto re-run (parity with derive-lib.js)',
      folded10['ask-t10'] && folded10['ask-t10'].summary === 'Operator renamed this' && folded10['ask-t10'].title_source === 'operator',
      JSON.stringify(folded10['ask-t10']));
    fs.rmSync(t10Dir, { recursive: true, force: true });
  }

  auditor.stop();
  try { fs.rmSync(tmp, { recursive: true, force: true }); } catch (_) {}

  console.log('');
  console.log('self-test summary: ' + PASSED + ' passed, ' + FAILED + ' failed');
  return FAILED > 0;
}
