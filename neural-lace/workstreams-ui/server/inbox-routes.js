'use strict';
// inbox-routes.js — the Inbox view's server surface (cockpit-roadmap-redesign
// Task 4, "Inbox view + context contract enforcement"). A NEW file by design,
// mirroring task 3/5's roadmap-routes.js/requests-routes.js precedent: task 1
// owns server.js, so this task adds its route handlers HERE and the ONE
// server.js mount line ships as a fragment
// (docs/plans/fragments/roadmap-t4-server-fragment.md) for the orchestrator
// to apply — never a direct edit to a file another task owns.
//
// ============================================================
// THE ORACLE: needs-you.sh's ledger.json (never the rendered NEEDS-YOU.md)
// ============================================================
// This module reads `<NEEDS_YOU_STATE_DIR>/ledger.json` directly — the SAME
// oracle `od_needs_me` (adapters/claude-code/hooks/lib/observability-
// derive.sh) already reads, per that function's own header: "THE oracle;
// never re-derives from the rendered NEEDS-YOU.md". The rendered .md is a
// human-readable PROJECTION of this same data (needs-you.sh's own render
// pipeline); re-deriving from it here would be a SECOND, divergeable parse
// of the same fact. The reader is a small, deliberately duplicated JSON
// reader (this codebase's own established convention — see auditor.js's
// header "WHY THE READERS BELOW ARE DUPLICATED, NOT REQUIRED FROM server.js"
// for the precedent this follows) rather than a new export threaded through
// derive-lib.js (task-1-owned; extending it needs a fragment, and this
// reader is small enough that duplicating it is the lower-risk path).
//
// ============================================================
// CONTEXT CONTRACT (I4/A8) — routing items into two buckets
// ============================================================
// ANSWERABLE = open items in section 'decision' or 'question' whose
// lint_warnings (stamped by needs-you.sh's cold-reader lint AT ADD TIME —
// never a second heuristic here) is EMPTY. Only decision/question sections
// count as "waiting on the operator" — 'inflight' entries are a status
// narrative the operator does not owe an action on (needs-you.sh's own
// SCOPING DECISION comment says the same about its progress-log/todo-pointer
// splice; this view applies the identical exclusion) and 'decided' entries
// are already resolved. The Inbox (N) headline count = answerable.length,
// EXACTLY (I4/A10 — quarantined and "My items" are excluded).
//
// QUARANTINED = open 'decision' items whose lint_warnings is non-empty.
// 'question' items are NEVER quarantined (needs-you.sh's lint is scoped to
// --section decision only, T25) — a context-less question simply cannot
// occur by construction.
//
// "My items" (operator-authored freeform items, A10): this task's own text
// names them as a section WITHIN the Inbox view, but Task 8's own bullet
// ("the standalone My-To-Do pane REMOVED — its operator-authored items move
// into the Inbox 'My items' section per A10/task 4") claims ownership of
// BOTH the removal AND the relocation as one unit of work. Per this task's
// dispatch note ("do NOT retire if assigned to task 8"), that migration is
// left to task 8; this route does not serve todo.js's /api/todo data. See
// docs/backlog.md for the tracked follow-up.
//
// ============================================================
// "blocks: <item>" (I5 collapsed-row anatomy) — HONEST LIMIT
// ============================================================
// The plan specs a "blocks: <item>" chip linking `#roadmap/<id>` when an
// Inbox item stalls live work. Task 1's deriveStalledReason() accepts a
// caller-supplied `stalledSignals.waitingOnYouId` per roadmap item
// (server/derive-lib.js:586), but roadmap-routes.js (task 3, already
// merged) never populates it — no roadmap item is today computed as
// "stalled: waiting-on-you" pointing at a specific needs-you ledger id, so
// there is no live data source for a reverse (ledger-id -> roadmap-item)
// lookup. Rather than fabricate a correlation that does not exist,
// `blocks` is always `null` on every item this route returns; inbox.js
// omits the chip entirely when null (never a fake/dead link). Wiring the
// forward signal is roadmap-routes.js's file (task-3-owned) — flagged in
// docs/backlog.md as a named follow-up, not silently routed around here.
//
// ============================================================
// ANATOMY PARSING (I5 — constitution §3 compact format, best-effort)
// ============================================================
// needs-you.sh stores the RAW --text block a producer supplied; for
// --section decision entries authored per the §3 template it has the shape:
//   ### <title>
//   <context prose, 1+ lines>
//   | Option | What happens |
//   |---|---|
//   | <option> | <outcome> |
//   My pick: <reason>
//   Reply with: <exact answers + what each triggers>
// parseDecisionAnatomy() below extracts title/context/options/my_pick/
// reply_with via tolerant line-shape detection (same heuristic-detection
// spirit as needs-you.sh's own _ny_lint_decision_text — presence-based, not
// a rigid grammar) so a well-formed block renders its full anatomy while an
// unanticipated shape degrades to "context: (whatever prose is left)"
// rather than crashing. 'question' section items have no such structure —
// needs-you.sh's SECTION SEMANTICS documents them as a single bullet line,
// so their anatomy is just the text itself.

const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawn } = require('child_process');

const WEB_DIR = path.join(__dirname, '..', 'web');

function sendJson(res, code, obj) {
  res.writeHead(code, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify(obj));
}

// ----------------------------------------------------------------------
// needsYouStateDir/needsYouLedgerFile — mirrors needs-you.sh's own
// `_ny_state_dir` resolution order (NEEDS_YOU_STATE_DIR env override, else
// $HOME/.claude/state/needs-you) so a self-test's env override is honored
// exactly like every other reader in this codebase.
// ----------------------------------------------------------------------
function needsYouStateDir() {
  return process.env.NEEDS_YOU_STATE_DIR ||
    path.join(process.env.HOME || os.homedir(), '.claude', 'state', 'needs-you');
}
function needsYouLedgerFile() {
  return path.join(needsYouStateDir(), 'ledger.json');
}
function readNeedsYouLedgerItems() {
  let raw;
  try { raw = fs.readFileSync(needsYouLedgerFile(), 'utf8'); } catch (_) { return null; } // absent — TRUE-empty, not an error
  let parsed;
  try { parsed = JSON.parse(raw); } catch (e) { throw new Error('ledger.json is not valid JSON: ' + (e && e.message || e)); }
  return (parsed && Array.isArray(parsed.items)) ? parsed.items : [];
}

// auditorNlIssueStatePath — MIRRORS auditor.js's own resolver exactly (same
// env var, same fallback) so this route can honestly report whether the A8
// auto-defect has ACTUALLY been filed yet by the auditor cycle, rather than
// asserting a defect exists before the cycle that files it has ever run.
function auditorNlIssueStatePath() {
  return process.env.AUDITOR_NL_ISSUE_STATE_PATH ||
    path.join(process.env.HOME || os.homedir(), '.claude', 'state', 'auditor-nl-issue-state.json');
}
function readAuditorFiledIds() {
  try {
    const parsed = JSON.parse(fs.readFileSync(auditorNlIssueStatePath(), 'utf8'));
    return (parsed && typeof parsed.filed === 'object' && parsed.filed) || {};
  } catch (_) { return {}; }
}

// ----------------------------------------------------------------------
// needs-you.sh CLI delegation (one-writer discipline) — duplicated per this
// codebase's small-helper convention (requests-routes.js's own header note
// on why each route module carries its own copy).
// ----------------------------------------------------------------------
function needsYouCliPath() {
  return process.env.NEEDS_YOU_CLI ||
    path.join(__dirname, '..', '..', '..', 'adapters', 'claude-code', 'scripts', 'needs-you.sh');
}
function runNeedsYouCli(args) {
  return new Promise((resolve) => {
    const cli = needsYouCliPath();
    if (!fs.existsSync(cli)) return resolve({ ok: false, missing: true, error: 'needs-you.sh not found' });
    let bashBin, spawnEnv;
    try {
      const dc = require('./derive-cache.js');
      bashBin = dc.bashBin; spawnEnv = dc.spawnEnv;
    } catch (e) { return resolve({ ok: false, error: 'shell environment unavailable' }); }
    const shQuote = (s) => "'" + String(s).replace(/'/g, "'\\''") + "'";
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
    setTimeout(() => done({ ok: false, error: 'needs-you.sh call timed out' }), 60000);
  });
}

// ----------------------------------------------------------------------
// parseDecisionAnatomy(rawText) — tolerant §3 block parser. See file
// header "ANATOMY PARSING" for the shape it targets and the degrade path.
// ----------------------------------------------------------------------
function stripMdEmphasis(s) { return String(s).replace(/^\*+/, '').replace(/\*+$/, '').trim(); }

function parseDecisionAnatomy(rawText) {
  const lines = String(rawText || '').split('\n');
  const title = stripMdEmphasis(lines[0] || '').replace(/^#+\s*/, '').trim() || '(untitled decision)';
  const context = [];
  const options = [];
  let myPick = '';
  let replyWith = '';
  let sawTableHeader = false;
  let sawTableSep = false;

  lines.slice(1).forEach((line) => {
    const t = line.trim();
    if (!t) return;
    const clean = stripMdEmphasis(t);

    const pickM = /^my pick:\s*(.*)$/i.exec(clean);
    if (pickM) { myPick = pickM[1].trim(); return; }
    const replyM = /^reply(?:\s*with)?:\s*(.*)$/i.exec(clean);
    if (replyM) { replyWith = replyM[1].trim(); return; }

    if (/^\|/.test(t)) {
      if (!sawTableHeader) { sawTableHeader = true; return; } // header row ("Option | What happens") — labels only
      // separator row, e.g. "|---|---|"
      if (/^[|:\s-]+$/.test(t)) { sawTableSep = true; return; }
      if (sawTableSep) {
        const cells = t.split('|').map((c) => c.trim()).filter((c, i, arr) => !(i === 0 && c === '') && !(i === arr.length - 1 && c === ''));
        if (cells.length >= 2) options.push({ option: cells[0], outcome: cells[1] });
      }
      return;
    }
    context.push(t);
  });

  return { title: title, context: context, options: options, my_pick: myPick, reply_with: replyWith };
}

// ----------------------------------------------------------------------
// replyChannel(item) — v1 ANSWER lifecycle verb (C3a): a "how to answer"
// line naming the exact channel, never inline answering (the PENDING
// decision — see plan Decisions Log; this build ships pointer+stub).
// ----------------------------------------------------------------------
function replyChannel(item) {
  if (item.session) return 'reply in session `' + item.session + '`';
  return 'reply via the NEEDS-YOU.md ledger entry (id `' + item.id + '`)';
}
function replyStub(title) {
  return 'Re: "' + title + '" — my answer: ';
}

// ----------------------------------------------------------------------
// LINT CODE -> human label (never render the raw needs-you.sh code alone —
// asks.js/requests.js's own anti-noise-law precedent: hardcoded, reviewed
// literals, not mechanism identifiers, in operator-visible text).
// ----------------------------------------------------------------------
const LINT_LABELS = {
  'no-context': 'no background — what this thing IS was never said',
  'no-anchor': 'no concrete anchor (a repo path, URL, or id)',
  'no-outcomes': 'no per-option outcome text (what each answer changes)',
};
function lintReasons(lintWarnings) {
  return (lintWarnings || []).map((code) => LINT_LABELS[code] || code);
}

// ----------------------------------------------------------------------
// buildInboxItem(item) — shared shape for BOTH answerable and quarantined
// rows (I5 anatomy fields are the same; quarantine-only fields are added by
// the caller). `kind` mirrors the ledger's own `section` value.
// ----------------------------------------------------------------------
function buildInboxItem(item) {
  const kind = item.section; // 'decision' | 'question'
  const anatomy = kind === 'decision'
    ? parseDecisionAnatomy(item.text)
    : { title: String(item.text || '').split('\n')[0].trim() || '(untitled question)', context: [], options: [], my_pick: '', reply_with: '' };

  return {
    id: item.id,
    kind: kind,
    title: anatomy.title,
    ask: kind === 'decision' ? anatomy.title : String(item.text || '').trim(),
    session: item.session || '',
    tier: item.tier || '',
    created_at: item.created_at || '',
    links: Array.isArray(item.links) ? item.links : [],
    context: anatomy.context,
    options: anatomy.options,
    my_pick: anatomy.my_pick,
    reply_with: anatomy.reply_with,
    reply_channel: replyChannel(item),
    reply_stub: replyStub(anatomy.title),
    raw_text: item.text || '',
    // HONEST LIMIT (see file header) — never fabricated; inbox.js omits the
    // "blocks:" chip entirely when null.
    blocks_roadmap_id: null,
  };
}

function buildQuarantineItem(item, filedIds) {
  const base = buildInboxItem(item);
  const lintWarnings = Array.isArray(item.lint_warnings) ? item.lint_warnings : [];
  return Object.assign(base, {
    lint_warnings: lintWarnings,
    lint_reasons: lintReasons(lintWarnings),
    defect_filed: !!filedIds['quarantine-' + item.id],
    open_source_session: item.session
      ? { has_session: true, resume_cmd: 'claude --resume ' + item.session }
      : { has_session: false, resume_cmd: '' },
  });
}

// ----------------------------------------------------------------------
// buildInboxPayload() — the CONTEXT CONTRACT split (I4/A8). See file header.
// ----------------------------------------------------------------------
function buildInboxPayload() {
  const items = readNeedsYouLedgerItems();
  if (items === null) {
    // No ledger file yet — a TRUE-empty state (nothing has ever landed),
    // never an error (C4: never mistake absence-of-file for a failure).
    return { ok: true, generated_at: new Date().toISOString(), answerable: [], quarantined: [], ledger_present: false };
  }
  const filedIds = readAuditorFiledIds();
  const answerable = [];
  const quarantined = [];
  items.forEach((it) => {
    if (!it || it.state !== 'open') return; // resolved/decided items have left the Inbox (C3b RESOLVE)
    if (it.section !== 'decision' && it.section !== 'question') return; // inflight/decided are not "waiting on the operator" (needs-you.sh's own scoping)
    const lintWarnings = Array.isArray(it.lint_warnings) ? it.lint_warnings : [];
    if (it.section === 'decision' && lintWarnings.length > 0) {
      quarantined.push(buildQuarantineItem(it, filedIds));
    } else {
      answerable.push(buildInboxItem(it));
    }
  });
  // sort = blocking-live-work first (none today — HONEST LIMIT above), then
  // age (oldest first — the longer something has waited, the more it
  // deserves attention first; I5's own sort law).
  const byAge = (a, b) => String(a.created_at).localeCompare(String(b.created_at));
  answerable.sort(byAge);
  quarantined.sort(byAge);
  return { ok: true, generated_at: new Date().toISOString(), answerable: answerable, quarantined: quarantined, ledger_present: true };
}

// ----------------------------------------------------------------------
// readBody — shared JSON body reader (same shape as requests-routes.js's).
// ----------------------------------------------------------------------
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
// handle(req, res) -> true when consumed. The ONE server.js mount line (see
// the fragment file): if (inboxRoutes.handle(req, res)) return;
// ----------------------------------------------------------------------
function handle(req, res) {
  const urlPath = String(req.url || '').split('?')[0];

  if (urlPath === '/inbox.js' && req.method === 'GET') {
    fs.readFile(path.join(WEB_DIR, 'inbox.js'), (err, buf) => {
      if (err) { res.writeHead(404); res.end('not found'); return; }
      res.writeHead(200, { 'Content-Type': 'text/javascript; charset=utf-8', 'Cache-Control': 'no-cache, must-revalidate' });
      res.end(buf);
    });
    return true;
  }

  if (urlPath === '/api/inbox' && req.method === 'GET') {
    try {
      sendJson(res, 200, buildInboxPayload());
    } catch (e) {
      // rc-style honesty: the client renders pane-error + Retry from
      // ok:false — NEVER the win state on failure (C4).
      sendJson(res, 200, { ok: false, error: String(e && e.message || e), answerable: [], quarantined: [] });
    }
    return true;
  }

  // POST /api/inbox/dismiss — the RESOLVE lifecycle verb (C3b): operator
  // dismiss is a LABELED override (consistent with every other derivation-
  // law override in this plan), delegated to needs-you.sh's own `resolve`
  // (one-writer discipline — no second ledger mutator).
  if (urlPath === '/api/inbox/dismiss' && req.method === 'POST') {
    readBody(req, (input) => {
      if (!input) return sendJson(res, 400, { ok: false, error: 'bad json' });
      const id = typeof input.id === 'string' ? input.id : '';
      if (!id) return sendJson(res, 400, { ok: false, error: 'id is required' });
      runNeedsYouCli(['resolve', id, '--note', 'dismissed by operator (Inbox view)'])
        .then((r) => {
          if (r.ok) return sendJson(res, 200, { ok: true, id: id });
          const why = r.missing ? 'needs-you.sh is not available on this build'
            : ('the ledger rejected the dismiss' + (r.stderr ? ': ' + String(r.stderr).trim().split('\n').pop() : ''));
          sendJson(res, 200, { ok: false, error: 'could not dismiss this item — ' + why });
        });
    });
    return true;
  }

  return false;
}

module.exports = {
  handle,
  buildInboxPayload,
  buildInboxItem,
  buildQuarantineItem,
  parseDecisionAnatomy,
  replyChannel,
  replyStub,
  lintReasons,
  readNeedsYouLedgerItems,
  needsYouStateDir,
  needsYouLedgerFile,
  auditorNlIssueStatePath,
  readAuditorFiledIds,
};
