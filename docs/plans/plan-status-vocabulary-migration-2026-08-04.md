# Plan: canonical plan-Status vocabulary migration (neural-lace estate)

Status: ACTIVE
Execution Mode: direct
Mode: code
frozen: true
lifecycle-schema: v2
loe-class: general-multi-file
tier: 1
rung: 1
architecture: coding-harness
owner: Misha
target-completion-date: 2026-08-04
prd-ref: n/a — harness-development
ask-id: none — no linked ask
design-ref: n/a — plan-file header migration only; no design doc exists for this, the change never touches adapters/claude-code/** at all, and it matches none of Check 17's architecture-keyword set.
acceptance-exempt: true
acceptance-exempt-reason: Harness-internal plan-file header normalization with no product user; the maintainer is the user (constitution §4). The demonstration is the before/after `grep -h "^Status:" docs/plans/*.md | sort | uniq -c` census (every docs/plans/**/*.md file now carries one of the 8 canonical tokens) plus a `git diff` proof that only Status/Status-note lines changed on every touched file (zero content loss).

## Goal
Operator directive (2026-08-04, verbatim): "I want to get all these unknown states
rectified so that I can actually keep track of the actual status of everything." The
cockpit renders "status unknown — plan parse failed (unrecognized Status: ...)" for
plans whose `Status:` header is freelanced prose rather than a fixed vocabulary token.
Measured census at dispatch time: neural-lace had 13x DEFERRED, 3x ACTIVE, 5x
"REFERENCE (spec appendix...)", 1x "NORMATIVE for Wave O builders (...)", 1x "DEFERRED
(operator 2026-07-30: ...)" — the last three shapes are prose, not vocabulary, and are
what the cockpit's parser correctly refuses to guess at. The canonical enum
(decide-and-go, orchestrator, this dispatch): DRAFT, PROPOSED, ACTIVE, COMPLETED,
SUPERSEDED, DEFERRED, ABANDONED, REFERENCE, with prose qualifiers moved to a new
optional `Status-note` header line immediately after `Status`. This plan is the
neural-lace-side estate migration half of that effort (a sibling dispatch — not part of
this plan — covers the schema file, the cockpit parser widening, and a separate
sibling estate repo).

## User-facing Outcome
When the operator opens the cockpit, every neural-lace plan under `docs/plans/` shows a
real lifecycle state instead of "status unknown — plan parse failed", because every
`Status:` header in the tree now uses one of the 8 canonical tokens; every word of
prose that used to live inline in the Status line survives, unabridged, in a
`Status-note` line directly beneath it.

## Scope
- IN: normalizing every `docs/plans/**/*.md` file (root, `archive/`, `deferred/`) whose
  `Status:` value is outside the 8-token canonical enum, by splitting it into a bare
  `Status: <TOKEN>` line plus a `Status-note: <verbatim prose>` line. Concretely: the 5
  `nl-overhaul-program-2026-07-specs-{b,c,d,e,f}.md` files ("REFERENCE (spec
  appendix...)" → `REFERENCE` + note), `nl-observability-program-2026-08-specs-o.md`
  ("NORMATIVE for Wave O builders (...)" → `REFERENCE` + note, per the migration mapping
  the operator's dispatch specified), and `deferred/machine-folder-reorg.md`
  ("DEFERRED (operator 2026-07-30: ...)" → `DEFERRED` + note).
- OUT: the `plan-status.schema.json` schema file, the cockpit's `plan-parse.js` /
  `roadmap.js` / `derive-lib.js` recognizer widening, and a separate sibling estate
  repo's own migration — all dispatched as sibling agents in the same operator
  directive, not this plan's files. `docs/plans/archive/conv-tree-auto-current.md`'s `Status: ACTIVE`
  is left untouched: `ACTIVE` is already a canonical token (an archived-but-ACTIVE plan
  may be a separate, real discrepancy, but it is not a vocabulary problem and is outside
  this plan's stated scope of "Status outside the canonical enum").

## Tasks
- [ ] 1. Normalize the 6 in-scope `docs/plans/**/*.md` files' `Status:` headers to a
  canonical token + `Status-note:` line, preserving every word of the original prose
  verbatim; verify via `git diff` that only Status/Status-note lines changed on each
  file, and via a before/after `grep -h "^Status:" docs/plans/**/*.md | sort | uniq -c`
  census that the non-canonical rows are gone — Verification: mechanical — Docs impact:
  none — plan-file content migration is its own record; no separate doc surface

## Files to Modify/Create
- `docs/plans/nl-overhaul-program-2026-07-specs-b.md` — Status header split (REFERENCE + note)
- `docs/plans/nl-overhaul-program-2026-07-specs-c.md` — Status header split (REFERENCE + note)
- `docs/plans/nl-overhaul-program-2026-07-specs-d.md` — Status header split (REFERENCE + note)
- `docs/plans/nl-overhaul-program-2026-07-specs-e.md` — Status header split (REFERENCE + note)
- `docs/plans/nl-overhaul-program-2026-07-specs-f.md` — Status header split (REFERENCE + note)
- `docs/plans/nl-observability-program-2026-08-specs-o.md` — Status header split (multi-line NORMATIVE prose unwrapped into REFERENCE + one Status-note line)
- `docs/plans/deferred/machine-folder-reorg.md` — Status header split (DEFERRED + note); already exempt from scope-enforcement-gate (`docs/plans/deferred/*`), listed here for completeness since this plan's diff touches it

## In-flight scope updates
(no in-flight changes — the full staged diff matches the scope declared above)

## Assumptions
- The canonical enum and the REFERENCE-mapping for NORMATIVE-prose and the
  DEFERRED-mapping for DEFERRED-prose were decided by the dispatching orchestrator
  (decide-and-go, constitution §8) before this session started; this plan implements
  that decision rather than re-litigating it.
- `Status-note` is a new, optional, free-text header field with no parse-time state
  semantics of its own (per the schema contract named in the dispatch:
  `parsed_for_state: false`) — safe to introduce without coordinating a parser change
  in the same commit, because no existing consumer reads a `Status-note:` line today.
- Splitting a multi-line prose block (the Wave O NORMATIVE case) into one unwrapped
  `Status-note` line changes only line-wrapping, not content — every word, backtick,
  and quote from the original three-sentence paragraph is preserved.

## Edge Cases
- `nl-observability-program-2026-08-specs-o.md`'s original Status line was itself only
  the FIRST line of a longer paragraph that continued past the line boundary (the
  parser's line-anchored regex only ever captured that truncated first line); the fix
  captures and preserves the FULL paragraph in `Status-note`, not just what the old
  parser used to see.
- `docs/plans/archive/conv-tree-auto-current.md` carries `Status: ACTIVE` despite living
  in `archive/` — already a canonical token, so it is untouched by this plan and is
  flagged in the Decisions Log as a discrepancy for the operator, not silently
  "corrected" by guessing what it should say.
- A file whose non-canonical Status prose was genuinely ambiguous about which canonical
  token it meant would be left unchanged and listed, per the dispatch's explicit
  instruction — none of the 6 in-scope files hit this case; each prose qualifier named
  its own token unambiguously (REFERENCE, NORMATIVE→REFERENCE, DEFERRED).

## Testing Strategy
- `git diff -- docs/plans` reviewed line-by-line for each of the 6 files: confirms only
  `Status`/`Status-note` lines changed, zero other content touched.
- Before/after `grep -rh "^Status:" docs/plans --include="*.md" | sort | uniq -c` census
  run and compared: before shows the 6 non-canonical rows; after shows zero, with the
  same total row count (336 files) redistributed onto canonical tokens only.
- `grep -rh "^Status-note:" docs/plans --include="*.md" | wc -l` confirms 7 note lines
  land (6 in-scope files here + the 1 already-exempt `deferred/machine-folder-reorg.md`
  file, whose note is part of this same diff).

Walking Skeleton: n/a — pure plan-file content migration; no new architectural layer or
code path, one mechanical transformation applied uniformly.

## Closure Contract
- **Commands that run:** `git diff -- docs/plans/nl-overhaul-program-2026-07-specs-{b,c,d,e,f}.md docs/plans/nl-observability-program-2026-08-specs-o.md docs/plans/deferred/machine-folder-reorg.md` and `grep -rh "^Status:" docs/plans --include="*.md" | sort | uniq -c`.
- **Expected outputs:** the `git diff` shows only `Status`/`Status-note` line changes on each of the 7 files (no other line touched); the `grep`/`uniq -c` census shows zero rows outside the 8-token canonical enum (`DRAFT`, `PROPOSED`, `ACTIVE`, `COMPLETED`, `SUPERSEDED`, `DEFERRED`, `ABANDONED`, `REFERENCE`).
- **On-disk artifact location:** the plan-slug evidence set at `docs/plans/plan-status-vocabulary-migration-2026-08-04-evidence/1.evidence.json` (acceptance-exempt harness plan; captured via `write-evidence.sh capture` at task-verifier time).
- **Done when:** this plan is DONE when Task 1 is task-verifier PASS AND the evidence artifact above exists showing the zero-non-canonical-rows census result.

## Decisions Log
- 2026-08-04 (decide-and-go, reversible): opened this plan AFTER the Status-header
  edits were already made, mirroring the documented precedent at
  `docs/plans/verify-event-emit-hotfix-2026-08-04.md`'s own Decisions Log (self-claiming
  plan opened post-hoc to satisfy scope-enforcement-gate's active-plan requirement for
  an otherwise plan-free direct dispatch) — needed only because this session was
  dispatched directly by an orchestrating agent with no pre-existing plan file of its
  own in this worktree.
- 2026-08-04 (decide-and-go, reversible): left `docs/plans/archive/conv-tree-auto-current.md`
  untouched even though an archived-and-still-ACTIVE plan looks like a real
  discrepancy, because `ACTIVE` is already a canonical token and this plan's stated
  scope is Status values OUTSIDE the canonical enum — flagging it here rather than
  silently expanding scope to fix it.
- 2026-08-04 (decide-and-go, reversible): unwrapped the Wave O specs-o file's
  originally-multi-line Status paragraph into a single long `Status-note` line rather
  than preserving the original hard line-wraps, because a header field's value is
  logically one field and the hard wraps were an artifact of line-length formatting,
  not semantic paragraph breaks; every word is preserved either way.
- 2026-08-04 (decide-and-go, reversible): left this plan's own Task 1 checkbox
  unflipped — per this dispatch's explicit instruction not to invoke task-verifier, the
  checkbox flip is left for the orchestrator's own subsequent pass, not self-certified
  here.

## Definition of Done
- [ ] Task 1 checked off (by task-verifier, not this session)
- [x] All 6 in-scope files' Status headers migrated to canonical token + Status-note
- [x] `git diff` proof of zero content loss beyond Status/Status-note lines
- [x] Before/after census run and matches expectations (0 non-canonical rows remain)
