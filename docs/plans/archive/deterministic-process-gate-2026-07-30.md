# Plan: Deterministic-process review gate — pre-push becomes authoritative
Status: COMPLETED
Execution Mode: direct
Mode: code
Backlog items absorbed: REVIEW-GATE-UNSATISFIABLE-FROM-BUILDER-01
acceptance-exempt: true
acceptance-exempt-reason: harness-internal git-hook and manifest work with no product UI surface; the maintainer is the user and the demonstration is the self-test suite plus a manual end-to-end verification through the real git-hooks/pre-push dispatcher.
tier: 3
rung: 2
architecture: coding-harness
frozen: true
lifecycle-schema: v2
loe-class: harness-mechanism
owner: misha
target-completion-date: 2026-07-30
prd-ref: n/a — harness-development
ask-id: none — no linked ask

## Goal
Operator directive 2026-07-30: "We should never need to review whether the
reviewers fired. Make them a deterministic part of the process." Written up
as `adapters/claude-code/doctrine/deterministic-process.md` (already landed
on this branch at e91cdfa), with three rules: (1) enforce at the narrowest
chokepoint every path traverses; (2) an override the actor authors
unilaterally is not an override; (3) a step nothing invokes is not part of
the process. Plus a proof obligation: every `"blocking": true` manifest unit
declares `chokepoint` and `bypass_paths`.

Measured problem (docs/backlog.md `REVIEW-GATE-UNSATISFIABLE-FROM-BUILDER-01`):
`review-record-commit-gate.sh` (a PreToolUse commit-time gate) blocked
commits of unreviewed harness content, but its remedy — dispatch
harness-reviewer — is unreachable from a builder subagent session with no
Task/Agent-dispatch tool. 78 override events in
`~/.claude/state/review-record-gate-overrides.log` (68 on 2026-07-29, 10 on
2026-07-30), every one of today's ten citing that exact deadlock. This is a
remedy-chain deadlock (ADR 059 D5 class): the gate demanded an action the
actor it fired on could not perform.

This plan moves the authoritative check to `git push` — the funnel every
local commit crosses to reach the shared remote, and the layer where the
actor (the orchestrator, via `scripts/estate-merge.sh` or an operator's own
push) DOES have dispatch capability — and mechanizes the proof obligation
via a new `harness-doctor.sh` check.

## User-facing Outcome
n/a — harness-internal: the user is the maintainer. What changes for a
session: a builder subagent with no Task/Agent-dispatch tool can now commit
uncovered harness content and make forward progress (the commit-time gate
warns but never blocks); the SAME content is still refused when anyone
tries to push it to master/main, until it is genuinely reviewed or an
operator explicitly authorizes an emergency override for that exact commit.
The `--self-test` suites of the touched files are the demonstration.

## Scope
- IN: `hooks/review-record-push-gate.sh` (new, authoritative pre-push
  gate); `scripts/authorize-review-record-push-override.sh` (new,
  operator-facing override-marker writer); `git-hooks/pre-push` (wire in
  the new gate as stage 4); `hooks/review-record-commit-gate.sh` (demote
  blocking:true → advisory-only, remove the `REVIEW_RECORD_GATE_OVERRIDE`
  escape hatch entirely); `hooks/lib/review-record-gate-lib.sh` (add the
  shared `rrg_validate_waiver_reason` helper); `manifest.json` +
  `schemas/manifest.schema.json` (new `chokepoint`/`bypass_paths` fields,
  flip `review-record-commit-gate`'s `blocking` to `false`, add the two new
  entries); `hooks/harness-doctor.sh` (new
  `check_deterministic_process_proof`); `doctrine/review-before-deploy.md`
  + `-full.md` (correct the stale "commit gate IS the enforcement" claim);
  the generated docs `doctrine/INDEX.md` and `docs/harness-architecture.md`
  (regenerated from the manifest changes); `docs/backlog.md` (resolution
  note + two follow-up entries).
- OUT: fixing the identical range-diff fail-open bug in
  `hooks/pre-push-scan.sh` (the credential scanner) — spawned as a separate
  task (`docs/backlog.md` `PRE-PUSH-SCAN-RANGE-DIFF-FAIL-OPEN-01`) to keep
  this diff reviewable. Building a range-aware variant of
  `rq_auto_enqueue_uncovered` so the push gate can auto-enqueue independent
  review the way the commit gate does — filed as
  `RQ-AUTO-ENQUEUE-NOT-RANGE-AWARE-01`, not built here. Widening
  `rrg_in_surface` to cover `git-hooks/*` itself (harness-reviewer-identified
  gap: the dispatcher that decides whether the authoritative gate runs at
  all is outside the review surface) — noted, not fixed in this pass.
  Server-side GitHub branch-protection required-status-checks (would close
  the `--no-verify` / web-UI-merge / unconfigured-machine bypass paths) —
  explicitly out of scope, named as accepted gaps in the manifest entry.

## Tasks
- [x] 1. Build `hooks/review-record-push-gate.sh`: reads git's pre-push
      stdin protocol, computes the pushed commit range (reusing the
      proven `pre-push-scan.sh` first-push fallback logic), resolves each
      in-surface file's blob AT the pushed sha (not the working tree) via
      `rrg_blob_sha_of_ref`, checks coverage via `rrg_is_covered`, and
      blocks (nonzero exit, which aborts the whole `git push` under the
      dispatcher's `set -e`) on any uncovered file unless a fresh,
      sha-scoped, reason-validated override marker exists. — Verification: full
      **Prove it works:**
      1. Build a throwaway harness-shaped fixture repo + bare "remote"
         locally, point `core.hooksPath` at the real `git-hooks/pre-push`
         dispatcher files (not a copy).
      2. Commit an uncovered in-surface file and attempt `git push` —
         confirm it is refused (nonzero exit) and the message names the
         file and the exact remedy commands.
      3. Run `authorize-review-record-push-override.sh "<reason>" --sha
         <sha>`, retry the push — confirm it now succeeds and the push
         actually landed on the bare remote (`git log` on the remote shows
         the commit).
      4. Commit a SECOND, different uncovered file and attempt to push —
         confirm it is refused again (the earlier override does not cover
         a different commit).
      **Wire checks:**
      - `adapters/claude-code/git-hooks/pre-push` stage 4 → `bash "$REVIEW_GATE" "$@"` invokes `adapters/claude-code/hooks/review-record-push-gate.sh`
      - `adapters/claude-code/hooks/review-record-push-gate.sh` → sources `adapters/claude-code/hooks/lib/review-record-gate-lib.sh` and calls `rrg_in_surface` / `rrg_is_covered` / `rrg_blob_sha_of_ref`
      - `adapters/claude-code/hooks/review-record-push-gate.sh` `_rrpg_fresh_override` → reads markers named `review-record-push-override-<sha>-` written by `adapters/claude-code/scripts/authorize-review-record-push-override.sh`
      **Integration points:**
      - `git-hooks/pre-push` dispatcher (core.hooksPath) — verified live: a real `git push` against a throwaway bare remote was refused, then allowed after running the real authorize script, then refused again for a second commit.
      - `scripts/estate-merge.sh`'s real push call (`git -C "$main" push "$r" "$target:$target"`, line ~583) — confirmed it carries no `-c core.hooksPath=` override and no `--no-verify`, so it traverses this gate on the real machine (the `core.hooksPath ""` disabling calls in that same file are scoped to its OWN self-test fixtures, not the real merge path).
      - `hooks/lib/review-record-gate-lib.sh`'s existing `rrg_in_surface` / `rrg_is_covered` — reused as-is, not reimplemented; verified via the shared lib's own self-test (40/0 on both bash interpreters) plus this gate's own self-test scenarios exercising real coverage/grandfather/index.json fixtures.
- [x] 2. Build `scripts/authorize-review-record-push-override.sh`: the
      operator-facing script that writes the SHA-scoped, time-boxed,
      reason-validated override marker the push gate consumes — the
      Rule-2 "authorization artifact the acting agent cannot produce for
      itself in one step" (same shape as `/grant-local-edit`). —
      Verification: full
      **Prove it works:**
      1. From a repo with a known HEAD sha, run the script with a
         substantive reason; confirm a marker file is written under
         `~/.claude/state/` (or the test-override dir) named with that
         exact sha.
      2. Run it with a too-short or placeholder reason ("test", "skip");
         confirm it refuses and writes no marker.
      3. Run it with `--sha <other-sha>`; confirm the marker is written
         for the NAMED sha, not the current HEAD.
      **Wire checks:**
      - `adapters/claude-code/scripts/authorize-review-record-push-override.sh` → sources `adapters/claude-code/hooks/lib/review-record-gate-lib.sh` and calls `rrg_validate_waiver_reason`
      - `adapters/claude-code/scripts/authorize-review-record-push-override.sh` writes `review-record-push-override-<sha>-<ts>.txt` → consumed by `adapters/claude-code/hooks/review-record-push-gate.sh` `_rrpg_fresh_override`
      **Integration points:**
      - `hooks/review-record-push-gate.sh` self-test Scenario 14 runs the REAL script (not a stub) and confirms the gate honors the marker it writes.
- [x] 3. Demote `hooks/review-record-commit-gate.sh` from blocking to
      advisory-only; remove the `REVIEW_RECORD_GATE_OVERRIDE` escape hatch
      entirely (nothing left to waive); rewrite the self-test so every
      former `rc=2` assertion becomes `rc=0` plus a message assertion
      (so a regression that stops DETECTING, not just stops BLOCKING,
      still turns the suite red); add a golden scenario proving a builder
      with no override set makes forward progress. — Verification: full
      **Prove it works:**
      1. Stage an uncovered in-surface file with `REVIEW_RECORD_GATE_OVERRIDE`
         unset; run the gate directly against the staged commit; confirm
         exit 0 (commit proceeds) with the detection message still printed
         on stderr.
      2. Confirm setting `REVIEW_RECORD_GATE_OVERRIDE` to any value (empty,
         substantive, placeholder) has NO differential effect any more —
         still exit 0 either way — and nothing is written to the retired
         override-audit log.
      **Wire checks:**
      - `adapters/claude-code/hooks/review-record-commit-gate.sh` `_rrcg_main` → always `return 0` at both former-blocking exit sites (grep for `ADVISORY ONLY`)
      - `adapters/claude-code/hooks/review-record-commit-gate.sh` `_rrcg_advisory_message` → prints the message naming `adapters/claude-code/hooks/review-record-push-gate.sh` as the authoritative gate
      **Integration points:**
      - The live PreToolUse hook chain (settings.json.template) — n/a to re-verify here since wiring is unchanged (still the same hook basename); only the internal exit-code behavior changed, covered by the self-test.
- [x] 4. Add `chokepoint` + `bypass_paths` fields to
      `manifest.json`/`schemas/manifest.schema.json`; flip
      `review-record-commit-gate`'s `blocking` to `false`; add manifest
      entries for the two new files, honestly enumerating every known
      bypass path (CLOSED or NAMED-AND-ACCEPTED) including the
      harness-reviewer-identified gap that the acting agent can self-issue
      an override marker (no permission gate covers `~/.claude/state/`
      writes). — Verification: mechanical — Docs impact: regenerates
      `doctrine/INDEX.md` and `docs/harness-architecture.md`
- [x] 5. Add `harness-doctor.sh`'s `check_deterministic_process_proof`:
      REDs any `blocking:true` manifest entry declaring NEITHER
      `chokepoint` nor `bypass_paths`, with a closed, dated
      (`DETERMINISTIC_PROCESS_GRANDFATHERED`) id-list for the 38
      pre-existing `blocking:true` entries this check does not yet cover,
      plus the same `added_after < '2026-07'` date threshold
      `check_new_gate_evidence_bar` already uses (reused deliberately to
      avoid colliding with this file's own huge pre-existing self-test
      fixture corpus, most of which predates this field by convention). —
      Verification: full
      **Prove it works:**
      1. Run `harness-doctor.sh --self-test`; confirm the new
         `deterministic-process-proof-*` scenarios (red / green /
         grandfather-green / grandfather-leak-red / partial-green /
         nonblocking-green) all PASS.
      2. Run `harness-doctor.sh --quick` against the repo (not the live
         mirror) and confirm zero REDs from this new check against the
         real manifest.
      **Wire checks:**
      - `adapters/claude-code/hooks/harness-doctor.sh` `run_quick_checks` → calls `check_deterministic_process_proof`
      - `adapters/claude-code/hooks/harness-doctor.sh` `check_deterministic_process_proof` → reads `chokepoint`/`bypass_paths` from `adapters/claude-code/manifest.json` via `resolve_manifest`
      **Integration points:**
      - `scripts/manifest-check.sh` — confirmed still GREEN (151 entries) after the schema additions, since the two new fields are optional and additive.
- [x] 6. Correct `doctrine/review-before-deploy.md` and `-full.md`, which
      both claimed the (now advisory) commit gate "IS the enforcement" for
      the cockpit surface; add an Amendment H section naming the push gate
      as authoritative. — Verification: mechanical — Docs impact: this
      task IS the doc fix.

## Files to Modify/Create
- `adapters/claude-code/hooks/review-record-push-gate.sh` — new, the authoritative pre-push gate.
- `adapters/claude-code/scripts/authorize-review-record-push-override.sh` — new, operator-facing override-marker writer.
- `adapters/claude-code/git-hooks/pre-push` — wires the new gate in as stage 4, with a loud warning if it cannot be resolved.
- `adapters/claude-code/hooks/review-record-commit-gate.sh` — demoted to advisory-only; override mechanism removed; self-test rewritten.
- `adapters/claude-code/hooks/lib/review-record-gate-lib.sh` — adds the shared `rrg_validate_waiver_reason` helper.
- `adapters/claude-code/manifest.json` — new `chokepoint`/`bypass_paths` fields; `review-record-commit-gate` flipped to `blocking:false`; two new entries added.
- `adapters/claude-code/schemas/manifest.schema.json` — declares the two new optional fields.
- `adapters/claude-code/hooks/harness-doctor.sh` — new `check_deterministic_process_proof` check + self-test scenarios.
- `adapters/claude-code/doctrine/review-before-deploy.md` and `-full.md` — Amendment H, correcting the stale enforcement claim.
- `adapters/claude-code/doctrine/INDEX.md` — regenerated (`manifest-check.sh --gen-index`).
- `docs/harness-architecture.md` — regenerated (`gen-architecture-doc.sh`).
- `docs/backlog.md` — resolution note on `REVIEW-GATE-UNSATISFIABLE-FROM-BUILDER-01`, plus two new follow-up entries.
- `docs/reviews/records/2026-07-30-harness-change-review-30797d1d.json` + `index.json` — the harness-reviewer PASS record covering this diff.

## In-flight scope updates
- 2026-07-30: `docs/plans/deterministic-process-gate-2026-07-30.md` (this
  file) — created retroactively after `scope-enforcement-gate.sh` blocked
  the commit; the work itself was fully specified by the operator's direct
  chat directive plus `adapters/claude-code/doctrine/deterministic-process.md`
  and `docs/backlog.md`'s `REVIEW-GATE-UNSATISFIABLE-FROM-BUILDER-01` entry,
  neither of which is itself a `docs/plans/` file. Option 2 (open a new
  plan) per the gate's own remedy menu.

## Assumptions
- `scripts/estate-merge.sh`'s real merge-and-push path is the one that
  matters for "does the authoritative gate actually fire on the
  orchestrator's real push" — verified by reading its push call site
  directly rather than assuming from the file's self-test fixtures (which
  deliberately disable hooks for THEIR OWN throwaway repos).
- `git-hooks/pre-push` is invoked via `git config --global core.hooksPath`
  on this machine and any machine running the harness the same way; a
  machine without that config is explicitly out of scope (named in
  `bypass_paths`, not silently assumed away).
- The existing `rrg_in_surface` / `rrg_is_covered` surface and coverage
  definitions in `hooks/lib/review-record-gate-lib.sh` are correct and
  complete as-is; this plan reuses them without auditing or changing that
  surface definition (a known residual: `git-hooks/*` itself is NOT in
  that surface, noted as an out-of-scope gap above).

## Edge Cases
- A `git push` whose pushed range cannot be diffed (e.g. `remote_sha` is a
  sha the local object store does not have — reachable on both a plain
  push and a `--force` push) is handled by falling back to a full-tree scan
  at the pushed sha rather than silently treating the diff failure as "no
  files changed" (harness-reviewer PROVEN reachable during review; fixed
  and regression-tested via self-test Scenario 13b).
- An override marker for one commit must not authorize a push of a
  different, later commit (sha-scoping); a stale marker past its 900s TTL
  must not apply; a hand-crafted marker with an invalid reason must not
  apply even if the sha and timestamp are otherwise valid — all three
  covered by dedicated self-test scenarios (5, 6, 7).
- A first push of a brand-new branch (no `remote_sha`) must still be
  checked against its full history, not silently allowed — covered by
  self-test Scenario 13, reusing the same oldest-commit-not-on-any-remote
  logic `pre-push-scan.sh` already established.
- Self-test fixtures throughout `harness-doctor.sh`'s existing (pre-this-
  plan) suite construct synthetic `blocking:true` manifest entries under
  made-up ids for OTHER checks' scenarios; the new
  `check_deterministic_process_proof` must not false-positive across that
  large pre-existing corpus — handled via the closed grandfather id-list
  plus the reused `added_after < '2026-07'` date threshold (matching the
  convention those fixtures already follow to dodge the sibling
  evidence-bar check).

## Acceptance Scenarios
n/a — harness-internal plan (`acceptance-exempt: true` above); no product
user or UI surface. The demonstration is the self-test suites (review-
record-gate-lib.sh 40/0, review-record-push-gate.sh 23/0, authorize-
override script 10/0, review-record-commit-gate.sh 59/0, harness-doctor.sh
155/1 with the one failure proven pre-existing and unrelated) plus the
manual end-to-end verification through the real `git-hooks/pre-push`
dispatcher against a throwaway bare-remote fixture (block → authorize →
allow → sha-scoped re-block).

## Out-of-scope scenarios
None — no end-user advocate scenarios were proposed for this plan
(acceptance-exempt).

## Closure Contract
- **Commands that run:** `bash adapters/claude-code/hooks/lib/review-record-gate-lib.sh --self-test`; `bash adapters/claude-code/hooks/review-record-push-gate.sh --self-test`; `bash adapters/claude-code/scripts/authorize-review-record-push-override.sh --self-test`; `bash adapters/claude-code/hooks/review-record-commit-gate.sh --self-test`; `bash adapters/claude-code/hooks/harness-doctor.sh --self-test`; `bash adapters/claude-code/scripts/manifest-check.sh`; `bash adapters/claude-code/scripts/gen-architecture-doc.sh --check` — each run on both `/bin/bash` and `/opt/homebrew/bin/bash`.
- **Expected outputs:** lib 40/0; push-gate 23/0; authorize script 10/0; commit-gate 59/0; doctor 155/1 (the 1 pre-existing, unrelated, reproduced identically against the unmodified base); manifest-check GREEN; gen-architecture-doc GREEN.
- **On-disk artifact location:** this plan file's own Testing Strategy section (below) records the exact counts observed during the build; `docs/reviews/records/2026-07-30-harness-change-review-30797d1d.json` is the harness-reviewer PASS artifact.
- **Done when:** all six tasks above are checked off AND the self-test counts in the Testing Strategy section match a fresh re-run AND the harness-reviewer PASS record exists and covers every in-surface file this plan touches.

## Testing Strategy
- `hooks/lib/review-record-gate-lib.sh --self-test` — 40/0 on both bash 3.2.57 and bash 5.3.15.
- `hooks/review-record-push-gate.sh --self-test` — 23/0 on both interpreters, including a mutation-proof scenario (Scenario 15: neutering the block decision in a copy of the script flips the golden-case result, proving the real gate's `rc=1` is load-bearing, not coincidental) and a range-diff-failure scenario (Scenario 13b: a well-formed-but-nonexistent `remote_sha` still triggers a full-tree fallback scan rather than a silent allow).
- `scripts/authorize-review-record-push-override.sh --self-test` — 10/0 on both interpreters.
- `hooks/review-record-commit-gate.sh --self-test` — 59/0 on both interpreters (was 62/62 pre-demotion; net -3: two scenarios that tested the removed override mechanism retired with an explanatory comment, one net-new golden scenario added).
- `hooks/harness-doctor.sh --self-test` — 155/1 on both interpreters. The one failure, `orphaned-worktree-work-live-owned-green`, was reproduced IDENTICALLY against the unmodified `git show HEAD:...` version of the same file run in place — proven pre-existing and unrelated to this plan's changes, not a regression.
- `scripts/manifest-check.sh` — GREEN, 151 entries, 0 warn.
- `scripts/gen-architecture-doc.sh --check` — GREEN (regenerated after the manifest changes).
- Manual end-to-end verification (not just self-test): built a throwaway harness-shaped fixture repo + bare "remote", pointed `core.hooksPath` at the REAL `git-hooks/pre-push` dispatcher files, and confirmed a real `git push` of uncovered content was refused; ran the real `authorize-review-record-push-override.sh` and confirmed the retry succeeded; committed a second, different uncovered file and confirmed the earlier override did not cover it (sha-scoping holds).
- Reviewed by `harness-reviewer` (opus model, three passes): round 1 REJECT (3 Critical / 9 Major / 5 Minor); round 2 REJECT (1 Critical / 2 Major / 3 Minor) after fixes — caught a remedy that would have manufactured the exact author-email-equality shape `review-reviewer-independence` REDs on; round 3 REFORMULATE (one wrong `review-queue.sh --status` value) after routing the remedy through `review-queue.sh` → `review-runner.sh` instead of a self-authored commit. All findings fixed; PASS recorded at `docs/reviews/records/2026-07-30-harness-change-review-30797d1d.json`.

## Walking Skeleton
The thinnest end-to-end slice was Task 1 (`review-record-push-gate.sh`)
wired into Task 1's own `git-hooks/pre-push` edit and exercised against a
real bare-remote fixture BEFORE any of the manifest/doctor/doctrine
bookkeeping (Tasks 4-6) — proving the actual `git push` → dispatcher →
gate → coverage-check → block/allow chain worked end-to-end first, with
the proof-obligation mechanization and doctrine corrections layered on
after the mechanism was already demonstrated live. First task: 1.

## Decisions Log
- **Demote vs. harden the commit-time gate** (mid-build, surfaced by the
  orchestrating session): initial instructions asked for the commit-time
  gate's override validation to be hardened; a correction arrived mid-build
  citing the measured 78-override remedy-chain deadlock and directing that
  the commit gate be demoted to advisory instead, with pre-push made
  authoritative. Verified independently (grepped the override log,
  confirmed the docs/backlog.md entry and its `e91cdfa` landing) before
  proceeding — decided and went per the correction, since it was better-
  evidenced than the original framing and the operator's own doctrine file
  (deterministic-process.md) directly supports moving enforcement to the
  layer where the remedy is reachable.
- **Reuse the `added_after < '2026-07'` date threshold in the new doctor
  check, rather than inventing a second cutover mechanism** (mid-build):
  the new `check_deterministic_process_proof`'s id-based grandfather list
  alone collided with dozens of this file's own pre-existing self-test
  fixtures (synthetic `blocking:true` entries under made-up ids for
  unrelated checks). Reusing the identical field+threshold
  `check_new_gate_evidence_bar` already established, rather than adding
  every colliding fixture id by hand, was chosen for consistency with an
  existing, working convention — flagged by harness-reviewer as leaving a
  now-corrected overclaim in the header comment (fixed: the comment no
  longer says "ZERO grandfather" unqualified).
- **Route the push-gate's primary remedy through `review-queue.sh` →
  `review-runner.sh` rather than a direct `write-review-record.sh capture`
  + `git commit`** (round-2 review finding): the direct-write shape would
  have had the pushing session author and commit its own PASS record,
  which `harness-doctor`'s `review-reviewer-independence` check REDs on
  (author-email equality) and which `doctrine/review-before-deploy.md`
  already names as the disallowed path. Fixed to route through the
  sanctioned claim/finalize pathway, which commits under the reviewer's
  own identity.

## Pre-Submission Audit
n/a — Mode: code, not Mode: design; this section is only required for
Mode: design plans per the template.

## Definition of Done
- [x] All tasks checked off
- [x] All tests pass (see Testing Strategy — one pre-existing, unrelated
      flake noted and proven so, not silently ignored)
- [x] Linting/formatting clean (`bash -n` syntax-checked on every touched
      `.sh` file; `python3 -c "import json"` validated both JSON files)
- [x] SCRATCHPAD.md updated with final state — n/a, this session's
      SCRATCHPAD.md is not present in this worktree; the plan file itself
      is the durable record.
- [x] Completion report appended to this plan file (see below)

## Completion Report

_Generated by close-plan.sh on 2026-07-31T00:06:06Z._

### 1. Implementation Summary

Plan: `docs/plans/deterministic-process-gate-2026-07-30.md` (slug: `deterministic-process-gate-2026-07-30`).

Files touched (per plan's `## Files to Modify/Create`):

- `adapters/claude-code/doctrine/INDEX.md`
- `adapters/claude-code/doctrine/review-before-deploy.md`
- `adapters/claude-code/git-hooks/pre-push`
- `adapters/claude-code/hooks/harness-doctor.sh`
- `adapters/claude-code/hooks/lib/review-record-gate-lib.sh`
- `adapters/claude-code/hooks/review-record-commit-gate.sh`
- `adapters/claude-code/hooks/review-record-push-gate.sh`
- `adapters/claude-code/manifest.json`
- `adapters/claude-code/schemas/manifest.schema.json`
- `adapters/claude-code/scripts/authorize-review-record-push-override.sh`
- `docs/backlog.md`
- `docs/harness-architecture.md`
- `docs/reviews/records/2026-07-30-harness-change-review-30797d1d.json`

Commits referencing these files:

```
00293c4 docs(discoveries): triage remaining pending — 4 status flips + 1 current-state note + HARNESS-GAP-50
0090d4b feat(hook): bug-persistence-gate.sh — mechanical enforcement of testing.md rule
00a08a2 docs(F.2): regenerate doctrine/INDEX.md — fold in the 6 previously-uncovered doctrine files
00d592d fix(macos-portability M6): S11 flake root-caused + fixed (retry-guard state leak) + baseline housekeeping
0291279 feat(workstreams): shared canonical-state-path resolver — converge 9-file scatter onto one file
038503e fix(D.5 remediation): doctor --full REDs — pr-template repo-root class fix + pin-d command repair, extract-pending runtime repoint (feature was dead live), heartbeat-theater doc honesty — findings 022/023
038c648 fix(session-start-digest): honor the reentry guard at the --self-test entry point (T2); single-flight the SessionStart default path per repo root (T3)
03a7827 evidence(D.5 addendum): doctor --full LITERAL GREEN 8/8 — first full-sweep green; backlog v64
03e4883 feat(harness): credentials inventory mechanism for cross-session auth visibility
05db587 chore(wave-o): orchestrator fragment application — manifest, template, consumer-map
0758232 fix(harness): ask-id sentinel class — extend the '<'-placeholder guard to the literal 'none' spelling (re-review REFORMULATE fixes)
07691d5 feat(conv-tree): Claude-side event emitter — Dispatch conversations auto-populate the GUI
07a114d NL Overhaul Wave E batch 2: E.3 waiver-density, E.4 synthetic-runner, E.5 KPIs, E.6 NEEDS-YOU, E.10 incentive-pin retrofit (#82)
086fcd5 NL Overhaul §E.W integration cutover: template wiring + manifest merge (Wave-E live wiring) (#86)
0909869 feat(work-shapes): Tranche C — work-shape library + rule + integrations
099d4e2 feat(phase-1d-c-2): Task 9 — wire prd-validity-gate + spec-freeze-gate into settings.json (template + live)
0b14705 fix(scope-gate): Windows drive-letter git-dir recognized as absolute (+ HARNESS-GAP-27 docs superseded) (#27)
0b56c31 docs(strategy): capture Claude Code quality strategy + backlog gaps
0b767aa fix(git-hooks): restore the exec bit — NO git hook has been firing on this Mac
0be6526 feat(hook): A1 — independent goal extraction (UserPromptSubmit + Stop)
0d6bc43 feat(scope-gate): full-skip scope check during rebase/merge conflict resolution (#26)
0e2c3a6 fix(harness-architecture): restore 8 regressed Phase 1d-C-2/1d-C-3 doc rows + Task 1-3 evidence
0f34109 feat(phase-1d-c-3): Tasks 1+2+6 — Decision 019 + findings-template + findings-ledger rule + docs/findings.md bootstrap
1007841 fix(review-record): surface-vs-enforcement parity (REFORMULATE finding 1)
10adac2 feat(plan-reviewer): land Check 8A — Pre-Submission Audit gate on Mode: design plans
10effe9 verify(wave-o): O.6 flipped by task-verifier — PASS conf 9 (hb_classify fix proven 3 ways; 2 live REDs = truthful estate debt, filed) + auto-triage row
119bd26 fix(wave-o-o6): re-point obs-heartbeats-fresh to the canonical staleness oracle
11c9d13 docs(backlog): correct decision-context finding — bug #3 (Windows node-path) REFUTED; gate core verified working post path-fix + zod (P1->P2)
120593c feat(harness): plan-closure-validator gate + /close-plan skill (HARNESS-GAP-16, Phase 1d-H)
123dcaa fix-trivial(agent-efficiency T5): correct the hook-shim backlog row honesty gap
```

Backlog items absorbed: see plan header `Backlog items absorbed:` field;
the orchestrator can amend this section post-procedure with shipped/deferred
status per item.

### 2. Design Decisions & Plan Deviations

See the plan's `## Decisions Log` section for the inline record. Tier 2+
decisions should each have a `docs/decisions/NNN-*.md` record landed in
their implementing commit per `~/.claude/rules/planning.md`.

### 3. Known Issues & Gotchas

(orchestrator may amend post-procedure)

### 4. Manual Steps Required

(orchestrator may amend post-procedure — env vars, deploys, third-party setup)

### 5. Testing Performed & Recommended

See the plan's `## Testing Strategy` and `## Evidence Log` sections.
This procedure verifies that every task has its declared verification level
satisfied before allowing closure.

### 6. Cost Estimates

(orchestrator may amend; harness-development plans typically have no recurring cost — n/a)

## Closure Outcome

_Written by close-plan.sh at closure (2026-07-31T00:06:05Z)._

Outcome metric: no outcome metric declared by the plan at close time
Re-check date: 2026-08-13T17:06:05Z (default)

Evidence pointers:
- 00293c4 docs(discoveries): triage remaining pending — 4 status flips + 1 current-state note + HARNESS-GAP-50
- 0090d4b feat(hook): bug-persistence-gate.sh — mechanical enforcement of testing.md rule
- 00a08a2 docs(F.2): regenerate doctrine/INDEX.md — fold in the 6 previously-uncovered doctrine files
- 00d592d fix(macos-portability M6): S11 flake root-caused + fixed (retry-guard state leak) + baseline housekeeping
- 0291279 feat(workstreams): shared canonical-state-path resolver — converge 9-file scatter onto one file
- 038503e fix(D.5 remediation): doctor --full REDs — pr-template repo-root class fix + pin-d command repair, extract-pending runtime repoint (feature was dead live), heartbeat-theater doc honesty — findings 022/023
- 038c648 fix(session-start-digest): honor the reentry guard at the --self-test entry point (T2); single-flight the SessionStart default path per repo root (T3)
- 03a7827 evidence(D.5 addendum): doctor --full LITERAL GREEN 8/8 — first full-sweep green; backlog v64
- 03e4883 feat(harness): credentials inventory mechanism for cross-session auth visibility
- 05db587 chore(wave-o): orchestrator fragment application — manifest, template, consumer-map
