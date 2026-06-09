# Plan: Workstreams Phase C — self-contained items (no fragments / no turn-noise)
Status: ACTIVE
Execution Mode: orchestrator
Mode: code
Backlog items absorbed: none
acceptance-exempt: true
acceptance-exempt-reason: harness-internal work; the four --self-tests (schema 12/12, backfill 11/11, turn-emit 45/45, decision-context-gate 29/29) are the acceptance artifact — there is no product runtime to advocate for.
tier: 2
rung: 1
architecture: orchestration
frozen: true
prd-ref: n/a — harness-development

## Goal
Make every item the Workstreams UI surfaces SELF-CONTAINED for a cold reader.
Misha (2026-06-09): items showed "INCOMPLETE METADATA" / fragments like
"Turn 2229" or a garbled `\" decisions…` — useless. "Assume I will not look
at this until I've completely forgotten what we're doing. I need background to
trigger my memory and the info to make a decision." Every emitted item must
carry a BACKGROUND memory-trigger + the DECISION/QUESTION/ASK + OPTIONS +
RECOMMENDATION + LINKS where applicable.

## User-facing Outcome
The operator opens the Workstreams GUI cold and every item card shows a
Background paragraph (what this is, what we were doing, why it matters) plus the
actionable ask — no "Turn N" noise nodes, no mid-sentence fragments, no
"INCOMPLETE METADATA" fallback.

## Scope
- IN: the item `details` content schema; the deterministic every-turn writer's
  extraction (fragment rejection + self-contained details + no turn nodes); the
  fence-emit path's `details` assembly (shared assembler); a one-shot backfill
  of the canonical file's existing open items.
- OUT: the GUI renderer (already reads the rich `details` shape); the canonical
  state-path resolver (Phase A); orphan recovery (Phase B); any product code.

## Tasks
- [x] 1. Schema: ItemDetailsContentSchema + assembleItemDetails + fenceToDetails — Verification: mechanical
- [x] 2. workstreams-turn-emit.sh: fragment guard + root-node items + self-contained details + drop turn-noise — Verification: mechanical
- [x] 3. decision-context-gate.sh: emit details via shared fenceToDetails — Verification: mechanical
- [x] 4. backfill-phasec-background.js + apply to canonical file (37 items) — Verification: mechanical
- [x] 5. Sync both hooks to live ~/.claude/hooks (byte-identical) — Verification: mechanical

## Files to Modify/Create
- `neural-lace/workstreams-ui/state/decision-context-schema.js` — content-shape schema + assembler + self-test
- `neural-lace/workstreams-ui/state/decision-context-schema.d.ts` — type declarations for the new surface
- `adapters/claude-code/hooks/workstreams-turn-emit.sh` — the rewritten extraction (the heart)
- `adapters/claude-code/hooks/decision-context-gate.sh` — fence-path details via shared assembler
- `neural-lace/workstreams-ui/state/backfill-phasec-background.js` — one-shot canonical-file backfill

## In-flight scope updates
(no in-flight changes)

## Assumptions
- The GUI detail-pane (web/app.js) already renders `_category`/`background`/
  `about`/per-category fields/`options`/`recommendation`/`links`/`references`
  from the item-details-set payload (verified by reading app.js 826-1004).
- schema_version stays 1 — strengthening the interior content-shape of the
  opaque `details` payload of an existing event is additive (ADR-032 §1).

## Edge Cases
- Schema lib absent in the runtime checkout → turn-emit uses an inline fallback
  assembler applying the same contract (verified: produces full details).
- A turn whose message has no clean self-contained item → emit NOTHING (no
  empty/garbage card).
- Re-fire on the same message → idempotent (deterministic event_id).
- Historical garbage items (turn-noise/fragment) → backfill skips them honestly
  (cannot make a fragment self-contained); the rewrite prevents new ones.

## Acceptance Scenarios
n/a — acceptance-exempt (harness-internal; self-tests are the acceptance artifact).

## Out-of-scope scenarios
n/a

## Testing Strategy
Each artifact ships a `--self-test`. Acceptance = all green: schema 12/12,
backfill 11/11, turn-emit 45/45 (incl. fragment-rejected + real-decision-with-
full-content), decision-context-gate 29/29.

## Walking Skeleton
The thinnest end-to-end slice: a PAUSING-marker turn → turn-emit extracts ONE
clean item → assembleItemDetails builds background+question+_category+links →
item-details-set lands on the project root node (no turn node) → the GUI
detail-pane renders the self-contained card. Exercised by turn-emit ST1/ST12.

## Decisions Log
### Decision: items on the ROOT node, not a per-turn "Turn N" node
- **Tier:** 1
- **Status:** proceeded with recommendation
- **Chosen:** attach extracted items directly to the project/global root node
  (the shape decision-context-gate.sh already uses), removing the per-turn
  branch-opened entirely.
- **Reasoning:** the "Turn 2229" titles were the exact noise Misha named;
  items live ON a node (FR-2) and the root is the natural home.

### Decision: escaping-agnostic leading-char fragment guard
- **Tier:** 1
- **Status:** proceeded with recommendation
- **Chosen:** reject by leading char (backslash/quote/closing-punct/open-paren/
  fence/smart-quote/bare-path/single-token) rather than unescaping JSONL.
- **Alternatives:** unescape-then-inspect (fragile across shells — the embedded
  node program is single-quoted bash); lowercase-leading rejection (false
  negatives on legit asks like "need your call…").
- **Reasoning:** leading-char is robust across escaping and catches every
  garbage shape in the canonical file while keeping all real asks.

## Pre-Submission Audit
- S1 (Entry-Point Surfacing): swept — all 5 files cited in Tasks + Files-to-Modify.
- S2 (Existing-Code-Claim Verification): swept — app.js detail-field contract
  (826-1004), reducer item-details-set (329-333), schema EVENT_REQUIRED_FIELDS
  re-read against the live files.
- S3 (Cross-Section Consistency): swept — turn-emit + fence paths both routed
  through the one assembler; no contradiction.
- S4 (Numeric-Parameter Sweep): swept — 12-char min, 220/700-char caps consistent.
- S5 (Scope-vs-Analysis Check): swept — all "Add/Modify" verbs target the 5
  declared files; GUI/resolver explicitly OUT.

## Definition of Done
- [x] All tasks checked off
- [x] All four self-tests pass
- [x] Both hooks synced to live ~/.claude/hooks (byte-identical)
- [x] Canonical file backfilled (37 items) + pushed to workstreams-coordination
- [x] Completion report appended

## Completion Report

### 1. Implementation Summary
All five tasks shipped. Schema (assembler + content shape), the turn-emit
rewrite (the heart), the fence-path parity, and the canonical backfill all
landed. No backlog items absorbed.

### 2. Design Decisions & Plan Deviations
Two Tier-1 decisions (above): root-node items (no turn nodes) and the
escaping-agnostic fragment guard. No deviations from scope.

### 3. Known Issues & Gotchas
- 9 historical turn-noise/fragment items remain in the canonical file with NULL
  details — they cannot be made self-contained; the operator can prune them. The
  rewrite prevents creating new ones.
- The schema-lib content-shape additions land in the main checkout only when
  phaseC-content merges; until then live hooks use the inline fallback assembler
  (verified to produce identical full details).

### 4. Manual Steps Required
None. Hooks already synced to live; canonical file already pushed.

### 5. Testing Performed & Recommended
schema 12/12, backfill 11/11, turn-emit 45/45, decision-context-gate 29/29.
Before/after demonstrated: a fragment input emits nothing; a real decision emits
a full self-contained card (background + question + _category + links).

### 6. Cost Estimates
None — harness-internal; no new services or recurring cost.
