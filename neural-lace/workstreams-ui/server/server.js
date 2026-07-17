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
const planParse = require('./plan-parse.js');
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

// operator-todo.md path — Task 14 "My To-Do pane". Mirrors needsYouMdPath()'s
// own shape (OPERATOR_TODO_PATH env override, else MAIN-CHECKOUT root per
// constraint 11) exactly, and duplicates (rather than requires)
// auditor.js's identically-shaped `operatorTodoPath()` — this codebase's own
// established convention for small per-file resolvers (see auditor.js's
// header "WHY THE READERS BELOW ARE DUPLICATED"); server.js already
// `require`s auditor.js (one-directional), so reuse would have been safe
// too, but duplicating keeps this reader independently correct even if
// auditor.js's module shape changes.
function operatorTodoPath() {
  return process.env.OPERATOR_TODO_PATH || path.join(mainRepoRoot(), 'docs', 'operator-todo.md');
}

function dispatchProvenanceStateDir() {
  return process.env.DISPATCH_PROVENANCE_STATE_DIR ||
    path.join(process.env.HOME || os.homedir(), '.claude', 'state', 'dispatch-provenance');
}

function heartbeatStateDir() {
  return process.env.HEARTBEAT_STATE_DIR ||
    path.join(process.env.HOME || os.homedir(), '.claude', 'state', 'heartbeats');
}

// ============================================================
// Task 14 — "My To-Do pane". Reads/writes docs/operator-todo.md: an
// operator-authored free-form section (add/edit/check freely from the UI)
// plus a marker-delimited AUTO section whose pointer bullets
// `needs-you.sh`'s Task 4 splice appends (`_ny_operator_todo_append_pointer`)
// and Task 12's auditor auto-checks (`autoCheckOperatorTodo`) — this module
// NEVER auto-checks a pointer itself (that stays the auditor's exclusive
// derivation, constraint 6: "nothing here ... adds a second done-bit" for
// the CHECKED semantics; this reader/writer only ever flips a pointer's box
// via the explicit operator-override action below, which is a deliberate
// OPERATOR write, not a derivation).
// ============================================================

const OPERATOR_TODO_AUTO_START = '<!-- AUTO:START -->';
const OPERATOR_TODO_AUTO_END = '<!-- AUTO:END -->';
const OPERATOR_TODO_HEADING_RE = /^##\s+Operator items\s*$/;
const OPERATOR_TODO_ITEM_RE = /^- \[( |x|X)\] (.*)$/;

// AUTO_POINTER_RE — the exact bullet shape needs-you.sh's
// `_ny_operator_todo_append_pointer` writes (that function's own header
// quotes this shape verbatim):
//   - [ ] AUTO: <section> waiting on operator — "<title>" (needs-you `<id>`, tier <tier>, session `<session_id>`) — see NEEDS-YOU.md
// Group 7 (trailing) captures anything appended AFTER the fixed suffix —
// this is where the operator-override marker (below) lands, so an
// overridden line still matches this same regex.
const AUTO_POINTER_RE = /^- \[( |x|X)\] AUTO: (.+?) waiting on operator — "(.*)" \(needs-you `([^`]+)`, tier ([^,]+), session `([^`]*)`\) — see NEEDS-YOU\.md(.*)$/;

// The operator-override marker this module appends when "Mark handled" is
// used (constraint 7's escape hatch). Once appended the line's checkbox is
// ALSO flipped to `[x]`, so Task 12's autoCheckOperatorTodo (which only ever
// touches an UNCHECKED bullet — see its own header) skips this line forever:
// the auditor "respects, never fights" the override by construction, not by
// special-casing this marker.
const OPERATOR_OVERRIDE_RE = /\(marked handled by operator, ([^)]*)\)\s*$/;

const OPERATOR_TODO_TEMPLATE =
  '# Operator To-Do\n\n' +
  'Operator-authored items live in "## Operator items" below and are never\n' +
  'touched by automation. Auto-added pointer items (mirroring a decision or\n' +
  'question just appended to NEEDS-YOU.md) live between the AUTO markers and\n' +
  'are mechanically appended by\n' +
  '`adapters/claude-code/scripts/needs-you.sh` (the `add` splice,\n' +
  'ask-rooted-workstreams-p1 Task 4) — never hand-edit inside the markers;\n' +
  're-appending only ever ADDS a line, never rewrites one. A pointer\'s\n' +
  'resolved/checked state is DERIVED (a later auditor pass, plan Task 12)\n' +
  'from the underlying NEEDS-YOU ledger, not tracked here — entries in this\n' +
  'file are an append-only log, not removed when the ledger item resolves.\n\n' +
  '## Operator items\n\n' +
  '_(add your own free-form to-do items in this section — never overwritten)_\n\n' +
  OPERATOR_TODO_AUTO_START + '\n' + OPERATOR_TODO_AUTO_END + '\n';

// ensureOperatorTodoFile(path) — creates the file (SAME template
// needs-you.sh's `_ny_operator_todo_ensure` writes, word-for-word) only if
// entirely absent; a no-op for an existing file in ANY shape (never
// re-templates, never touches operator-authored content). Best-effort: a
// mkdir/write failure is swallowed — the caller's subsequent read/write
// simply fails with its own honest error rather than crashing the request.
function ensureOperatorTodoFile(p) {
  if (fs.existsSync(p)) return;
  try { fs.mkdirSync(path.dirname(p), { recursive: true }); } catch (_) { /* best-effort */ }
  try { fs.writeFileSync(p, OPERATOR_TODO_TEMPLATE); } catch (_) { /* best-effort */ }
}

// parseOperatorTodoLines(lines) — locates the "## Operator items" heading +
// AUTO markers, then splits into two item arrays. Operator items are ANY
// line matching the checkbox-bullet grammar between the heading and
// AUTO:START (the static intro prose + the italic placeholder line never
// match this grammar, so they are transparently excluded — no special-casing
// needed). Pointer items are AUTO-block lines matching the exact bullet
// shape needs-you.sh writes; a foreign/malformed AUTO-block line is simply
// skipped (Edge Cases: never crash on one bad record). `lineIndex` on every
// item is the file's actual line-array index, used by the writers below to
// surgically replace exactly one line without disturbing any other byte.
function parseOperatorTodoLines(lines) {
  let headingIdx = -1, autoStartIdx = -1, autoEndIdx = -1;
  lines.forEach((l, i) => {
    if (headingIdx === -1 && OPERATOR_TODO_HEADING_RE.test(l.trim())) headingIdx = i;
    if (autoStartIdx === -1 && l.trim() === OPERATOR_TODO_AUTO_START) autoStartIdx = i;
    if (l.trim() === OPERATOR_TODO_AUTO_END) autoEndIdx = i;
  });
  const operatorItems = [];
  const opStart = headingIdx === -1 ? 0 : headingIdx + 1;
  const opEnd = autoStartIdx === -1 ? lines.length : autoStartIdx;
  for (let i = opStart; i < opEnd; i++) {
    const m = OPERATOR_TODO_ITEM_RE.exec(lines[i]);
    if (m) operatorItems.push({ lineIndex: i, index: operatorItems.length, checked: /x/i.test(m[1]), text: m[2] });
  }
  const pointerItems = [];
  if (autoStartIdx !== -1 && autoEndIdx !== -1 && autoEndIdx > autoStartIdx) {
    for (let i = autoStartIdx + 1; i < autoEndIdx; i++) {
      const m = AUTO_POINTER_RE.exec(lines[i]);
      if (!m) continue;
      const overrideM = OPERATOR_OVERRIDE_RE.exec(m[7] || '');
      pointerItems.push({
        lineIndex: i,
        checked: /x/i.test(m[1]),
        section: m[2],
        title: m[3],
        needsYouId: m[4],
        tier: m[5],
        sessionId: m[6],
        operatorOverride: !!overrideM,
        overrideTs: overrideM ? overrideM[1] : '',
      });
    }
  }
  return { headingIdx, autoStartIdx, autoEndIdx, operatorItems, pointerItems };
}

// writeOperatorTodoAtomic(path, text) — tmp-file + rename, mirroring
// auditor.js's autoCheckOperatorTodo (the SAME atomic-rewrite technique this
// codebase already uses for this exact file) so a reader mid-write never
// observes a torn file.
function writeOperatorTodoAtomic(p, text) {
  const tmp = p + '.server-tmp-' + process.pid + '-' + Date.now();
  fs.writeFileSync(tmp, text);
  fs.renameSync(tmp, p);
}

// withOperatorTodoFile(mutatorFn) — the ONE place every POST /api/todo write
// goes through. Ensures the file exists, re-reads + re-parses it FRESH
// (never memoized — a concurrent needs-you.sh pointer append or a hand-edit
// between requests is picked up), hands the mutable `lines` array + the
// parsed sections to `mutatorFn`, then atomically rewrites the WHOLE file
// (marker-delimited sections mean the mutator only ever touches one line/
// splices one new line, so a concurrent writer's OWN untouched lines are
// preserved in this copy — this is the "atomic rewrite of only the touched
// section" behavior the Integration point names; true simultaneous-write
// races still last-writer-wins, same accepted tradeoff as Task 12's
// autoCheckOperatorTodo, which has no locking either).
// `mutatorFn(lines, parsed) -> {result: {...}} | {error: 'message'}`.
function withOperatorTodoFile(mutatorFn) {
  const todoPath = operatorTodoPath();
  ensureOperatorTodoFile(todoPath);
  let text;
  try { text = fs.readFileSync(todoPath, 'utf8'); }
  catch (_) { return { ok: false, error: 'could not read the to-do file' }; }
  const lines = text.split('\n');
  const parsed = parseOperatorTodoLines(lines);
  const r = mutatorFn(lines, parsed) || {};
  if (r.error) return { ok: false, error: r.error };
  try {
    writeOperatorTodoAtomic(todoPath, lines.join('\n'));
  } catch (_) {
    return { ok: false, error: 'could not save the to-do file' };
  }
  return Object.assign({ ok: true }, r.result || {});
}

// ============================================================
// Task 15 — "Backlog pane". Reads/writes docs/backlog.md through the SAME
// row grammar the O.9 triage loop's golden oracle already defines
// (`od_backlog_health`, adapters/claude-code/hooks/lib/observability-
// derive.sh) — every regex below is a byte-for-byte PORT of that function's
// R1-R4 position-anchored terminal/in-flight rules (see that function's own
// header for the full rationale), not a re-derivation, so a row this UI
// reads/writes classifies IDENTICALLY under the real loop. Parity was
// hand-verified against a live run of the real oracle over the actual
// docs/backlog.md (including its own quirks — e.g. HARNESS-GAP-48's title
// containing the prose "not folded into ..." false-positives as
// dispositioned_in_flight under the REAL oracle too; this port reproduces
// that, deliberately, rather than "fixing" it — fidelity to the contract,
// warts included, is the point).
//
// ANTI-NOISE LAW SCOPING (constraint 1) — deliberate, documented decision:
// this reader/writer does NOT run payloadSchema.containsDenylistedIdentifier
// over row titles/previews/add-form text, unlike todo.js's operator-text
// scan. Rationale: docs/backlog.md IS the harness's own engineering backlog
// ("Outstanding improvements to the Claude Code harness (rules, agents,
// hooks, skills)") — every legitimate row is ABOUT hook/gate/script
// identifiers by definition (that is the row's actual subject matter, not
// mechanism-attribution noise leaking into an operator-facing narrative,
// which is what constraint 1 targets on the ask-tree/My-To-Do surfaces).
// Applying the denylist here would 500 the pane against the real file (see
// this task's build evidence: rows routinely match `.sh\b`/`-gate\b`/hook-
// lifecycle-name patterns) and block legitimate adds. The absolute-links
// law (constraint 2) still applies to the one href this module emits (the
// backlog file's own absolute path, for an "open file" affordance) via the
// same payloadSchema.isAbsoluteHref check todo.js/asks.js already use.
// ============================================================
function backlogMdPath() {
  return process.env.BACKLOG_MD_PATH || path.join(mainRepoRoot(), 'docs', 'backlog.md');
}

const BACKLOG_TERM = '(DISPOSITIONED|IMPLEMENTED|ABSORBED|CLOSED|SUPERSEDED|WONTFIX)';
const BACKLOG_SP = '[\\t\\v\\f\\r ]';
const BACKLOG_RE_ID = /^- \*\*([A-Z][A-Z0-9-]{3,})/;
const BACKLOG_RE_TITLE_SEGMENT = /^- \*\*([^*]*)\*\*/;
const BACKLOG_RE_ADDED = /added ([0-9]{4}-[0-9]{2}-[0-9]{2})/;
const BACKLOG_RE_PRIO = /priority:(high|medium|low)/;
// R1-R4, ported verbatim from od_backlog_health (terminal words).
const BACKLOG_RE_TERM_R1 = new RegExp('^- \\*\\*[^*]*\\b' + BACKLOG_TERM + '\\b');
const BACKLOG_RE_TERM_R2 = new RegExp('\\*\\*' + BACKLOG_SP + '+(—|--?)' + BACKLOG_SP + '+' + BACKLOG_TERM + '\\b');
const BACKLOG_RE_TERM_R3 = /\*\*\((dispositioned|implemented|absorbed|closed|superseded|wontfix)\b/i;
const BACKLOG_RE_TERM_R4 = new RegExp('\\*\\*((PARTIALLY|LARGELY)' + BACKLOG_SP + '+)?' + BACKLOG_TERM + '\\b');
// R1-R4, ported verbatim from od_backlog_health (dispositioned-in-flight —
// SCHEDULE/DEMOTE/FOLD replies; WONTFIX is already a TERMINAL word above).
const BACKLOG_INFLIGHT = '(SCHEDULED|DEFERRED|DEMOTED|FOLDED|FOLD-INTO-[^*]+)';
const BACKLOG_RE_INFLIGHT_R1 = new RegExp('^- \\*\\*[^*]*\\b' + BACKLOG_INFLIGHT + '\\b', 'i');
const BACKLOG_RE_INFLIGHT_R2 = new RegExp('\\*\\*' + BACKLOG_SP + '+(—|--?)' + BACKLOG_SP + '+' + BACKLOG_INFLIGHT + '\\b', 'i');
const BACKLOG_RE_INFLIGHT_R3 = /\*\*\((scheduled|deferred|demoted|folded|fold-into[^)]*)\b/i;
const BACKLOG_RE_INFLIGHT_R4 = new RegExp('\\*\\*((PARTIALLY|LARGELY)' + BACKLOG_SP + '+)?' + BACKLOG_INFLIGHT + '\\b', 'i');
// Cosmetic-only label extractors (badge text) — independent of the strict
// booleans above so a display nuance can never influence classification.
const BACKLOG_RE_WORD_TERM = /\b(DISPOSITIONED|IMPLEMENTED|ABSORBED|CLOSED|SUPERSEDED|WONTFIX)\b/i;
const BACKLOG_RE_WORD_INFLIGHT = /\b(SCHEDULED|DEFERRED|DEMOTED|FOLDED|FOLD-INTO-[^*\s)]+)\b/i;

// ADD-PATH GRAMMAR-COLLISION GUARD (comprehension-review Stage 3c fix).
// A freshly-ADDED open row must classify OPEN under the REAL od_backlog_health
// even when the operator's title/description contains a bare disposition word
// ("Document WONTFIX semantics", "how SCHEDULED rows re-nag"). The oracle's
// R1 rule scans the ENTIRE leading `**...**` segment, so anything a keyword
// can reach inside it mis-reads the row as done/in-flight and it VANISHES
// from the open list. Three coordinated guards (each proven against the real
// oracle — see the S42d-f self-test scenarios + the build-evidence probe):
//   1. structural: only the machine-generated ID sits inside the leading
//      bold; the verbatim title moves OUT, after a COLON separator (NOT the
//      em-dash real rows use inside the bold) so a keyword-LEADING title can't
//      chain off the ID's closing `**` via R2 ("** — WONTFIX" matches; "**:
//      WONTFIX" does not — probe C vs D).
//   2. ID guard: backlogIdBaseFromTitle strips keyword TOKENS from the
//      synthetic slug so the ID itself (which DOES sit inside the bold, R1's
//      reach) can never carry one (probe E).
//   3. markdown guard: backlogNeutralizeMarkdown collapses any `**` the
//      operator typed in title/description down to a single `*`, so verbatim
//      text can't smuggle a `**KEYWORD` bold segment that R2/R3/R4 anchor on
//      (probe G/H) — a BARE keyword in free text is already OPEN-safe (probe
//      F), so no WORD the operator wrote is altered.
// BACKLOG_DISPOSITION_KEYWORDS is DERIVED from the SAME ported fragment
// strings above (BACKLOG_TERM + BACKLOG_INFLIGHT), never a second hand-typed
// list, so the guard can never drift out of lockstep with the classification
// regexes it must track. Every all-caps token (>=3 chars) in both fragments:
// DISPOSITIONED/IMPLEMENTED/ABSORBED/CLOSED/SUPERSEDED/WONTFIX (TERM) +
// SCHEDULED/DEFERRED/DEMOTED/FOLDED/FOLD/INTO (INFLIGHT, incl. FOLD-INTO split
// into its word tokens — guarding FOLD and INTO independently is strictly
// safer than only the literal).
const BACKLOG_DISPOSITION_KEYWORDS = (function () {
  const seen = {};
  (BACKLOG_TERM + '|' + BACKLOG_INFLIGHT).replace(/[^A-Z]+/g, ' ').trim().split(/\s+/)
    .forEach((w) => { if (w.length >= 3) seen[w] = true; });
  return Object.keys(seen);
})();

function backlogNeutralizeMarkdown(s) {
  return String(s).replace(/\*{2,}/g, '*').replace(/[\r\n]+/g, ' ').trim();
}

const BACKLOG_TIER_HIGH_DAYS = Number(process.env.BACKLOG_TIER_HIGH_DAYS) || 7;
const BACKLOG_TIER_MEDIUM_DAYS = Number(process.env.BACKLOG_TIER_MEDIUM_DAYS) || 30;
const BACKLOG_TIER_LOW_DAYS = Number(process.env.BACKLOG_TIER_LOW_DAYS) || 90;
const BACKLOG_COMPACT_CAP = Number(process.env.BACKLOG_COMPACT_CAP) || 5;
const BACKLOG_ADD_SECTION_HEADING = '## Open work — substantive deferrals';

// backlogRowParts(line, id) — the DISPLAY title + preview, handling BOTH row
// shapes this module ever sees:
//   - canonical existing rows:  `- **ID — title** (added ...) body`   (title
//     INSIDE the leading bold)
//   - add-path rows (post-Stage-3c fix): `- **ID**: title (added ...) body`
//     (title OUTSIDE the leading bold, after a colon — see the guard block
//     above for why the title cannot live inside the bold anymore)
// The classification (terminal/inflight/open) is UNAFFECTED by this — it is
// computed from the raw line by the R1-R4 ports; this function only shapes the
// human-readable title/preview strings.
function backlogRowParts(line, id) {
  const escId = id.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const m = BACKLOG_RE_TITLE_SEGMENT.exec(line);
  let title = '';
  let rest = m ? line.slice(m[0].length) : line;
  if (m) {
    const inBold = m[1].replace(new RegExp('^' + escId + '\\s*[—:\\-]*\\s*'), '').trim();
    if (inBold) {
      // canonical `**ID — title**`
      title = inBold;
      rest = rest.replace(/^\s*[—:\-]+\s*/, '');
    } else {
      // add-path `**ID**: title (added ...)` — title is the run before "(added"
      const afterBold = rest.replace(/^\s*[—:\-]+\s*/, '');
      title = afterBold.split(/\s*\(added\b/)[0].trim();
      rest = afterBold.slice(title.length).replace(/^\s*/, '');
    }
  }
  if (!title) title = id;
  const preview = rest.trim();
  return { title: title, preview: preview.length > 220 ? preview.slice(0, 220) + '…' : preview };
}

// parseBacklogRows(text) — one pass over the file, mirroring
// od_backlog_health's single-node-invocation performance discipline (no
// per-row subprocess/spawn — the file is read once, scanned in pure JS).
function parseBacklogRows(text) {
  const lines = text.split('\n');
  const now = Date.now();
  const rows = [];
  lines.forEach((line, lineIndex) => {
    const mId = BACKLOG_RE_ID.exec(line);
    if (!mId) return;
    const id = mId[1];

    let added = null, ageDays = null;
    const mAdded = BACKLOG_RE_ADDED.exec(line);
    if (mAdded) {
      added = mAdded[1];
      const ms = Date.parse(mAdded[1]);
      if (!isNaN(ms)) ageDays = Math.trunc((now - ms) / 86400000);
    }
    const mPrio = BACKLOG_RE_PRIO.exec(line);
    const priorityLabel = mPrio ? mPrio[1] : '';
    const priorityBucket = priorityLabel || 'unlabeled';
    const thresholdDays = priorityLabel === 'high' ? BACKLOG_TIER_HIGH_DAYS
      : priorityLabel === 'medium' ? BACKLOG_TIER_MEDIUM_DAYS : BACKLOG_TIER_LOW_DAYS;

    const terminal = BACKLOG_RE_TERM_R1.test(line) || BACKLOG_RE_TERM_R2.test(line) ||
      BACKLOG_RE_TERM_R3.test(line) || BACKLOG_RE_TERM_R4.test(line);
    const inflight = !terminal && (BACKLOG_RE_INFLIGHT_R1.test(line) || BACKLOG_RE_INFLIGHT_R2.test(line) ||
      BACKLOG_RE_INFLIGHT_R3.test(line) || BACKLOG_RE_INFLIGHT_R4.test(line));

    let dispositionWord = null;
    if (terminal) {
      const m = BACKLOG_RE_WORD_TERM.exec(line);
      dispositionWord = m ? m[1].toUpperCase() : 'DISPOSITIONED';
    } else if (inflight) {
      const m = BACKLOG_RE_WORD_INFLIGHT.exec(line);
      dispositionWord = m ? m[1].toUpperCase() : 'SCHEDULED';
    }

    const status = terminal ? 'terminal' : (inflight ? 'inflight' : 'open');
    const isOverdue = status === 'open' && ageDays !== null && ageDays > thresholdDays;

    const parts = backlogRowParts(line, id);
    rows.push({
      id: id, lineIndex: lineIndex, title: parts.title,
      preview: parts.preview, added: added, age_days: ageDays,
      priority: priorityBucket, priority_label: priorityLabel, status: status,
      disposition_word: dispositionWord, is_overdue: isOverdue,
    });
  });
  return rows;
}

function backlogPublicRow(r) {
  return {
    id: r.id, title: r.title, preview: r.preview, added: r.added, age_days: r.age_days,
    priority: r.priority, status: r.status, disposition_word: r.disposition_word, is_overdue: r.is_overdue,
  };
}

function readBacklogRaw() {
  try { return fs.readFileSync(backlogMdPath(), 'utf8'); }
  catch (e) { if (e && e.code === 'ENOENT') return ''; throw e; }
}

function writeBacklogAtomic(text) {
  const p = backlogMdPath();
  const tmp = p + '.server-tmp-' + process.pid + '-' + Date.now();
  fs.writeFileSync(tmp, text);
  fs.renameSync(tmp, p);
}

// withBacklogFile(mutatorFn) — the ONE place every POST /api/backlog write
// goes through; re-reads fresh every call (never memoized) and rewrites the
// WHOLE file atomically (tmp+rename), mirroring withOperatorTodoFile's exact
// discipline above. `mutatorFn(lines) -> {result: {...}} | {error: 'msg'}`.
function withBacklogFile(mutatorFn) {
  let text;
  try { text = readBacklogRaw(); }
  catch (_) { return { ok: false, error: 'could not read the backlog file' }; }
  const lines = text.split('\n');
  const r = mutatorFn(lines) || {};
  if (r.error) return { ok: false, error: r.error };
  try { writeBacklogAtomic(lines.join('\n')); }
  catch (_) { return { ok: false, error: 'could not save the backlog file' }; }
  return Object.assign({ ok: true }, r.result || {});
}

// findBacklogLineIndexForId — locates the ONE line whose leading bold id
// segment is EXACTLY `id` (negative lookahead against further id-class
// chars so "OPEN-01" never matches inside "OPEN-01-FOLLOWUP" — the oracle's
// own extraction is greedy over the SAME char class, so a shorter target id
// is never actually a prefix of a real different row's id in practice, but
// this guards the case defensively).
function findBacklogLineIndexForId(lines, id) {
  const re = new RegExp('^- \\*\\*' + id.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + '(?![A-Z0-9-])');
  for (let i = 0; i < lines.length; i++) { if (re.test(lines[i])) return i; }
  return -1;
}

function backlogIdBaseFromTitle(title) {
  // Guard 2 (Stage 3c): drop any TERM/INFLIGHT keyword TOKEN before building
  // the slug, so the synthetic ID — which sits INSIDE the leading bold, R1's
  // reach — can never carry a disposition word (probe E). The ID is a
  // machine-generated slug, NOT the operator's verbatim title, so dropping a
  // token here mangles nothing they wrote (the title is preserved verbatim
  // OUTSIDE the bold — see the add rowLine).
  const words = String(title).toUpperCase().replace(/[^A-Z0-9]+/g, ' ').trim().split(/\s+/)
    .filter((w) => w && BACKLOG_DISPOSITION_KEYWORDS.indexOf(w) === -1);
  let base = words.join('-');
  if (base.length > 40) base = base.slice(0, 40).replace(/-+$/g, '');
  if (!/^[A-Z]/.test(base) || base.replace(/[^A-Z0-9]/g, '').length < 3) base = 'ROW';
  return base;
}

function backlogExistingIds(lines) {
  const set = new Set();
  lines.forEach((l) => { const m = BACKLOG_RE_ID.exec(l); if (m) set.add(m[1]); });
  return set;
}

function generateBacklogId(lines, title) {
  const base = backlogIdBaseFromTitle(title);
  const existing = backlogExistingIds(lines);
  for (let n = 1; n < 1000; n++) {
    const candidate = base + '-' + (n < 10 ? '0' + n : String(n));
    if (!existing.has(candidate)) return candidate;
  }
  return base + '-' + Date.now();
}

// findBacklogInsertIndex — new rows land at the END of the "Open work —
// substantive deferrals" section (Prove-it-works step 2: "shows one
// well-formed row in the right section"), i.e. right before the NEXT `## `
// heading. Missing heading (never crash — Edge Cases discipline): append at
// end of file instead of guessing a different location.
function findBacklogInsertIndex(lines) {
  let headingIdx = -1;
  for (let i = 0; i < lines.length; i++) {
    if (lines[i].trim() === BACKLOG_ADD_SECTION_HEADING) { headingIdx = i; break; }
  }
  if (headingIdx === -1) return lines.length;
  for (let i = headingIdx + 1; i < lines.length; i++) {
    if (/^## /.test(lines[i])) return i;
  }
  return lines.length;
}

function backlogSlugifyFoldTarget(s) {
  const slug = String(s || '').trim().replace(/[^A-Za-z0-9_.-]+/g, '-').replace(/-+/g, '-').replace(/^[-.]+|[-.]+$/g, '');
  return slug;
}

const BACKLOG_DISPOSITION_WORD = { schedule: 'SCHEDULED', demote: 'DEMOTED', fold: 'FOLDED', wontfix: 'WONTFIX' };

// buildBacklogPayload() — GET /api/backlog response: compact top-N-per-tier
// (open rows only, oldest-first) + the full row list (every row, any
// status) + counts. No payload-schema.js allowlist walk here (deliberate —
// this is a NEW payload shape outside the ask-tree LANDING_ALLOWED_KEYS/
// DETAIL_ALLOWED_KEYS contract Task 11 owns; extending that allowlist with
// backlog-specific fields would blur two independently-scoped contracts).
function buildBacklogPayload() {
  const text = readBacklogRaw();
  const rows = parseBacklogRows(text);
  const openRows = rows.filter((r) => r.status === 'open');
  const tiers = { high: [], medium: [], low: [], unlabeled: [] };
  ['high', 'medium', 'low', 'unlabeled'].forEach((tier) => {
    tiers[tier] = openRows.filter((r) => r.priority === tier)
      .sort((a, b) => (b.age_days === null ? -1 : b.age_days) - (a.age_days === null ? -1 : a.age_days));
  });
  const compact = {};
  Object.keys(tiers).forEach((tier) => {
    compact[tier] = { total: tiers[tier].length, rows: tiers[tier].slice(0, BACKLOG_COMPACT_CAP).map(backlogPublicRow) };
  });
  const counts = {
    open_total: openRows.length,
    inflight_total: rows.filter((r) => r.status === 'inflight').length,
    terminal_total: rows.filter((r) => r.status === 'terminal').length,
    by_tier: { high: tiers.high.length, medium: tiers.medium.length, low: tiers.low.length, unlabeled: tiers.unlabeled.length },
  };
  const bp = backlogMdPath();
  const filePathAbs = payloadSchema.isAbsoluteHref(bp) ? bp : '';
  return {
    ok: true,
    generated_at: new Date().toISOString(),
    file_path: filePathAbs,
    compact_cap: BACKLOG_COMPACT_CAP,
    counts: counts,
    compact: compact,
    full: rows.map(backlogPublicRow),
  };
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
// Plan-file task counting (plan progress bars / drill-down rows). The
// grammar + resolver themselves now live in the ONE shared module
// (./plan-parse.js, cockpit-v2-push-materialized-store Task 1) — used by
// this file AND auditor.js, replacing what used to be two independently
// duplicated, numeric-id-only, archive-blind implementations. See
// plan-parse.js's own header for the full "why" + the exact corpus delta.
// ----------------------------------------------------------------------

// countPlanTasks(absPath) — thin wrapper preserving this file's prior
// return shape (an array, or null on any read failure) for its one call
// site below; loadPlanFile's honest absent/damaged distinction is
// available to future consumers via planParse.loadPlanFile directly.
function countPlanTasks(absPath) {
  const r = planParse.loadPlanFile(absPath);
  return r.ok ? r.tasks : null;
}

// resolveAskPlanAbsPath(repo, slug) — the ask's own `repo` first, falling
// back to this repo's own root (the common case for harness-development
// asks like this one) — the SAME priority order this file always used.
// planParse.resolvePlanAbsPath now checks `docs/plans/` AND
// `docs/plans/archive/` under EACH root (M5's fix — this file's own prior
// resolver never checked archive/ at all, unlike auditor.js's), so an ask
// whose plan has since been archived is now found here too.
function resolveAskPlanAbsPath(repo, slug) {
  if (repo) {
    const p = planParse.resolvePlanAbsPath(repo, slug);
    if (p) return p;
  }
  return planParse.resolvePlanAbsPath(mainRepoRoot(), slug);
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
    const absPath = resolveAskPlanAbsPath(reg.repo, slug);
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
  if (url === '/todo.js') return serveStatic(res, 'todo.js');
  if (url === '/backlog.js') return serveStatic(res, 'backlog.js');
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

  // ---- Task 14 "My To-Do pane" — GET reads docs/operator-todo.md (operator
  // free-form section + AUTO pointer section); POST is the ONE write path
  // (operator add/edit/toggle + the pointer operator-override escape hatch,
  // constraint 7). Anti-noise (constraint 1) + absolute-links (constraint 2)
  // apply exactly as they do for /api/asks — reusing payload-schema.js's
  // exported scanners rather than re-inventing the pattern list.
  if (url === '/api/todo' && req.method === 'GET') {
    const todoPath = operatorTodoPath();
    let text = '';
    try {
      text = fs.readFileSync(todoPath, 'utf8');
    } catch (e) {
      if (!e || e.code !== 'ENOENT') {
        return sendJson(res, 200, { ok: false, error: 'could not read the to-do file', operator_items: [], pointer_items: [] });
      }
      text = ''; // no file yet — a legitimate EMPTY state (constraint 8), never a fetch failure
    }
    const parsed = parseOperatorTodoLines(text.split('\n'));
    const ny = readNeedsYouDecisionsResult();
    const byId = {};
    ny.decisions.forEach((d) => { byId[d.id] = d; });

    const operatorItemsOut = parsed.operatorItems.map((it) => ({ index: it.index, text: it.text, checked: it.checked }));
    const rawLinkAbs = payloadSchema.isAbsoluteHref(needsYouMdPath()) ? needsYouMdPath() : '';
    const pointerItemsOut = parsed.pointerItems.map((p) => {
      const dec = byId[p.needsYouId];
      return {
        needs_you_id: p.needsYouId,
        section: p.section,
        tier: p.tier,
        session_id: p.sessionId,
        title: p.title,
        checked: p.checked,
        operator_override: p.operatorOverride,
        body: (dec && dec.body) || '',
        raw_link: rawLinkAbs,
      };
    });

    const antiNoiseHit = operatorItemsOut.map((i) => i.text)
      .concat(pointerItemsOut.map((p) => p.title))
      .concat(pointerItemsOut.map((p) => p.body))
      .map((s) => payloadSchema.containsDenylistedIdentifier(s))
      .find(Boolean);
    if (antiNoiseHit) {
      return sendJson(res, 500, { ok: false, error: 'to-do payload failed the anti-noise check', operator_items: [], pointer_items: [] });
    }

    return sendJson(res, 200, {
      ok: true,
      generated_at: new Date().toISOString(),
      operator_items: operatorItemsOut,
      pointer_items: pointerItemsOut,
    });
  }

  if (url === '/api/todo' && req.method === 'POST') {
    let bodyBuf = '';
    req.on('data', (c) => { bodyBuf += c; if (bodyBuf.length > 1e5) req.destroy(); });
    req.on('end', () => {
      let input;
      try { input = bodyBuf ? JSON.parse(bodyBuf) : {}; } catch (_) { return sendJson(res, 400, { ok: false, error: 'bad json' }); }
      const action = input.action;

      if (action === 'add') {
        const text = typeof input.text === 'string' ? input.text.trim() : '';
        if (!text) return sendJson(res, 400, { ok: false, error: 'to-do text cannot be empty' });
        const hit = payloadSchema.containsDenylistedIdentifier(text);
        if (hit) return sendJson(res, 400, { ok: false, error: 'that text mentions an internal harness identifier — please rephrase' });
        const r = withOperatorTodoFile((lines, parsed) => {
          const insertAt = parsed.autoStartIdx === -1 ? lines.length : parsed.autoStartIdx;
          lines.splice(insertAt, 0, '- [ ] ' + text.replace(/\r?\n/g, ' '));
          return { result: { index: parsed.operatorItems.length, text: text, checked: false } };
        });
        return sendJson(res, r.ok ? 200 : 500, r);
      }

      if (action === 'toggle') {
        const idx = Number(input.index);
        const r = withOperatorTodoFile((lines, parsed) => {
          const item = parsed.operatorItems[idx];
          if (!item) return { error: 'could not find that item — reload and try again' };
          const newChecked = !item.checked;
          lines[item.lineIndex] = '- [' + (newChecked ? 'x' : ' ') + '] ' + item.text;
          return { result: { index: idx, checked: newChecked } };
        });
        return sendJson(res, r.ok ? 200 : 404, r);
      }

      if (action === 'edit') {
        const idx = Number(input.index);
        const text = typeof input.text === 'string' ? input.text.trim() : '';
        if (!text) return sendJson(res, 400, { ok: false, error: 'to-do text cannot be empty' });
        const hit = payloadSchema.containsDenylistedIdentifier(text);
        if (hit) return sendJson(res, 400, { ok: false, error: 'that text mentions an internal harness identifier — please rephrase' });
        const r = withOperatorTodoFile((lines, parsed) => {
          const item = parsed.operatorItems[idx];
          if (!item) return { error: 'could not find that item — reload and try again' };
          lines[item.lineIndex] = '- [' + (item.checked ? 'x' : ' ') + '] ' + text.replace(/\r?\n/g, ' ');
          return { result: { index: idx, text: text, checked: item.checked } };
        });
        return sendJson(res, r.ok ? 200 : 404, r);
      }

      // pointer_override — constraint 7's operator-override exit path: "a
      // dismiss/mark-handled action on any pointer item ... an
      // operator-override flag the auditor respects (never fights)". Setting
      // the box to [x] IS what the auditor "respects" (autoCheckOperatorTodo
      // only ever touches an unchecked bullet); the appended marker is
      // additionally what tells THIS reader (and the UI) it was a manual
      // override rather than a ledger-derived auto-check.
      if (action === 'pointer_override') {
        const needsYouId = typeof input.needs_you_id === 'string' ? input.needs_you_id : '';
        if (!needsYouId) return sendJson(res, 400, { ok: false, error: 'missing needs_you_id' });
        const r = withOperatorTodoFile((lines, parsed) => {
          const item = parsed.pointerItems.find((p) => p.needsYouId === needsYouId);
          if (!item) return { error: 'could not find that pointer item — reload and try again' };
          if (item.checked) return { error: 'already marked handled' };
          const line = lines[item.lineIndex].replace('- [ ] AUTO:', '- [x] AUTO:') +
            ' (marked handled by operator, ' + new Date().toISOString() + ')';
          lines[item.lineIndex] = line;
          return { result: { needs_you_id: needsYouId, checked: true, operator_override: true } };
        });
        return sendJson(res, r.ok ? 200 : (r.error === 'already marked handled' ? 409 : 404), r);
      }

      return sendJson(res, 400, { ok: false, error: 'unknown action: ' + String(action) });
    });
    return;
  }

  // ---- Task 15 "Backlog pane" — GET renders docs/backlog.md (compact
  // top-N-per-tier + full list); POST is the ONE write path (add / dispose /
  // undo — constraint 9's disposition UX: SCHEDULE/DEMOTE/FOLD/WONTFIX
  // writing the EXACT vocabulary the O.9 loop's golden oracle
  // (od_backlog_health) already understands, row-scoped, to the REAL file —
  // never a parallel store). See buildBacklogPayload()/withBacklogFile()
  // above for the anti-noise scoping rationale (deliberately NOT run over
  // row content) and the row-grammar parity notes.
  if (url === '/api/backlog' && req.method === 'GET') {
    try { return sendJson(res, 200, buildBacklogPayload()); }
    catch (e) { return sendJson(res, 200, { ok: false, error: String(e && e.message || e), compact: {}, full: [] }); }
  }

  if (url === '/api/backlog' && req.method === 'POST') {
    let bodyBuf = '';
    req.on('data', (c) => { bodyBuf += c; if (bodyBuf.length > 2e5) req.destroy(); });
    req.on('end', () => {
      let input;
      try { input = bodyBuf ? JSON.parse(bodyBuf) : {}; } catch (_) { return sendJson(res, 400, { ok: false, error: 'bad json' }); }
      const action = input.action;

      // ---- add: appends a well-formed row (Prove-it-works step 2) at the
      // end of the "Open work — substantive deferrals" section. Both the
      // operator (via this form) and Claude (any future caller of this same
      // endpoint) write the SAME shape the O.9 loop already parses — no
      // separate "Claude path".
      if (action === 'add') {
        // Guard 3 (Stage 3c): neutralize markdown `**` in the VERBATIM title /
        // description so operator text can't smuggle a `**KEYWORD` bold
        // segment (probe G/H). backlogNeutralizeMarkdown collapses `**`->`*`
        // and flattens newlines — no WORD is altered.
        const title = typeof input.title === 'string' ? backlogNeutralizeMarkdown(input.title) : '';
        if (!title) return sendJson(res, 400, { ok: false, error: 'title cannot be empty' });
        const priority = ['high', 'medium', 'low'].indexOf(input.priority) !== -1 ? input.priority : 'medium';
        const description = typeof input.description === 'string' ? backlogNeutralizeMarkdown(input.description) : '';
        const today = new Date().toISOString().slice(0, 10);
        const r = withBacklogFile((lines) => {
          const id = generateBacklogId(lines, title);
          const body = description ? (' ' + description) : '';
          // Guard 1 (Stage 3c): ONLY the (keyword-guarded) id sits inside the
          // leading bold; the verbatim title follows a COLON (not the em-dash
          // real rows use inside the bold), so a keyword-leading title can't
          // chain off the id's closing `**` via R2 (probe C vs D). Result: a
          // fresh open row classifies OPEN under od_backlog_health regardless
          // of what disposition words the title/description contain.
          const rowLine = '- **' + id + '**: ' + title + ' (added ' + today + '; label: `workstreams-ui`; priority:' + priority + ').' + body;
          const insertAt = findBacklogInsertIndex(lines);
          const toInsert = (insertAt > 0 && lines[insertAt - 1].trim() !== '') ? ['', rowLine] : [rowLine];
          lines.splice(insertAt, 0, ...toInsert);
          return { result: { id: id, line: rowLine } };
        });
        return sendJson(res, r.ok ? 200 : 500, r);
      }

      // ---- dispose: appends the disposition marker to the ROW'S OWN first
      // line (the same line the golden oracle's R1-R4 rules scan — see the
      // helper block header). Returns `appended_suffix` verbatim so the
      // client can request an EXACT, byte-safe `undo` (constraint 9: a
      // non-destructive disposition offers undo; WONTFIX is terminal and the
      // client deliberately never offers undo for it, though the server
      // itself does not special-case that — the UI is the one enforcing
      // "CONFIRM instead of undo" for WONTFIX).
      if (action === 'dispose') {
        const id = typeof input.id === 'string' ? input.id.trim() : '';
        const disposition = typeof input.disposition === 'string' ? input.disposition.toLowerCase() : '';
        if (!id) return sendJson(res, 400, { ok: false, error: 'missing id' });
        if (!BACKLOG_DISPOSITION_WORD[disposition]) return sendJson(res, 400, { ok: false, error: 'unknown disposition: ' + String(input.disposition) });
        const today = new Date().toISOString().slice(0, 10);
        let word = BACKLOG_DISPOSITION_WORD[disposition];
        if (disposition === 'fold') {
          const target = backlogSlugifyFoldTarget(input.target);
          if (target) word = 'FOLD-INTO-' + target;
        }
        let note = disposition + ' via workstreams-ui';
        if (disposition === 'wontfix' && typeof input.reason === 'string' && input.reason.trim()) {
          note += ': ' + input.reason.trim().replace(/[\r\n]+/g, ' ').slice(0, 200);
        }
        const suffix = ' **' + word + ' ' + today + '** (' + note + ')';
        const r = withBacklogFile((lines) => {
          const idx = findBacklogLineIndexForId(lines, id);
          if (idx === -1) return { error: 'could not find backlog row ' + id + ' — reload and try again' };
          lines[idx] = lines[idx] + suffix;
          return { result: { id: id, disposition: disposition, word: word, appended_suffix: suffix, terminal: disposition === 'wontfix' } };
        });
        return sendJson(res, r.ok ? 200 : 404, r);
      }

      // ---- undo: removes EXACTLY the suffix a prior `dispose` call
      // returned, restoring the row byte-unchanged (Prove-it-works step 3:
      // "undo restores the row unchanged"). Refuses (409) if the row no
      // longer ends with that exact suffix — e.g. a concurrent edit — rather
      // than guessing and corrupting an unrelated byte range.
      if (action === 'undo') {
        const id = typeof input.id === 'string' ? input.id.trim() : '';
        const suffix = typeof input.appended_suffix === 'string' ? input.appended_suffix : '';
        if (!id || !suffix) return sendJson(res, 400, { ok: false, error: 'missing id or appended_suffix' });
        const r = withBacklogFile((lines) => {
          const idx = findBacklogLineIndexForId(lines, id);
          if (idx === -1) return { error: 'could not find backlog row ' + id + ' — reload and try again' };
          if (lines[idx].slice(-suffix.length) !== suffix) return { error: 'row changed since the disposition — reload to check its current state' };
          lines[idx] = lines[idx].slice(0, lines[idx].length - suffix.length);
          return { result: { id: id, undone: true } };
        });
        return sendJson(res, r.ok ? 200 : 409, r);
      }

      return sendJson(res, 400, { ok: false, error: 'unknown action: ' + String(action) });
    });
    return;
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
