'use strict';
// plan-parse.js — the ONE shared plan-markdown grammar + resolver
// (cockpit-v2-push-materialized-store Task 1).
//
// ============================================================
// WHY THIS EXISTS
// ============================================================
//
// Before this module, THREE independent plan-markdown grammars lived in this
// codebase, and they disagreed:
//   - server.js's `TASK_LINE_RE` / `countPlanTasks` (deleted by this task) —
//     numeric task ids ONLY (`- [ ] 1.` / `- [x] 12.3.`).
//   - auditor.js's `TASK_LINE_RE` / `parsePlanFile` (deleted by this task) —
//     the SAME numeric-only grammar, independently duplicated.
//   - `adapters/claude-code/hooks/plan-lifecycle.sh`'s
//     `extract_all_task_line_ids` (untouched by this task — the plan
//     explicitly forbids editing it) — numeric AND LETTERED ids
//     (`A.1`, `F.2b`, `20R.`), because it must recognize every task line
//     that could legitimately be checked, not just the plain-numeric
//     convention.
//
// A whole-corpus measurement (`docs/plans/**` + `docs/plans/archive/**`,
// 2026-07-17) found 176 task lines using a letter-prefixed id
// (`- [ ] A.1 ...` / `- [x] F.2b ...`) that the server/auditor grammar could
// never see — those plans' progress bars and task counts have been silently
// wrong for as long as they've existed. Porting `plan-lifecycle.sh`'s ID
// grammar faithfully (not a narrower reinvention of it) also picks up one
// more previously-invisible shape it already accepts — a bare digit run
// with a trailing letter and no letter PREFIX (`20R.`, real task line in
// `docs/plans/archive/conv-tree-ui-v1.1.2-polish.md`) — for a total corpus
// delta of +180 lines now counted that were not before. The remaining 3 of
// those 180 are NOT genuine task lines: they are non-task checklist bullets
// under a `## Definition of Done` heading (`- [ ] 19/19 self-test pass`,
// `- [ ] 20/20 self-test pass`, `- [ ] 5a referenced from >= 5 narrative
// docs`) that happen to satisfy the same loose id-token shape
// `plan-lifecycle.sh` already accepts IN PRODUCTION TODAY (that hook scans
// every checkbox line in the whole file, not just the `## Tasks` section,
// for its own amendment/task-done detection) — a pre-existing property of
// the grammar this module is instructed to port faithfully, not a new
// defect introduced here. Narrowing the grammar to exclude them (e.g.
// scoping to a `## Tasks` section) would be an INVENTED restriction beyond
// "port it faithfully" and risks silently dropping real numeric task lines
// that happen to live outside a literal `## Tasks` heading in some plan —
// a real regression against the "behavior parity everywhere except the
// intended fix" mandate. See the plan's own Task 1 text and the build
// evidence for the exact file-by-file delta breakdown.
//
// TWO resolvers also disagreed: server.js's `resolvePlanAbsPath` searched
// ONLY `docs/plans/`; auditor.js's version ALSO searched
// `docs/plans/archive/`. This module's resolver is the union (M5): every
// caller now finds an archived plan, not just auditor.js's callers.
//
// ============================================================
// API (consumed by server.js and auditor.js — see those files' own
// `resolveAskPlanAbsPath` glue for the repo-then-main-root fallback order,
// which stays LOCAL to each consumer per this codebase's own established
// convention of small, deliberately duplicated per-file glue — see
// auditor.js's header "WHY THE READERS BELOW ARE DUPLICATED")
// ============================================================
//   parseTasks(markdown)        -> [{id, done, description}, ...]
//   parsePlanStatus(markdown)   -> string ('' if no `Status:` header line)
//   resolvePlanAbsPath(repoRoot, slug) -> absolute path | null
//     (checks `<repoRoot>/docs/plans/<slug>.md` then
//      `<repoRoot>/docs/plans/archive/<slug>.md`; a caller wanting a
//      repo-then-main-root fallback calls this TWICE, once per root, taking
//      the first non-null result — see server.js/auditor.js's own
//      `resolveAskPlanAbsPath`.)
//   loadPlanFile(absPath)  -> the honest, rich read:
//       { ok: true,  tasks: [...], status: '<Status: value>', absPath }
//       { ok: false, reason: 'absent',  absPath, error: null }
//       { ok: false, reason: 'damaged', absPath, error: '<message>' }
//     'absent' = the file genuinely does not exist (ENOENT) — the caller
//     renders "no plan file found", never a defect. 'damaged' = the file
//     EXISTS but could not be read as a plan (permission error, is a
//     directory, or any other non-ENOENT failure) — a genuinely different,
//     honest state a future consumer (Task 5's staleness renderer) can
//     surface as `damaged` rather than silently collapsing it into the same
//     "empty/absent" bucket (never a silent zero).
//   parsePlanFile(absPath) -> `{tasks, status, absPath}` | `null` — the
//     EXACT prior shape of auditor.js's own `parsePlanFile` (both 'absent'
//     and 'damaged' collapse to `null` here, for drop-in parity with every
//     existing caller, which never distinguished the two). Built on
//     `loadPlanFile`.

const fs = require('fs');
const path = require('path');

// ----------------------------------------------------------------------
// Task-line grammar
// ----------------------------------------------------------------------

// TASK_LINE_START_RE — any checkbox bullet line, checked or not, with at
// least one space/tab before its content (mirrors plan-lifecycle.sh's own
// `^- \[[ xX]\][ \t]+` line anchor exactly).
const TASK_LINE_START_RE = /^- \[([ xX])\][ \t]+(.*)$/;

// TASK_ID_TOKEN_RE — ported VERBATIM from plan-lifecycle.sh's
// `extract_all_task_line_ids` (adapters/claude-code/hooks/plan-lifecycle.sh
// ~L342-356): an optional letter-prefix (`A.`, `F.`), mandatory digits, an
// optional single trailing letter, then zero or more repeated
// `.digits[letter]` groups. Accepts every shape live in the plan corpus
// today: `1`, `6.2`, `A.1`, `B.0`, `D.2`, `F.2b`, `20R`.
const TASK_ID_TOKEN_RE = /^([A-Za-z]+\.)?[0-9]+[A-Za-z]?(\.[0-9]+[A-Za-z]?)*/;

// MODE_PREFIX_RE — the `[serial]`/`[parallel]` dispatch-mode prefix that
// immediately follows the id + separator on many newer plans.
const MODE_PREFIX_RE = /^\[(serial|parallel)\][ \t]*/;

// VERIFICATION_SUFFIX_RE — the trailing `— Verification: <level>` (or
// `-- Verification: <level>`) marker. Applied as a POST-PROCESS pass over
// the fully-assembled description (continuation lines folded in first),
// since the marker is frequently on the LAST continuation line, not the
// task's own first line.
const VERIFICATION_SUFFIX_RE = /[ \t]*[—-]{1,2}[ \t]*Verification:[ \t]*\S+[ \t]*$/;

const STATUS_LINE_RE = /^Status:[ \t]*(.+?)[ \t]*$/;

// stripIdSeparator — the id token never includes the separator that follows
// it in the source text (a literal "." for `1. text`, or just whitespace
// for `A.1 text` — the id token itself already consumed any embedded dots).
// This strips exactly one leading "." (+ following space) if present, else
// leaves the (already-whitespace-led) remainder alone.
function stripIdSeparator(s) {
  return s.replace(/^\.[ \t]*/, ' ');
}

// parseTasks(markdown) -> [{id, done, description}, ...]
//
// Returns plain JS objects — no manual JSON string-building anywhere in
// this module — so a description containing `"`, `\`, or a raw newline is
// JSON-safe BY CONSTRUCTION the moment a caller does `JSON.stringify(...)`
// on the result; there is nothing here that could corrupt it.
//
// Continuation lines: an indented, non-blank line immediately following an
// open task (not itself a new task line, not a heading, not a blank line)
// is folded into that task's `description`, space-joined — this is how a
// plan's task block reads visually as one unit. Capture ends at a blank
// line, a heading line (`#...`), a new task line (which starts the next
// task), or any other non-indented line (a sibling top-level list item).
function parseTasks(markdown) {
  const text = markdown == null ? '' : String(markdown);
  const lines = text.split('\n');
  const tasks = [];
  let current = null;

  lines.forEach((rawLine) => {
    const line = rawLine.replace(/\r$/, '');

    const m = TASK_LINE_START_RE.exec(line);
    if (m) {
      const rest = m[2];
      const idM = TASK_ID_TOKEN_RE.exec(rest);
      if (idM && idM[0]) {
        const descRest = stripIdSeparator(rest.slice(idM[0].length))
          .trim()
          .replace(MODE_PREFIX_RE, '')
          .trim();
        current = {
          id: idM[0],
          done: (m[1] === 'x' || m[1] === 'X'),
          description: descRest,
        };
        tasks.push(current);
        return;
      }
      // A checkbox line whose content does NOT start with a valid id token
      // (e.g. a plain non-task `- [ ] ...` bullet) is not a task line —
      // ends whatever task was capturing continuation lines, same as any
      // other sibling top-level bullet.
      current = null;
      return;
    }

    if (line.trim() === '') { current = null; return; }
    if (/^#/.test(line)) { current = null; return; }

    if (current && /^[ \t]/.test(line)) {
      const cont = line.trim();
      if (cont) current.description = current.description ? current.description + ' ' + cont : cont;
      return;
    }

    // Non-indented, non-task, non-blank, non-heading line: a sibling
    // top-level line (prose/list item) — ends continuation capture.
    current = null;
  });

  tasks.forEach((t) => { t.description = t.description.replace(VERIFICATION_SUFFIX_RE, '').trim(); });
  return tasks;
}

// parsePlanStatus(markdown) -> the plan header's `Status:` value, or ''.
function parsePlanStatus(markdown) {
  const text = markdown == null ? '' : String(markdown);
  const lines = text.split('\n');
  for (let i = 0; i < lines.length; i++) {
    const m = STATUS_LINE_RE.exec(lines[i].replace(/\r$/, ''));
    if (m) return m[1].trim();
  }
  return '';
}

// ----------------------------------------------------------------------
// Resolver (M5 — the shared module owns this too, not just the parser)
// ----------------------------------------------------------------------

// resolvePlanAbsPath(repoRoot, slug) — checks `<repoRoot>/docs/plans/<slug>.md`
// then `<repoRoot>/docs/plans/archive/<slug>.md` (the union of the two
// resolvers this replaces: server.js's never checked archive/ at all;
// auditor.js's did). Returns null HONESTLY when neither exists under this
// one root — a caller wanting a repo-then-main-root fallback calls this
// function twice (see server.js/auditor.js's own `resolveAskPlanAbsPath`).
function resolvePlanAbsPath(repoRoot, slug) {
  if (!repoRoot || !slug) return null;
  const candidates = [
    path.join(repoRoot, 'docs', 'plans', slug + '.md'),
    path.join(repoRoot, 'docs', 'plans', 'archive', slug + '.md'),
  ];
  for (let i = 0; i < candidates.length; i++) {
    try {
      if (fs.existsSync(candidates[i]) && fs.statSync(candidates[i]).isFile()) return candidates[i];
    } catch (_) { /* try next candidate */ }
  }
  return null;
}

// ----------------------------------------------------------------------
// File loading — the honest absent/damaged distinction.
// ----------------------------------------------------------------------

// loadPlanFile(absPath) -> the rich, honest read (see header for the full
// contract). A malformed-but-present plan file (permission error, a
// directory masquerading as a `.md` path, any read failure that is NOT
// "file genuinely does not exist") reports `damaged`, never a silent empty
// task list indistinguishable from "this plan has zero tasks" or "no plan
// file exists at all".
function loadPlanFile(absPath) {
  if (!absPath) return { ok: false, reason: 'absent', absPath: absPath || null, error: null };
  let text;
  try {
    text = fs.readFileSync(absPath, 'utf8');
  } catch (err) {
    if (err && err.code === 'ENOENT') {
      return { ok: false, reason: 'absent', absPath: absPath, error: null };
    }
    return { ok: false, reason: 'damaged', absPath: absPath, error: String(err && err.message || err) };
  }
  return {
    ok: true,
    tasks: parseTasks(text),
    status: parsePlanStatus(text),
    absPath: absPath,
  };
}

// parsePlanFile(absPath) -> `{tasks, status, absPath}` | `null` — the EXACT
// prior return shape of auditor.js's own (now-deleted) `parsePlanFile`, so
// every existing call site is a drop-in swap. Both 'absent' and 'damaged'
// collapse to `null` here (parity: neither prior implementation ever
// distinguished them) — use `loadPlanFile` directly for the honest
// three-way distinction.
function parsePlanFile(absPath) {
  const r = loadPlanFile(absPath);
  return r.ok ? { tasks: r.tasks, status: r.status, absPath: r.absPath } : null;
}

module.exports = {
  parseTasks: parseTasks,
  parsePlanStatus: parsePlanStatus,
  resolvePlanAbsPath: resolvePlanAbsPath,
  loadPlanFile: loadPlanFile,
  parsePlanFile: parsePlanFile,
  // exported for tests / documentation parity
  TASK_LINE_START_RE: TASK_LINE_START_RE,
  TASK_ID_TOKEN_RE: TASK_ID_TOKEN_RE,
};

// ============================================================
// --self-test (only runs when this file is EXECUTED directly, e.g.
// `node plan-parse.js --self-test`) — sandboxed under its own mktemp dir.
// ============================================================
if (require.main === module) {
  const arg = process.argv[2];
  if (arg === '--self-test' || arg === '--selftest') {
    const failed = selfTest();
    process.exit(failed ? 1 : 0);
  }
}

function selfTest() {
  const os = require('os');
  let PASSED = 0, FAILED = 0;
  function ok(name, cond, detail) {
    if (cond) { PASSED++; console.log('  PASS: ' + name); }
    else { FAILED++; console.log('  FAIL: ' + name + (detail ? ' (' + detail + ')' : '')); }
  }

  // Numeric regression (unchanged shape).
  const numericTasks = parseTasks([
    '## Tasks', '',
    '- [x] 1. Task one, done.',
    '- [ ] 2. Task two, not started.',
    '- [ ] 6.2. Sub-numbered task.',
    '',
  ].join('\n'));
  ok('numeric ids parse with correct id/done', numericTasks.length === 3 &&
    numericTasks[0].id === '1' && numericTasks[0].done === true &&
    numericTasks[1].id === '2' && numericTasks[1].done === false &&
    numericTasks[2].id === '6.2' && numericTasks[2].done === false,
    JSON.stringify(numericTasks));

  // Lettered ids parse (id + state + description).
  const letteredTasks = parseTasks([
    '## Tasks', '',
    '- [x] A.1 Create the fixture file with the required sections.',
    '- [ ] A.7 Smoke-test the workflow end-to-end.',
    '- [x] 20R. Revert item 20: restore the button label.',
    '',
  ].join('\n'));
  ok('lettered ids parse with correct id/done/description', letteredTasks.length === 3 &&
    letteredTasks[0].id === 'A.1' && letteredTasks[0].done === true &&
    /Create the fixture file/.test(letteredTasks[0].description) &&
    letteredTasks[1].id === 'A.7' && letteredTasks[1].done === false &&
    letteredTasks[2].id === '20R' && letteredTasks[2].done === true,
    JSON.stringify(letteredTasks));

  // [serial]/[parallel] prefix + Verification suffix + continuation lines.
  const richTasks = parseTasks([
    '## Tasks', '',
    '- [ ] 1. [serial] **The ONE parser.** The highest-value item in the',
    '  plan. Handles: numeric AND lettered ids, continuation lines —',
    '  Verification: mechanical',
    '- [ ] 2. [parallel] **Second task.** — Verification: full',
    '',
  ].join('\n'));
  ok('mode prefix + Verification suffix stripped, continuation folded', richTasks.length === 2 &&
    richTasks[0].id === '1' &&
    !/\[serial\]/.test(richTasks[0].description) &&
    !/Verification/.test(richTasks[0].description) &&
    /highest-value item/.test(richTasks[0].description) &&
    /continuation lines/.test(richTasks[0].description) &&
    richTasks[1].id === '2' && !/\[parallel\]/.test(richTasks[1].description) &&
    !/Verification/.test(richTasks[1].description),
    JSON.stringify(richTasks));

  // Description round-trip: a `"`, a backslash, and a raw newline survive
  // JSON.stringify/JSON.parse unchanged (JSON-safe by construction — we
  // never manually concatenate into a JSON string).
  const quoteTasks = parseTasks([
    '## Tasks', '',
    '- [ ] 1. A description with a "quote", a back\\slash, and a',
    '  continuation line that completes the paragraph.',
    '',
  ].join('\n'));
  const roundTripped = JSON.parse(JSON.stringify(quoteTasks));
  ok('description containing a quote/backslash survives JSON round-trip',
    roundTripped.length === 1 &&
    /"quote"/.test(roundTripped[0].description) &&
    roundTripped[0].description.indexOf('back\\slash') !== -1 &&
    /continuation line/.test(roundTripped[0].description),
    JSON.stringify(roundTripped));
  const newlineTasks = parseTasks('- [ ] 1. First line.\n  Second physical line folds in.\n');
  ok('a description assembled from a multi-line source is a single JSON-safe string',
    newlineTasks.length === 1 && typeof newlineTasks[0].description === 'string' &&
    /First line\..*Second physical line/.test(newlineTasks[0].description),
    JSON.stringify(newlineTasks));

  // Resolver: docs/plans/ then docs/plans/archive/; honest null when absent.
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'plan-parse-selftest-'));
  fs.mkdirSync(path.join(tmp, 'docs', 'plans', 'archive'), { recursive: true });
  fs.writeFileSync(path.join(tmp, 'docs', 'plans', 'current-plan.md'), '# Plan\nStatus: ACTIVE\n\n- [ ] 1. x\n');
  fs.writeFileSync(path.join(tmp, 'docs', 'plans', 'archive', 'archived-plan.md'), '# Plan\nStatus: COMPLETED\n\n- [x] 1. y\n');

  ok('resolver finds a plan under docs/plans/', resolvePlanAbsPath(tmp, 'current-plan') === path.join(tmp, 'docs', 'plans', 'current-plan.md'));
  ok('resolver finds a plan under docs/plans/archive/', resolvePlanAbsPath(tmp, 'archived-plan') === path.join(tmp, 'docs', 'plans', 'archive', 'archived-plan.md'));
  ok('resolver returns null (not a crash, not a guess) when the slug matches nothing', resolvePlanAbsPath(tmp, 'no-such-plan') === null);

  // loadPlanFile: absent vs damaged, never a silent zero.
  const absentAbs = path.join(tmp, 'docs', 'plans', 'never-existed.md');
  const absentResult = loadPlanFile(absentAbs);
  ok('loadPlanFile reports absent (ENOENT) honestly, not a silent empty task list',
    absentResult.ok === false && absentResult.reason === 'absent', JSON.stringify(absentResult));

  const damagedAbs = path.join(tmp, 'docs', 'plans', 'a-directory.md');
  fs.mkdirSync(damagedAbs); // a directory at a .md path — read fails, but it is NOT absent
  const damagedResult = loadPlanFile(damagedAbs);
  ok('loadPlanFile reports damaged (present but unreadable) — never collapses to absent or a silent zero',
    damagedResult.ok === false && damagedResult.reason === 'damaged' && !!damagedResult.error,
    JSON.stringify(damagedResult));

  const okResult = loadPlanFile(path.join(tmp, 'docs', 'plans', 'current-plan.md'));
  ok('loadPlanFile reports ok with tasks + status + absPath for a genuine plan',
    okResult.ok === true && okResult.status === 'ACTIVE' && okResult.tasks.length === 1 && okResult.absPath,
    JSON.stringify(okResult));

  // parsePlanFile parity shape (auditor.js drop-in): null on absent/damaged.
  ok('parsePlanFile returns null (not an object) for an absent plan — auditor.js drop-in parity',
    parsePlanFile(absentAbs) === null);
  ok('parsePlanFile returns null for a damaged plan too (parity: prior code never distinguished)',
    parsePlanFile(damagedAbs) === null);
  const parsedOk = parsePlanFile(path.join(tmp, 'docs', 'plans', 'archive', 'archived-plan.md'));
  ok('parsePlanFile returns {tasks, status, absPath} for a real archived plan',
    parsedOk && parsedOk.status === 'COMPLETED' && parsedOk.tasks.length === 1 && parsedOk.tasks[0].done === true,
    JSON.stringify(parsedOk));

  try { fs.rmSync(tmp, { recursive: true, force: true }); } catch (_) { /* best-effort */ }

  console.log('');
  console.log('plan-parse self-test summary: ' + PASSED + ' passed, ' + FAILED + ' failed');
  return FAILED > 0;
}
