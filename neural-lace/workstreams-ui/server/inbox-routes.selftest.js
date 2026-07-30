'use strict';
// inbox-routes.selftest.js — sandboxed self-test for the Inbox view's
// server surface (cockpit-roadmap-redesign Task 4). Own file (not
// server.selftest.js or a sibling route's selftest) so no task races on a
// shared test file — same rationale as requests-routes.selftest.js's header.
//
// REAL-SCENARIO discipline (no mocking the SUT): fixtures are a REAL
// ledger.json under a mktemp sandbox (NEEDS_YOU_STATE_DIR), requests are
// REAL HTTP GET/POSTs against the mounted handler.
//
// Run: `node server/inbox-routes.selftest.js`. Exit 0 PASS / 1 FAIL.
// Extra mode: `node server/inbox-routes.selftest.js --serve` keeps the
// fixture server alive (prints the port) for a manual browser livesmoke.

const fs = require('fs');
const os = require('os');
const path = require('path');
const http = require('http');

process.env.HARNESS_SELFTEST = '1';

let PASSED = 0, FAILED = 0;
function ok(name, cond, detail) {
  if (cond) { PASSED++; console.log('  PASS: ' + name); }
  else { FAILED++; console.log('  FAIL: ' + name + (detail ? ' (' + detail + ')' : '')); }
}

function httpGet(port, urlPath) {
  return new Promise((resolve, reject) => {
    http.get({ host: '127.0.0.1', port: port, path: urlPath, agent: false }, (res) => {
      let body = '';
      res.on('data', (c) => { body += c; });
      res.on('end', () => {
        let parsed = null;
        try { parsed = JSON.parse(body); } catch (_) {}
        resolve({ status: res.statusCode, headers: res.headers, body: body, json: parsed });
      });
    }).on('error', reject);
  });
}
function httpPostJson(port, urlPath, obj) {
  return new Promise((resolve, reject) => {
    const payload = JSON.stringify(obj || {});
    const req = http.request({
      host: '127.0.0.1', port: port, path: urlPath, method: 'POST', agent: false,
      headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(payload) },
    }, (res) => {
      let body = '';
      res.on('data', (c) => { body += c; });
      res.on('end', () => {
        let parsed = null;
        try { parsed = JSON.parse(body); } catch (_) {}
        resolve({ status: res.statusCode, body: body, json: parsed });
      });
    });
    req.on('error', reject);
    req.end(payload);
  });
}
function findItem(items, id) {
  for (let i = 0; i < (items || []).length; i++) { if (items[i].id === id) return items[i]; }
  return null;
}

async function main() {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'inbox-t4-st-'));
  const nyStateDir = path.join(tmp, 'ny-state');
  fs.mkdirSync(nyStateDir, { recursive: true });
  process.env.NEEDS_YOU_STATE_DIR = nyStateDir;
  process.env.NEEDS_YOU_CLI = path.join(tmp, 'no-such-needs-you.sh'); // default: missing, named-error path
  process.env.AUDITOR_NL_ISSUE_STATE_PATH = path.join(tmp, 'auditor-nl-issue-state.json');
  // ROADMAP-WAITING-ON-YOU-SIGNAL-01 (round 14) reverse-lookup sandbox: a
  // dedicated docs/plans/ root, independent of this repo's real plans, so
  // resolveBlocksRoadmapId's match-verification (which plan-parse.loadPlanFile
  // reads for real) is fully deterministic and never depends on real repo state.
  const planScanRoot = path.join(tmp, 'plan-scan-root');
  fs.mkdirSync(path.join(planScanRoot, 'docs', 'plans'), { recursive: true });
  fs.writeFileSync(path.join(planScanRoot, 'docs', 'plans', 'fixture-plan.md'),
    '# Plan: Fixture\nStatus: ACTIVE\n\n## Tasks\n- [ ] 9. A real task, referenced by NY-blocks below.\n');
  process.env.ROADMAP_PLAN_SCAN_ROOT = planScanRoot;

  const GOOD_TEXT = '### Ship the O.9 dashboard tonight?\n' +
    'The backlog KPI dashboard (adapters/claude-code/docs/kpis.md) has been green in staging for 3 days.\n' +
    '| Option | What happens |\n' +
    '|---|---|\n' +
    '| Ship tonight | goes live now, I am on call |\n' +
    '| Wait for Monday | ships Monday, no weekend risk |\n' +
    'My pick: ship tonight.\n' +
    'Reply with: "ship" or "wait".';

  const ledgerItems = [
    // ask-clean: well-formed §3 decision, no lint warnings -> answerable, full anatomy parses.
    { id: 'NY-clean', section: 'decision', state: 'open', session: 'sess-clean', tier: '2', created_at: '2026-07-19T10:00:00Z', links: ['https://example.test/x'], lint_warnings: [], text: GOOD_TEXT },
    // ask-q: a clean question -> answerable, no anatomy structure.
    { id: 'NY-question', section: 'question', state: 'open', session: 'sess-q', created_at: '2026-07-19T11:00:00Z', lint_warnings: [], text: 'Which deploy target for the new worker?' },
    // ask-quarantined: lint-flagged decision, HAS a session -> quarantined, excluded from answerable.
    { id: 'NY-quarantined', section: 'decision', state: 'open', session: 'sess-bad', created_at: '2026-07-19T09:00:00Z', lint_warnings: ['no-context', 'no-anchor'], text: 'Ship tonight? My pick: yes.' },
    // ask-legacy: lint-flagged decision, NO session (legacy no-producer) -> quarantined.
    { id: 'NY-legacy', section: 'decision', state: 'open', created_at: '2026-07-19T08:00:00Z', lint_warnings: ['no-anchor'], text: 'An old bare decision.' },
    // ask-inflight: inflight section -> excluded ENTIRELY (not answerable, not quarantined).
    { id: 'NY-inflight', section: 'inflight', state: 'open', created_at: '2026-07-19T12:00:00Z', lint_warnings: [], text: 'Wave X batch building.' },
    // ask-resolved: already resolved -> excluded ENTIRELY (left the Inbox).
    { id: 'NY-resolved', section: 'decision', state: 'resolved', created_at: '2026-07-18T10:00:00Z', lint_warnings: [], text: 'Old resolved thing.' },
    // ask-blocks: ROADMAP-WAITING-ON-YOU-SIGNAL-01 (round 14) -- an explicit
    // docs/plans/<slug>.md anchor + "task 9" mention, verified against the
    // real fixture-plan.md task list (planScanRoot above) -> blocks_roadmap_id
    // should resolve to 'fixture-plan/9'.
    { id: 'NY-blocks', section: 'decision', state: 'open', created_at: '2026-07-19T13:00:00Z', lint_warnings: [], text: 'See docs/plans/fixture-plan.md -- task 9 needs your call. My pick: A.' },
    // ask-nonmatch: names a path + a number, but NOT a real task of that plan
    // (task 999 does not exist in fixture-plan.md) -- must NEVER fabricate a match.
    { id: 'NY-nonmatch', section: 'decision', state: 'open', created_at: '2026-07-19T14:00:00Z', lint_warnings: [], text: 'See docs/plans/fixture-plan.md -- task 999 needs your call. My pick: A.' },
    // ask-realshape: INBOX-MULTILINE-ASK-TRUNCATED-AT-RENDER-01 (round 14,
    // operator live complaint) -- a REDUCED reproduction of the real
    // production ledger item (NY-1785357818-7d3f) that exposed the bug: no
    // "### " heading (a bare "Decision needed: ..." first line instead),
    // arrow-format options ("Option NAME -> outcome", never a markdown
    // table), inline repo-path + workflow-id anchors, and NO producer-
    // supplied --link entries at all.
    {
      id: 'NY-realshape', section: 'decision', state: 'open', session: 'a3fcb6ea', created_at: '2026-07-29T20:43:38Z',
      lint_warnings: [],
      text: 'Decision needed: which review-independence model unblocks master.\n' +
        'Context: the harness requires a harness-reviewer PASS record per changed enforcement file (adapters/claude-code/doctrine/review-before-deploy.md); nothing merges without it.\n' +
        'Option SWEEP -> I dispatch reviewer subagents now -> master unblocks today.\n' +
        'Option DESKTOP -> the desktop machine reviews instead -> genuinely independent eyes.\n' +
        'My pick: SWEEP -- fastest path.\n' +
        'Reply with: SWEEP or DESKTOP.',
    },
  ];
  fs.writeFileSync(path.join(nyStateDir, 'ledger.json'), JSON.stringify({ schema_version: 1, items: ledgerItems }));
  // Mark NY-quarantined as ALREADY auto-defect-filed (auditor state fixture) so the
  // "defect_filed" honesty check has one true and one false case to distinguish.
  fs.writeFileSync(process.env.AUDITOR_NL_ISSUE_STATE_PATH, JSON.stringify({
    filed: { 'quarantine-NY-quarantined': { ts: '2026-07-19T09:05:00Z', divergence_class: 'quarantined_no_context' } },
    escalated: {},
  }));

  delete require.cache[require.resolve('./inbox-routes.js')];
  const inboxRoutes = require('./inbox-routes.js');

  const PORT = 19880 + (process.pid % 997);
  const server = http.createServer((req, res) => {
    if (inboxRoutes.handle(req, res)) return;
    res.writeHead(404); res.end('not found');
  });
  await new Promise((resolve) => server.listen(PORT, '127.0.0.1', resolve));

  if (process.argv.indexOf('--serve') !== -1) {
    console.log('[inbox-routes.selftest] fixture server on http://127.0.0.1:' + PORT + ' (Ctrl-C to stop)');
    return;
  }

  try {
    // ---- S1: payload shape ----
    const r1 = await httpGet(PORT, '/api/inbox');
    ok('S1 GET /api/inbox returns ok:true with answerable[]/quarantined[] arrays',
      r1.status === 200 && r1.json && r1.json.ok === true && Array.isArray(r1.json.answerable) && Array.isArray(r1.json.quarantined));

    // ---- S2: CONTEXT CONTRACT split (I4/A8) ----
    const answerableIds = (r1.json.answerable || []).map((i) => i.id).sort();
    const quarantinedIds = (r1.json.quarantined || []).map((i) => i.id).sort();
    ok('S2 clean decision + clean question + the blocks-matching fixtures + the real-shape fixture land in answerable; nothing else does',
      answerableIds.length === 5 &&
      answerableIds[0] === 'NY-blocks' && answerableIds[1] === 'NY-clean' &&
      answerableIds[2] === 'NY-nonmatch' && answerableIds[3] === 'NY-question' && answerableIds[4] === 'NY-realshape',
      JSON.stringify(answerableIds));
    ok('S2b lint-flagged decisions (session-backed AND legacy no-producer) land in quarantined',
      quarantinedIds.length === 2 && quarantinedIds[0] === 'NY-legacy' && quarantinedIds[1] === 'NY-quarantined',
      JSON.stringify(quarantinedIds));
    ok('S2c inflight and already-resolved items are excluded ENTIRELY -- neither answerable nor quarantined',
      answerableIds.indexOf('NY-inflight') === -1 && quarantinedIds.indexOf('NY-inflight') === -1 &&
      answerableIds.indexOf('NY-resolved') === -1 && quarantinedIds.indexOf('NY-resolved') === -1);

    // ---- S3: anatomy parsing (I5 -- constitution §3 compact format) ----
    const clean = findItem(r1.json.answerable, 'NY-clean');
    ok('S3 title extracted from the "### " heading line', clean && clean.title === 'Ship the O.9 dashboard tonight?', JSON.stringify(clean && clean.title));
    ok('S3b context prose captured (the anchor-bearing line)', clean && clean.context.some((l) => /kpis\.md/.test(l)), JSON.stringify(clean && clean.context));
    ok('S3c trade-offs table parsed into {option, outcome} pairs, header/separator rows excluded',
      clean && clean.options.length === 2 &&
      clean.options[0].option === 'Ship tonight' && clean.options[0].outcome === 'goes live now, I am on call' &&
      clean.options[1].option === 'Wait for Monday',
      JSON.stringify(clean && clean.options));
    ok('S3d my_pick extracted', clean && clean.my_pick === 'ship tonight.', JSON.stringify(clean && clean.my_pick));
    ok('S3e reply_with extracted', clean && clean.reply_with === '"ship" or "wait".', JSON.stringify(clean && clean.reply_with));

    const question = findItem(r1.json.answerable, 'NY-question');
    ok('S3f a question item has no anatomy structure -- ask is the raw text itself, no options/my_pick',
      question && question.ask === 'Which deploy target for the new worker?' && question.options.length === 0 && !question.my_pick);

    // ------------------------------------------------------------------
    // S3g-S3l: INBOX-MULTILINE-ASK-TRUNCATED-AT-RENDER-01 (round 14,
    // operator live complaint) -- a stored multi-line ask must round-trip
    // to the API with its FULL text/structure, never silently losing the
    // options/anchors/context past line 1.
    // ------------------------------------------------------------------
    const realshape = findItem(r1.json.answerable, 'NY-realshape');
    ok('S3g title does NOT double the "Decision needed:"/"Question:" label the producer already included on line 1 (the live bug: title rendered "Decision needed: Decision needed: ...")',
      realshape && realshape.title === 'which review-independence model unblocks master.',
      JSON.stringify(realshape && realshape.title));
    ok('S3h arrow-format options ("Option NAME -> outcome", never a markdown table) parse into REAL {option, outcome} pairs -- the exact shape that used to fall through to unstructured context prose, losing the Trade-offs table entirely',
      realshape && realshape.options.length === 2 &&
      realshape.options[0].option === 'SWEEP' && /master unblocks today/.test(realshape.options[0].outcome) &&
      realshape.options[1].option === 'DESKTOP' && /independent eyes/.test(realshape.options[1].outcome),
      JSON.stringify(realshape && realshape.options));
    ok('S3i the Context: line survives as its own context entry (never dropped, never merged into the option lines)',
      realshape && realshape.context.length === 1 && /review-before-deploy\.md/.test(realshape.context[0]),
      JSON.stringify(realshape && realshape.context));
    ok('S3j my_pick and reply_with both still extract correctly alongside the new arrow-option parsing (no regression to the existing anatomy fields)',
      realshape && realshape.my_pick === 'SWEEP -- fastest path.' && realshape.reply_with === 'SWEEP or DESKTOP.',
      JSON.stringify(realshape && { my_pick: realshape.my_pick, reply_with: realshape.reply_with }));
    ok('S3k raw_text carries the COMPLETE original text verbatim (the round-trip oracle: nothing the parser could not structure is ever actually lost)',
      realshape && realshape.raw_text === ledgerItems.find((i) => i.id === 'NY-realshape').text,
      JSON.stringify(realshape && realshape.raw_text.length));
    ok('S3l links[] is populated by SERVER-SIDE anchor extraction from the raw text even though the producer supplied NO --link entries at all (the repo path mentioned inline) -- part (b) of the fix',
      realshape && realshape.links.length === 1 && realshape.links[0] === 'adapters/claude-code/doctrine/review-before-deploy.md',
      JSON.stringify(realshape && realshape.links));

    // ---- S4: reply_channel (v1 ANSWER lifecycle, C3a) ----
    ok('S4 a session-backed item names "reply in session `<id>`"', clean && clean.reply_channel === 'reply in session `sess-clean`', clean && clean.reply_channel);
    const legacy = findItem(r1.json.quarantined, 'NY-legacy');
    ok('S4b a producer-less item falls back to the ledger-entry channel, naming its own id', legacy && legacy.reply_channel === 'reply via the NEEDS-YOU.md ledger entry (id `NY-legacy`)', legacy && legacy.reply_channel);

    // ---- S5: quarantine-only fields (I4/A8) ----
    const quarantined = findItem(r1.json.quarantined, 'NY-quarantined');
    ok('S5 lint_reasons humanizes the raw codes (never the bare code alone)',
      quarantined && quarantined.lint_reasons.length === 2 && quarantined.lint_reasons.every((r) => !/^no-/.test(r)),
      JSON.stringify(quarantined && quarantined.lint_reasons));
    ok('S5b defect_filed is TRUE for the item the auditor-state fixture already marked filed',
      quarantined && quarantined.defect_filed === true);
    ok('S5c defect_filed is FALSE (never fabricated) for an item the auditor has not yet cycled over',
      legacy && legacy.defect_filed === false);
    ok('S5d open_source_session names a copyable resume command when a session is known',
      quarantined && quarantined.open_source_session.has_session === true && /claude --resume sess-bad/.test(quarantined.open_source_session.resume_cmd));
    ok('S5e open_source_session honestly reports no session for a legacy no-producer item (never a fabricated command)',
      legacy && legacy.open_source_session.has_session === false && legacy.open_source_session.resume_cmd === '');

    // ---- S6: "blocks:" WIRED (ROADMAP-WAITING-ON-YOU-SIGNAL-01, round 14) ----
    ok('S6 blocks_roadmap_id is null when the item carries no plan/task anchor at all (never fabricated)',
      clean && clean.blocks_roadmap_id === null && quarantined && quarantined.blocks_roadmap_id === null);
    const blocksItem = findItem(r1.json.answerable, 'NY-blocks');
    ok('S6b blocks_roadmap_id resolves to "<slug>/<task_id>" when the item explicitly names a real docs/plans/<slug>.md anchor + a real "task <id>" of that plan',
      blocksItem && blocksItem.blocks_roadmap_id === 'fixture-plan/9', JSON.stringify(blocksItem && blocksItem.blocks_roadmap_id));
    const nonmatchItem = findItem(r1.json.answerable, 'NY-nonmatch');
    ok('S6c blocks_roadmap_id stays null when the mentioned task id does NOT exist on the referenced plan (task 999 is not a real task of fixture-plan.md) -- never a fabricated correlation',
      nonmatchItem && nonmatchItem.blocks_roadmap_id === null, JSON.stringify(nonmatchItem && nonmatchItem.blocks_roadmap_id));

    // ---- S7: dismiss endpoint -- named error with no CLI, then delegates once a fake CLI exists ----
    const dismiss1 = await httpPostJson(PORT, '/api/inbox/dismiss', { id: 'NY-clean' });
    ok('S7 dismiss with no needs-you.sh CLI returns ok:false with a plain-language error',
      dismiss1.json && dismiss1.json.ok === false && typeof dismiss1.json.error === 'string' && dismiss1.json.error.length > 10);
    const cliLog = path.join(tmp, 'cli-args.log');
    const fakeCli = path.join(tmp, 'fake-needs-you.sh');
    fs.writeFileSync(fakeCli, '#!/bin/bash\necho "$@" >> ' + JSON.stringify(cliLog.replace(/\\/g, '/')) + '\nexit 0\n');
    fs.chmodSync(fakeCli, 0o755);
    process.env.NEEDS_YOU_CLI = fakeCli;
    const dismiss2 = await httpPostJson(PORT, '/api/inbox/dismiss', { id: 'NY-clean' });
    const cliArgs = fs.existsSync(cliLog) ? fs.readFileSync(cliLog, 'utf8') : '';
    ok('S7b with the CLI present, dismiss DELEGATES (one-writer discipline): resolve <id> --note ...',
      dismiss2.json && dismiss2.json.ok === true && /resolve NY-clean/.test(cliArgs) && /--note/.test(cliArgs),
      cliArgs.slice(0, 200));

    // ---- S8: error honesty -- a corrupt ledger.json never crashes the route ----
    fs.writeFileSync(path.join(nyStateDir, 'ledger.json'), '{"broken json\n');
    const r2 = await httpGet(PORT, '/api/inbox');
    ok('S8 corrupt ledger.json degrades to ok:false, never a 500 crash',
      r2.status === 200 && r2.json && r2.json.ok === false && typeof r2.json.error === 'string');
    ok('S8b corrupt ledger.json reports status:"unavailable" (three-state contract) with ledger_present:true (file DOES exist, just untrusted)',
      r2.json && r2.json.status === 'unavailable' && r2.json.ledger_present === true,
      JSON.stringify(r2.json));

    // ---- S9: absent ledger.json -- TRUE-empty (C4), never an error ----
    fs.rmSync(path.join(nyStateDir, 'ledger.json'), { force: true });
    const r3 = await httpGet(PORT, '/api/inbox');
    ok('S9 an absent ledger.json is an honest TRUE-empty state (ok:true, ledger_present:false), never an error',
      r3.status === 200 && r3.json && r3.json.ok === true && r3.json.ledger_present === false &&
      r3.json.answerable.length === 0 && r3.json.quarantined.length === 0);
    ok('S9b absent ledger.json reports status:"not_yet_derived" -- DISTINCT from a confirmed zero (S11), so the renderer can say "not set up" rather than "you\'re caught up"',
      r3.json && r3.json.status === 'not_yet_derived', JSON.stringify(r3.json));

    // ------------------------------------------------------------------
    // S11-S14: 2026-07-29 THREE-STATE CONTRACT hardening (incident:
    // ledger.json sat as a 1-byte "\n" for ~2 days; GET /api/inbox returned
    // ok:false the whole time but nothing distinguished that from "we
    // checked and there's nothing" -- see inbox-routes.js's
    // readNeedsYouLedgerItems/buildInboxPayload header comments for the
    // full contract these scenarios pin down).
    // ------------------------------------------------------------------

    // S11: GENUINE ZERO -- a valid, present ledger with zero open
    // answerable/quarantined items (everything resolved or inflight) must
    // report status:'ok' -- a CONFIRMED zero, distinct from S9b's
    // not_yet_derived (nothing was ever derived) and from S12's unavailable
    // (couldn't tell). This is the exact discrimination the incident's
    // renderer lacked: "Inbox (0)" must mean something different from
    // "Inbox (--)" or "Inbox (setup pending)".
    fs.writeFileSync(path.join(nyStateDir, 'ledger.json'), JSON.stringify({
      schema_version: 1,
      items: [
        { id: 'NY-done', section: 'decision', state: 'resolved', created_at: '2026-07-01T00:00:00Z', lint_warnings: [], text: 'Old resolved thing.' },
        { id: 'NY-fyi', section: 'inflight', state: 'open', created_at: '2026-07-01T00:00:00Z', lint_warnings: [], text: 'Some status narrative.' },
      ],
    }));
    const r4 = await httpGet(PORT, '/api/inbox');
    ok('S11 a valid ledger with zero open decision/question items is a CONFIRMED zero: status:"ok", ok:true, ledger_present:true, empty arrays',
      r4.status === 200 && r4.json && r4.json.ok === true && r4.json.status === 'ok' &&
      r4.json.ledger_present === true && r4.json.answerable.length === 0 && r4.json.quarantined.length === 0,
      JSON.stringify(r4.json));

    // S12: THE GOLDEN INCIDENT FIXTURE -- ledger.json is EXACTLY the
    // observed corruption (a 1-byte file containing a single newline).
    // Must be classified status:'unavailable' (present-but-untrusted), the
    // SAME bucket as S8's malformed-JSON case, NEVER as a confirmed zero.
    fs.writeFileSync(path.join(nyStateDir, 'ledger.json'), '\n');
    const r5 = await httpGet(PORT, '/api/inbox');
    ok('S12 the exact incident fixture (1-byte newline ledger.json) is classified status:"unavailable", ok:false -- never silently "0 items"',
      r5.status === 200 && r5.json && r5.json.ok === false && r5.json.status === 'unavailable' &&
      r5.json.ledger_present === true && r5.json.answerable.length === 0 && r5.json.quarantined.length === 0 &&
      typeof r5.json.error === 'string' && /ledger\.json/.test(r5.json.error),
      JSON.stringify(r5.json));

    // S12b: a genuinely 0-byte file (not even a newline) -- same bucket.
    fs.writeFileSync(path.join(nyStateDir, 'ledger.json'), '');
    const r6 = await httpGet(PORT, '/api/inbox');
    ok('S12b a 0-byte ledger.json is ALSO classified status:"unavailable" (same incident shape, different exact byte count)',
      r6.status === 200 && r6.json && r6.json.ok === false && r6.json.status === 'unavailable' && r6.json.ledger_present === true,
      JSON.stringify(r6.json));

    // S13: VALID JSON, WRONG SHAPE -- before this hardening, a top-level
    // `null`/`{}`/`{"items":"nope"}` silently fell through to `[]`,
    // indistinguishable from a confirmed zero. Must now ALSO be
    // 'unavailable': the ledger is technically parseable but not the
    // trustworthy shape this reader depends on.
    fs.writeFileSync(path.join(nyStateDir, 'ledger.json'), 'null');
    const r7 = await httpGet(PORT, '/api/inbox');
    ok('S13 a valid-JSON-but-wrong-shape ledger (top-level null) is "unavailable", not a silent confirmed zero',
      r7.json && r7.json.ok === false && r7.json.status === 'unavailable', JSON.stringify(r7.json));

    fs.writeFileSync(path.join(nyStateDir, 'ledger.json'), '{}');
    const r8 = await httpGet(PORT, '/api/inbox');
    ok('S13b a valid JSON object missing `.items` entirely is "unavailable", not a silent confirmed zero',
      r8.json && r8.json.ok === false && r8.json.status === 'unavailable', JSON.stringify(r8.json));

    fs.writeFileSync(path.join(nyStateDir, 'ledger.json'), JSON.stringify({ schema_version: 1, items: 'not-an-array' }));
    const r9 = await httpGet(PORT, '/api/inbox');
    ok('S13c a valid JSON object whose `.items` is not an array is "unavailable", not a silent confirmed zero',
      r9.json && r9.json.ok === false && r9.json.status === 'unavailable', JSON.stringify(r9.json));

    // S14: recovery -- once the ledger is restored to a real, valid shape
    // (as needs-you.sh's own state-json-init.sh recovery would do), the
    // route immediately goes back to status:'ok' with no persistent taint.
    fs.writeFileSync(path.join(nyStateDir, 'ledger.json'), JSON.stringify({ schema_version: 1, items: [] }));
    const r10 = await httpGet(PORT, '/api/inbox');
    ok('S14 once the ledger is restored to a valid shape, the route reports status:"ok" again (no persistent taint from the prior corruption)',
      r10.json && r10.json.ok === true && r10.json.status === 'ok' && r10.json.ledger_present === true,
      JSON.stringify(r10.json));

    // ------------------------------------------------------------------
    // S15: INBOX-UNREADABLE-LEDGER-WIN-STATE-01 (2026-07-29 round 14) — a
    // PRESENT-but-permission-denied (EACCES) ledger.json must classify
    // exactly like S12's corrupt-content case (status:'unavailable'),
    // NEVER silently fall into S9's absent/not_yet_derived win-state path
    // (the pre-fix bug: fs.readFileSync's catch(_){return null} treated
    // EVERY read error, including EACCES, as "absent"). chmod 000 is a
    // no-op for the root user (and some CI sandboxes run as root, or a
    // filesystem that ignores unix permission bits) — probe first and skip
    // honestly rather than a false PASS/FAIL on a permission model that
    // cannot express the scenario here.
    // ------------------------------------------------------------------
    {
      const probePath = path.join(nyStateDir, '.eacces-probe');
      fs.writeFileSync(probePath, 'x');
      fs.chmodSync(probePath, 0o000);
      let probeBlocked = true;
      try { fs.readFileSync(probePath, 'utf8'); probeBlocked = false; } catch (_) { probeBlocked = true; }
      fs.chmodSync(probePath, 0o644);
      fs.rmSync(probePath, { force: true });

      if (!probeBlocked) {
        console.log('  SKIP: S15 EACCES-ledger scenario -- chmod 000 is a no-op in this sandbox (likely running as root, or a filesystem ignoring unix permission bits); the permission model cannot express this scenario here');
      } else {
        fs.writeFileSync(path.join(nyStateDir, 'ledger.json'), JSON.stringify({
          schema_version: 1,
          items: [{ id: 'NY-hidden', section: 'decision', state: 'open', created_at: '2026-07-01T00:00:00Z', lint_warnings: [], text: '### Something waiting\nreal context here.\n| Option | What happens |\n|---|---|\n| A | B |\nMy pick: A.\nReply with: "a".' }],
        }));
        fs.chmodSync(path.join(nyStateDir, 'ledger.json'), 0o000);
        const r15 = await httpGet(PORT, '/api/inbox');
        ok('S15 a chmod-000 (EACCES) ledger.json is classified status:"unavailable", ok:false -- NEVER the not_yet_derived win-state path (INBOX-UNREADABLE-LEDGER-WIN-STATE-01)',
          r15.json && r15.json.ok === false && r15.json.status === 'unavailable' && r15.json.status !== 'not_yet_derived' &&
          r15.json.ledger_present === true && r15.json.answerable.length === 0,
          JSON.stringify(r15.json));
        ok('S15b the EACCES error message names the errno, not a generic "not valid JSON" (a distinct failure mode from S8/S12\'s parse errors)',
          r15.json && typeof r15.json.error === 'string' && /EACCES|could not be read/.test(r15.json.error),
          JSON.stringify(r15.json));
        fs.chmodSync(path.join(nyStateDir, 'ledger.json'), 0o644); // restore so cleanup/rmSync never trips on this fixture
      }
    }

    // ---- S10: /inbox.js is served by this handler (single mount line) ----
    const asset = await httpGet(PORT, '/inbox.js');
    ok('S10 GET /inbox.js serves the client module with a JS content type',
      asset.status === 200 && /javascript/.test(asset.headers['content-type'] || '') && asset.body.length > 500,
      'status=' + asset.status + ' len=' + asset.body.length);

    // ------------------------------------------------------------------
    // S18: extractAnchorsFromText / mergeLinks unit coverage (round 14).
    // ------------------------------------------------------------------
    const anchorsUrl = inboxRoutes.extractAnchorsFromText('see https://example.test/pr/42 for details.');
    ok('S18 extractAnchorsFromText finds an http(s) URL, trailing punctuation stripped', anchorsUrl.length === 1 && anchorsUrl[0] === 'https://example.test/pr/42', JSON.stringify(anchorsUrl));
    const anchorsPath = inboxRoutes.extractAnchorsFromText('per adapters/claude-code/doctrine/review-before-deploy.md, nothing merges.');
    ok('S18b extractAnchorsFromText finds a repo-relative path with a recognized extension', anchorsPath.length === 1 && anchorsPath[0] === 'adapters/claude-code/doctrine/review-before-deploy.md', JSON.stringify(anchorsPath));
    const anchorsIds = inboxRoutes.extractAnchorsFromText('see NY-1785357818-7d3f and workflow wf_77b4b077-7a5 for context.');
    ok('S18c extractAnchorsFromText finds NY-<id> and wf_<id> tokens', anchorsIds.length === 2 && anchorsIds.indexOf('NY-1785357818-7d3f') !== -1 && anchorsIds.indexOf('wf_77b4b077-7a5') !== -1, JSON.stringify(anchorsIds));
    const anchorsNone = inboxRoutes.extractAnchorsFromText('I have 9 tasks left, no anchors here at all.');
    ok('S18d extractAnchorsFromText never fabricates a match on ordinary prose with no anchor shape', anchorsNone.length === 0, JSON.stringify(anchorsNone));
    ok('S18e mergeLinks keeps producer-supplied links FIRST, appends extracted ones, deduplicated',
      JSON.stringify(inboxRoutes.mergeLinks(['https://a.test'], ['https://a.test', 'https://b.test'])) === JSON.stringify(['https://a.test', 'https://b.test']));
  } finally {
    server.close();
    try { fs.rmSync(tmp, { recursive: true, force: true }); } catch (_) {}
  }

  console.log('');
  console.log('inbox-routes self-test: ' + PASSED + ' passed, ' + FAILED + ' failed');
  process.exit(FAILED === 0 ? 0 : 1);
}

main().catch((e) => { console.error(e); process.exit(1); });
