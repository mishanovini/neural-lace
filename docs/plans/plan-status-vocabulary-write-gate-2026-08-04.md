# Plan: Plan Status vocabulary — schema + write-time gate (Agent 3 slice)

Status: ACTIVE
Mode: code
Backlog items absorbed: none
tier: 2
rung: 0
architecture: coding-harness
frozen: false
prd-ref: n/a — harness-development
design-ref: n/a — small self-contained addition (one static enum-registry JSON file plus one check inside an existing, already-blocking hook); no architectural decision is being made that a design review would adjudicate.

## Goal

Close the gap behind the cockpit's "status unknown — plan parse failed (unrecognized
Status: ...)" chips: plan authors have been freelancing prose directly onto the `Status:`
header line (measured 2026-08-04: 30 files across this repo and a sibling repo on
this machine, e.g. "REFERENCE (spec appendix...)", "DEFERRED (operator 2026-07-30: ...)",
"NORMATIVE for Wave O builders (...)"), which the cockpit's plan parser cannot recognize.
This plan is Agent 3's slice of a coordinated multi-agent effort ("the class", operator
directive 2026-08-04): define the canonical 8-token enum as a schema file, and extend the
existing write-time plan-edit hook so a future plan write can no longer introduce a ninth
freelanced value. Migrating the 30 already-freelanced files and updating the cockpit's own
consumer-side recognized-token list are separate agents' slices, out of scope here.

## Scope

- IN: `adapters/claude-code/schemas/plan-status.schema.json` (the new enum registry);
  extending `adapters/claude-code/hooks/plan-edit-validator.sh`'s existing PreToolUse
  write-time gate with a Status-value validation check; the accompanying self-test
  scenarios; the `manifest.json` entry text describing the extended check.
- OUT: migrating the 30 already-freelanced plan files to the canonical tokens; updating
  `workstreams-ui/server/roadmap-routes.js`'s recognized-token list or
  `plan-lifecycle.sh`'s terminal-status handling; any change to `plan-reviewer.sh`.

## Tasks

- [x] 1. Add `adapters/claude-code/schemas/plan-status.schema.json`: the 8-token enum
      (DRAFT/PROPOSED/ACTIVE/COMPLETED/SUPERSEDED/DEFERRED/ABANDONED/REFERENCE) with a
      description, phase, cockpit-render label, and archival-lifecycle metadata per token,
      plus the optional `Status-note:` header contract for the prose that used to be glued
      onto `Status:` itself. Verification: mechanical — `jq empty` on the file plus the two
      jq access patterns named in the dispatch (`.statuses[].token`, the
      `triggers_archival` subset) both return the expected token lists.
- [x] 2. Extend `plan-edit-validator.sh` with `pev_validate_status_line`: blocks a `Status:`
      value not present in the schema's token list, and separately blocks any text left on
      the line after a valid token, printing a fix message with the exact `Status:` /
      `Status-note:` two-line rewrite. Wired into both the Edit and Write code paths
      (fresh-plan creation and existing-plan overwrite), grandfathered so a Status: line
      carried through UNCHANGED is never retroactively blocked, and fails open if the
      schema file is missing. Verification: full — 9 new self-test scenarios (valid/
      invalid/prose-laden tokens on both Edit and Write, both grandfather paths, the
      missing-schema fail-open path), full suite 36/36 passing (was 27/27), and all four
      new code paths mutation-tested by disabling each in isolation and confirming exactly
      the scenarios that should catch it flip red.

## Files to Modify/Create

- `adapters/claude-code/schemas/plan-status.schema.json` — new; the enum registry
- `adapters/claude-code/hooks/plan-edit-validator.sh` — extend with the Status-value
  write-time check + 9 new self-test scenarios (G1-G9); one pre-existing self-test
  fixture (F15) retargeted off the `Status:` line so it stays decoupled from the new
  check without losing its own original assertion
- `adapters/claude-code/manifest.json` — `plan-edit-validator` entry's `honest_status`
  text extended to name the new check

## Assumptions

- Assumes `jq` is present on the machine running the hook (already a hard dependency of
  this file — every existing check in it already shells out to `jq`), so reading the
  schema at check time costs one more small process spawn, not a new dependency class.
- Assumes the grandfather design (validate only a Status: value this specific edit/write
  actually introduces or changes, never one merely carried through unchanged) is the
  correct posture, matching this same hook file's own Check-19-adjacent precedent
  against retroactively blocking pre-existing plans on their next unrelated touch.

## Edge Cases

- A plan file with no `Status:` line at all: the new check never fires (nothing to
  validate), unchanged from before this plan.
- The schema file is missing or unreadable at check time: the check fails OPEN (never
  blocks a plan write because the harness's own schema file is absent) — covered by
  self-test scenario G9.
- An Edit whose old_string/new_string span happens to carry an unchanged legacy
  freelanced `Status:` line purely as surrounding context for an unrelated change: the
  check must not fire — covered by self-test scenario G6 (Edit) and G7 (Write).
- A token that is not in the enum AND also carries trailing text: the enum-membership
  finding fires (not the prose finding), since an unrecognized word is the more
  fundamental defect — covered by self-test scenario G5.

## Testing Strategy

`bash adapters/claude-code/hooks/plan-edit-validator.sh --self-test` — full suite must
report `36 passed, 0 failed`. Additionally, mutation-test the four new code paths (enum
check, prose-after-value check, both grandfather comparisons, the schema-read fail-open
guard) by disabling each in an isolated sandbox copy and confirming exactly the
self-test scenarios documented to depend on it flip to FAIL, and no others.

Walking Skeleton: n/a — a harness write-time gate has no end-user-facing runtime slice;
the self-test suite plus mutation testing IS the demonstration (constitution §4's
harness-maintainer clause).

## Definition of Done

- [x] `plan-edit-validator.sh --self-test` reports 36 passed, 0 failed.
- [x] `jq empty adapters/claude-code/schemas/plan-status.schema.json` succeeds and both
      documented jq access patterns return the expected token lists.
- [x] `adapters/claude-code/scripts/manifest-check.sh` reports GREEN.
