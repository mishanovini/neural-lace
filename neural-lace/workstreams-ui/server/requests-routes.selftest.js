'use strict';
// requests-routes.selftest.js — sandboxed self-test for the Requests ledger
// view's server surface (cockpit-roadmap-redesign Task 5). Own file (not
// server.selftest.js or roadmap-routes.selftest.js) so no task races on a
// shared test file — same rationale as roadmap-routes.selftest.js's header.
//
// REAL-SCENARIO discipline (no mocking the SUT): fixtures are a REAL
// ask-registry.jsonl under a mktemp sandbox (ASK_REGISTRY_STATE_DIR),
// requests are REAL HTTP GET/POSTs against the mounted handler.
//
// Run: `node server/requests-routes.selftest.js`. Exit 0 PASS / 1 FAIL.
// Extra mode: `node server/requests-routes.selftest.js --serve` keeps the
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
  for (let i = 0; i < (items || []).length; i++) {
    if (items[i].id === id) return items[i];
  }
  return null;
}

async function main() {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'requests-t5-st-'));
  const stateDir = path.join(tmp, 'state');
  const progressDir = path.join(tmp, 'progress');
  fs.mkdirSync(stateDir, { recursive: true });
  fs.mkdirSync(progressDir, { recursive: true });

  process.env.ASK_REGISTRY_STATE_DIR = stateDir;
  process.env.PROGRESS_LOG_STATE_DIR = progressDir;
  // Point the CLI delegation at a nonexistent path by default: both write
  // endpoints must return a NAMED error, never a silent success.
  process.env.ASK_REGISTRY_CLI = path.join(tmp, 'no-such-cli.sh');

  const reg = [
    // ask-open: registered, never touched again -> state=open, never amended.
    { ask_id: 'ask-open', record_type: 'created', ts: '2026-07-15T10:00:00Z', summary: 'A fresh idea', repo: '/r', project: 'demo', origin_session: 'sess-1', status: 'active', emitter: 'ask-registry' },

    // ask-promoted: registered, then linked to a plan -> state=closed,
    // reason=promoted, "became -> demo-plan", reciprocal roadmap_id=PLAN slug
    // (Round 8 re-rooted the Roadmap on plan slugs; an ask id false-misses).
    { ask_id: 'ask-promoted', record_type: 'created', ts: '2026-07-10T10:00:00Z', summary: 'Build the alpha feature', repo: '/r', project: 'demo', origin_session: 'sess-2', status: 'active', emitter: 'ask-registry' },
    { ask_id: 'ask-promoted', record_type: 'plan_linked', ts: '2026-07-10T11:00:00Z', plan_slug: 'demo-plan' },

    // ask-done-direct: marked done WITHOUT ever being promoted -> closed, reason=done.
    { ask_id: 'ask-done-direct', record_type: 'created', ts: '2026-07-01T10:00:00Z', summary: 'Old finished thing', repo: '/r', project: 'demo', origin_session: 'sess-3', status: 'active', emitter: 'ask-registry' },
    { ask_id: 'ask-done-direct', record_type: 'status_change', ts: '2026-07-02T10:00:00Z', status: 'done', emitter: 'operator-ui' },

    // ask-dismissed -> closed, reason=dismissed.
    { ask_id: 'ask-dismissed', record_type: 'created', ts: '2026-07-03T10:00:00Z', summary: 'Abandoned idea', repo: '/r', project: 'demo', origin_session: 'sess-4', status: 'active', emitter: 'ask-registry' },
    { ask_id: 'ask-dismissed', record_type: 'status_change', ts: '2026-07-04T10:00:00Z', status: 'dismissed', emitter: 'operator-ui' },

    // ask-dup: merged into ask-open -> closed, reason=merged, merged_into set.
    { ask_id: 'ask-dup', record_type: 'created', ts: '2026-07-05T10:00:00Z', summary: 'Duplicate of the fresh idea', repo: '/r', project: 'demo', origin_session: 'sess-5', status: 'active', emitter: 'ask-registry' },
    { ask_id: 'ask-dup', record_type: 'merged', ts: '2026-07-06T10:00:00Z', status: 'merged', merged_into: 'ask-open', emitter: 'operator-ui' },

    // ask-renamed: operator title change AFTER a LATER auto summary update —
    // A3: operator ALWAYS outranks auto regardless of timestamp order.
    { ask_id: 'ask-renamed', record_type: 'created', ts: '2026-07-08T10:00:00Z', summary: 'auto distilled summary', repo: '/r', project: 'demo', origin_session: 'sess-6', status: 'active', emitter: 'ask-registry' },
    { ask_id: 'ask-renamed', record_type: 'title_set', ts: '2026-07-08T11:00:00Z', title: 'Operator chosen title', title_source: 'operator', emitter: 'operator-ui' },
    { ask_id: 'ask-renamed', record_type: 'summary_updated', ts: '2026-07-08T12:00:00Z', summary: 'a later, better auto summary' },

    // ask-amend: carries one PENDING amendment candidate + one already
    // classified 'noise' (forward-compat fixture — task 2 doesn't produce
    // these yet in production, but the fold must honor the shape).
    { ask_id: 'ask-amend', record_type: 'created', ts: '2026-07-12T10:00:00Z', summary: 'Ask with amendments', repo: '/r', project: 'demo', origin_session: 'sess-7', status: 'active', emitter: 'ask-registry' },
    { ask_id: 'ask-amend', record_type: 'amendment_candidate', ts: '2026-07-12T11:00:00Z', verbatim_ref: '/t/transcript.jsonl#42', classification: '' },
    { ask_id: 'ask-amend', record_type: 'amendment_candidate', ts: '2026-07-12T12:00:00Z', verbatim_ref: '/t/transcript.jsonl#77', classification: 'noise' },

    // ask-detached: a candidate that HAS been detached -> must NOT render.
    { ask_id: 'ask-detached', record_type: 'created', ts: '2026-07-13T10:00:00Z', summary: 'Ask with a detached amendment', repo: '/r', project: 'demo', origin_session: 'sess-8', status: 'active', emitter: 'ask-registry' },
    { ask_id: 'ask-detached', record_type: 'amendment_candidate', ts: '2026-07-13T11:00:00Z', verbatim_ref: '/t/transcript.jsonl#99', classification: 'amendment' },
    { ask_id: 'ask-detached', record_type: 'amendment_detached', ts: '2026-07-13T12:00:00Z', detach_ref: '2026-07-13T11:00:00Z', emitter: 'operator-ui' },
  ];
  fs.writeFileSync(path.join(stateDir, 'ask-registry.jsonl'), reg.map((r) => JSON.stringify(r)).join('\n') + '\n');

  delete require.cache[require.resolve('./requests-routes.js')];
  const requestsRoutes = require('./requests-routes.js');

  const PORT = 19790 + (process.pid % 997);
  const server = http.createServer((req, res) => {
    if (requestsRoutes.handle(req, res)) return;
    const WEB = path.join(__dirname, '..', 'web');
    const clean = req.url.split('?')[0];
    const file = clean === '/' ? 'index.html' : clean.replace(/^\//, '');
    const abs = path.join(WEB, file);
    if (/\.(html|js|css)$/.test(file) && fs.existsSync(abs)) {
      const mime = /\.html$/.test(file) ? 'text/html' : /\.css$/.test(file) ? 'text/css' : 'text/javascript';
      res.writeHead(200, { 'Content-Type': mime + '; charset=utf-8' });
      res.end(fs.readFileSync(abs));
      return;
    }
    res.writeHead(404); res.end('not found');
  });
  await new Promise((resolve) => server.listen(PORT, '127.0.0.1', resolve));

  if (process.argv.indexOf('--serve') !== -1) {
    console.log('[requests-routes.selftest] fixture server on http://127.0.0.1:' + PORT + ' (Ctrl-C to stop)');
    return;
  }

  try {
    // ---- S1: payload shape ----
    const r1 = await httpGet(PORT, '/api/requests');
    ok('S1 GET /api/requests returns ok:true with items[]', r1.status === 200 && r1.json && r1.json.ok === true && Array.isArray(r1.json.items));
    const items = (r1.json && r1.json.items) || [];
    ok('S1b every ask registered in the fixture appears in the ledger (nothing silently vanishes)',
      ['ask-open', 'ask-promoted', 'ask-done-direct', 'ask-dismissed', 'ask-dup', 'ask-renamed', 'ask-amend', 'ask-detached'].every((id) => !!findItem(items, id)));

    // ---- S2: title fold (A3 — operator ALWAYS outranks auto regardless of ts) ----
    const renamed = findItem(items, 'ask-renamed');
    ok('S2 operator title wins even though a LATER auto summary_updated arrived after it',
      renamed && renamed.title === 'Operator chosen title' && renamed.title_source === 'operator');
    ok('S2b distilled_intent keeps the AUTO text for filtering, distinct from the operator-renamed title',
      renamed && renamed.distilled_intent === 'a later, better auto summary' && renamed.distilled_intent !== renamed.title);

    // ---- S3: open vs closed classification + closed_reason ----
    const openItem = findItem(items, 'ask-open');
    ok('S3 a never-touched ask renders state=open with no closed_reason', openItem && openItem.state === 'open' && openItem.closed_reason === '');
    const promoted = findItem(items, 'ask-promoted');
    ok('S3b a plan-linked ask renders CLOSED, reason=promoted, "became" names the plan + the reciprocal roadmap id (= the plan slug, Round 8)',
      promoted && promoted.state === 'closed' && promoted.closed_reason === 'promoted' &&
      promoted.became && promoted.became.plan_slug === 'demo-plan' && promoted.became.roadmap_id === 'demo-plan');
    const doneDirect = findItem(items, 'ask-done-direct');
    ok('S3c a directly-done ask (never promoted) renders CLOSED, reason=done, no became', doneDirect && doneDirect.state === 'closed' && doneDirect.closed_reason === 'done' && doneDirect.became === null);
    const dismissed = findItem(items, 'ask-dismissed');
    ok('S3d a dismissed ask renders CLOSED, reason=dismissed', dismissed && dismissed.state === 'closed' && dismissed.closed_reason === 'dismissed');
    const dup = findItem(items, 'ask-dup');
    ok('S3e a merged (duplicate) ask renders CLOSED, reason=merged, merged_into names the target', dup && dup.state === 'closed' && dup.closed_reason === 'merged' && dup.merged_into === 'ask-open');

    // ---- S4: timeline anatomy — oldest-first, origin pinned first, "became" as a real event ----
    const promotedTimeline = promoted.timeline;
    ok('S4 timeline is chronological (oldest-first)',
      promotedTimeline.every((e, i) => i === 0 || String(promotedTimeline[i - 1].ts) <= String(e.ts)));
    ok('S4b origin is ALWAYS the first event and carries the registered summary', promotedTimeline[0].type === 'origin' && /Build the alpha feature/.test(promotedTimeline[0].text));
    ok('S4c the terminal event is the "became →" promotion, naming the plan', promotedTimeline[promotedTimeline.length - 1].type === 'promoted' && /became → demo-plan/.test(promotedTimeline[promotedTimeline.length - 1].text));

    // ---- S5: recency (I1) — last_amended_ts reflects the latest non-origin event ----
    ok('S5 an ask with zero amendments/decisions has last_amended_ts = "" (never fabricated)', openItem.last_amended_ts === '');
    ok('S5b a promoted ask\'s last_amended_ts is the promotion event\'s ts', promoted.last_amended_ts === '2026-07-10T11:00:00Z');

    // ---- S6: verbatim origin carried eagerly ("one click away") ----
    ok('S6 verbatim_ref is present on the landing payload item (no second fetch needed to reveal it)', openItem.verbatim_ref === '' || typeof openItem.verbatim_ref === 'string');
    ok('S6b an ask with no verbatim ref captured renders an honest empty string, not a fabricated placeholder', openItem.verbatim_ref === '');

    // ---- S7: amendment forward-compat + honest filtering (noise/detached never render) ----
    const amendItem = findItem(items, 'ask-amend');
    const amendEvents = amendItem.timeline.filter((e) => e.type === 'amendment');
    ok('S7 a PENDING (unclassified) amendment candidate renders as a detachable timeline entry', amendEvents.length === 1 && amendEvents[0].detachable === true && /not yet classified/.test(amendEvents[0].text));
    ok('S7b a candidate classified "noise" by task 2\'s classifier never renders (best-effort honesty, not a guarantee)',
      amendItem.timeline.filter((e) => e.verbatim_ref === '/t/transcript.jsonl#77').length === 0);
    const detachedItem = findItem(items, 'ask-detached');
    ok('S7c a DETACHED amendment is excluded from the timeline (detach marks it not-an-amendment, I6)',
      detachedItem.timeline.filter((e) => e.type === 'amendment').length === 0);

    // ---- S8: title endpoint — named error with no CLI, then delegates once a fake CLI exists ----
    const title = await httpPostJson(PORT, '/api/requests/title', { ask_id: 'ask-open', title: 'A better name' });
    ok('S8 title update with no registry CLI returns ok:false with a plain-language error',
      title.json && title.json.ok === false && typeof title.json.error === 'string' && title.json.error.length > 10);
    const cliLog = path.join(tmp, 'cli-args.log');
    const fakeCli = path.join(tmp, 'fake-ask-registry.sh');
    fs.writeFileSync(fakeCli, '#!/bin/bash\necho "$@" >> ' + JSON.stringify(cliLog.replace(/\\/g, '/')) + '\nexit 0\n');
    fs.chmodSync(fakeCli, 0o755);
    process.env.ASK_REGISTRY_CLI = fakeCli;
    const title2 = await httpPostJson(PORT, '/api/requests/title', { ask_id: 'ask-open', title: 'A better name' });
    const cliArgs = fs.existsSync(cliLog) ? fs.readFileSync(cliLog, 'utf8') : '';
    ok('S8b with the CLI present, the title edit DELEGATES (one-writer discipline): set-title --title-source operator',
      title2.json && title2.json.ok === true && /set-title/.test(cliArgs) && /--title-source operator/.test(cliArgs) && /A better name/.test(cliArgs),
      cliArgs.slice(0, 200));

    // ---- S9: amend/detach endpoint — named error with no CLI, delegates with the pinned shape once present ----
    process.env.ASK_REGISTRY_CLI = path.join(tmp, 'no-such-cli.sh');
    const detach1 = await httpPostJson(PORT, '/api/requests/amend/detach', { ask_id: 'ask-amend', event_ts: '2026-07-12T11:00:00Z' });
    ok('S9 detach with no registry CLI returns ok:false naming the gap, never a silent success',
      detach1.json && detach1.json.ok === false && /not available/.test(detach1.json.error));
    process.env.ASK_REGISTRY_CLI = fakeCli;
    const detach2 = await httpPostJson(PORT, '/api/requests/amend/detach', { ask_id: 'ask-amend', event_ts: '2026-07-12T11:00:00Z' });
    const cliArgs2 = fs.existsSync(cliLog) ? fs.readFileSync(cliLog, 'utf8') : '';
    ok('S9b with the CLI present, detach DELEGATES the pinned shape: detach-amendment --ask-id --event-ts --emitter operator-ui',
      detach2.json && detach2.json.ok === true && /detach-amendment/.test(cliArgs2) && /--event-ts 2026-07-12T11:00:00Z/.test(cliArgs2) && /--emitter operator-ui/.test(cliArgs2),
      cliArgs2.slice(0, 300));

    // ---- S10: error honesty — a torn registry file never crashes the route ----
    fs.writeFileSync(path.join(stateDir, 'ask-registry.jsonl'), '{"broken json\n');
    const r2 = await httpGet(PORT, '/api/requests');
    ok('S10 corrupt registry degrades to an EMPTY-BUT-OK payload, never a 500 crash',
      r2.status === 200 && r2.json && r2.json.ok === true && Array.isArray(r2.json.items) && r2.json.items.length === 0);

    // ---- S11: /requests.js is served by this handler (single mount line) ----
    const asset = await httpGet(PORT, '/requests.js');
    ok('S11 GET /requests.js serves the client module with a JS content type',
      asset.status === 200 && /javascript/.test(asset.headers['content-type'] || '') && asset.body.length > 500,
      'status=' + asset.status + ' len=' + asset.body.length);
  } finally {
    server.close();
    try { fs.rmSync(tmp, { recursive: true, force: true }); } catch (_) {}
  }

  console.log('');
  console.log('requests-routes self-test: ' + PASSED + ' passed, ' + FAILED + ' failed');
  process.exit(FAILED === 0 ? 0 : 1);
}

main().catch((e) => { console.error(e); process.exit(1); });
