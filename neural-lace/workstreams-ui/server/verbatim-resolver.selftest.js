'use strict';
// verbatim-resolver.selftest.js — sandboxed self-test for the ask-registry
// verbatim_ref resolver + deterministic amendment classifier (2026-07-30
// operator-facing defect: "the Requests tab isn't showing much of
// anything"). Own file (matches the *.selftest.js-per-module convention
// used across this codebase — requests-routes.selftest.js's own header).
//
// REAL-SCENARIO discipline: fixture transcripts are REAL JSONL files on disk
// (mktemp sandbox), read through the real fs calls this module uses in
// production — no mocking the SUT.
//
// Run: `node server/verbatim-resolver.selftest.js`. Exit 0 PASS / 1 FAIL.

const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync } = require('child_process');

const resolver = require('./verbatim-resolver.js');

let PASSED = 0, FAILED = 0;
function ok(name, cond, detail) {
  if (cond) { PASSED++; console.log('  PASS: ' + name); }
  else { FAILED++; console.log('  FAIL: ' + name + (detail ? ' (' + detail + ')' : '')); }
}

function transcriptLine(obj) { return JSON.stringify(obj); }

function userTurn(ts, content, extra) {
  return transcriptLine(Object.assign({
    type: 'user', timestamp: ts, isSidechain: false,
    message: { role: 'user', content: content },
  }, extra || {}));
}
function toolResultTurn(ts) {
  return transcriptLine({
    type: 'user', timestamp: ts, isSidechain: false,
    message: { role: 'user', content: [{ type: 'tool_result', content: 'ok' }] },
  });
}
function assistantTurn(ts) {
  return transcriptLine({ type: 'assistant', timestamp: ts, message: { role: 'assistant', content: [{ type: 'text', text: 'ack' }] } });
}
function sidechainUserTurn(ts, content) {
  return transcriptLine({
    type: 'user', timestamp: ts, isSidechain: true,
    message: { role: 'user', content: content },
  });
}

function main() {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'verbatim-resolver-st-'));

  // ---- parseRef ----
  ok('parseRef splits path and ordinal on the last #', JSON.stringify(resolver.parseRef('/a/b/c.jsonl#12')) === JSON.stringify({ path: '/a/b/c.jsonl', ordinal: 12 }));
  ok('parseRef returns null with no #', resolver.parseRef('/a/b/c.jsonl') === null);
  ok('parseRef tolerates a non-numeric ordinal (ordinal:null, path kept)', (() => {
    const r = resolver.parseRef('/a/b/c.jsonl#abc');
    return r && r.path === '/a/b/c.jsonl' && r.ordinal === null;
  })());

  // ---- extractRealOperatorText ----
  ok('extractRealOperatorText: plain string content is real text',
    resolver.extractRealOperatorText({ type: 'user', message: { role: 'user', content: 'hello there' } }) === 'hello there');
  ok('extractRealOperatorText: a tool_result-bearing array is NOT real text (synthetic echo)',
    resolver.extractRealOperatorText({ type: 'user', message: { role: 'user', content: [{ type: 'tool_result', content: 'x' }] } }) === null);
  ok('extractRealOperatorText: isSidechain excludes a sub-agent turn',
    resolver.extractRealOperatorText({ type: 'user', isSidechain: true, message: { role: 'user', content: 'sub-agent text' } }) === null);
  ok('extractRealOperatorText: an assistant-role message is never real operator text',
    resolver.extractRealOperatorText({ type: 'user', message: { role: 'assistant', content: 'x' } }) === null);
  ok('extractRealOperatorText: text+image array joins the text blocks',
    resolver.extractRealOperatorText({ type: 'user', message: { role: 'user', content: [{ type: 'image' }, { type: 'text', text: 'see attached' }] } }) === 'see attached');

  // ---- resolveVerbatimRef: nearest-by-timestamp is robust to interleaved
  // synthetic/tool-result/sidechain noise, unlike naive ordinal counting ----
  const t1 = path.join(tmp, 't1.jsonl');
  fs.writeFileSync(t1, [
    userTurn('2026-07-28T04:00:00.000Z', 'Please connect to gh and download the latest copy of Neural Lace.'),
    assistantTurn('2026-07-28T04:00:05.000Z'),
    toolResultTurn('2026-07-28T04:00:06.000Z'),
    userTurn('2026-07-28T04:04:19.733Z', 'How would you recommend proceeding?'),
    toolResultTurn('2026-07-28T04:05:00.000Z'),
    sidechainUserTurn('2026-07-28T04:05:01.000Z', 'internal sub-agent chatter, never a real ask'),
    userTurn('2026-07-28T04:10:00.000Z', 'Give me the TLDR on active plans on this machine.'),
  ].join('\n') + '\n');

  const r1 = resolver.resolveVerbatimRef(t1 + '#1', '2026-07-28T04:04:19Z');
  ok('resolveVerbatimRef: nearest-timestamp resolves the correct real-user entry despite interleaved synthetic/tool-result/sidechain lines',
    r1.ok === true && r1.text === 'How would you recommend proceeding?' && r1.confidence === 'nearest',
    JSON.stringify(r1));

  const r2 = resolver.resolveVerbatimRef(t1 + '#2', '2026-07-28T04:10:00Z');
  ok('resolveVerbatimRef: a second, later candidate in the same transcript resolves independently (self-correcting per-record, no drift)',
    r2.ok === true && r2.text === 'Give me the TLDR on active plans on this machine.',
    JSON.stringify(r2));

  const r3 = resolver.resolveVerbatimRef(t1 + '#0', '2026-07-30T00:00:00Z'); // way out of tolerance
  ok('resolveVerbatimRef: falls back to ordinal indexing when no timestamp is within tolerance',
    r3.ok === true && r3.text === 'Please connect to gh and download the latest copy of Neural Lace.' && r3.confidence === 'ordinal',
    JSON.stringify(r3));

  const r4 = resolver.resolveVerbatimRef(path.join(tmp, 'nope.jsonl') + '#0', '2026-07-28T04:00:00Z');
  ok('resolveVerbatimRef: a missing transcript file fails honestly (ok:false), never fabricates', r4.ok === false);

  const r5 = resolver.resolveVerbatimRef('not-a-valid-ref', '2026-07-28T04:00:00Z');
  ok('resolveVerbatimRef: an unparseable ref fails honestly', r5.ok === false);

  // ---- cache invalidation: a growing transcript is picked up, not stuck stale ----
  const t2 = path.join(tmp, 't2.jsonl');
  fs.writeFileSync(t2, userTurn('2026-07-29T00:00:00.000Z', 'first message') + '\n');
  resolver.resolveVerbatimRef(t2 + '#0', '2026-07-29T00:00:00Z'); // warm the cache
  fs.appendFileSync(t2, userTurn('2026-07-29T00:05:00.000Z', 'second message, appended later') + '\n');
  const r6 = resolver.resolveVerbatimRef(t2 + '#1', '2026-07-29T00:05:00Z');
  ok('resolveVerbatimRef: cache picks up a transcript that grew after the first read (mtime-keyed, never permanently stale)',
    r6.ok === true && r6.text === 'second message, appended later', JSON.stringify(r6));

  // ---- resolveVerbatimRef: same-second burst (a real production shape —
  // several real prompts captured inside one wall-clock second, since this
  // repo's own capture convention has 1-second resolution) disambiguates by
  // ordinal instead of silently collapsing every candidate onto entry 0 ----
  const t3 = path.join(tmp, 't3.jsonl');
  const sameSecond = '2026-07-30T19:57:33.000Z';
  fs.writeFileSync(t3, [
    userTurn(sameSecond, 'first burst message'),
    userTurn(sameSecond, 'second burst message'),
    userTurn(sameSecond, 'third burst message'),
  ].join('\n') + '\n');
  const rTie0 = resolver.resolveVerbatimRef(t3 + '#0', '2026-07-30T19:57:33Z');
  const rTie1 = resolver.resolveVerbatimRef(t3 + '#1', '2026-07-30T19:57:33Z');
  const rTie2 = resolver.resolveVerbatimRef(t3 + '#2', '2026-07-30T19:57:33Z');
  ok('resolveVerbatimRef: a same-second burst of 3 candidates resolves to 3 DISTINCT texts via ordinal tiebreak, not all collapsing onto entry 0',
    rTie0.ok && rTie1.ok && rTie2.ok &&
    rTie0.text === 'first burst message' && rTie1.text === 'second burst message' && rTie2.text === 'third burst message',
    JSON.stringify([rTie0, rTie1, rTie2]));

  // ---- classifyCandidate ----
  const c1 = resolver.classifyCandidate('connect to gh and download the latest copy of neural lace', 'thanks, looks good so far');
  ok('classifyCandidate: a short acknowledgement is noise', c1.classification === 'noise', JSON.stringify(c1));

  const c2 = resolver.classifyCandidate('connect to gh and download the latest copy of neural lace', 'ok');
  ok('classifyCandidate: a bare "ok" is noise', c2.classification === 'noise', JSON.stringify(c2));

  const c3 = resolver.classifyCandidate(
    'Please connect to gh and download the latest copy of Neural Lace.',
    'Give me the TLDR. Are you measuring active plans on this machine or across all?');
  ok('classifyCandidate: a substantively unrelated request is new-topic (near-zero lexical overlap)',
    c3.classification === 'new-topic', JSON.stringify(c3));

  const c4 = resolver.classifyCandidate(
    'Please fix the login page so the submit button actually submits the form',
    'also please make the submit button on the login page disabled while the form is submitting');
  ok('classifyCandidate: a request sharing substantive vocabulary with the parent is an amendment',
    c4.classification === 'amendment', JSON.stringify(c4));

  const c5 = resolver.classifyCandidate('anything', '');
  ok('classifyCandidate: empty candidate text is noise (never crashes on empty input)', c5.classification === 'noise');

  // ---- harness-reviewer Major 2 (2026-07-30): short context-dependent
  // follow-up QUESTIONS never get promoted, even with near-zero overlap —
  // PROVEN necessary against the real live registry (a plain overlap-only
  // decision promoted "Why don't I see it?", "Did this work?", "How would
  // you recommend proceeding?" into their own top-level asks) ----
  const parentText = 'Please connect to gh and download the latest copy of Neural Lace.';
  const c6 = resolver.classifyCandidate(parentText, 'Why don’t I see it?');
  ok('classifyCandidate: a short follow-up question is amendment, never promoted, despite zero vocabulary overlap',
    c6.classification === 'amendment', JSON.stringify(c6));
  const c7 = resolver.classifyCandidate(parentText, 'How would you recommend proceeding?');
  ok('classifyCandidate: another short follow-up question stays amendment (not promoted)',
    c7.classification === 'amendment', JSON.stringify(c7));
  const c8 = resolver.classifyCandidate(parentText, 'Did this work?');
  ok('classifyCandidate: a very short (single-substantive-token) follow-up question is noise — not promoted, not amendment',
    c8.classification === 'noise', JSON.stringify(c8));
  // Mutation control: a LONG question that carries its own substantial,
  // self-contained topic (>8 words) is UNCHANGED — still promoted. Length,
  // not "ends in a question mark", is what this fix keys on.
  const c9 = resolver.classifyCandidate(parentText,
    'Give me the TLDR. Are you measuring active plans on this machine or across all?');
  ok('classifyCandidate: mutation control — a LONG substantive question is still promoted (new-topic), this fix only intervenes on SHORT ones',
    c9.classification === 'new-topic', JSON.stringify(c9));
  // A short candidate with 2-3 substantive tokens and no question mark
  // stays 'amendment' too (below the promotion floor), not 'noise' and not
  // 'new-topic' — never silently dropped, just not minted as its own ask.
  const c10 = resolver.classifyCandidate(parentText, 'completely unrelated stuff');
  ok('classifyCandidate: a short (below the substantive-token floor) unrelated fragment is amendment, not promoted',
    c10.classification === 'amendment' && c10.overlap === 0, JSON.stringify(c10));

  // ---- CLI: resolve ----
  const cliResolve = JSON.parse(execFileSync(process.execPath, [path.join(__dirname, 'verbatim-resolver.js'), 'resolve', t1 + '#1', '2026-07-28T04:04:19Z']).toString());
  ok('CLI resolve: prints the same verdict as the in-process call', cliResolve.ok === true && cliResolve.text === 'How would you recommend proceeding?', JSON.stringify(cliResolve));

  // ---- CLI: classify (end-to-end against a synthetic registry file) ----
  const regFile = path.join(tmp, 'registry.jsonl');
  fs.writeFileSync(regFile, JSON.stringify({
    ask_id: 'ask-cli-classify', record_type: 'created', ts: '2026-07-28T04:00:00Z',
    summary: 'Please connect to gh and download the latest copy of Neural Lace.',
    verbatim_ref: t1 + '#0',
  }) + '\n');

  const cliClassifyNewTopic = JSON.parse(execFileSync(process.execPath, [
    path.join(__dirname, 'verbatim-resolver.js'), 'classify', regFile, 'ask-cli-classify', t1 + '#2', '2026-07-28T04:10:00Z',
  ]).toString());
  ok('CLI classify: end-to-end resolves the parent from the registry\'s created record, resolves the candidate, and classifies new-topic',
    cliClassifyNewTopic.ok === true && cliClassifyNewTopic.classification === 'new-topic' && cliClassifyNewTopic.parent_resolved === true,
    JSON.stringify(cliClassifyNewTopic));

  // ---- synthetic content (task-notification etc.) is ALWAYS noise, never
  // promoted — PROVEN necessary against the real live registry: 78 of 116
  // real amendment_candidate records on this machine resolved to exactly
  // this shape (background task notifications that fire UserPromptSubmit
  // but were never something the operator typed); without this guard they
  // would each get "promoted" into their own garbled top-level request. ----
  fs.appendFileSync(t1, userTurn('2026-07-28T04:20:00.000Z', '<task-notification>\n<task-id>abc123</task-id>\nsome background task finished\n</task-notification>') + '\n');
  const cliClassifySynthetic = JSON.parse(execFileSync(process.execPath, [
    path.join(__dirname, 'verbatim-resolver.js'), 'classify', regFile, 'ask-cli-classify', t1 + '#3', '2026-07-28T04:20:00Z',
  ]).toString());
  ok('CLI classify: a synthetic (task-notification) candidate is classified noise unconditionally, never promoted into its own request',
    cliClassifySynthetic.ok === true && cliClassifySynthetic.classification === 'noise',
    JSON.stringify(cliClassifySynthetic));

  let cliClassifyMissingCandidateFailed = false;
  try {
    execFileSync(process.execPath, [
      path.join(__dirname, 'verbatim-resolver.js'), 'classify', regFile, 'ask-cli-classify', path.join(tmp, 'nope.jsonl') + '#0', '2026-07-28T04:00:00Z',
    ]);
  } catch (e) {
    cliClassifyMissingCandidateFailed = true;
  }
  ok('CLI classify: an unresolvable candidate exits non-zero (caller must leave the candidate pending, honest degrade)', cliClassifyMissingCandidateFailed);

  try { fs.rmSync(tmp, { recursive: true, force: true }); } catch (_) { /* best-effort cleanup */ }

  console.log('\nverbatim-resolver self-test: ' + PASSED + ' passed, ' + FAILED + ' failed');
  process.exit(FAILED === 0 ? 0 : 1);
}

main();
