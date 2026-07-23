'use strict';
// requests-routes.js — the Requests ledger view's server surface
// (cockpit-roadmap-redesign Task 5: "Requests ledger view"). A NEW file by
// design, mirroring task 3's roadmap-routes.js precedent: task 1 owns
// server.js, task 2 (in flight) owns ask-registry.sh, so this task adds its
// route handlers HERE and the ONE server.js mount line ships as a fragment
// (docs/plans/fragments/roadmap-t5-server-fragment.md) for the orchestrator
// to apply at merge — never a direct edit to a file another task owns.
//
// Routes (handle() returns true when it consumed the request):
//   GET  /requests.js            — serves the client module (one mount line).
//   GET  /api/requests           — the ledger payload (contract below).
//   POST /api/requests/title     — title edit, DELEGATED to ask-registry.sh
//                                  (A3 one-writer discipline; same set-title
//                                  verb roadmap-routes.js already pins).
//   POST /api/requests/amend/detach — amendment "detach" correction (I6),
//                                  DELEGATED to a NEW ask-registry.sh verb
//                                  this task pins (task 2 owns the file —
//                                  see the fragment's §3).
//
// ============================================================
// PAYLOAD CONTRACT (pinned for task-2 merge re-verification)
// ============================================================
// GET /api/requests -> { ok, generated_at, items: [RequestItem] }
// RequestItem = {
//   id,                              // == ask_id (== the Roadmap intent's own id — task 3 precedent)
//   title, title_source: 'operator'|'auto',      // A3: always-editable, operator always outranks auto
//   distilled_intent,                // the auto-derived summary text, KEPT for filtering even
//                                     // after an operator rename (findability — C8)
//   verbatim_ref,                    // '' if none captured — "one click away" (I6)
//   project,
//   created_ts,
//   last_amended_ts,                 // latest NON-origin timeline event ts, '' if never amended (I1)
//   state: 'open'|'closed',
//   closed_reason: ''|'promoted'|'done'|'dismissed'|'merged',
//   closed_at,                       // ISO ts | ''
//   became: {plan_slug, roadmap_id} | null,   // roadmap_id addresses #roadmap/<id> (C6 reciprocal
//                                             // law). Round 8 re-rooted the Roadmap on PLAN slugs
//                                             // (roadmap-routes.js id: pf.slug), so roadmap_id IS
//                                             // the plan slug — an ask id here false-misses.
//   merged_into,                     // ask_id | ''
//   timeline: [TimelineEvent],       // OLDEST-FIRST; origin always first (I6 timeline anatomy)
// }
// TimelineEvent = {
//   type: 'origin'|'title_changed'|'amendment'|'decision'|'project_changed'|'promoted',
//   ts, text,                        // text is ALWAYS a hardcoded/reviewed literal + operator data
//                                    // (asks.js's anti-noise law precedent) — never a gate/hook name
//   detachable,                      // true only for an undetached, non-noise 'amendment' event
//   event_key,                       // correlator for the detach call (see CONTRACT below)
//   plan_slug, verbatim_ref,         // present only on the event types that carry them
// }
//
// ============================================================
// EVOLUTION TIMELINE / CLOSE-ON-PROMOTE (this task's own derivation — no
// task-1/2 seam here; unlike roadmap-routes.js this file owns its fold
// end-to-end, since "the request's exit verb" is THIS view's own law, not
// borrowed from derive-lib)
// ============================================================
// state/closed_reason precedence (documented assumption — the plan names
// "close-on-promote" as the exit verb but doesn't order it against the
// pre-existing done/dismissed/merged registry statuses): an EXPLICIT
// terminal registry status always outranks the STRUCTURALLY-INFERRED
// "promoted" state — merged > dismissed > done > promoted > open. A
// promoted-then-separately-dismissed ask (rare) still reads "dismissed",
// never a stale "became →" for something the operator explicitly closed
// out; the common case (promoted, status still 'active') reads "promoted"
// with the reciprocal #roadmap/<id> link (C6).
//
// ============================================================
// AMENDMENTS — forward-compatible STUB (task 2's capture/classification lane
// is IN FLIGHT; NO record_type:"amendment_candidate" is produced by anything
// today). This reader folds the record type honestly if/when it appears
// (task 2's own schema decision; this fold is this task's best-effort
// documented guess, reconciled at task-2 merge per the fragment) so the
// timeline anatomy + detach affordance are provably wired NOW against real
// fixture data, without fabricating amendments that were never captured
// (HONEST LIMIT — A2: "amendment detection is best-effort, not a
// guarantee"). Pinned shapes:
//   {record_type:"amendment_candidate", ask_id, ts, verbatim_ref,
//    classification:""|"amendment"|"noise"}
//   {record_type:"amendment_detached", ask_id, ts, detach_ref:<candidate ts>,
//    emitter}
// A candidate classified "noise" or ever detached never renders (I6:
// detach "marks not-an-amendment" — same effect as classifier noise).
// event_key correlates a candidate to its detach call: "<candidate ts>"
// (documented risk: two candidates sharing the same second-granularity ts
// for one ask would collide — accepted at this granularity, same convention
// used elsewhere in this codebase for ts-keyed correlation).

const fs = require('fs');
const path = require('path');
const deriveLib = require('./derive-lib.js');

const WEB_DIR = path.join(__dirname, '..', 'web');

function sendJson(res, code, obj) {
  res.writeHead(code, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify(obj));
}

// ----------------------------------------------------------------------
// decisionText(status, emitter) — a plain-English, hardcoded-literal label
// for a status_change/merged event (asks.js's anti-noise law precedent:
// never a gate/hook/oracle identifier in operator-visible text).
// ----------------------------------------------------------------------
function decisionText(status, emitter) {
  const who = emitter === 'operator-ui' ? '(you)' : emitter === 'auditor' ? '(auto-detected)' : (emitter ? '(' + emitter + ')' : '');
  let verb;
  if (status === 'done') verb = 'marked done';
  else if (status === 'dismissed') verb = 'dismissed';
  else if (status === 'active') verb = 'reopened';
  else verb = status || 'status changed';
  return (verb + ' ' + who).trim();
}

// ----------------------------------------------------------------------
// foldRegistryForRequests() — reads the raw registry once and folds per-ask,
// building the OLDEST-FIRST timeline as it goes (evolution timeline: origin
// pinned first via the 'created' record, every subsequent record type below
// appending its own timeline entry).
// ----------------------------------------------------------------------
function foldRegistryForRequests() {
  const lines = deriveLib.readAskRegistry().slice()
    .sort((a, b) => String(a.ts).localeCompare(String(b.ts)));
  const byAsk = {};
  function askOf(id) {
    if (!byAsk[id]) {
      byAsk[id] = {
        ask_id: id, plan_slugs: [], status: 'active', status_ts: '', status_emitter: '',
        created_ts: '', origin_session: '', repo: '', project: '',
        summary: '', verbatim_ref: '', auto_title: '', operator_title: '',
        merged_into: '', timeline: [], _amendments: {}, _detached: {},
      };
    }
    return byAsk[id];
  }

  lines.forEach((rec) => {
    if (!rec || !rec.ask_id) return;
    const cur = askOf(rec.ask_id);
    if (rec.project) cur.project = rec.project;
    if (rec.repo) cur.repo = rec.repo;

    if (rec.record_type === 'created') {
      cur.created_ts = rec.ts || '';
      cur.origin_session = rec.origin_session || rec.session_id || '';
      if (rec.summary) { cur.summary = rec.summary; cur.auto_title = rec.summary; }
      if (rec.verbatim_ref) cur.verbatim_ref = rec.verbatim_ref;
      if (rec.status) { cur.status = rec.status; cur.status_ts = rec.ts || ''; }
      cur.timeline.push({
        type: 'origin', ts: cur.created_ts,
        text: 'Registered' + (cur.summary ? ': "' + cur.summary + '"' : ''),
        event_key: (cur.created_ts || '') + ':origin',
      });
      return;
    }
    if (rec.record_type === 'plan_linked' && rec.plan_slug) {
      if (cur.plan_slugs.indexOf(rec.plan_slug) === -1) cur.plan_slugs.push(rec.plan_slug);
      cur.timeline.push({
        type: 'promoted', ts: rec.ts || '', plan_slug: rec.plan_slug,
        text: 'became → ' + rec.plan_slug,
        event_key: (rec.ts || '') + ':promoted:' + rec.plan_slug,
      });
      return;
    }
    if (rec.record_type === 'status_change' && rec.status) {
      cur.status = rec.status; cur.status_ts = rec.ts || ''; cur.status_emitter = rec.emitter || '';
      cur.timeline.push({
        type: 'decision', ts: rec.ts || '', text: decisionText(rec.status, rec.emitter),
        event_key: (rec.ts || '') + ':decision:' + rec.status,
      });
      return;
    }
    if (rec.record_type === 'merged' && rec.status) {
      cur.status = rec.status; cur.status_ts = rec.ts || ''; cur.status_emitter = rec.emitter || '';
      cur.merged_into = rec.merged_into || '';
      cur.timeline.push({
        type: 'decision', ts: rec.ts || '',
        text: 'merged into ' + (rec.merged_into || 'another request'),
        event_key: (rec.ts || '') + ':decision:merged',
      });
      return;
    }
    if (rec.record_type === 'summary_updated' && rec.summary) {
      cur.auto_title = rec.summary;
      cur.timeline.push({
        type: 'title_changed', ts: rec.ts || '', text: 'title auto-updated: "' + rec.summary + '"',
        event_key: (rec.ts || '') + ':title:auto',
      });
      return;
    }
    if (rec.record_type === 'title_set' && rec.title) {
      if (rec.title_source === 'operator') cur.operator_title = rec.title; else cur.auto_title = rec.title;
      cur.timeline.push({
        type: 'title_changed', ts: rec.ts || '',
        text: 'title ' + (rec.title_source === 'operator' ? 'edited' : 'auto-updated') + ': "' + rec.title + '"',
        event_key: (rec.ts || '') + ':title:' + (rec.title_source || 'auto'),
      });
      return;
    }
    if (rec.record_type === 'project_override' && rec.project) {
      cur.timeline.push({
        type: 'project_changed', ts: rec.ts || '', text: 'moved to project "' + rec.project + '"',
        event_key: (rec.ts || '') + ':project',
      });
      return;
    }
    // ---- forward-compatible amendment lane (see header STUB note) ----
    if (rec.record_type === 'amendment_candidate') {
      const key = String(rec.ts || '');
      cur._amendments[key] = { ts: rec.ts || '', verbatim_ref: rec.verbatim_ref || '', classification: rec.classification || '' };
      return;
    }
    if (rec.record_type === 'amendment_detached' && rec.detach_ref) {
      cur._detached[String(rec.detach_ref)] = true;
      return;
    }
  });

  Object.keys(byAsk).forEach((askId) => {
    const cur = byAsk[askId];
    Object.keys(cur._amendments).forEach((key) => {
      const a = cur._amendments[key];
      if (a.classification === 'noise') return; // classifier said not-an-amendment
      if (cur._detached[key]) return; // detached = treated as not-an-amendment (I6)
      const pending = !a.classification;
      cur.timeline.push({
        type: 'amendment', ts: a.ts, verbatim_ref: a.verbatim_ref,
        text: pending ? 'possible amendment captured (not yet classified)' : 'amendment captured',
        detachable: true, event_key: key,
      });
    });
    cur.timeline.sort((a, b) => String(a.ts).localeCompare(String(b.ts)));
    delete cur._amendments;
    delete cur._detached;
  });
  return byAsk;
}

// classifyRequestState(cur) — see header precedence note.
function classifyRequestState(cur) {
  if (cur.status === 'merged') {
    return { state: 'closed', closed_reason: 'merged', closed_at: cur.status_ts || '', became: null };
  }
  if (cur.status === 'dismissed') {
    return { state: 'closed', closed_reason: 'dismissed', closed_at: cur.status_ts || '', became: null };
  }
  if (cur.status === 'done') {
    return { state: 'closed', closed_reason: 'done', closed_at: cur.status_ts || '', became: null };
  }
  if (cur.plan_slugs.length) {
    const promotedEvents = cur.timeline.filter((e) => e.type === 'promoted');
    const latest = promotedEvents.length ? promotedEvents[promotedEvents.length - 1] : null;
    const slug = latest ? latest.plan_slug : cur.plan_slugs[cur.plan_slugs.length - 1];
    const closedAt = latest ? latest.ts : '';
    return { state: 'closed', closed_reason: 'promoted', closed_at: closedAt, became: { plan_slug: slug, roadmap_id: slug } };
  }
  return { state: 'open', closed_reason: '', closed_at: '', became: null };
}

function buildRequestItem(cur) {
  const title = cur.operator_title || cur.auto_title || cur.summary || cur.ask_id;
  const titleSource = cur.operator_title ? 'operator' : 'auto';
  const distilledIntent = cur.auto_title || cur.summary || '';
  const cls = classifyRequestState(cur);
  const nonOrigin = cur.timeline.filter((e) => e.type !== 'origin');
  const lastAmendedTs = nonOrigin.length ? nonOrigin.map((e) => e.ts).sort().pop() : '';
  return {
    id: cur.ask_id,
    title: title,
    title_source: titleSource,
    distilled_intent: distilledIntent,
    verbatim_ref: cur.verbatim_ref || '',
    project: cur.project || '',
    created_ts: cur.created_ts || '',
    last_amended_ts: lastAmendedTs || '',
    state: cls.state,
    closed_reason: cls.closed_reason,
    closed_at: cls.closed_at || '',
    became: cls.became,
    merged_into: cur.merged_into || '',
    timeline: cur.timeline.map((e) => ({
      type: e.type, ts: e.ts || '', text: e.text || '',
      detachable: !!e.detachable, event_key: e.event_key || '',
      plan_slug: e.plan_slug || '', verbatim_ref: e.verbatim_ref || '',
    })),
  };
}

function buildRequestsPayload() {
  const byAsk = foldRegistryForRequests();
  const items = Object.keys(byAsk).map((id) => buildRequestItem(byAsk[id]));
  // Newest-registered first — open items needing triage surface earliest;
  // closed items are re-grouped by age client-side regardless (C8).
  items.sort((a, b) => String(b.created_ts).localeCompare(String(a.created_ts)));
  return { ok: true, generated_at: new Date().toISOString(), items: items };
}

// ----------------------------------------------------------------------
// ask-registry.sh delegation (one-writer discipline) — duplicated per this
// codebase's small-helper convention (roadmap-routes.js's own header note:
// "because server.js is task-1-owned right now"; here because
// ask-registry.sh is task-2-owned and concurrently in flight).
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
// handle(req, res) -> true when consumed. The ONE server.js mount line (see
// the fragment file): if (requestsRoutes.handle(req, res)) return;
// ----------------------------------------------------------------------
function handle(req, res) {
  const urlPath = String(req.url || '').split('?')[0];

  if (urlPath === '/requests.js' && req.method === 'GET') {
    fs.readFile(path.join(WEB_DIR, 'requests.js'), (err, buf) => {
      if (err) { res.writeHead(404); res.end('not found'); return; }
      res.writeHead(200, { 'Content-Type': 'text/javascript; charset=utf-8', 'Cache-Control': 'no-cache, must-revalidate' });
      res.end(buf);
    });
    return true;
  }

  if (urlPath === '/api/requests' && req.method === 'GET') {
    try {
      sendJson(res, 200, buildRequestsPayload());
    } catch (e) {
      // rc-style honesty: the client renders pane-error + Retry from
      // ok:false — NEVER the empty state on failure (C4).
      sendJson(res, 200, { ok: false, error: String(e && e.message || e), items: [] });
    }
    return true;
  }

  if (urlPath === '/api/requests/title' && req.method === 'POST') {
    readBody(req, (input) => {
      if (!input) return sendJson(res, 400, { ok: false, error: 'bad json' });
      const askId = typeof input.ask_id === 'string' ? input.ask_id : '';
      const title = typeof input.title === 'string' ? input.title.trim() : '';
      if (!askId || !title) return sendJson(res, 400, { ok: false, error: 'ask_id and a non-empty title are required' });
      // One-writer discipline (A3): the title lives in the registry, so this
      // endpoint ONLY delegates — no second title store. Same pinned verb
      // roadmap-routes.js's /api/roadmap/title already calls.
      runAskRegistryCli(['set-title', '--ask-id', askId, '--title', title, '--title-source', 'operator', '--emitter', 'operator-ui'])
        .then((r) => {
          if (r.ok) return sendJson(res, 200, { ok: true, ask_id: askId, title: title, title_source: 'operator' });
          const why = r.missing ? 'the title store is not available on this build yet'
            : ('the title store rejected the change' + (r.stderr ? ': ' + String(r.stderr).trim().split('\n').pop() : ''));
          sendJson(res, 200, { ok: false, error: 'could not save the title — ' + why });
        });
    });
    return true;
  }

  if (urlPath === '/api/requests/amend/detach' && req.method === 'POST') {
    readBody(req, (input) => {
      if (!input) return sendJson(res, 400, { ok: false, error: 'bad json' });
      const askId = typeof input.ask_id === 'string' ? input.ask_id : '';
      const eventTs = typeof input.event_ts === 'string' ? input.event_ts : '';
      if (!askId || !eventTs) return sendJson(res, 400, { ok: false, error: 'ask_id and event_ts are required' });
      // Amendment correction (I6) — task 2 (in flight) owns ask-registry.sh
      // and this exact verb; until it lands, the honest answer is a NAMED
      // error, never a silent success (this task's dispatch mandate).
      runAskRegistryCli(['detach-amendment', '--ask-id', askId, '--event-ts', eventTs, '--emitter', 'operator-ui'])
        .then((r) => {
          if (r.ok) return sendJson(res, 200, { ok: true, ask_id: askId, event_ts: eventTs });
          const why = r.missing ? 'the amendment-correction verb is not available on this build yet'
            : ('the registry rejected the correction' + (r.stderr ? ': ' + String(r.stderr).trim().split('\n').pop() : ''));
          sendJson(res, 200, { ok: false, error: 'could not detach this amendment — ' + why });
        });
    });
    return true;
  }

  return false;
}

module.exports = {
  handle,
  buildRequestsPayload,
  foldRegistryForRequests,
  classifyRequestState,
  decisionText,
};
