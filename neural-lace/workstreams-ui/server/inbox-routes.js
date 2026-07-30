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
// "blocks: <item>" (I5 collapsed-row anatomy) — WIRED (2026-07-29 round 14,
// ROADMAP-WAITING-ON-YOU-SIGNAL-01)
// ============================================================
// The plan specs a "blocks: <item>" chip linking `#roadmap/<id>` when an
// Inbox item stalls live work. roadmap-routes.js's buildWaitingOnYouMap()
// now produces the forward signal (an Inbox item's text/links, matched
// CONSERVATIVELY via plan-parse.js's extractPlanTaskReferences — see that
// function's own header for the exact rule — feeds
// stalledSignals.waitingOnYouId into deriveStalledReason). This route
// performs the SAME conservative match in the REVERSE direction
// (resolveBlocksRoadmapId, below) — duplicated per this codebase's own
// established small-duplicated-reader convention (see this file's own
// header above, and auditor.js's "WHY THE READERS BELOW ARE DUPLICATED")
// rather than a cross-route require (roadmap-routes.js already requires
// THIS file for the ledger read; requiring back would be circular).
// `blocks_roadmap_id` is `null` whenever no conservative match is found —
// inbox.js omits the chip entirely when null (never a fake/dead link).
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
const planParse = require('./plan-parse.js');
const deriveLib = require('./derive-lib.js');

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

// ----------------------------------------------------------------------
// LedgerUnavailableError — thrown by readNeedsYouLedgerItems() for every
// "the file is present but we cannot trust it" case. A distinct type (not
// a bare Error) so buildInboxPayload() can tell "ledger genuinely broken"
// apart from any other unexpected exception without string-sniffing a
// message.
// ----------------------------------------------------------------------
class LedgerUnavailableError extends Error {}

// readNeedsYouLedgerItems() — THREE-STATE read contract (2026-07-29
// hardening, incident: ~/.claude/state/needs-you/ledger.json sat as a
// 1-byte "\n" file for ~2 days; GET /api/inbox returned
// {"ok":false,"error":"...Unexpected end of JSON input"} the whole time
// while the cockpit rendered a confident "nothing on your list" beside the
// count badge — the renderer had no explicit signal distinguishing "we
// checked, there is truly nothing" from "we could not check at all").
//
// Return contract:
//   - Returns `null`                         -> file ABSENT (never created;
//     needs-you.sh has never run on this machine). Not an error.
//   - Returns an array (possibly empty)       -> file PRESENT, VALID, and
//     shaped as expected. An empty array here is a GENUINE, trustworthy
//     zero — the ledger was actually read and confirmed to have no items.
//   - THROWS LedgerUnavailableError            -> file PRESENT but
//     UNTRUSTWORTHY: empty/whitespace-only, truncated, malformed JSON, OR
//     valid JSON in the wrong shape (not an object, or `.items` missing/
//     not an array). This must NEVER be silently coerced into an empty
//     array — a caller cannot tell "confirmed zero" from "have no idea"
//     that way, which is exactly the incident's blind spot.
//
// NOTE on the 0-byte/1-byte-newline shape specifically (the incident's
// exact fixture): unlike bash's `jq empty` (which treats whitespace-only
// input as a VACUOUS SUCCESS — the blind spot the sibling bash fix in
// needs-you.sh/state-json-init.sh had to work around with `jq -e 'type'`),
// JS's JSON.parse has NO such trap — `JSON.parse('')` and `JSON.parse('\n')`
// both throw "Unexpected end of JSON input" natively, every engine, always.
// So the empty/whitespace case is already caught below by the JSON.parse
// try/catch with no extra check needed; the check that's actually NEW here
// is the shape validation after a successful parse (a valid-JSON-but-wrong-
// shape document like `null`/`{}` used to silently coerce to `[]`).
function readNeedsYouLedgerItems() {
  let raw;
  try {
    raw = fs.readFileSync(needsYouLedgerFile(), 'utf8');
  } catch (err) {
    // INBOX-UNREADABLE-LEDGER-WIN-STATE-01 (2026-07-29 round 14): ENOENT
    // (the file genuinely does not exist) is the ONLY true-empty case —
    // needs-you.sh has never run on this machine, not an error. Every
    // OTHER errno (EACCES/EISDIR/EIO/a mid-read race on a present file)
    // means the ledger EXISTS but could not be read — that must raise the
    // SAME LedgerUnavailableError as a malformed/wrong-shape ledger below,
    // never be silently folded into "absent" (which renders the
    // not_yet_derived -> "nothing waiting on you" WIN STATE while open
    // items may actually wait). Mirrors derive-lib.js's own
    // listRawHeartbeatsResult fix for the identical errno-conflation class
    // (Task 1 comprehension-review fix R-1) — the ledger reader was the
    // missed sibling that fix's own sweep note flagged.
    if (err && err.code === 'ENOENT') return null; // absent — TRUE-empty, not an error
    throw new LedgerUnavailableError('ledger.json exists but could not be read (' + (err && err.code ? err.code : String(err && err.message || err)) + ')');
  }

  let parsed;
  try { parsed = JSON.parse(raw); }
  catch (e) { throw new LedgerUnavailableError('ledger.json is not valid JSON: ' + (e && e.message || e)); }

  // Shape validation: a valid JSON document that ISN'T our expected
  // {items: [...]} object (e.g. `null`, `{}`, `{"items":"oops"}`) used to
  // silently fall through to `[]` — indistinguishable from "confirmed
  // zero". That is the same class of blind spot as the empty-file case:
  // the ledger is technically parseable but not trustworthy, so it must
  // raise the SAME unavailable signal, not a quiet empty array.
  if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
    throw new LedgerUnavailableError('ledger.json parsed but is not an object (got ' + (parsed === null ? 'null' : Array.isArray(parsed) ? 'array' : typeof parsed) + ')');
  }
  if (!Array.isArray(parsed.items)) {
    throw new LedgerUnavailableError('ledger.json parsed but .items is missing or not an array (got ' + typeof parsed.items + ')');
  }
  return parsed.items;
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
//
// INBOX-OPTIONS-ARROW-FORMAT-NOT-PARSED (2026-07-29 round 14, operator
// live complaint): a REAL production ledger item (NY-1785357818-7d3f)
// proved a second, lint-PASSING §3 shape this parser never recognized —
// "Option <NAME> -> <effect> -> <outcome>" prose (never a markdown
// table). needs-you.sh's own cold-reader lint only checks for the WORDS
// (context/anchor/outcomes present), not a rigid grammar, so this shape
// legitimately passes the write-side gate while the read side silently
// swallowed its three options into unstructured context prose — the
// Trade-offs table (anatomy step 3) rendered EMPTY for a decision that
// very clearly enumerated three real options with real outcomes. Fixed
// by recognizing this shape as a SECOND options grammar, alongside the
// markdown-table one (both accumulate into the SAME options[] array).
// ----------------------------------------------------------------------
function stripMdEmphasis(s) { return String(s).replace(/^\*+/, '').replace(/\*+$/, '').trim(); }

// OPTION_ARROW_RE — "Option <NAME> -> ... " (an em-dash arrow "—>" or a
// double-hyphen "-->" are also accepted spellings seen in practice).
// Deliberately captures EVERYTHING after the arrow as the outcome
// (including any FURTHER arrows in a multi-step "action -> effect ->
// outcome" chain, our real fixture's own shape) rather than trying to
// split on every arrow — losing no text is more important than a
// perfectly-segmented cell (I5's own "never drop content" spirit).
const OPTION_ARROW_RE = /^option\s+(\S+)\s*(?:->|-->|—>)\s*(.+)$/i;

function parseDecisionAnatomy(rawText) {
  const lines = String(rawText || '').split('\n');
  // A producer sometimes repeats the literal "Decision needed:"/"Question:"
  // label INSIDE its own first line (needs-you.sh's lint accepts this shape
  // too) — strip it here so the client's expandedAnatomy header (which
  // ALWAYS prepends its own "Decision needed: "/"Question: " label) never
  // doubles it (the live bug: title rendered "Decision needed: Decision
  // needed: ...").
  const titleLine = stripMdEmphasis(lines[0] || '').replace(/^#+\s*/, '').trim();
  const title = titleLine.replace(/^(decision needed|question)\s*:\s*/i, '').trim() || '(untitled decision)';
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

    const arrowM = OPTION_ARROW_RE.exec(t);
    if (arrowM) { options.push({ option: arrowM[1], outcome: arrowM[2].trim() }); return; }

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
// extractAnchorsFromText(text) — INBOX-MULTILINE-ASK-TRUNCATED-AT-RENDER-01
// part (b): a producer that never called needs-you.sh's `--link` still
// routinely names concrete anchors INLINE in its prose (repo paths, ledger
// ids, workflow ids, URLs) — needs-you.sh's own cold-reader lint requires
// "a concrete anchor" to pass at all (LINT_LABELS 'no-anchor' above), so an
// answerable item is GUARANTEED to name one somewhere in its text, yet
// `links[]` stayed empty because nothing ever scanned the text for it.
// CONSERVATIVE, three shapes only (a false/unresolvable "link" is worse
// than none — the coordinator's own binding rule):
//   - http(s) URLs (always resolve — real absolute hrefs client-side).
//   - repo-relative paths with a recognized source-file extension AND at
//     least one internal slash (low false-positive risk; ordinary prose
//     essentially never contains a slash-delimited, extensioned token by
//     accident) — rendered client-side as copyable text, NEVER a fake
//     clickable href (a relative path cannot honestly resolve in a
//     browser — see inbox.js's absoluteLinkNode).
//   - this codebase's own NY-<digits>-<hex> ledger ids and wf_<hex...>
//     workflow ids (both unambiguous, narrow shapes).
// Merged into (never replacing) any producer-supplied `--link` entries,
// deduplicated.
// ----------------------------------------------------------------------
const ANCHOR_URL_RE = /https?:\/\/[^\s)]+/g;
const ANCHOR_PATH_RE = /\b[\w.-]+(?:\/[\w.-]+)+\.(?:md|js|sh|json|ts|tsx|py|yml|yaml|css|html)\b/g;
const ANCHOR_NY_ID_RE = /\bNY-\d+-[a-f0-9]+\b/g;
const ANCHOR_WF_ID_RE = /\bwf_[a-f0-9-]+\b/g;

function extractAnchorsFromText(text) {
  const hay = String(text || '');
  const found = [];
  const seen = {};
  function collect(re) {
    let m;
    re.lastIndex = 0;
    while ((m = re.exec(hay))) {
      const v = m[0].replace(/[.,;:)]+$/, ''); // trailing punctuation never belongs to the anchor
      if (!seen[v]) { seen[v] = true; found.push(v); }
    }
  }
  collect(ANCHOR_URL_RE);
  collect(ANCHOR_PATH_RE);
  collect(ANCHOR_NY_ID_RE);
  collect(ANCHOR_WF_ID_RE);
  return found;
}

// mergeLinks(producerLinks, extractedLinks) -> deduplicated array,
// producer-supplied entries first (an explicit `--link` is a stronger,
// deliberate signal than a best-effort text scan).
function mergeLinks(producerLinks, extractedLinks) {
  const out = Array.isArray(producerLinks) ? producerLinks.slice() : [];
  const seen = {};
  out.forEach((l) => { seen[l] = true; });
  (extractedLinks || []).forEach((l) => { if (!seen[l]) { seen[l] = true; out.push(l); } });
  return out;
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
// resolveBlocksRoadmapId(item) — see the file header "blocks: <item>"
// section above for the full contract. Returns the roadmap item id
// ('<slug>/<task_id>') a real, verified reference resolves to, or null.
// ----------------------------------------------------------------------
function planScanRootForBlocksLookup() {
  return process.env.ROADMAP_PLAN_SCAN_ROOT || deriveLib.mainRepoRoot();
}
function resolveBlocksRoadmapId(item) {
  const haystack = String(item.text || '') + ' ' + (Array.isArray(item.links) ? item.links.join(' ') : '');
  const refs = planParse.extractPlanTaskReferences(haystack);
  if (!refs.length) return null;
  const scanRoot = planScanRootForBlocksLookup();
  for (let i = 0; i < refs.length; i++) {
    const ref = refs[i];
    const abs = planParse.resolvePlanAbsPath(scanRoot, ref.slug);
    if (!abs) continue;
    const loaded = planParse.loadPlanFile(abs);
    if (!loaded.ok) continue;
    const isRealTask = (loaded.tasks || []).some((t) => t.id === ref.taskId);
    if (!isRealTask) continue; // never a fabricated correlation
    return ref.slug + '/' + ref.taskId;
  }
  return null;
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
    // INBOX-MULTILINE-ASK-TRUNCATED-AT-RENDER-01 (b): producer-supplied
    // `--link` entries FIRST, then any anchor extractAnchorsFromText finds
    // inline in the raw text that isn't already listed — merged, never
    // replacing what the producer explicitly supplied.
    links: mergeLinks(Array.isArray(item.links) ? item.links : [], extractAnchorsFromText(item.text)),
    context: anatomy.context,
    options: anatomy.options,
    my_pick: anatomy.my_pick,
    reply_with: anatomy.reply_with,
    reply_channel: replyChannel(item),
    reply_stub: replyStub(anatomy.title),
    raw_text: item.text || '',
    // WIRED (see file header "blocks: <item>") — null when no conservative
    // match is found; inbox.js omits the "blocks:" chip entirely then
    // (never a fake/dead link).
    blocks_roadmap_id: resolveBlocksRoadmapId(item),
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
//
// THREE-STATE CONTRACT (2026-07-29 hardening — see readNeedsYouLedgerItems'
// own header for the incident this closes). Every response carries a
// `status` field the renderer can switch on WITHOUT having to reconstruct
// the distinction from `ok` + `error` + array-emptiness:
//
//   status: 'ok'              — the ledger was read and TRUSTED. answerable/
//     quarantined are the real truth, including the case where both are
//     empty (a GENUINE, confirmed zero — "you're caught up", not "unknown").
//     ok: true, ledger_present: true, error: null.
//
//   status: 'not_yet_derived' — ledger.json has never been created (needs-
//     you.sh has never run on this machine). Distinct from a confirmed
//     zero: nothing has been DERIVED at all yet, so this should read as
//     "not set up" rather than "you're caught up". ok: true (this is not a
//     failure), ledger_present: false, error: null, arrays empty.
//
//   status: 'unavailable'     — ledger.json EXISTS but could not be
//     trusted (empty/whitespace-only, truncated, malformed JSON, or valid-
//     JSON-wrong-shape — see readNeedsYouLedgerItems). The renderer MUST
//     NOT show a confident "nothing on your list" here — genuine zero
//     cannot be asserted. ok: false, ledger_present: true, error: a plain-
//     language reason, arrays empty (never fabricated).
// ----------------------------------------------------------------------
function buildInboxPayload() {
  const generatedAt = new Date().toISOString();
  let items;
  try {
    items = readNeedsYouLedgerItems();
  } catch (e) {
    return {
      ok: false,
      status: 'unavailable',
      generated_at: generatedAt,
      answerable: [],
      quarantined: [],
      ledger_present: true,   // the file exists — it's just untrustworthy, never confused with "never created"
      error: String(e && e.message || e),
    };
  }
  if (items === null) {
    // No ledger file yet — needs-you.sh has never run on this machine.
    // Distinct from a CONFIRMED zero (status 'ok' with empty arrays): this
    // is "nothing has been derived", not "we checked and there is nothing".
    return {
      ok: true,
      status: 'not_yet_derived',
      generated_at: generatedAt,
      answerable: [],
      quarantined: [],
      ledger_present: false,
      error: null,
    };
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
  return {
    ok: true,
    status: 'ok',
    generated_at: generatedAt,
    answerable: answerable,
    quarantined: quarantined,
    ledger_present: true,
    error: null,
  };
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
      // Last-resort net: buildInboxPayload() itself already catches every
      // ledger-read failure into a well-formed {status:'unavailable', ...}
      // payload, so reaching here means something OTHER than the ledger
      // read blew up (a genuine bug). Same three-state shape regardless,
      // so the renderer never has to special-case this path.
      sendJson(res, 200, { ok: false, status: 'unavailable', generated_at: new Date().toISOString(), error: String(e && e.message || e), answerable: [], quarantined: [], ledger_present: true });
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
  LedgerUnavailableError,
  resolveBlocksRoadmapId,
  extractAnchorsFromText,
  mergeLinks,
};
