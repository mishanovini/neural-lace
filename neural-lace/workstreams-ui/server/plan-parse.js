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
//   parseTasks(markdown)        -> [{id, done, description, section}, ...]
//     R11 EXTENSION (2026-07-28, operator round 11, "batch source" Critical
//     1/2 — docs/reviews/2026-07-28-roadmap-hierarchy-ux-review.md): each
//     task now also carries `section`, the VERBATIM text of the nearest
//     `###` sub-heading appearing INSIDE the file's `## Tasks` section, in
//     file-order (heading-position tracking — a task before any `###`
//     heading, or in a plan with no `## Tasks` heading at all, or outside a
//     `## Tasks` section entirely, carries `section: ''`, honest absence).
//     This is the ONLY batch-label source alongside the task's own id token
//     (never title/description text — see roadmap-routes.js's
//     deriveTaskBatches for the consumer + the PROVEN title-cross-reference
//     trap this additive field exists to avoid).
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

// TASK_ID_TOKEN_RE — ported from plan-lifecycle.sh's
// `extract_all_task_line_ids` (adapters/claude-code/hooks/plan-lifecycle.sh
// ~L342-356): an optional letter-prefix (`A.`, `F.`), mandatory digits, an
// optional single trailing letter, then zero or more repeated
// `.digits[letter]` groups. Accepts every shape live in the plan corpus
// today: `1`, `6.2`, `A.1`, `B.0`, `D.2`, `F.2b`, `20R`.
//
// R11 EXTENSION (2026-07-28, operator round 11): the LETTERED-BATCH shapes
// (`A1`, `B2`, `C2-3` — single UPPERCASE batch letter directly fused to the
// digits, dash-separated sub-ids) verified live in 4 Circuit plans + the
// A2P master family were SILENTLY DROPPED by the verbatim port (proven:
// parseTasks on `- [ ] A1. lettered...` returned []) — every lettered plan
// rendered with most tasks invisible, corrupting the roadmap's progress
// counts ("progress seems completely random" had a data hole under it).
// The prefix is deliberately a SINGLE UPPERCASE letter so prose bullets
// like `v2 rollout` stay non-tasks; plan-lifecycle.sh shares the old
// grammar and its own lettered blindness is filed via nl-issue (parity
// delta is DELIBERATE here, not drift — see the R11 pins).
// R12/SE EXTENSION (2026-07-30, operator: "speaking the same language on all
// surfaces"): the plan-Key convention fuses a 2-3 UPPERCASE key to the digit
// (SE1, RI1, EST14). The R11 grammar capped the fused prefix at ONE uppercase
// letter, so SE/RI plans parsed to ZERO tasks and rendered taskless — the
// silent-drop class again, one letter wider. Cap stays at 3 so 4+-letter
// acronym prose (WCAG 2...) still never parses as a task id.
//
// R13/HARNESS-REVIEW EXTENSION (2026-07-30, harness-change-review REFORMULATE
// on plan-edit-validator.sh, finding 2): the R12 widening to 2-3 letters
// shipped with ZERO regression fixtures and silently admits fused
// acronym+digit PROSE tokens as task ids — a `- [ ] SHA256 digest check`
// checklist bullet parses id="SHA256" (SHA=3 uppercase letters, 256=digits),
// same for ISO8601/MD5/EC2/UTF8. DESIGN DECISION (decide-and-go): a 2-3
// letter FUSED prefix is a task id only when it lexically separates from
// generic tech-acronym prose. Two-tier gate, checked in this priority order:
//   1. Key-match (primary — "kills the whole class" per the review): if the
//      plan declares a `Key:` header (parsePlanKey below), a 2-3 letter
//      fused prefix is valid ONLY when it equals that Key, case-sensitive
//      uppercase (EST14 is a task under `Key: EST`; SHA256 in the SAME plan
//      is not, because "SHA" != "EST"). This is the real fix: it separates
//      EST14 from SHA256 by what the PLAN ITSELF declares, not a guess.
//   2. Curated negative list (fallback — for plans with NO declared Key,
//      e.g. review-independence.md's real RI1-RI4 corpus usage, which
//      predates the Key convention and must not regress to zero tasks): a
//      2-3 letter fused prefix is rejected only if it is one of the known
//      generic tech acronyms (SHA|ISO|MD|EC|UTF) that collide with this
//      shape; anything else is accepted, same as before this fix.
// The 0-letter (pure numeric) and 1-letter (R11 batch-letter: A1/B2/T7)
// cases are UNGATED by either tier — they were never the false-positive
// class this finding names, and gating them would regress the R11 fix.
// Dot-form ids (`B.1`, `F.2b` — the ORIGINAL, pre-R11 grammar) are also
// ungated: the letters there are separated from the digits by a literal
// "." in the source text, so they were never ambiguous with fused acronym
// prose in the first place.
const TASK_ID_TOKEN_RE = /^([A-Za-z]+\.)?([A-Z]{0,3})[0-9]+[A-Za-z]?([.-][0-9]+[A-Za-z]?)*/;

// GENERIC_ACRONYM_FUSED_PREFIXES — the curated negative-list fallback (tier
// 2 above) for plans with no declared Key. Exact-match against the captured
// fused-letter-prefix (group 2 of TASK_ID_TOKEN_RE), never a substring test.
const GENERIC_ACRONYM_FUSED_PREFIXES = new Set(['SHA', 'ISO', 'MD', 'EC', 'UTF']);

// KEY_LINE_RE / parsePlanKey — the plan header's `Key:` value (e.g. `Key:
// SE`, `Key: ORG`), mirroring parsePlanStatus's own header-scan shape.
// Returns '' (honest absence) when the plan declares no Key — most plans,
// including every plan predating the R12/SE convention.
const KEY_LINE_RE = /^Key:[ \t]*(.+?)[ \t]*$/;
function parsePlanKey(markdown) {
  const text = markdown == null ? '' : String(markdown);
  const lines = text.split('\n');
  for (let i = 0; i < lines.length; i++) {
    const m = KEY_LINE_RE.exec(lines[i].replace(/\r$/, ''));
    if (m) return m[1].trim();
  }
  return '';
}

// isValidTaskId(idM, planKey) -> boolean — the two-tier gate from
// TASK_ID_TOKEN_RE's header comment. `idM` is a TASK_ID_TOKEN_RE match
// array; `planKey` is the plan's declared Key, already trimmed+uppercased
// ('' if none declared).
function isValidTaskId(idM, planKey) {
  const isDotForm = !!idM[1];
  const fusedPrefix = idM[2] || '';
  if (isDotForm || fusedPrefix.length < 2) {
    // Dot-form ids (B.1) and 0/1-letter fused ids (1, 6.2, A1, T7) are
    // never the false-positive class this gate exists for — ungated.
    return true;
  }
  // 2-3 letter fused prefix: tier 1 (Key-match) takes priority when the
  // plan declares one; tier 2 (curated negative list) is the fallback for
  // Key-less plans (e.g. review-independence.md's real RI1-RI4 usage).
  if (planKey) return fusedPrefix === planKey;
  return !GENERIC_ACRONYM_FUSED_PREFIXES.has(fusedPrefix);
}

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
// HEADING_RE — any ATX heading line (`#` through `######`), capturing its
// level (hash count) and verbatim text (trailing whitespace stripped only —
// never re-worded, per R11's "must quote a string that exists in the source
// artifact" general law).
const HEADING_RE = /^(#{1,6})[ \t]+(.*)$/;

function parseTasks(markdown) {
  const text = markdown == null ? '' : String(markdown);
  const lines = text.split('\n');
  const tasks = [];
  let current = null;
  // R13 (finding 2): the plan's declared Key, read once per parse — the
  // tier-1 gate for a 2-3 letter fused id prefix (see TASK_ID_TOKEN_RE's
  // header comment for the full two-tier design).
  const planKey = parsePlanKey(text).trim().toUpperCase();
  // R11 batch-source tracking (Critical 1/2): a task's `section` is the
  // VERBATIM nearest-preceding `###` heading, but ONLY while inside a `##
  // Tasks` heading's span — a `###` anywhere else (e.g. under `## Files to
  // Modify`) never leaks in as a false batch label.
  let inTasksSection = false;
  let currentBatchHeading = '';

  lines.forEach((rawLine) => {
    const line = rawLine.replace(/\r$/, '');

    const m = TASK_LINE_START_RE.exec(line);
    if (m) {
      const rest = m[2];
      const idM = TASK_ID_TOKEN_RE.exec(rest);
      if (idM && idM[0] && isValidTaskId(idM, planKey)) {
        const descRest = stripIdSeparator(rest.slice(idM[0].length))
          .trim()
          .replace(MODE_PREFIX_RE, '')
          .trim();
        current = {
          id: idM[0],
          done: (m[1] === 'x' || m[1] === 'X'),
          description: descRest,
          section: inTasksSection ? currentBatchHeading : '',
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

    const hm = HEADING_RE.exec(line);
    if (hm) {
      const level = hm[1].length;
      const headingText = hm[2].replace(/\s+$/, '');
      if (level === 2) {
        // A NEW `##` heading — `## Tasks` (any casing) opens the span;
        // any other `##` heading (e.g. `## Files to Modify/Create`) closes
        // it. Either way the prior sub-heading no longer applies.
        inTasksSection = /^tasks$/i.test(headingText.trim());
        currentBatchHeading = '';
      } else if (level === 3 && inTasksSection) {
        currentBatchHeading = headingText.trim();
      } else if (level <= 2) {
        // (level === 1, or an unreached level===2 branch above) — a
        // top-level heading always closes any open Tasks span.
        inTasksSection = false;
        currentBatchHeading = '';
      }
      current = null;
      return;
    }

    if (line.trim() === '') { current = null; return; }

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
// extractPlanTaskReferences(text) -> [{slug, taskId}, ...] —
// ROADMAP-WAITING-ON-YOU-SIGNAL-01 (2026-07-29 round 14): CONSERVATIVE,
// EXPLICIT reference extraction shared by roadmap-routes.js (the
// stalledSignals.waitingOnYouId producer) and inbox-routes.js (the
// reverse blocks_roadmap_id chip) — pure string matching, no disk I/O, no
// fuzzy title/keyword matching. Two accepted shapes, both requiring an
// EXPLICIT slug AND an EXPLICIT task id in the SAME text blob — a false
// correlation is worse than a missing one (this defect's own binding
// rule, echoed from the roll-up law's own C1/C5 discipline):
//   1. the app's own canonical address `#roadmap/<slug>/<task-id>`
//      (highest confidence — an intentional cross-reference).
//   2. a `docs/plans/<slug>.md` (or archive/) repo-path anchor — the SAME
//      concrete-anchor needs-you.sh's own cold-reader lint already
//      REQUIRES of every answerable decision item (LINT_LABELS
//      'no-anchor' in inbox-routes.js) — combined with an explicit
//      "task <id>" mention anywhere in the SAME text blob.
// Callers MUST still verify the (slug, taskId) pair against the plan's
// REAL parsed task list (parseTasks) before trusting it — a bare number
// appearing near a path is not proof it names that plan's actual task;
// this function only narrows the candidate set, it never asserts
// existence.
function extractPlanTaskReferences(text) {
  const hay = String(text || '');
  const out = [];
  const seen = {};
  function push(slug, taskId) {
    const key = slug + '/' + taskId;
    if (seen[key]) return;
    seen[key] = true;
    out.push({ slug: slug, taskId: taskId });
  }

  const hashRe = /#roadmap\/([A-Za-z0-9._-]+)\/([A-Za-z0-9](?:[.-][A-Za-z0-9]+)*)/g;
  let hm;
  while ((hm = hashRe.exec(hay))) push(hm[1], hm[2]);

  const pathRe = /docs\/plans\/(?:archive\/)?([A-Za-z0-9._-]+)\.md/g;
  const slugs = [];
  let pm;
  while ((pm = pathRe.exec(hay))) slugs.push(pm[1]);
  if (slugs.length) {
    const taskRe = /\btask\s+([A-Za-z0-9](?:[.-][A-Za-z0-9]+)*)\b/gi;
    const taskIds = [];
    let tm;
    while ((tm = taskRe.exec(hay))) taskIds.push(tm[1]);
    slugs.forEach((slug) => taskIds.forEach((tid) => push(slug, tid)));
  }
  return out;
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
  extractPlanTaskReferences: extractPlanTaskReferences,
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

  // R11 batch-source (Critical 1/2): `###` sub-headings inside `## Tasks`
  // are captured VERBATIM per task, file-order, never re-worded.
  const sectionedTasks = parseTasks([
    '## Tasks', '',
    '### Phase B — Foundations', '',
    '- [x] B1 first foundations task',
    '- [ ] B2 second foundations task',
    '### Phase C — Engine', '',
    '- [ ] C1 engine task',
    '',
  ].join('\n'));
  ok('R11 tasks under a `###` sub-heading carry its VERBATIM text as `section`',
    sectionedTasks.length === 3 &&
    sectionedTasks[0].section === 'Phase B — Foundations' &&
    sectionedTasks[1].section === 'Phase B — Foundations' &&
    sectionedTasks[2].section === 'Phase C — Engine',
    JSON.stringify(sectionedTasks));

  // A task appearing BEFORE any `###` heading (or in a plan with no `###`
  // headings at all) carries `section: ''` — honest absence, never a guess.
  const unsectionedTasks = parseTasks([
    '## Tasks', '',
    '- [ ] 1. plain task, no sub-heading above it',
    '',
  ].join('\n'));
  ok('a task with no preceding `###` sub-heading carries section: \'\'',
    unsectionedTasks.length === 1 && unsectionedTasks[0].section === '',
    JSON.stringify(unsectionedTasks));

  // A `###` heading OUTSIDE `## Tasks` (e.g. under a later `## Files to
  // Modify` section) must NEVER leak in as a false batch label for tasks
  // that happen to precede it in a DIFFERENT file, nor persist past the
  // `## Tasks` span's own close.
  const crossSectionTasks = parseTasks([
    '## Tasks', '',
    '- [ ] 1. a task with no sub-heading',
    '## Files to Modify', '',
    '### some/path.js', '',
  ].join('\n'));
  ok('a `###` heading outside `## Tasks` never contaminates section tracking',
    crossSectionTasks.length === 1 && crossSectionTasks[0].section === '',
    JSON.stringify(crossSectionTasks));

  // R13 (harness-change-review REFORMULATE finding 2): the fused-prefix
  // id-grammar Key-match gate. Positives per the review's exact list —
  // SE1/RI1/EST14 (2-3 letter fused, gated on Key or the curated fallback),
  // T7/B.1 (0/1-letter and dot-form, always ungated). Negatives — generic
  // tech-acronym prose that must NEVER parse as a task id, Key or no Key.

  // SE1 under a plan that declares `Key: SE` — the Key-match tier accepts
  // the matching prefix and rejects a same-plan SHA256 prose bullet whose
  // fused prefix ("SHA") does not match the declared Key.
  const seKeyTasks = parseTasks([
    'Key: SE', '',
    '## Tasks', '',
    '- [ ] SE1 — Handoff-complete emit at estate-merge.sh',
    '- [ ] SHA256 digest check for artifact integrity',
    '',
  ].join('\n'));
  ok('SE1 parses as a task under a matching declared Key: SE',
    seKeyTasks.length === 1 && seKeyTasks[0].id === 'SE1',
    JSON.stringify(seKeyTasks));

  // EST14 under a plan that declares `Key: EST` — a 3-letter Key, plus an
  // ISO8601 prose bullet in the SAME plan must not parse (fused prefix
  // "ISO" != declared Key "EST").
  const estKeyTasks = parseTasks([
    'Key: EST', '',
    '## Tasks', '',
    '- [ ] EST14 — per-plan actuals mining fixture',
    '- [ ] ISO8601 timestamps in the export format',
    '',
  ].join('\n'));
  ok('EST14 parses as a task under a matching declared 3-letter Key: EST',
    estKeyTasks.length === 1 && estKeyTasks[0].id === 'EST14',
    JSON.stringify(estKeyTasks));

  // RI1 in a plan with NO declared Key (review-independence.md's real
  // corpus shape, predating the Key convention) — falls to the curated
  // negative-list fallback, which does not reject "RI". A same-plan MD5/
  // EC2/UTF8/WCAG bullet must still never parse, Key or no Key.
  const noKeyTasks = parseTasks([
    '## Tasks', '',
    '- [ ] RI1. The review queue implementation',
    '- [ ] MD5 checksum comparison for the artifact',
    '- [ ] EC2 provisioning check for staging',
    '- [ ] UTF8 encoding validation pass',
    '- [ ] WCAG 2.2 AA compliance review',
    '',
  ].join('\n'));
  ok('RI1 parses as a task with no declared Key (curated fallback does not reject "RI")',
    noKeyTasks.length === 1 && noKeyTasks[0].id === 'RI1',
    JSON.stringify(noKeyTasks));

  // T7 (single-letter fused, R11 convention) and B.1 (dot-form, pre-R11
  // grammar) are ungated by either tier regardless of any declared Key.
  const ungatedIdTasks = parseTasks([
    'Key: ZZ', '',
    '## Tasks', '',
    '- [x] T7 — LOE v1 per-plan actuals mining',
    '- [ ] B.1 Create the fixture file',
    '',
  ].join('\n'));
  ok('T7 (single-letter fused) and B.1 (dot-form) parse regardless of a mismatched declared Key',
    ungatedIdTasks.length === 2 &&
    ungatedIdTasks[0].id === 'T7' && ungatedIdTasks[0].done === true &&
    ungatedIdTasks[1].id === 'B.1' && ungatedIdTasks[1].done === false,
    JSON.stringify(ungatedIdTasks));

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

  // ---- extractPlanTaskReferences (ROADMAP-WAITING-ON-YOU-SIGNAL-01) ----
  const refsHash = extractPlanTaskReferences('please look at #roadmap/cockpit-roadmap-redesign/9 today');
  ok('extractPlanTaskReferences: #roadmap/<slug>/<task-id> is the highest-confidence match',
    refsHash.length === 1 && refsHash[0].slug === 'cockpit-roadmap-redesign' && refsHash[0].taskId === '9',
    JSON.stringify(refsHash));

  const refsPathAndTask = extractPlanTaskReferences('see docs/plans/cockpit-roadmap-redesign.md — task 9 needs your call');
  ok('extractPlanTaskReferences: a docs/plans/<slug>.md anchor + an explicit "task <id>" mention in the same text combine into a match',
    refsPathAndTask.length === 1 && refsPathAndTask[0].slug === 'cockpit-roadmap-redesign' && refsPathAndTask[0].taskId === '9',
    JSON.stringify(refsPathAndTask));

  const refsArchive = extractPlanTaskReferences('docs/plans/archive/old-plan.md task A.1 blocked');
  ok('extractPlanTaskReferences: an archive/ path anchor is recognized too',
    refsArchive.length === 1 && refsArchive[0].slug === 'old-plan' && refsArchive[0].taskId === 'A.1',
    JSON.stringify(refsArchive));

  const refsPathOnly = extractPlanTaskReferences('see docs/plans/cockpit-roadmap-redesign.md for context');
  ok('extractPlanTaskReferences: a path anchor with NO explicit "task <id>" mention yields zero matches — conservative, never fuzzy',
    refsPathOnly.length === 0, JSON.stringify(refsPathOnly));

  const refsTaskOnly = extractPlanTaskReferences('task 9 is stuck');
  ok('extractPlanTaskReferences: an explicit "task <id>" mention with NO plan anchor yields zero matches — never guesses which plan',
    refsTaskOnly.length === 0, JSON.stringify(refsTaskOnly));

  const refsProse = extractPlanTaskReferences('I have 9 tasks left and read docs/plans/foo.md yesterday, no big deal');
  ok('extractPlanTaskReferences: a bare number near a path with no "task" keyword never fabricates a correlation',
    refsProse.length === 0, JSON.stringify(refsProse));

  try { fs.rmSync(tmp, { recursive: true, force: true }); } catch (_) { /* best-effort */ }

  console.log('');
  console.log('plan-parse self-test summary: ' + PASSED + ' passed, ' + FAILED + ' failed');
  return FAILED > 0;
}
