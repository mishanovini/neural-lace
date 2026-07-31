<!-- scaffold-created: 2026-07-31T02:34:20Z by start-plan.sh slug=review-gate-identity-anchor-2026-07-30 -->
# Plan: Anchor review-gate identity outside the pusher's write set
Status: ACTIVE
Execution Mode: direct
Mode: code
Backlog items absorbed: none
acceptance-exempt: true
acceptance-exempt-reason: Harness-internal enforcement change with no user-facing UI surface; the demonstration is the gate's own --self-test plus an end-to-end bare-remote attack reproduction
tier: 3
rung: 3
architecture: coding-harness
frozen: true
lifecycle-schema: v2
loe-class: harness-mechanism
owner: mishanovini
target-completion-date: 2026-07-30
prd-ref: n/a — harness-development
ask-id: none — no linked ask

## Intended Functionality

**Outcome (operator's terms):** The maintainer can no longer have unreviewed
harness code land on master behind their back: when an agent deletes the harness
manifest, the review gate's own library, or any in-surface gate file in the same
push that carries unreviewed content, the maintainer sees that push REFUSED with
the removal named — where before it succeeded silently and they were never told.

**Observation:** Run the push. Before: `git push` exits 0, prints no gate
output, and `git ls-tree -r origin/master` contains the unreviewed file. After:
`git push` exits non-zero, prints a `PUSH BLOCKED (gate identity removal)`
banner naming `adapters/claude-code/manifest.json`, and `git ls-tree -r
origin/master` does NOT contain the unreviewed file.

**Deterministic pass/fail:** Against a bare-remote fixture driven through the
real `git-hooks/pre-push` dispatcher, all four attack variants (add-uncovered;
add + `git rm` manifest; add + `git rm` manifest + gate; pure `git rm` of an
in-surface file) must exit rc=1 with >0 bytes of gate stderr, and the pushed
tree on the remote must not contain the attack file. Zero of the four may exit
rc=0.

**Explicitly NOT included:** Pushes that bypass local hooks entirely
(`--no-verify`, a GitHub web-UI merge, a machine with `core.hooksPath` unset or
repointed). Those need a server-side required-status-check, which does not
exist and is not built here.

**Human dependencies:**
- An operator authorizes a genuinely-intended in-surface deletion via `scripts/authorize-review-record-push-override.sh` — INTENDED
- A reviewer dispatch produces the PASS record covering the changed gate files — INTENDED

## Goal
harness-reviewer returned REJECT on `dd19a0f` with one severe finding: three
separate controls decided "is this the harness repo?" by reading the SAME
pusher-writable working-tree file, `adapters/claude-code/manifest.json`. A
single `git rm -f` of that file, in the same push that added an unreviewed
hook, disarmed all three at once — the push gate's scope test exited silently,
the C2-B bootstrap fail-open re-opened, and the dispatcher's block arm degraded
to a warning. The deletion itself was never reviewed because the file
enumeration used `--diff-filter=ACMR`, which excludes `D`.

This plan closes that class: gate identity is resolved from state the push
cannot rewrite, the trigger surface is derived from the gate's carrier chain
rather than a hand-written path list, deletions join the subject set, and three
manifest rows that overclaimed their closure are corrected.

## User-facing Outcome
n/a — harness-internal: the user is the maintainer. The deliverable outcome is
the three gates' `--self-test` PASS plus an end-to-end bare-remote reproduction
showing all four attack variants refused.

## Scope
- IN: `rrg_harness_identity` + the anchor chain; `rrg_in_surface` carrier-chain
  expansion (`git-hooks/*`, `schemas/*.json`, `install.sh`, `sync.sh`, non-`.sh`
  code under `hooks/`+`scripts/`); `D`-filtered deletions as UNCOVERED; the
  missing-library block; loudness of the scope test; correction of the C2-A,
  C2-B and "not closable" manifest rows; the stale `59/59` count; the `1923`
  byte constant; the parity-helper failure-mode note.
- OUT: `doctrine/**` in the trigger surface (measured at 89 files, +31% on its
  own — deferred with the measurement recorded in `docs/backlog.md`). A
  server-side required-status-check. A deletion-aware review-record schema.
  `core.hooksPath` tamper detection, which is not closable by a control that
  depends on that config to run at all.

## Tasks

- [ ] 1. Anchor harness-repo identity on remote-side state, decomposed per control below — Verification: full — Docs impact: none — the rationale lives in the code comments and the manifest entry Task 3 updates
  - [ ] 1a. `adapters/claude-code/hooks/lib/review-record-gate-lib.sh` — add `rrg_harness_identity` + `rrg_remote_tracking_refs`; re-anchor `_rrg_is_harness_repo` onto them
  - [ ] 1b. `adapters/claude-code/hooks/review-record-push-gate.sh` — replace the working-tree scope test with the anchor chain; add the identity-removal block and the missing-library block
  - [ ] 1c. `adapters/claude-code/git-hooks/pre-push` — re-anchor the M8 missing-gate arm on HEAD + remote-tracking refs before the working tree
  **Prove it works:**
  1. Build a harness-shaped repo with a real bare remote, `core.hooksPath` pointed at the real `adapters/claude-code/git-hooks`
  2. Commit an uncovered in-surface hook; `git push origin master` — confirm rc=1 and a `PUSH BLOCKED` banner
  3. Reset; commit the SAME hook plus `git rm -f adapters/claude-code/manifest.json`; `git push origin master`
  4. Confirm rc=1, stderr names `manifest.json`, and `git ls-tree -r master` on the bare remote does NOT contain the hook
  5. Repeat with `git rm` of the manifest AND the gate script, and with a pure `git rm` of the lib — both must also be rc=1
  **Wire checks:**
  - `adapters/claude-code/hooks/lib/review-record-gate-lib.sh` defines `rrg_harness_identity` → resolves `RRG_MANIFEST_RELPATH`
  - `adapters/claude-code/hooks/review-record-push-gate.sh` calls `rrg_harness_identity` → `_rrpg_identity_removal_block`
  - `adapters/claude-code/hooks/lib/review-record-gate-lib.sh` `_rrg_is_harness_repo` → delegates to `rrg_harness_identity`
  - `adapters/claude-code/git-hooks/pre-push` `IS_HARNESS_REPO` → `refs/remotes` anchor lookup
  **Integration points:**
  - `git-hooks/pre-push` dispatcher — verify with a real `git push` against a bare remote that a non-zero gate exit aborts the push (dispatcher runs under `set -e`)
  - `_rrg_is_harness_repo`'s consumer `rrg_is_covered` — verify the C2-B bootstrap fail-open stays scoped when the manifest is absent at the pushed ref but present at an earlier anchor

- [ ] 2. Derive the trigger surface from the carrier chain, and make deletions part of the subject set — Verification: full — Docs impact: `docs/backlog.md` REVIEW-SURFACE-OMITS-ITS-OWN-DISPATCHER-01 marked resolved-except-doctrine with the measured 89-file cost
  **Prove it works:**
  1. Commit an unreviewed change to `adapters/claude-code/git-hooks/pre-push`; push — confirm rc=1 naming that file
  2. Repeat for `adapters/claude-code/schemas/manifest.schema.json` and `adapters/claude-code/install.sh` — both rc=1
  3. Commit a pure `git rm` of an in-surface gate that exists at the baseline; push — confirm rc=1 naming the deleted file
  4. Source the lib and count `git ls-files` through `rrg_in_surface` — confirm 311, and confirm the same number on both interpreters
  **Wire checks:**
  - `adapters/claude-code/hooks/lib/review-record-gate-lib.sh` `git-hooks/*` → `rrg_in_surface`
  - `adapters/claude-code/hooks/review-record-push-gate.sh` `--diff-filter=D` → `deleted`
  **Integration points:**
  - `rrg_in_surface`'s other consumers (`install.sh`, `session-start-auto-install.sh`, `review-record-commit-gate.sh`) — verify the widened surface does not break their self-tests, since all three source the same lib

- [ ] 3. Correct the three overclaimed manifest rows, the stale count, and the two misreported constants — Verification: mechanical — Docs impact: none — the manifest IS the doc surface here

## Files to Modify/Create
- `adapters/claude-code/hooks/lib/review-record-gate-lib.sh` — `rrg_harness_identity`, `rrg_remote_tracking_refs`, carrier-chain surface arms, re-anchored `_rrg_is_harness_repo`, 24 new self-test assertions
- `adapters/claude-code/hooks/review-record-push-gate.sh` — anchored scope test, identity-removal block, missing-library block, `D`-filtered deletion enumeration, Scenarios 16–21
- `adapters/claude-code/git-hooks/pre-push` — M8 block arm re-anchored on HEAD + remote-tracking refs before the working tree
- `adapters/claude-code/manifest.json` — C2-A/C2-B rows restated by OUTCOME with executed proof; "not closable" row split; `59/59` → `60/60`; new bypass row for the library-deletion vector; Amendment H narrative with measured counts
- `adapters/claude-code/hooks/review-record-commit-gate.sh` — `1923` → measured `1937`, with the re-derivation command inline
- `adapters/claude-code/hooks/harness-doctor.sh` — comment recording which parity failure mode corresponds to which mutation
- `docs/backlog.md` — REVIEW-SURFACE-OMITS-ITS-OWN-DISPATCHER-01 resolved except `doctrine/**`, with the measured deferral cost
- `docs/plans/review-gate-identity-anchor-2026-07-30.md` — this plan

## In-flight scope updates
(no in-flight changes yet)

## Assumptions
- `git` supplies `remote_sha` on stdin from the real ref negotiation, so a push
  cannot forge it. If this were false, the strongest anchor would degrade to the
  remote-tracking ref, which the chain already falls back to.
- The harness repo always has at least one configured remote whose
  `master`/`main` tracking ref carries the manifest. A clone with no remotes
  falls back to HEAD, then the working tree — never to "not the harness repo"
  while any anchor survives.
- `docs/reviews/records/` remains pusher-writable repo content; this plan does
  not change that trust boundary, it only stops the manifest from being the
  single point of failure for deciding whether the gate applies.
- Deleting an in-surface file is rare enough that requiring an operator override
  is acceptable — measured at 8 of 1763 commits (0.45%) on master.

## Edge Cases
- **First push (`remote_sha` all zeros):** the zero sha is skipped as an anchor;
  identity falls through to the remote-tracking ref, then HEAD. Scenario 13
  still passes.
- **Unresolvable `remote_sha` (fetch-first race, force-push after a remote
  rewrite):** `cat-file -e` fails on that anchor and the chain continues;
  the existing empty-tree range fallback is untouched. Scenario 13b still passes.
- **Genuinely foreign repo:** no anchor matches anywhere, so the gate stays
  silent at rc=0. Asserted in Scenario 11 and again in Scenario 18's second half
  (rc=0 AND zero bytes of stderr).
- **The gate run from a directory with no adjacent `lib/`:** blocks in the
  harness repo. This bit the mutation-proof scenarios, which now build their
  mutants in a sandbox carrying a `lib/` copy so the mutation under test is the
  only variable.
- **Manifest deleted in an earlier push, not in this range:** the per-ref
  identity check runs before the range diff, so it fires on the anchor
  comparison rather than depending on the `D` enumeration.
- **Non-`.sh` files under `hooks/`/`scripts/` that are NOT code** (`*.md`,
  `*.example`): deliberately excluded, asserted negatively so the expansion
  cannot silently overshoot into docs.

## Behavioral Contracts

### Idempotency
The gate is a pure read over the object graph and refs — it writes nothing
except the override audit log, and re-running the same push produces the same
verdict. A blocked push leaves no partial state to clean up.

### Performance budget
The anchor chain adds at most `1 + (remotes × 2) + 1` `git cat-file -e` calls
per push, each O(1) against the object store; the deletion enumeration adds one
`git diff --name-only --diff-filter=D` over a range already being diffed.
Overhead is under the noise floor of the push itself; the full 42-scenario
self-test completes in seconds on both interpreters.

### Retry semantics
None — a blocked push is not retried automatically. The operator either obtains
a PASS review record or writes a sha-scoped, time-boxed override marker (900s
TTL) and pushes again.

### Failure modes
Missing `git`/`jq` fail OPEN but LOUD (a machine problem must never brick a
push). A missing or truncated gate library fails CLOSED in the harness repo and
silent-open in a foreign repo (repo content, not a machine problem). An
unresolvable diff range degrades to scanning the whole pushed tree rather than
scanning nothing. Every bailout resolves toward block.

## Acceptance Scenarios
n/a — harness-dev plan, no product user; see acceptance-exempt-reason above.

## Out-of-scope scenarios
None — all advocate-proposed scenarios are out of scope for an
acceptance-exempt harness plan.

## Closure Contract
- **Commands that run:** `bash adapters/claude-code/hooks/lib/review-record-gate-lib.sh --self-test`, `bash adapters/claude-code/hooks/review-record-push-gate.sh --self-test`, `bash adapters/claude-code/hooks/review-record-commit-gate.sh --self-test`, `bash adapters/claude-code/scripts/manifest-check.sh` — each on BOTH `/bin/bash` (3.2.57) and `/opt/homebrew/bin/bash` (5.3.15), sequentially, by absolute path; plus the bare-remote attack reproduction driving the real dispatcher.
- **Expected outputs:** lib `67 passed, 0 failed`; push gate `42 passed, 0 failed` + `self-test: OK`; commit gate `60 passed, 0 failed` + `self-test: OK`; manifest-check rc=0; and all four bare-remote attack variants rc=1 with the attack file absent from the remote tree.
- **On-disk artifact location:** `docs/plans/review-gate-identity-anchor-2026-07-30-evidence.md`, plus the self-test transcripts quoted in the implementing commit message.
- **Done when:** this plan is DONE when all three tasks are task-verifier PASS AND the four self-tests report the counts above on both interpreters AND the bare-remote reproduction shows zero attack variants exiting rc=0.

## Testing Strategy
- Task 1: reproduced the attack FIRST against a real bare remote through the
  real dispatcher (control rc=1 / attack rc=0 with the file landed), then fixed,
  then re-ran the identical fixture requiring all four variants rc=1. Regression
  scenarios 16, 18 and 20 in the push gate's `--self-test`; identity scenarios in
  the lib's `--self-test`.
- Task 2: per-arm push scenarios (Scenario 19) for the dispatcher, schema and
  installer; Scenario 17 for pure deletion; a carrier-chain assertion in the lib
  that fails if ANY link falls out of surface; negative assertions so the
  expansion cannot overshoot into docs. Surface size measured on both
  interpreters.
- Task 3: `manifest-check.sh` GREEN on both interpreters; the corrected constants
  re-derived by executing the suites rather than by reading the old text; the
  "not closable" audit executed via `grep -oi 'not closable'` rather than
  asserted.
- MUTATION PROOFS (three, each isolating one control): Scenario 15 neuters the
  block decision, Scenario 20 reverts the identity anchor, Scenario 21 drops the
  deletion enumeration. Each must make the corresponding attack pass again; a
  mutant that still blocks fails the scenario loudly rather than passing
  vacuously.

## Walking Skeleton
The thinnest end-to-end slice is the bare-remote fixture itself: a harness-shaped
repo + bare remote + `core.hooksPath` pointed at the real dispatcher, pushed
once to prove the control blocks and once to prove the attack succeeds. That
slice exercises every layer this plan touches (dispatcher → gate → lib → git
object graph → remote tree) before a single line of the fix is written, which is
how the reviewer's finding was confirmed rather than assumed.
First task: 1.

## Decisions Log
- 2026-07-30: **Extension-based, not executable-bit, for non-`.sh` surface
  members.** The reviewer suggested covering "executable non-`.sh` members".
  Measured first: all 13 tracked non-`.sh` files under `hooks/`+`scripts/` are
  mode 100644, including the live `hooks/lib/workstreams-task-bridge.js` that
  motivated the finding. A mode-bit rule would have matched zero files and
  shipped as theatre, so the landed rule matches `.js|.ts|.py|.ps1` and excludes
  `.md`/`.example`. Tier 1 (one-line revert).
- 2026-07-30: **In-surface deletions are UNCOVERED by construction.** A deleted
  path has no blob at `local_sha`, so `rrg_is_covered` can never return true for
  it; the operator override is the only route. Considered keying coverage on the
  blob at `remote_sha`, but a PASS record attesting content does not authorize
  removing it. Measured the FP bill before adopting: 0.45% of commits. A
  deletion-aware record kind is deferred rather than half-built. Tier 2.
- 2026-07-30: **The missing-library arm fails CLOSED in the harness repo**,
  breaking symmetry with the `jq`/`git` arms that fail open. The distinction is
  system binary (machine problem) vs repo content (the repo disarming its own
  gate). Found by this builder while reproducing Critical 1, not reported by the
  reviewer. Tier 2.

## Definition of Done
- [ ] All tasks checked off
- [ ] All tests pass
- [ ] Linting/formatting clean
- [ ] SCRATCHPAD.md updated with final state
- [ ] Completion report appended to this plan file
