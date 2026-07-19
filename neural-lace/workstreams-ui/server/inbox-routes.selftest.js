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
    ok('S2 clean decision + clean question land in answerable; nothing else does',
      answerableIds.length === 2 && answerableIds[0] === 'NY-clean' && answerableIds[1] === 'NY-question',
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

    // ---- S6: "blocks:" HONEST LIMIT -- always null (no fabricated correlation) ----
    ok('S6 blocks_roadmap_id is always null (no roadmap-side signal exists yet -- see server header HONEST LIMIT)',
      clean && clean.blocks_roadmap_id === null && quarantined && quarantined.blocks_roadmap_id === null);

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

    // ---- S9: absent ledger.json -- TRUE-empty (C4), never an error ----
    fs.rmSync(path.join(nyStateDir, 'ledger.json'), { force: true });
    const r3 = await httpGet(PORT, '/api/inbox');
    ok('S9 an absent ledger.json is an honest TRUE-empty state (ok:true, ledger_present:false), never an error',
      r3.status === 200 && r3.json && r3.json.ok === true && r3.json.ledger_present === false &&
      r3.json.answerable.length === 0 && r3.json.quarantined.length === 0);

    // ---- S10: /inbox.js is served by this handler (single mount line) ----
    const asset = await httpGet(PORT, '/inbox.js');
    ok('S10 GET /inbox.js serves the client module with a JS content type',
      asset.status === 200 && /javascript/.test(asset.headers['content-type'] || '') && asset.body.length > 500,
      'status=' + asset.status + ' len=' + asset.body.length);
  } finally {
    server.close();
    try { fs.rmSync(tmp, { recursive: true, force: true }); } catch (_) {}
  }

  console.log('');
  console.log('inbox-routes self-test: ' + PASSED + ' passed, ' + FAILED + ' failed');
  process.exit(FAILED === 0 ? 0 : 1);
}

main().catch((e) => { console.error(e); process.exit(1); });
