# Plan: Anti-vaporware config-control policy — the inverse shape (HARNESS-GAP-57)
Status: ACTIVE
Execution Mode: direct
Mode: code
Backlog items absorbed: none
acceptance-exempt: true
acceptance-exempt-reason: Harness-internal mechanism with no product user; the maintainer is the user (constitution §4). The `--self-test` suite (7/7 scenarios, both `/bin/bash` 3.2.57 and `/opt/homebrew/bin/bash` 5.3.15) plus a live mutation transcript (delete an allowlist entry → suite fails; restore → suite passes, both interpreters) IS the demonstration.
tier: 1
rung: 1
architecture: coding-harness
frozen: true
lifecycle-schema: v2
owner: Misha
target-completion-date: 2026-07-29
prd-ref: n/a — harness-development
ask-id: none — no linked ask

## Goal
Generalize the anti-vaporware "decorative config control" policy (HARNESS-GAP-45,
closed 2026-07-13 via `docs/plans/archive/vaporware-config-controls.md`) to its
INVERSE shape. GAP-45's enforcement — the registry-vs-callsite invariant,
functionality-verifier's config-control protocol, functionality-auditor's
registry-vs-callsite sweep — checks one direction only: does a registry entry
(a permission ID, a feature flag with a UI) have an enforce-mode CONSUMER. It
structurally assumes the producer side is guaranteed, because a UI toggle's
producer is the user clicking it.

Non-UI config levers (env vars, CLI overrides, caller-set fields read deep in
library code) have no such guarantee. `NL_PROTECTED_ORCHESTRATOR`, documented
in `hooks/lib/admission-lib.sh` as the tag a "protected downstream
orchestrator" must set, was discovered (accountable-estate T7, task-verifier
pass 4, D-4, 2026-07-29) to have ZERO producers anywhere in the repo — all 888
live ledger rows carry `protected:0`. It IS consumed (real read site, real
branch); nothing ever sets it. Neither GAP-45's registry sweep (no
registry+UI surface here) nor its config-control protocol (no `Verification:
full` task ever claimed this flag governs behavior) would have caught this —
a task-verifier pass caught it only by reading the comment narratively. This
plan makes that catch mechanical and repeatable.

## User-facing Outcome
n/a — harness-internal: the maintainer is the user. The demonstration is (a)
`scripts/config-control-producer-scan.sh --self-test` returning 7/7 PASS under
both bash interpreters, including a live-repo scenario asserting zero FLAGGED
levers against the real `hooks/`+`scripts/` trees today, and (b) a mutation
transcript proving the check actually discriminates (delete an allowlist
entry → RED; restore it → GREEN, both interpreters).

## Scope
- IN: a new standing, self-testing scan (`scripts/config-control-producer-scan.sh`)
  classifying every consumed `NL_*`-prefixed lever as PRODUCED / MARKED /
  ALLOWLISTED / FLAGGED; the allowlist file (`config/config-control-allowlist.txt`)
  documenting the 7 pre-existing legitimate operator-shell/self-test-only
  overrides found during construction; fixtures for the self-test; doctrine
  generalization (`doctrine/vaporware-prevention.md` compact clause +
  `doctrine/vaporware-prevention-full.md` "inverse shape" section); FM-038
  generalization bullet; a `manifest.json` entry carrying the full
  constitution §10 fields (golden scenario / FP expectation / retirement
  condition, per ADR 059 D4's new-gate-evidence-bar since `added_after` is
  2026-07); `doctrine/INDEX.md` regeneration; the `docs/backlog.md`
  HARNESS-GAP-57 row.
- OUT: wiring the scan into any blocking PreToolUse hook, pre-commit chain, or
  CI workflow (ships as a standing/manual/CI-invocable check first, per D-2 in
  the archived GAP-45 plan — prove the false-positive rate in practice before
  wiring a block; filed as a follow-up in the backlog row); generalizing
  beyond the `NL_*` naming convention (this repo's one established prefix for
  its own config levers; a different prefix convention would need its own
  audit pass); retrofitting inline honest-status comments into the 7
  allowlisted vars' own consuming files (two of those files —
  `scripts/selftest-sweep-exclusions.sh` and others under active-builder
  ownership this session — are out of this session's file-touch scope; the
  allowlist file achieves the same documentation goal without touching them).

## Tasks

- [ ] 1. Build `scripts/config-control-producer-scan.sh`: a standing,
  self-testing, bash-3.2-compatible scan over `hooks/`+`scripts/` that
  classifies every consumed `NL_*`-prefixed lever PRODUCED (real standalone
  assignment exists) / MARKED (an honest-status marker sits within a small
  line-proximity of ANY mention of the var, not just its syntactic read site
  — the real admission-lib.sh annotation sits 566 lines from the functional
  read and 1 line from the var's own name) / ALLOWLISTED (documented in
  `config/config-control-allowlist.txt`) / FLAGGED (none of the above — the
  vaporware shape); build the allowlist file auditing the 7 pre-existing
  legitimate overrides against their real read sites; build fixtures
  reproducing the real admission-lib.sh text verbatim (pre-fix and post-fix)
  plus produced/marked/flagged/allowlisted synthetic cases; generalize
  doctrine (`vaporware-prevention.md` + `-full.md`), FM-038, the
  `manifest.json` entry (with `added_after`/`golden_scenario`/
  `fp_expectation`/`retirement_condition`/`honesty_rationale`/`honest_status`
  per ADR 059 D4), and `doctrine/INDEX.md`; file the `docs/backlog.md`
  HARNESS-GAP-57 row. — Verification: full — Docs impact: doctrine + FM-038 +
  manifest + INDEX + backlog, all listed above are the doc delta itself.

  **Prove it works:** (1) `/bin/bash adapters/claude-code/scripts/config-control-producer-scan.sh --self-test`
  → `all self-tests passed`, exit 0, 7/7 scenario lines each say `PASS`,
  including `(live-repo) [real hooks/+scripts/ trees must have zero FLAGGED
  today]: PASS`. (2) same command under
  `/opt/homebrew/bin/bash` → identical 7/7 PASS, exit 0. (3) Mutation
  transcript: remove the `NL_CHECKOUT_OVERRIDE` line from
  `config/config-control-allowlist.txt`, re-run `--self-test` under
  `/bin/bash` → `(live-repo)` scenario reports `exit=1` with `FLAGGED
  NL_CHECKOUT_OVERRIDE` in the captured output and the suite ends `self-test
  failures detected`; restore the line, re-run under both interpreters →
  both return to `all self-tests passed`, exit 0. (4) `bash
  adapters/claude-code/scripts/manifest-check.sh` → `GREEN — 146 entries, 120
  hooks covered, 0 warn`.

  **Wire checks:** `adapters/claude-code/scripts/config-control-producer-scan.sh`
  (`marker_near_read`, `find_sh_files`) →
  `adapters/claude-code/config/config-control-allowlist.txt` (the
  `ALLOWLIST_FILE` default path the script reads via `grep -qE "^${var}[[:space:]]"`)
  → `adapters/claude-code/tests/config-control-producer-scan/` (the
  `FIXTURE_ROOT` the `--self-test` block reads, containing `produced/`,
  `marked/`, `flagged/`, `golden-nl-protected-orchestrator-pre-fix/`,
  `golden-nl-protected-orchestrator-post-fix/`, `empty-allowlist.txt`,
  `covering-allowlist.txt`) → `adapters/claude-code/manifest.json` (the
  `config-control-producer-scan` entry's `hooks: ["scripts/config-control-producer-scan.sh"]`)
  → `adapters/claude-code/doctrine/INDEX.md` (regenerated row, same id) →
  `adapters/claude-code/doctrine/vaporware-prevention-full.md` (the "inverse
  shape" section naming `scripts/config-control-producer-scan.sh` and
  `config/config-control-allowlist.txt` by path).

  **Integration points:** `adapters/claude-code/scripts/manifest-check.sh` —
  `bash adapters/claude-code/scripts/manifest-check.sh` → `[manifest-check]
  GREEN — 146 entries, 120 hooks covered, 0 warn` (validates the new entry's
  schema conformance, including the ADR 059 D4 new-gate-evidence-bar fields).
  `docs/failure-modes.md` FM-038 — `grep -n "Generalization — the inverse
  shape" docs/failure-modes.md` returns the new bullet. `docs/backlog.md` —
  `grep -n "HARNESS-GAP-57" docs/backlog.md` returns the filed-and-disposed
  row.

## Files to Modify/Create
- `adapters/claude-code/scripts/config-control-producer-scan.sh` — NEW: the scan
- `adapters/claude-code/config/config-control-allowlist.txt` — NEW: the allowlist
- `adapters/claude-code/tests/config-control-producer-scan/` — NEW: self-test fixtures (7 files + 2 allowlist fixtures)
- `adapters/claude-code/doctrine/vaporware-prevention.md` — "Its inverse" clause
- `adapters/claude-code/doctrine/vaporware-prevention-full.md` — "The inverse shape" section
- `docs/failure-modes.md` — FM-038 generalization bullet
- `adapters/claude-code/manifest.json` — new `config-control-producer-scan` entry
- `adapters/claude-code/doctrine/INDEX.md` — regenerated via `manifest-check.sh --gen-index`
- `docs/backlog.md` — HARNESS-GAP-57 row (filed + dispositioned)
- `docs/plans/anti-vaporware-config-controls-generalization.md` — this plan

## In-flight scope updates
n/a

## Assumptions
- The `NL_*` prefix is this repo's one established convention for its own
  config levers (confirmed by grepping every existing hooks/scripts env var);
  scoping the scan to that prefix is deliberate, not an oversight — a
  different naming convention recurring in this class would need its own
  audit pass before extending the scan's `VAR_PREFIX`.
- "Consumed" means the var appears in a `$VAR`/`${VAR` read-syntax form
  somewhere under `hooks/`+`scripts/`; a var name that ONLY ever appears in
  prose (never actually read) is not a candidate — nothing consumes it, so
  the producer question doesn't arise.
- The marker-proximity anchor (line-distance to ANY mention, not the
  syntactic read site) is calibrated against exactly one real annotation
  (admission-lib.sh); a second real-world instance with a different
  documentation shape may require revisiting the window size or anchor
  definition — flagged in the retirement condition.

## Edge Cases
- A var consumed in a file this scan doesn't scan (e.g., a `.js`/`.ts` file,
  or a `.sh` file outside `hooks/`+`scripts/`) is invisible to this check —
  documented as an explicit non-goal (`VAR_PREFIX`/`SCAN_ROOTS` are both
  override-able via `CCPS_VAR_PREFIX`/`CCPS_SCAN_ROOTS` for a future
  extension, not auto-discovered).
- The scanner excludes its OWN file from the scan (`find_sh_files`'s `!
  -name "$self_base"` guard) — without this, the scanner's own documentation
  comments (which necessarily discuss real var names and marker phrases as
  examples) would self-pollute its classification. Caught during
  construction: an early version without this guard produced a real false
  MARKED verdict on `NL_CHECKOUT_OVERRIDE` because the scanner's own header
  comment mentioned both the var name and the phrase "HONEST STATUS" in the
  same file.
- A marker phrase appearing far from any mention of the var it's meant to
  document (e.g., an unrelated HONEST STATUS note elsewhere in a large file)
  will NOT rescue an unrelated var, because the proximity anchor requires
  the marker to sit near an actual MENTION of that specific var name, not
  just anywhere in the file — verified by the golden-pre-fix/post-fix fixture
  pair, which differ ONLY in the marker comment's presence.

## Acceptance Scenarios
n/a — acceptance-exempt harness-dev plan; see acceptance-exempt-reason in the
header. Closure evidence is the `--self-test` suite + mutation transcript +
`manifest-check.sh` GREEN.

## Out-of-scope scenarios
None — the one task's three sub-blocks cover every verification surface this
plan claims.

## Closure Contract
- **Commands that run:** (1) `/bin/bash adapters/claude-code/scripts/config-control-producer-scan.sh --self-test`;
  (2) `/opt/homebrew/bin/bash adapters/claude-code/scripts/config-control-producer-scan.sh --self-test`;
  (3) `bash adapters/claude-code/scripts/manifest-check.sh`.
- **Expected outputs:** (1)+(2) `all self-tests passed`, exit 0, 7/7 PASS
  lines; (3) `[manifest-check] GREEN — 146 entries, 120 hooks covered, 0 warn`.
- **On-disk artifact location:** this plan's Completion Report + the
  `docs/backlog.md` HARNESS-GAP-57 row (both narrate the mutation transcript
  inline; no separate `-evidence/` directory for this single-task plan).
- **Done when:** the one checkbox is flipped by task-verifier AND both
  self-test runs + manifest-check are green AND the commit is on this branch.

## Testing Strategy
- The `--self-test` suite IS the test suite (7 scenarios: produced, marked,
  flagged, allowlisted, golden-post-fix-shape, golden-pre-fix-shape,
  live-repo) — no separate unit-test framework; this is a bash script and the
  harness convention for bash tooling is a `--self-test` entrypoint (see
  `doctrine/harness-dev.md`).
- RED→GREEN was driven for real during construction, not just asserted after
  the fact: the marker-proximity design went through two real failures
  (file-scoped matching rescued an unrelated var via the scanner's own
  documentation; syntactic-read-site anchoring failed the real
  admission-lib.sh case because the annotation sits 566 lines from the
  functional read) before the "any mention, small window" design passed all
  7 scenarios under both interpreters.
- Post-hoc mutation transcript (this plan's Prove-it-works step 3) confirms
  the live-repo scenario is a genuine regression detector over real repo
  state, not merely over synthetic fixtures.

Walking Skeleton: n/a — one script + one data file + fixtures + doctrine; no
new architectural layers to thread.

## Decisions Log
- 2026-07-29 (decide-and-go, constitution §8 — reversible): ship as a
  standing/manual/CI-invocable scan, NOT a new blocking PreToolUse hook.
  Rationale: D-2 in `docs/plans/archive/vaporware-config-controls.md` declined
  a new gate for the sibling registry-vs-callsite class absent a proven
  recurrence past the existing functionality-verifier/task-verifier chain;
  `NL_PROTECTED_ORCHESTRATOR` is that recurrence but in a shape (no
  registry+UI surface) D-2 didn't anticipate — the honest move is a new
  mechanical check first, with CI/blocking wiring as the natural next step
  once this build's 0%-FP claim has stood for a review cycle. Reversal =
  wire it blocking later, or delete the script; both are one-commit changes.
- 2026-07-29 (decide-and-go, reversible): use an ALLOWLIST FILE
  (`config/config-control-allowlist.txt`) for the 7 pre-existing legitimate
  operator-shell/self-test-only overrides, rather than retrofitting inline
  honest-status comments into each consuming file. Rationale: two of those
  files (`scripts/selftest-sweep-exclusions.sh` among them) are outside this
  session's file-touch scope (other builders own them concurrently); the
  allowlist achieves the same documented-intent goal without touching them,
  and mirrors the existing `config/selftest-sweep-exclusions.txt` precedent
  for exactly this "ledger of known-legitimate exceptions" shape.
- 2026-07-29 (decide-and-go, reversible): scope the mechanical check to the
  `NL_*` prefix rather than attempting to detect "any config lever" generi-
  cally. Rationale: `NL_*` is this repo's one established, grep-confirmed
  convention for its own levers; a prefix-agnostic detector would have a
  much higher false-positive rate (catching third-party tool env vars,
  standard shell vars) for no evidenced benefit — no second naming
  convention was found during construction.
- 2026-07-29: plan created `frozen: true` after the work was already built
  and self-tested — the spec IS the completed investigation (scope-
  enforcement-gate blocked the commit of already-finished work; this plan
  exists to give that work a declared scope, per the gate's own "open a new
  plan" remediation path).

## Definition of Done
- [ ] All tasks checked off (task-verifier only)
- [ ] Both self-test runs green (both bash interpreters) + manifest-check GREEN
- [ ] SCRATCHPAD.md updated with final state
- [ ] Completion report appended to this plan file
