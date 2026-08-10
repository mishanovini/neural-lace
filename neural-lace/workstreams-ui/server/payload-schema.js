'use strict';
// payload-schema.js — the machine-checked ask-tree payload contract
// (ask-rooted-workstreams-p1, Task 11: "Server read surface").
//
// ============================================================
// WHY THIS EXISTS
// ============================================================
//
// Hard constraint 1 (anti-noise law): no gate/hook identifier may EVER reach
// the landing payload or render on the landing surface. Hard constraint 2
// (absolute links, always): every href/path the surface renders is absolute;
// a relative href silently breaks once the surface is opened from anywhere
// other than the exact directory a relative path assumed.
//
// This module is the MECHANICAL enforcement of both laws for the two
// ask-rooted-workstreams payloads server.js serves
// (`GET /api/asks` / `GET /api/ask/<id>`). It runs in TWO places:
//   1. server.selftest.js — asserting the negative fixtures (a payload with
//      a gate/hook identifier field, a payload with a relative href) FAIL.
//   2. server.js itself, at serve time (not just in tests) — a landing
//      payload that fails validation renders {ok:false, error:...} with a
//      diagnostics detail, never a leaking payload (Systems Analysis §3:
//      "validation failure = 500 with diagnostics detail, not a leaking
//      payload" — see server.js's route handlers).
//
// ============================================================
// THE ALLOWLIST (plan Task 11: "an ALLOWLIST of fields")
// ============================================================
//
// Rather than a full JSON-Schema type engine, this is a flat, exhaustive SET
// of every field name that is PERMITTED to appear anywhere in a given
// payload's object keys (LANDING_ALLOWED_KEYS / DETAIL_ALLOWED_KEYS below).
// Any object key encountered during a recursive walk that is NOT in the
// relevant set fails validation — this is what "an ALLOWLIST of fields"
// means operationally: a future field silently added to server.js's payload
// builder (e.g. a raw `emitter` or `type` sneaking back in) fails THIS
// check the moment server.selftest.js runs, rather than leaking to the UI
// unnoticed.
//
// Separately (and orthogonally to field NAMES), every STRING VALUE anywhere
// in the payload is scanned against GATE_HOOK_DENYLIST_PATTERNS (constraint
// 1) and every value under an HREF_KEYS field name is checked for
// absoluteness (constraint 2). The two checks are independent: a field can
// have an allowed NAME but a disallowed VALUE (e.g. `summary` legitimately
// exists, but a summary string that happens to quote a hook filename still
// fails the denylist scan) or vice versa.
//
// ============================================================
// THE "NO NEW LINK HANDLING" EXCEPTION (ux-review amendment 6)
// ============================================================
//
// Plan drill-down links resolve through the EXISTING /api/doc + /api/doc/open
// (query params `?project=<name>&path=<repo-relative-path>`) rather than a
// literal absolute href — that IS the established pattern this app's docs
// browser already uses (see config/projects.js's resolveDoc + web/app.js's
// openDoc). A `plan_doc: {project, path}` object is therefore EXEMPT from
// the absolute-href check by design (`path` there is a project-relative
// resolver argument, not a rendered href) — the exemption is scoped to
// EXACTLY that shape (an object literally named `plan_doc` with `project`
// and `path` string members), not a blanket carve-out for any field named
// `path`.

// ----------------------------------------------------------------------
// GATE_HOOK_DENYLIST_PATTERNS — constraint 1. Deliberately broad and
// case-insensitive: every field this app renders is either operator prose
// (a `summary`, a §3 block's `body`) or a plain data value (an id, a
// timestamp, a status word, an absolute path to a *.md/*.jsonl file) — NONE
// of which should ever need to mention a shell script filename, an
// internal oracle function, a hook lifecycle name, or a known mechanism's
// emitter token. See the plan's Hard constraint 1 + Testing Strategy
// ("gate identifier in STATE COPY -> FAIL").
// ----------------------------------------------------------------------
const GATE_HOOK_DENYLIST_PATTERNS = [
  /\.sh\b/i, // any shell script filename (plan-lifecycle.sh, needs-you.sh, ...)
  /\bod_[a-z0-9_]+\b/i, // oracle function names (od_harness_health, od_needs_me, ...)
  /[a-z0-9_-]*-gate\b/i, // gate script/identifier suffix (work-integrity-gate, ...)
  /\b(pretooluse|posttooluse|sessionstart|userpromptsubmit)\b/i, // hook lifecycle names
  // Known mechanism/emitter tokens. Deliberately EXCLUDES "needs-you" as a
  // bare token: the plan's own §3-defect-form contract requires this module
  // to carry an absolute link to the literal "NEEDS-YOU.md" ledger FILE
  // (raw_link) — that filename is the canonical operator-facing artifact
  // (the constitution §2 ledger), not the "needs-you.sh" mechanism; the
  // generic `\.sh\b` pattern above already denies the actual script name.
  /\b(plan-lifecycle|workstreams-emit|workstreams-read|session-start-digest|post-commit|close-plan|ask-registry|dispatch-provenance|plan-auto-closure|plan-edit-validator)\b/i,
];

function containsDenylistedIdentifier(value) {
  if (typeof value !== 'string' || !value) return null;
  for (let i = 0; i < GATE_HOOK_DENYLIST_PATTERNS.length; i++) {
    if (GATE_HOOK_DENYLIST_PATTERNS[i].test(value)) {
      return GATE_HOOK_DENYLIST_PATTERNS[i].toString();
    }
  }
  return null;
}

// ----------------------------------------------------------------------
// HREF_KEYS — field names whose (non-empty) values MUST be absolute
// (constraint 2). `path` is deliberately EXCLUDED here — it is only ever
// rendered inside the exempt `plan_doc {project, path}` shape (see header).
// ----------------------------------------------------------------------
const HREF_KEYS = new Set(['evidence_link', 'raw_link']);

// ----------------------------------------------------------------------
// DENYLIST_EXEMPT_KEYS — cockpit-v2-push-materialized-store Task 6: a
// KNOWING, DELIBERATE widening of the anti-noise constraint (hard
// constraint 1), scoped to EXACTLY this one field name.
//
// WHY THIS EXISTS: `description` carries verbatim PLAN-CONTENT prose (a
// plan's own task text / scope text, quoted for display) — and plan
// content in THIS repo routinely and legitimately names the very
// mechanisms GATE_HOOK_DENYLIST_PATTERNS exists to keep OUT of rendered
// UI copy (e.g. a task literally titled "fix the plan-lifecycle.sh
// PostToolUse matcher", or scope prose mentioning "posttooluse"). Running
// the denylist scan against `description` would make it impossible to
// ever render this plan's own task list without a false-positive
// validation failure — the scan is right to exist for operator-authored
// STATUS/narrative copy (summary, narrative_excerpt), but plan content
// text is a different animal: it is expected to name scripts/hooks/gates
// because that IS the subject matter.
//
// The length cap below is the compensating constraint: since the
// denylist can no longer bound this field's content, a cap on RAW SIZE
// still bounds how much arbitrary text can ride through the payload
// under this carve-out (over-cap is a validation ERROR, never a silent
// truncation — truncating would just hide the size problem from the
// caller instead of surfacing it).
// ----------------------------------------------------------------------
// cross-machine-plan-inventory (2026-08-06) adds TWO more, for the same
// reason and with the same length cap:
//
// `plan_slug` — a plan slug is a FILENAME STEM, i.e. the plan's identity,
// not rendered status copy. Plan filenames in this repo routinely and
// legitimately name the mechanisms they are about, so the denylist fires on
// ordinary, correct slugs: measured on this machine, 4 of 29 discovered
// plans trip it purely on `-gate` (e.g. "review-gate-identity-anchor-
// 2026-07-30"). Before this round only a couple of plans reached the
// landing payload, so the collision was rare enough to look like noise; the
// shared disk-scan inventory now ships every eligible plan, which would
// make an unrecoverable /api/asks 500 the STEADY STATE for every machine
// with a peer. Note this widens nothing the operator cannot already see:
// GET /api/roadmap renders these very slugs and is not schema-validated at
// all (server.js validates only /api/asks and /api/ask/<id>).
//
// `plan_state_reason` — the NAMED reason a plan could not be read. It
// quotes the offending artifact verbatim (an unrecognized `Status:` value,
// a resolver path), which is the whole point of naming the absence; running
// the identifier scan over it would force this module to choose between an
// honest reason string and a servable payload.
//
// `path` — the same argument as `plan_slug`, one level down. `path` appears
// ONLY inside the {project, path} doc-ref shape (plan_doc, doc_ref,
// link_refs, verbatim_doc_ref, evidence_doc_ref), where it is a filesystem
// LOCATOR the operator clicks through to — not status copy. It is a
// derived filename, so it inherits every identifier its file name contains:
// "docs/plans/review-gate-identity-anchor-2026-07-30.md" trips the `-gate`
// pattern purely because the plan it points at is about a gate. Note the
// module header already carves `path` out of HREF_KEYS for exactly this
// "it is a resolver argument, not rendered prose" reason; this is the same
// carve-out against the other of the two orthogonal scans.
const DENYLIST_EXEMPT_KEYS = new Set(['description', 'plan_slug', 'plan_state_reason', 'path']);
const DENYLIST_EXEMPT_MAX_LEN = 2000;

// ----------------------------------------------------------------------
// DENYLIST_EXEMPT_PATHS — an exemption scoped by POSITION, not by key name
// (cross-machine-plan-inventory remediation, 2026-08-06).
//
// THE OUTAGE THIS FIXES. `/api/asks` returned 500 on this machine's real
// data with:
//   gate/hook identifier leaked at $.groups[8].asks[0].summary
//   (matched /\.sh\b/i): "Fix divergence between node and jq implementations
//   of claim-honesty check in harness-doctor.sh self-test."
// and `/api/ask/ask-auto-0833ef2dd72e6eca` returned 500 on the SAME string
// at `$.summary`. Both endpoints were dead; the landing view was blank.
//
// WHY A NEW MECHANISM RATHER THAN `DENYLIST_EXEMPT_KEYS.add('summary')`.
// The key `summary` carries TWO DIFFERENT THINGS in these payloads:
//   1. `$.groups[].asks[].summary` / `$.completed.asks[].summary` /
//      `$.summary` — the ASK'S OWN TITLE (server.js's buildAskCard and
//      buildAskDetailPayload, both `reg.summary` off the folded ask
//      registry). This is the NAME OF A UNIT OF WORK.
//   2. `$.narrative[].summary` — a per-EVENT narrative line
//      (server.js:1100, `narrativeSummary(e)`), machine-composed status
//      copy about what a mechanism did. This is exactly the noise the
//      anti-noise law exists to keep off the surface, and it is already
//      locked by a negative fixture (S70b).
// A key-scoped exemption cannot tell them apart — adding 'summary' to
// DENYLIST_EXEMPT_KEYS would silently un-guard the narrative channel too.
// The walk already builds a JSON path; keying the exemption off that path
// (with array indices normalized to `[]`) separates the two roles exactly.
//
// WHY THE ASK TITLE IS THE `plan_slug` ARGUMENT, ONE LEVEL UP. An ask title
// is the ask's IDENTITY — the operator's (or the distiller's) name for a
// unit of work — in a repo whose work is largely ABOUT harness mechanisms.
// Naming the subject is the whole job of a title, so every one of the five
// denylist patterns can appear in a correct one: `.sh` (measured: 1 of 106
// real ask summaries on this machine today), `-gate` (the branch already
// had to exempt `plan_slug` for this, 4 of 29 plans), a hook lifecycle
// name, an `od_*` oracle, a mechanism token like `close-plan`. This is the
// SAME class the `plan_slug` block above documents, and the same class the
// header's "needs-you" carve-out documents: when a pattern collides with a
// legitimate operator-facing NAME, the name wins and the pattern is scoped
// away from it — the pattern itself is never weakened.
//
// WHY NOT NARROW `/\.sh\b/i` INSTEAD. There is no lexical difference
// between a leak ("blocked by workstreams-state-gate.sh") and a legitimate
// title ("fix harness-doctor.sh self-test") — the discriminator is the
// FIELD'S ROLE, not the string. Any narrowing that lets the title through
// also lets the leak through, in EVERY field, which is disabling the
// pattern with extra steps. Scoping by role costs one field and keeps the
// pattern at full strength everywhere else.
//
// WHAT THE DENYLIST STILL CATCHES AFTER THIS CHANGE. All five patterns
// still run, unmodified, against every string in both payloads except the
// four DENYLIST_EXEMPT_KEYS and the three paths below. On the real landing
// payload measured here that is 3,300+ string values across 29 key names,
// including every machine-composed status field the anti-noise law was
// written for: `narrative_excerpt` (the ask card's progress line —
// negative fixtures S27a/S51/S71e), `$.narrative[].summary` (the event
// narrative — S70b/S71d), `message` and `divergence_class` and
// `detail_ref` (drift badges), `state_label`, `provenance_label`, `label`,
// `people_map_error`, `status`, `error`, `person`, `role`, `state`,
// `discovery`, `plan_state`, `projects_config`, `source`, `branch`,
// `host`, `repo`, `project`. Only the ask TITLE moved.
//
// The DENYLIST_EXEMPT_MAX_LEN cap applies here for the same compensating
// reason it applies to `description`: the denylist no longer bounds this
// field's content, so raw size still does.
// ----------------------------------------------------------------------
const DENYLIST_EXEMPT_PATHS = new Set([
  '$.groups[].asks[].summary',  // landing: an ask CARD title (buildAskCard)
  '$.completed.asks[].summary', // landing: a completed ask card title (same builder)
  '$.summary',                  // detail: the ask's own title (buildAskDetailPayload)
]);

// Cheap pre-filter: only these key names can EVER be path-exempt, so the
// path normalization below runs for a handful of values rather than for
// every string in a ~200 KB payload.
const PATH_EXEMPT_CANDIDATE_KEYS = new Set(['summary']);

function normalizeWalkPath(pathLabel) {
  return pathLabel.replace(/\[\d+\]/g, '[]');
}

function isDenylistExemptPath(key, pathLabel) {
  if (!PATH_EXEMPT_CANDIDATE_KEYS.has(key)) return false;
  return DENYLIST_EXEMPT_PATHS.has(normalizeWalkPath(pathLabel));
}

function isAbsoluteHref(value) {
  if (typeof value !== 'string' || value === '') return true; // empty is a legitimate "no link yet"
  if (/^https?:\/\//i.test(value)) return true;
  if (/^file:\/\//i.test(value)) return true;
  if (/^[A-Za-z]:[\\/]/.test(value)) return true; // Windows drive-letter absolute (C:\... or C:/...)
  if (/^\\\\/.test(value)) return true; // UNC path (\\host\share\...)
  if (/^\//.test(value)) return true; // POSIX absolute
  return false;
}

// ----------------------------------------------------------------------
// LANDING_ALLOWED_KEYS / DETAIL_ALLOWED_KEYS — the two payload allowlists.
// Kept in sync with exactly what server.js's buildAsksLandingPayload /
// buildAskDetailPayload emit; server.selftest.js's negative fixtures prove
// an UNLISTED field fails.
// ----------------------------------------------------------------------
const LANDING_ALLOWED_KEYS = new Set([
  'ok', 'error', 'status_filter', 'generated_at',
  'groups', 'project', 'asks',
  'completed', 'count', 'newest_completed_ts',
  // card fields
  'ask_id', 'summary', 'repo', 'status', 'activity_ts',
  'plan_progress', 'done', 'in_flight', 'not_started', 'total',
  'waiting_count', 'drift_badges', 'narrative_excerpt',
  // drift-badge fields (Task 12 — background auditor). `divergence_class` is
  // a short, prose-safe label (never a raw event `type`/hook/script name);
  // `detail_ref` is an opaque, stable id for the future click-through
  // (Task 13); `plan_slug`/`task_id` name which row a badge belongs to;
  // `message` is plain operator prose; `de_emphasize` flags a
  // provenance:unknown event per constraint 10 (never rendered as
  // mechanism truth).
  'divergence_class', 'detail_ref', 'de_emphasize', 'message', 'plan_slug', 'task_id',
  // ----------------------------------------------------------------------
  // Peer-view fields (cockpit-v2-push-materialized-store Task 4) — the
  // "Peers" section on GET /api/asks (server.js's buildPeersBlock ->
  // peer-view.js#computePeerView). `plan_doc`/`tasks`/`id`/`session_id`/
  // `role`/`state` are REUSED from the existing DETAIL vocabulary (same
  // meaning as there — a plan-doc {project,path} ref, a task row, a
  // session row, a session/peer state word — now also legal on the
  // LANDING payload); everything else here is new to this task. `plan_doc`
  // stays exempt from the absolute-href check via the SAME "no new link
  // handling" mechanism documented above (HREF_KEYS never lists it).
  'peers', 'has_data', 'my_coord_refresh', 'entries', 'host', 'state',
  'state_label', 'age_minutes', 'received_at', 'branch', 'dirty', 'head_sha',
  'unmerged', 'plans', 'plan_doc', 'tasks', 'id', 'provenance_label',
  'sessions', 'session_id', 'role', 'last_heartbeat_at', 'label',
  'last_refreshed_at', 'source',
  // ----------------------------------------------------------------------
  // `path` — THE MISSING KEY (fixed 2026-08-06, cross-machine-plan-
  // inventory). `plan_doc` has been on this list since the peer block
  // shipped, but its own `{project, path}` members were never added, and
  // `project` only validated by coincidence (it is on the list already, as
  // a GROUP field). So the moment ANY peer exported a populated plan_doc,
  // the recursive walk hit `$.peers.entries[i].plans[j].plan_doc.path`,
  // reported "unknown field (not in allowlist)", and server.js:1243 turned
  // that into a 500 on /api/asks — blanking the cockpit's entire landing
  // view, on every OTHER machine, as soon as one machine synced a real
  // plan record. This was already firing before this round's change
  // (reproduced against the live plan-export/ clone), and it is the reason
  // `path` is listed here rather than in some new block: the DETAIL
  // allowlist has carried `path` for exactly this shape all along.
  'path',
  // ----------------------------------------------------------------------
  // Shared plan-inventory fields (cross-machine-plan-inventory). The peer
  // plans block is now the disk-scan inventory, so each row additionally
  // carries whether it is archived, HOW it was discovered ('scan' vs
  // 'ask-link' — deliberately not named `source`, which already means
  // something unrelated above), and the NAMED read state.
  //
  // `plan_state` is the named-absence label ('parsed' | 'ineligible' |
  // 'unresolvable' | 'absent' | 'damaged' | 'legacy-unlabelled' |
  // 'unknown'); `tasks`/`plan_progress` are null for every value except
  // 'parsed', which is what keeps an unreadable plan from rendering as a
  // healthy 0/0. `unknown_rows` is the aggregate's count of rows it could
  // not read. `scan_coverage` names what this host actually scanned, so
  // the per-machine multi-repo difference (config/projects.json is
  // gitignored and machine-local) is a DECLARED state rather than
  // something the operator infers from a short list.
  'archived', 'discovery', 'plan_state', 'plan_state_reason', 'unknown_rows',
  'scan_coverage', 'repos', 'projects_config', 'completed_age_days',
  'stale_links_omitted',
  // ----------------------------------------------------------------------
  // Person-grouping fields (cockpit-roadmap-redesign Task 7, round 5) —
  // peer-view.js#computePeerView: `person` on each peer entry (a mapped
  // display name or the literal named state 'unassigned'), `persons` =
  // [{person, hosts:[...]}] group aggregation, `people_map_error` = the
  // NAMED failure string when config/people.json exists but is unreadable/
  // malformed ('' otherwise) — plain prose, subject to the denylist scan
  // like every other status string.
  'person', 'persons', 'hosts', 'people_map_error',
]);

const DETAIL_ALLOWED_KEYS = new Set([
  'ok', 'error',
  'ask_id', 'summary', 'project', 'repo', 'status', 'verbatim_ref',
  'plan_slugs',
  'narrative', 'ts', 'evidence_link',
  'plan_rows', 'plan_slug', 'plan_doc', 'path', 'tasks', 'id', 'done', 'in_flight',
  'waiting_items', 'needs_you_id', 'defect', 'message', 'title', 'body', 'links',
  'session_id', 'added', 'raw_link',
  // COCKPIT-DEAD-FILE-HREF-RESIDUAL-01 — the doc-ref siblings of the four
  // absolute-path fields asks.js renders (raw_link, links[], verbatim_ref,
  // evidence_link). Each is a {project, path} pair (or null) resolved by
  // deriveLib.projectDocRefFor, carrying NO new link handling: the client
  // drills through the EXISTING /api/doc + /api/doc/open resolver, exactly
  // as `plan_doc` already does. They stay OUT of HREF_KEYS for the same
  // reason plan_doc does — a {project, path} pair is not an href.
  'doc_ref', 'link_refs', 'verbatim_doc_ref', 'evidence_doc_ref',
  'artifacts', 'sha',
  // cross-machine-plan-inventory: computePlanRows now carries the NAMED
  // read state onto every plan row it emits (this payload's `plan_rows`),
  // and aggregatePlanProgress reports how many rows it could not read
  // instead of folding them in as zeros.
  'plan_state', 'plan_state_reason', 'unknown_rows',
  'sessions', 'role', 'state', 'resumed_from', 'task_id',
  'drift_badges',
  // drift-badge fields (Task 12) — see LANDING_ALLOWED_KEYS comment above.
  'divergence_class', 'detail_ref', 'de_emphasize',
  // cockpit-v2-push-materialized-store Task 6 — plan-content prose (a
  // task/scope excerpt quoted verbatim for display). See the
  // DENYLIST_EXEMPT_KEYS block above for why this field is ALSO exempt
  // from the gate/hook-identifier scan (by key, not by payload).
  'description',
]);

// ----------------------------------------------------------------------
// walk(node, allowedKeys, pathLabel, errors) — recursive allowlist +
// denylist + href walk. Objects: every own key must be in allowedKeys (else
// "unknown field" error) and every string value scanned for a denylisted
// identifier + (if the key is an HREF_KEY) absoluteness. Arrays/objects
// recurse; every other type is a no-op leaf.
// ----------------------------------------------------------------------
function walk(node, allowedKeys, pathLabel, errors) {
  if (node === null || node === undefined) return;
  if (Array.isArray(node)) {
    node.forEach((item, i) => walk(item, allowedKeys, pathLabel + '[' + i + ']', errors));
    return;
  }
  if (typeof node === 'object') {
    Object.keys(node).forEach((key) => {
      const here = pathLabel + '.' + key;
      if (!allowedKeys.has(key)) {
        errors.push('unknown field (not in allowlist): ' + here);
      }
      const val = node[key];
      if (typeof val === 'string') {
        // DENYLIST_EXEMPT_KEYS — by KEY, exactly the HREF_KEYS precedent
        // above: `description` skips the gate/hook-identifier scan (see the
        // block comment at DENYLIST_EXEMPT_KEYS's definition for why), but
        // is bounded instead by a raw length cap. Over-cap is a validation
        // ERROR (never a silent truncation — truncating would hide the
        // size problem rather than surface it).
        // DENYLIST_EXEMPT_PATHS is the SAME carve-out scoped by POSITION
        // instead of by key name — see its definition for why the ask
        // TITLE (`$.groups[].asks[].summary`, `$.summary`) needs it while
        // the identically-named event line (`$.narrative[].summary`) must
        // stay scanned. Both routes land in the same length-capped branch.
        if (DENYLIST_EXEMPT_KEYS.has(key) || isDenylistExemptPath(key, here)) {
          if (val.length > DENYLIST_EXEMPT_MAX_LEN) {
            errors.push('exempt field exceeds max length (' + DENYLIST_EXEMPT_MAX_LEN + ' chars) at ' + here + ': ' + val.length + ' chars');
          }
        } else {
          const hit = containsDenylistedIdentifier(val);
          if (hit) errors.push('gate/hook identifier leaked at ' + here + ' (matched ' + hit + '): ' + JSON.stringify(val).slice(0, 120));
        }
        if (HREF_KEYS.has(key) && !isAbsoluteHref(val)) {
          errors.push('relative href at ' + here + ' (must be absolute): ' + JSON.stringify(val));
        }
      } else {
        walk(val, allowedKeys, here, errors);
      }
    });
    return;
  }
  // primitives (number/boolean) — nothing to check.
}

function validateLanding(payload) {
  const errors = [];
  walk(payload, LANDING_ALLOWED_KEYS, '$', errors);
  return { ok: errors.length === 0, errors: errors };
}

function validateAskDetail(payload) {
  const errors = [];
  walk(payload, DETAIL_ALLOWED_KEYS, '$', errors);
  return { ok: errors.length === 0, errors: errors };
}

module.exports = {
  validateLanding,
  validateAskDetail,
  containsDenylistedIdentifier,
  isAbsoluteHref,
  LANDING_ALLOWED_KEYS,
  DETAIL_ALLOWED_KEYS,
  HREF_KEYS,
  DENYLIST_EXEMPT_KEYS,
  DENYLIST_EXEMPT_MAX_LEN,
  DENYLIST_EXEMPT_PATHS,
};
