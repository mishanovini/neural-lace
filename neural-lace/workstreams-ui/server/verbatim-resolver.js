'use strict';
// verbatim-resolver.js — resolves an ask-registry `verbatim_ref` pointer
// (`<transcript-jsonl-path>#<ordinal>`) back to the operator's REAL prompt
// text, and provides a lightweight, deterministic amendment/noise/new-topic
// classifier for amendment candidates.
//
// ============================================================
// WHY THIS EXISTS (URGENT operator-facing defect, 2026-07-30)
// ============================================================
//
// The Requests tab was showing almost nothing: 114 of 117 real operator
// asks in the live registry were sitting as `amendment_candidate` records
// with `classification:"pending"`, `summary:""` and no raw text — all 114
// filed under ONE ask_id (the session's FIRST prompt), because
// `hooks/workstreams-read.sh`/`pl_ask_id_for_session` derives ask_id
// 1:1 from session_id for the session's whole lifetime (a long-running
// session never mints a second top-level ask on its own). Every
// subsequent, wildly-different operator request in that session was
// mechanically filed as a pending "amendment" of the FIRST ask, forever.
//
// Two further, INDEPENDENT bugs compounded this into total invisibility:
//   1. The async LLM classifier (ask-registry.sh's `_ar_classify_candidate_text`,
//      gated on ASK_SUMMARIZER=haiku, defaulted on since 2026-07-21/22) is
//      PROVEN dead in production: `env -u CLAUDECODE claude --model haiku -p
//      ...`, invoked from a hook running INSIDE an already-live Claude Code
//      session, does not fail fast — it HANGS until the 20s
//      `nl_run_bounded` bound kills it (reproduced directly: `timeout 25
//      env -u CLAUDECODE claude --model haiku -p "..." </dev/null` -> rc=124).
//      Zero of the 114 real candidates captured 2026-07-28..30 ever got a
//      `candidate_classified` record — the lane's own self-tests never
//      caught this because they always inject a FAKE `_AR_CLASSIFY_CMD`
//      instead of shelling out to the real `claude` binary.
//   2. Even where classification DID succeed, workstreams-ui's
//      requests-routes.js never read `candidate_classified` records at all
//      — it only ever looked at the (permanently "pending") birth
//      `amendment_candidate` record's own `classification` field. Fixed
//      alongside this module (see requests-routes.js's fold rewrite).
//
// This module is the deterministic replacement for the LLM classify path
// (no model call, no network, no hang risk — just text comparison) AND the
// read-time resolver the UI uses to show REAL text instead of the generic
// "possible amendment captured" placeholder. The registry itself
// deliberately never stores raw operator text (ask-registry.sh's own
// documented design: "transcript ref + minted candidate_id, NEVER the raw
// text — the registry stays small") — resolution happens ON READ (or,
// for the classifier, transiently in memory, never persisted) from the
// operator's own Claude Code session transcript.
//
// ============================================================
// RESOLUTION ALGORITHM
// ============================================================
//   1. Parse `<path>#<ordinal>` from the ref.
//   2. Read + parse the transcript JSONL (cached per path, keyed by
//      mtimeMs+size so a growing transcript is only re-read when it
//      actually grows — these files can be tens of MB on a long session).
//   3. Filter to "real operator prompt" entries: type==="user", NOT
//      isSidechain, message.role==="user", content is a non-empty string OR
//      an array whose blocks are only text/image (a tool_result block means
//      this is a synthetic tool-result echo, never something a human typed).
//   4. PRIMARY: nearest-by-timestamp match against the candidate's own
//      capture `ts` (within RESOLVE_TOLERANCE_SECONDS). Validated across the
//      114 real production records on this machine: consistently a 0-1s
//      delta. The ordinal in the ref is an in-session counter of CAPTURED
//      prompts, not a transcript line number, and drifts if any capture was
//      ever skipped; timestamp-nearest self-corrects per-record instead of
//      accumulating that drift.
//   5. FALLBACK: if no entry falls within tolerance, fall back to indexing
//      the filtered sequence by the ref's ordinal directly (0-indexed) —
//      degraded confidence, still better than nothing.
//   6. Failure (no transcript, unreadable, no entry either way) returns
//      {ok:false, reason}. NEVER fabricates text.

const fs = require('fs');

const RESOLVE_TOLERANCE_SECONDS = 10;

// ----------------------------------------------------------------------
// parseRef(ref) -> {path, ordinal} | null
// ----------------------------------------------------------------------
function parseRef(ref) {
  const s = String(ref || '');
  const hashIdx = s.lastIndexOf('#');
  if (hashIdx === -1) return null;
  const p = s.slice(0, hashIdx);
  const ordRaw = s.slice(hashIdx + 1);
  if (!p) return null;
  const ordinal = /^[0-9]+$/.test(ordRaw) ? parseInt(ordRaw, 10) : null;
  return { path: p, ordinal: ordinal };
}

// ----------------------------------------------------------------------
// isRealOperatorEntry(rec) -> the extracted text, or null if this transcript
// line is not something a human actually typed (tool-result echo, a
// sidechain/sub-agent turn, or a non-user role).
// ----------------------------------------------------------------------
function extractRealOperatorText(rec) {
  if (!rec || rec.type !== 'user') return null;
  if (rec.isSidechain) return null;
  const msg = rec.message || {};
  if (msg.role !== 'user') return null;
  const content = msg.content;
  if (typeof content === 'string') {
    return content.trim() ? content : null;
  }
  if (Array.isArray(content)) {
    const kinds = content.map((c) => c && c.type);
    if (kinds.indexOf('tool_result') !== -1) return null; // synthetic echo
    const texts = content
      .filter((c) => c && c.type === 'text' && typeof c.text === 'string')
      .map((c) => c.text);
    const joined = texts.join(' ').trim();
    return joined ? joined : null;
  }
  return null;
}

// Known harness-injected synthetic markers that appear as `type:"user"` /
// `role:"user"` transcript entries but were never typed by the operator via
// UserPromptSubmit (background task notifications, system reminders,
// compact-continuation summaries). Used only to TAG confidence, never to
// silently drop a resolved entry — "never silently drop" applies here too.
const SYNTHETIC_PREFIXES = [
  '<task-notification>',
  '<system-reminder>',
  '<local-command-stdout',
  'This session is being continued from a previous conversation',
];
function looksSynthetic(text) {
  const t = String(text || '').trimStart();
  return SYNTHETIC_PREFIXES.some((p) => t.indexOf(p) === 0);
}

// ----------------------------------------------------------------------
// Transcript cache — keyed by path, invalidated on mtimeMs+size change.
// ----------------------------------------------------------------------
const _cache = new Map();

function loadRealUserEntries(transcriptPath) {
  let stat;
  try { stat = fs.statSync(transcriptPath); } catch (_) { return null; }
  const key = transcriptPath;
  const cached = _cache.get(key);
  if (cached && cached.mtimeMs === stat.mtimeMs && cached.size === stat.size) {
    return cached.entries;
  }
  let raw;
  try { raw = fs.readFileSync(transcriptPath, 'utf8'); } catch (_) { return null; }
  const entries = [];
  const lines = raw.split('\n');
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i].trim();
    if (!line) continue;
    let rec;
    try { rec = JSON.parse(line); } catch (_) { continue; }
    const text = extractRealOperatorText(rec);
    if (text === null) continue;
    const ts = rec.timestamp ? Date.parse(rec.timestamp) : NaN;
    entries.push({ ts: ts, text: text, synthetic: looksSynthetic(text) });
  }
  entries.sort((a, b) => (a.ts || 0) - (b.ts || 0));
  _cache.set(key, { mtimeMs: stat.mtimeMs, size: stat.size, entries: entries });
  return entries;
}

// ----------------------------------------------------------------------
// resolveVerbatimRef(ref, captureTs) -> {ok, text, confidence, deltaSeconds,
// synthetic, reason}
//   confidence: 'nearest' (timestamp match within tolerance) | 'ordinal'
//   (fallback index lookup) | none when ok:false.
// ----------------------------------------------------------------------
function resolveVerbatimRef(ref, captureTs) {
  const parsed = parseRef(ref);
  if (!parsed) return { ok: false, reason: 'unparseable verbatim_ref' };
  const entries = loadRealUserEntries(parsed.path);
  if (!entries) return { ok: false, reason: 'transcript unreadable or missing' };
  if (!entries.length) return { ok: false, reason: 'transcript has no real operator entries' };

  const captureMs = captureTs ? Date.parse(captureTs) : NaN;
  if (!isNaN(captureMs)) {
    // Collect every entry tied for the smallest diff, not just the first
    // one seen — second-resolution timestamps (this repo's own capture
    // convention: `date -u '+%Y-%m-%dT%H:%M:%SZ'`) mean a fast burst of
    // several real prompts within the same wall-clock second is common
    // (proven: three synthetic captures inside one manual smoke-test all
    // landed on the identical second), and picking the first-found on a
    // tie would silently resolve every one of them to entry 0.
    let bestDiff = null;
    let tied = [];
    for (let i = 0; i < entries.length; i++) {
      const e = entries[i];
      if (!e.ts || isNaN(e.ts)) continue;
      const diff = Math.abs(e.ts - captureMs) / 1000;
      if (bestDiff === null || diff < bestDiff) {
        bestDiff = diff;
        tied = [{ entry: e, index: i }];
      } else if (diff === bestDiff) {
        tied.push({ entry: e, index: i });
      }
    }
    if (tied.length && bestDiff !== null && bestDiff <= RESOLVE_TOLERANCE_SECONDS) {
      let chosen = tied[0];
      if (tied.length > 1 && parsed.ordinal !== null) {
        const ordinalMatch = tied.find((t) => t.index === parsed.ordinal);
        if (ordinalMatch) chosen = ordinalMatch;
      }
      return { ok: true, text: chosen.entry.text, confidence: 'nearest', deltaSeconds: bestDiff, synthetic: chosen.entry.synthetic };
    }
  }

  if (parsed.ordinal !== null && parsed.ordinal >= 0 && parsed.ordinal < entries.length) {
    const e = entries[parsed.ordinal];
    return { ok: true, text: e.text, confidence: 'ordinal', deltaSeconds: null, synthetic: e.synthetic };
  }

  return { ok: false, reason: 'no transcript entry matched (timestamp out of tolerance and ordinal out of range)' };
}

// ============================================================
// DETERMINISTIC CLASSIFIER (replaces the proven-dead LLM lane)
// ============================================================
const STOPWORDS = new Set([
  'the', 'a', 'an', 'and', 'or', 'but', 'is', 'are', 'was', 'were', 'be',
  'been', 'being', 'to', 'of', 'in', 'on', 'for', 'with', 'that', 'this',
  'it', 'its', 'you', 'your', 'yours', 'i', 'me', 'my', 'we', 'our', 'do',
  'does', 'did', 'not', 'can', 'could', 'would', 'should', 'will', 'shall',
  'just', 'so', 'if', 'then', 'than', 'also', 'still', 'what', 'when',
  'where', 'who', 'how', 'why', 'which', 'there', 'here', 'have', 'has',
  'had', 'as', 'at', 'by', 'from', 'into', 'about', 'up', 'down', 'out',
  'over', 'again', 'more', 'most', 'some', 'any', 'all', 'both', 'each',
  'other', 'such', 'only', 'own', 'same', 'too', 'very', 'now', 'want',
  'need', 'like', 'get', 'got', 'one', 'let', 'lets', 'going',
]);

function tokenize(text) {
  return String(text || '')
    .toLowerCase()
    .replace(/[^a-z0-9\s]/g, ' ')
    .split(/\s+/)
    .filter(Boolean)
    .filter((tok) => tok.length > 2 && !STOPWORDS.has(tok));
}

// Short conversational continuations that are never a distinct request in
// their own right, regardless of token overlap with the parent — a curated,
// deliberately small list (false-negatives here just fall through to the
// normal overlap-based decision, which is the safe direction: "never
// silently drop" means a miss here still gets classified, just maybe as
// 'amendment' instead of 'noise').
const ACK_WHOLE_RE = /^(ok|okay|k|kk|yes|yep|yeah|no|nope|sure|great|good|nice|thanks?|thank you|got it|continue|go ahead|please continue|looks good|sounds good|great work|perfect|cool|makes sense|understood|noted|ack)[.!]?$/i;
// A short (<= 8 words) utterance that STARTS with a conversational
// acknowledgement is still just an ack ("thanks, looks good so far" /
// "ok go ahead and do that") — length-bounded so a genuinely substantive
// request that happens to open with "ok" ("ok here's the actual bug: ...")
// still falls through to the normal overlap-based decision below.
const ACK_STARTER_RE = /^(ok|okay|yes|yep|yeah|sure|thanks?|thank you|got it|great|nice|perfect|cool|sounds good|looks good)\b[,.!]?\s*/i;

function classifyCandidate(parentText, candidateText) {
  const trimmedCandidate = String(candidateText || '').trim();
  if (!trimmedCandidate) {
    return { classification: 'noise', overlap: null, reason: 'empty candidate text' };
  }
  const wordCount = trimmedCandidate.split(/\s+/).filter(Boolean).length;
  if (ACK_WHOLE_RE.test(trimmedCandidate) || (wordCount <= 8 && ACK_STARTER_RE.test(trimmedCandidate))) {
    return { classification: 'noise', overlap: null, reason: 'matches a short-acknowledgement pattern' };
  }
  const candTokens = new Set(tokenize(trimmedCandidate));
  if (candTokens.size <= 1) {
    return { classification: 'noise', overlap: null, reason: 'too few substantive tokens' };
  }
  // harness-reviewer Major 2 (2026-07-30): PROVEN against the real live
  // registry that a plain overlap-only decision promotes short, context-
  // dependent follow-up QUESTIONS ("Why don't I see it?", "Did this work?",
  // "How would you recommend proceeding?") into their own top-level asks —
  // a real request they are not; they are near-universally continuations of
  // whatever the operator and Claude were just discussing, referenced by
  // pronoun ("it"/"this"/"that") rather than shared vocabulary, so lexical
  // overlap with the parent's ORIGINAL text is a poor signal for them
  // specifically. Route short interrogatives to 'amendment' unconditionally
  // — never promoted, regardless of overlap — while a LONG question that
  // happens to end in "?" (e.g. "Give me the TLDR. Are you measuring active
  // plans on this machine or across all?") still gets the normal decision,
  // since length is exactly what distinguishes a quick contextual check-in
  // from a genuinely substantive, self-contained new request.
  const SHORT_QUESTION_MAX_WORDS = 8;
  const isShortQuestion = wordCount <= SHORT_QUESTION_MAX_WORDS && /\?\s*$/.test(trimmedCandidate);
  if (isShortQuestion) {
    return { classification: 'amendment', overlap: null, reason: 'short interrogative — treated as a contextual follow-up, never promoted regardless of vocabulary overlap' };
  }
  // Same rationale, token-count form: promoting a candidate into a real,
  // permanent, operator-visible top-level ask should require it to carry
  // enough of its OWN substance to stand alone — below this floor, default
  // to 'amendment' (extends the parent) rather than minting a new ask nobody
  // asked for out of a fragment.
  const MIN_SUBSTANTIVE_TOKENS_FOR_PROMOTION = 4;
  const parentTokens = new Set(tokenize(parentText));
  let intersect = 0;
  candTokens.forEach((t) => { if (parentTokens.has(t)) intersect++; });
  const union = new Set([].concat(Array.from(candTokens), Array.from(parentTokens))).size;
  const overlap = union > 0 ? intersect / union : 0;
  const NEW_TOPIC_THRESHOLD = 0.12;
  if (parentTokens.size > 0 && overlap < NEW_TOPIC_THRESHOLD && candTokens.size >= MIN_SUBSTANTIVE_TOKENS_FOR_PROMOTION) {
    return { classification: 'new-topic', overlap: overlap, reason: 'shares almost no vocabulary with the parent ask, and carries enough of its own substance to stand alone' };
  }
  return { classification: 'amendment', overlap: overlap, reason: 'shares substantive vocabulary with the parent ask, is too short to stand alone as its own request, or the parent has no resolvable text to compare against' };
}

module.exports = {
  parseRef,
  extractRealOperatorText,
  loadRealUserEntries,
  resolveVerbatimRef,
  tokenize,
  classifyCandidate,
  RESOLVE_TOLERANCE_SECONDS,
};

// ============================================================
// CLI — used by ask-registry.sh (bash) and the backfill script, which
// cannot cheaply do JSON/date parsing themselves. One writer (bash, via
// ask-registry.sh's _ar_append_record) still owns every registry mutation —
// this CLI only ever DECIDES, never writes.
//
//   node verbatim-resolver.js resolve <ref> <capture_ts>
//     -> {"ok":true,"text":"...","confidence":"nearest|ordinal","deltaSeconds":N}
//        or {"ok":false,"reason":"..."}
//
//   node verbatim-resolver.js classify <registry_file> <ask_id> <candidate_ref> <candidate_ts>
//     -> resolves the ask's OWN origin text (from its 'created' record's
//        verbatim_ref+ts, falling back to its stored `summary` when that
//        doesn't resolve) and the candidate's text, then classifies.
//        {"ok":true,"classification":"amendment|noise|new-topic",
//         "candidate_text":"...","parent_resolved":bool,"overlap":N|null}
//        or {"ok":false,"reason":"..."} (candidate text itself unresolvable
//        — caller should leave the candidate pending, an honest degrade).
// ============================================================
if (require.main === module) {
  const [, , cmd, ...rest] = process.argv;
  function out(obj, ok) {
    process.stdout.write(JSON.stringify(obj) + '\n');
    process.exit(ok ? 0 : 1);
  }
  try {
    if (cmd === 'resolve') {
      const [ref, ts] = rest;
      const r = resolveVerbatimRef(ref, ts);
      out(r, r.ok);
    } else if (cmd === 'classify') {
      const [registryFile, askId, candidateRef, candidateTs] = rest;
      const candResolved = resolveVerbatimRef(candidateRef, candidateTs);
      if (!candResolved.ok) {
        out({ ok: false, reason: 'candidate text unresolved: ' + candResolved.reason }, false);
      } else if (candResolved.synthetic) {
        // A harness-injected marker (background task notification, system
        // reminder, compact-continuation summary) that fired UserPromptSubmit
        // but was never something the operator typed — PROVEN common on this
        // machine (78 of 116 real amendment_candidate records in the live
        // registry resolved to exactly this shape). Never a genuine request:
        // classify noise unconditionally rather than running the normal
        // overlap decision, which would otherwise happily "promote" a
        // <task-notification> blob into its own garbled top-level ask.
        out({
          ok: true, classification: 'noise', overlap: null,
          reason: 'synthetic harness-injected content (task notification / system reminder / continuation summary), never a genuine operator prompt',
          candidate_text: candResolved.text, parent_resolved: false,
        }, true);
      } else {
        let parentText = '';
        let parentResolved = false;
        try {
          const raw = fs.readFileSync(registryFile, 'utf8');
          const lines = raw.split('\n').map((l) => l.trim()).filter(Boolean);
          let createdRec = null;
          for (let i = 0; i < lines.length; i++) {
            let rec;
            try { rec = JSON.parse(lines[i]); } catch (_) { continue; }
            if (rec && rec.ask_id === askId && rec.record_type === 'created') { createdRec = rec; break; }
          }
          if (createdRec) {
            if (createdRec.verbatim_ref) {
              const pr = resolveVerbatimRef(createdRec.verbatim_ref, createdRec.ts);
              if (pr.ok) { parentText = pr.text; parentResolved = true; }
            }
            if (!parentResolved && createdRec.summary) {
              parentText = createdRec.summary;
            }
          }
        } catch (_) { /* registry unreadable — classify against empty parent text */ }
        const verdict = classifyCandidate(parentText, candResolved.text);
        out({
          ok: true,
          classification: verdict.classification,
          overlap: verdict.overlap,
          reason: verdict.reason,
          candidate_text: candResolved.text,
          parent_resolved: parentResolved,
        }, true);
      }
    } else {
      out({ ok: false, reason: 'unknown command "' + cmd + '" (usage: resolve <ref> <ts> | classify <registry_file> <ask_id> <candidate_ref> <candidate_ts>)' }, false);
    }
  } catch (e) {
    out({ ok: false, reason: 'exception: ' + String(e && e.message || e) }, false);
  }
}
