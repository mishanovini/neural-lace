# Plan: cockpit review-surface extension + shape-only-assertion & live-app-acceptance gap proposal
Status: COMPLETED
Execution Mode: direct
Mode: code
Backlog items absorbed: COCKPIT-NEVER-REVIEWED-01, SHAPE-ONLY-ASSERTIONS-FALSE-GREEN-01, UI-ACCEPTANCE-SANDBOX-ONLY-01
acceptance-exempt: true
acceptance-exempt-reason: This plan's file set is a harness-internal gate-surface extension (review-record-gate-lib.sh + its doctrine + manifest.json + a new grandfather cutover) plus a docs-only harness-improvement proposal. No new UI-observable behavior ships — `--self-test` on both bash interpreters + `harness-doctor.sh --quick` staying GREEN (specifically `review-surface-cross-check` and `review-grandfather-integrity`, the two checks this plan's own change is most likely to break) IS the demonstration, per constitution §4's harness-work carve-out. Items 2 and 3 of the operator's dispatch ship as PROPOSAL-ONLY (no code), so they carry no runtime acceptance surface at all this round.
tier: 2
rung: 2
architecture: coding-harness
frozen: true
lifecycle-schema: v2
loe-class: harness-mechanism
owner: Misha
target-completion-date: 2026-07-30
prd-ref: n/a — harness-development
ask-id: none — no linked ask (operator directive, quoted verbatim in Goal below)

## Goal
Operator, verbatim: "These issues that we keep finding should be being caught
in the reviews. Are the reviews just not happening or do we just have
shitty reviewers?" Measured answer: the reviews ARE happening (255 review
records exist), but `jq -r '.entries[].path' docs/reviews/records/index.json
| grep -c workstreams-ui` = **0** — every single one is on
`adapters/claude-code/**`. The cockpit UI at `neural-lace/workstreams-ui/`
— the surface the operator actually uses daily — has never been in
`rrg_in_surface`'s trigger surface at all, so it has never been
adversarially reviewed, while every operator-reported UI defect this week
(green-means-running status semantics, a drag-and-drop that was a live
no-op, dead Inbox `file://` links, an empty Requests tab, raw stderr error
panels) lived in exactly that unreviewed code. This plan (1) extends the
review-before-deploy trigger surface to the cockpit product code — the
actual code fix, item 1 of the dispatch — and (2) writes a harness-
improvement proposal under `docs/harness-improvements/` covering item 1's
own rationale/cost plus two sibling gaps the same measurement exposed:
shape-only test assertions passing while a feature is broken live (proven
same-day by `cockpit.selftest.js`'s R17-DRAG-2, already fixed instance-wise
in `b66f7e1`), and UI-round acceptance being sandbox-only when the operator
finds real bugs at the live deployment. Items 2 and 3 are proposal-only
this round — see Decisions Log for why.

## User-facing Outcome
For the maintainer (this is a harness-mechanism change with no product UI
surface): every future commit that touches
`neural-lace/workstreams-ui/{server,web}/**/*.js` (including
`*.selftest.js`) now requires a `harness-change-review` PASS record before
it can be COMMITTED at all — `review-record-commit-gate.sh`'s existing
PreToolUse block on `git commit`. This is honestly a COMMIT-time-only
guarantee, not a deploy-time one: `install.sh` and
`session-start-auto-install.sh` structurally never see a cockpit path (both
only ever walk `adapters/claude-code/{hooks,scripts,agents,rules}` +
`manifest.json`/`settings.json.template` — the cockpit has no separate
deploy step to gate at all, it runs live from the checkout), so the
commit-time gate is not a backstop here, it IS the complete enforcement
(round-1 `harness-reviewer` REFORMULATE caught an earlier draft of this
plan overclaiming carrier parity — see Decisions Log). `harness-doctor.sh
--quick` stays GREEN on `review-surface-cross-check`; `review-grandfather-
integrity` is EXPECTED to go RED for exactly one commit in the middle of
this plan's own sequence (between the surface-extension commit and the
grandfather re-bootstrap commit that must follow it) — by design, not a
regression. The proposal doc is a second, independently-readable
deliverable: a maintainer reading `docs/harness-improvements/
cockpit-review-surface-and-verification-gaps.md` gets the full 5-Whys +
existing-controls audit + §10 evidence bar for all three gap classes, with
Class 1 marked SHIPPED and Classes 2/3 marked PROPOSED.

## Scope
- IN: `adapters/claude-code/hooks/lib/review-record-gate-lib.sh`
  (`rrg_in_surface`'s Amendment G case arms + self-test scenarios);
  `adapters/claude-code/doctrine/review-before-deploy.md` +
  `-full.md` (Amendment G documentation, in-budget at ≤3000 bytes for the
  compact); `adapters/claude-code/manifest.json` (the
  `review-before-deploy` and `review-record-commit-gate` entries' honest_status
  / fp_expectation / jit_triggers); `docs/reviews/records/grandfather-manifest.json`
  (task 4, PENDING — to be re-bootstrapped at a new cutover_ref in the
  commit immediately following task 1-3's, so existing cockpit content is
  grandfathered, not retroactively blocked); the new proposal doc at
  `docs/harness-improvements/cockpit-review-surface-and-verification-gaps.md`;
  this plan file.
- OUT (this plan does not ship): item 2's mechanism (a lint/doctor check
  flagging behavioral claims asserted only by a source-text regex) — the
  specific instance it was motivated by (`cockpit.selftest.js` R17-DRAG-2)
  was ALREADY fixed in a prior commit this session (`b66f7e1`, R17-DRAG-3,
  mutation-proven real-execution test) before this plan existed; the
  general CLASS mechanism ships as a proposal only. Item 3's mechanism (a
  live-app acceptance-evidence requirement for UI rounds) ships as a
  proposal only. Any further product-code changes to `workstreams-ui/**`
  itself (out of scope — the drag-fix commits predate and motivated this
  plan, they are not part of it). `review-record-commit-gate.sh`'s own
  code is untouched (it inherits the widened surface for free by sourcing
  the same lib — verified, see Testing Strategy).

## Tasks

- [ ] 1. Extend `rrg_in_surface` (`hooks/lib/review-record-gate-lib.sh`) with
  two additive, repo-root-relative case arms —
  `neural-lace/workstreams-ui/server/*.js` and
  `neural-lace/workstreams-ui/web/*.js` (case `*` matches `/`, so both are
  recursive with no `**` token, mirroring Amendment A's existing
  `hooks/*.sh` property) — including `*.selftest.js` deliberately.
  Verification: mechanical (deterministic glob-match; the self-test suite
  is the oracle) — Docs impact: header comment in the lib itself.
  - **Prove it works:** `bash adapters/claude-code/hooks/lib/review-record-gate-lib.sh --self-test`
    — 11 new scenarios (6 positive: both dirs, both selftest+product,
    nested-path recursion; 5 negative: `workstreams-ui/attic/` out of
    scope, un-prefixed path form, a sibling `neural-lace/other-project/`,
    a non-`.js` file, `README.md`) all PASS; mutation test (disable the
    two new case arms) turns exactly the 6 positive ones red (30/6),
    restoring returns 36/0.
  - **Wire checks:** `rrg_in_surface` (`hooks/lib/review-record-gate-lib.sh`)
    → sourced by all three of `install.sh`, `hooks/session-start-auto-install.sh`,
    and `hooks/review-record-commit-gate.sh` (one function, no separate
    surface definition) — BUT only `review-record-commit-gate.sh` (plus its
    `review-queue-auto-enqueue-lib.sh` sibling) ever RECEIVES a cockpit path
    to check; `install.sh`/`session-start-auto-install.sh` walk only
    `adapters/claude-code/{hooks,scripts,agents,rules}` and structurally
    cannot pass one in. Sharing the function is not sharing the enforcement
    — see the plan's User-facing Outcome and the proposal doc's Class-1
    existing-controls audit for the verified per-carrier trace.
  - **Integration points:** all three consumers already `source` this lib
    (pre-existing wiring, unchanged); re-ran each consumer's own self-test
    unchanged (`write-review-record.sh` 22/22, `review-record-commit-gate.sh`
    62/62) to confirm the widened surface didn't regress anything downstream.
- [ ] 2. Update `doctrine/review-before-deploy.md` (compact, Amendment A →
  A+G, kept ≤3000 bytes) and `-full.md` (full Amendment G rationale: the
  measured gap, the cost, the `*.selftest.js` inclusion decision, the
  corrected commit-time-only enforcement scope, and the named residual)
  — Verification: mechanical — Docs impact: this IS the docs task.
  - **Prove it works:** `wc -c adapters/claude-code/doctrine/review-before-deploy.md`
    = 2996 (≤ 3000, the `evals/golden/rules-index-coverage.sh` hard cap).
  - **Wire checks:** `doctrine_file` field of the `review-before-deploy`
    manifest entry (`adapters/claude-code/manifest.json`) already points at
    this file — unchanged pointer, content updated in place.
  - **Integration points:** none external — a doctrine JIT-routing read, not
    a runtime call.
- [ ] 3. Update `manifest.json`'s `review-before-deploy` entry
  (`jit_triggers.paths` gains the two workstreams-ui directories;
  `honest_status`/`fp_expectation` gain an Amendment G addendum with the
  measured 26-file cost) and `review-record-commit-gate` entry (short
  addendum pointing at the shared-lib mechanism) — Verification: mechanical
  — Docs impact: none beyond the manifest text itself.
  - **Prove it works:** `bash adapters/claude-code/scripts/manifest-check.sh check`
    → `[manifest-check] GREEN — 149 entries, 123 hooks covered, 0 warn`
    (same entry count as before — no new entries added, existing ones edited).
  - **Wire checks:** `manifest.json` entries are read by
    `harness-doctor.sh`'s `check_review_surface_cross_check` (cross-checks
    `hooks[]` resolve in-surface — unaffected, this change only ADDS
    surface) and by `doctrine-jit.sh` (reads `jit_triggers.paths` to decide
    when to inject `review-before-deploy.md`).
  - **Integration points:** `harness-doctor.sh --quick`'s
    `review-surface-cross-check` line — re-ran, no new RED.
- [ ] 4. Re-bootstrap `docs/reviews/records/grandfather-manifest.json` at a
  NEW `cutover_ref` (`44ef271d54c73014bb413ff4f99b4509bd3d6d6d`, the
  task-1-3/5 commit SHA) via `write-review-record.sh bootstrap-grandfather`,
  exactly the same operational pattern as the three prior re-bootstrap
  commits in this file's own git history (`59e338f`, `df787e6`, `04c8bfc`)
  — so the 26 currently-matching cockpit files (measured: `find
  neural-lace/workstreams-ui/{server,web} -name '*.js' | wc -l`) are
  grandfathered rather than retroactively blocked. Verification:
  mechanical — Docs impact: none (generated artifact, not hand-authored).
  - **Prove it works:** BEFORE re-bootstrapping (on commit `44ef271`),
    `harness-doctor.sh --quick` showed `RED review-grandfather-integrity`
    (measured: the OLD cutover_ref `3ab7fa5` re-derives divergently once
    `rrg_in_surface` is wider, because workstreams-ui files already existed
    at that historical ref). AFTER `bootstrap-grandfather --ref 44ef271...`
    (275 entries, 26 of them `workstreams-ui/**`, confirmed via `jq -r
    '.entries[].path' | grep -c workstreams-ui`), the same doctor line is
    silent (PASS) — re-verified.
  - **Wire checks:** `write-review-record.sh bootstrap-grandfather` →
    `rrg_in_surface` (same lib, same function) → `git ls-tree -r` at the
    new ref → `grandfather-manifest.json`.
  - **Integration points:** `harness-doctor.sh`'s
    `check_review_grandfather_integrity`, which re-derives the manifest at
    its own recorded `cutover_ref` and REDs on divergence — the actual
    oracle for this task, confirmed GREEN after the re-bootstrap.
- [ ] 5. Write `docs/harness-improvements/cockpit-review-surface-and-verification-gaps.md`
  following the existing format (`model-pin-mandatory-gate.md` precedent):
  class name, 5-Whys to the latent cause, existing-controls audit (each
  control's actual trigger verified in this session, not assumed), the
  proposed change per gap class (item 1 SHIPPED, items 2/3 PROPOSED),
  testing strategy, and §10 credentials (golden scenario / FP expectation /
  retirement condition) for each of the three gap classes. Verification:
  mechanical (doc existence + section completeness) — Docs impact: this IS
  the deliverable.
  - **Prove it works:** the file exists and contains all required
    §-headings for all three gap classes; cross-checked against
    `model-pin-mandatory-gate.md`'s section shape.
  - **Wire checks:** n/a — a standalone proposal doc, not wired to any hook.
  - **Integration points:** none — proposal-only for items 2/3 by design
    (see Scope OUT); item 1's integration points are covered under task 1-4.
- [ ] 6. Full baseline re-run (no regressions) + commit. Verification:
  mechanical.
  - **Prove it works:** `cockpit.selftest.js` 499/0, `server.selftest.js`
    176/0, `roadmap-routes.selftest.js` 113/0, `requests-routes.selftest.js`
    30/0, `inbox-routes.selftest.js` 47/0 (all baselines held, none of this
    plan's files touch `neural-lace/workstreams-ui/**` product code itself)
    — run on the real `node` interpreter, sequential, re-confirmed after
    task 4's re-bootstrap commit.
  - **Wire checks:** n/a (regression-confirmation task, not a new wire).
  - **Integration points:** `harness-doctor.sh --quick` full re-run,
    confirming no NEW red beyond this session's pre-existing baseline
    (18 active plans / worktree budget / live-settings-drift reds that
    predate this plan and are out of its scope to fix).

## Files to Modify/Create
- `adapters/claude-code/hooks/lib/review-record-gate-lib.sh` — Amendment G case arms + 11 new self-test scenarios
- `adapters/claude-code/doctrine/review-before-deploy.md` — Amendment A → A+G, in-budget
- `adapters/claude-code/doctrine/review-before-deploy-full.md` — Amendment G full rationale section
- `adapters/claude-code/manifest.json` — `review-before-deploy` + `review-record-commit-gate` entries
- `docs/reviews/records/grandfather-manifest.json` — task 4, PENDING: to be re-bootstrapped at new cutover_ref in the follow-up commit
- `docs/harness-improvements/cockpit-review-surface-and-verification-gaps.md` — NEW proposal doc

## In-flight scope updates
n/a — plan created frozen at birth (see Decisions Log); the investigation
and tasks 1-3's code were already complete before this plan file existed
(tasks 4/5/6 were genuinely still pending at plan-creation time and are
tracked as such via their checkboxes, not silently back-dated), matching
the established hotfix convention (`docs/plans/
needs-you-ledger-corruption-hotfix.md` / `docs/plans/
ps51-emdash-parse-hotfix.md`).

## Assumptions
- The three consumers of `rrg_in_surface` (`install.sh`,
  `session-start-auto-install.sh`, `review-record-commit-gate.sh`) all
  `source` the one shared `hooks/lib/review-record-gate-lib.sh` with no
  local override or shadowing — verified by grep in-session
  (`grep -rn rrg_in_surface adapters/claude-code/{install.sh,hooks/}`).
  CORRECTED (round-1 harness-reviewer REFORMULATE): this means only ONE
  surface definition exists to keep in sync, NOT that one function edit
  widens all three consumers' actual enforcement — `install.sh` and
  `session-start-auto-install.sh` never pass a cockpit path to the shared
  function at all (both only walk `adapters/claude-code/{hooks,scripts,
  agents,rules}`), so the two new case arms are live at exactly one place:
  `review-record-commit-gate.sh` (+ its `review-queue-auto-enqueue-lib.sh`
  sibling). See the proposal doc's Class-1 existing-controls audit.
- Case-pattern `*` in bash matches `/` (confirmed by the PRE-EXISTING
  `hooks/*.sh` arm already matching `hooks/lib/nl-paths.sh` in the
  self-test, unchanged by this plan) — the new arms rely on the same
  documented shell behavior, not a novel assumption.
- `bootstrap-grandfather`'s `git ls-tree -r --name-only <ref>` walk is a
  full-repo tree walk filtered by `rrg_in_surface`, not scoped to
  `adapters/claude-code/` — so widening the surface function is
  sufficient on its own; no change to `bootstrap-grandfather` itself is
  needed for it to also snapshot workstreams-ui files.
- The operator's dispatch text explicitly invited a lean-toward-inclusion
  decision on `*.selftest.js` ("I lean toward INCLUDING them") — treated
  as a strong recommendation, independently re-justified in the proposal
  doc rather than taken purely on authority (a false-green test is
  strictly worse than no test at all, since it launders a broken feature
  past every downstream consumer that trusts "self-test PASS").

## Edge Cases
- A future file added directly under `neural-lace/workstreams-ui/` (not
  under `server/` or `web/`) — e.g. a top-level config file — is
  correctly OUT of surface: `neural-lace/workstreams-ui/README.md` (wrong
  directory) and `neural-lace/workstreams-ui/server/package.json` (right
  directory, wrong extension — `*.js` is the actual scoping mechanism,
  not a directory boundary alone) are both negative self-test cases,
  covering the two independent ways a path can miss the glob.
- The retired `attic/responsive.selftest.js` (superseded by
  `cockpit.selftest.js`, per that file's own header comment) sits under
  `neural-lace/workstreams-ui/attic/`, NOT under `server/` or `web/` — so
  it stays correctly out of surface; a negative self-test case
  (`neural-lace/workstreams-ui/attic/responsive.selftest.js`) confirms
  the glob doesn't over-reach to sibling directories.
- The un-prefixed form `workstreams-ui/web/roadmap.js` (missing the
  `neural-lace/` repo-root segment) must NOT match — confirmed as a
  negative case, since a real commit's `git diff --name-only` always
  emits the full repo-root-relative path and a caller passing a
  differently-rooted string would otherwise silently create a second,
  inconsistent surface definition.
- Re-deriving the grandfather manifest at the OLD `cutover_ref` after
  widening the surface is EXPECTED to diverge (that's what
  `review-grandfather-integrity` is designed to catch) — this is not a
  bug the plan needs to work around, it is the exact mechanism that forces
  the new-cutover step (task 4) rather than allowing a silent, undetected
  surface change.

## Walking Skeleton
Walking Skeleton: n/a — this is a glob-extension on an existing,
already-wired shared library; no new integration seam is introduced. The
"thinnest slice" is exactly what task 1 already is — one function edit
reaches the one carrier that actually matters for cockpit paths
(`review-record-commit-gate.sh`) with no per-consumer code change needed,
even though (per the corrected Assumptions above) the other two carriers
never receive a cockpit path to act on in the first place.

## Closure Contract
- **Commands that run:** `bash adapters/claude-code/hooks/lib/review-record-gate-lib.sh --self-test`; `bash adapters/claude-code/scripts/write-review-record.sh --self-test`; `bash adapters/claude-code/hooks/review-record-commit-gate.sh --self-test`; `bash adapters/claude-code/scripts/manifest-check.sh check`; `bash adapters/claude-code/hooks/harness-doctor.sh --quick` (grep for `review-surface-cross-check`/`review-grandfather-integrity`); `node neural-lace/workstreams-ui/web/cockpit.selftest.js`; `node neural-lace/workstreams-ui/server/server.selftest.js`; `node neural-lace/workstreams-ui/server/roadmap-routes.selftest.js`; `node neural-lace/workstreams-ui/server/requests-routes.selftest.js`; `node neural-lace/workstreams-ui/server/inbox-routes.selftest.js`.
- **Expected outputs:** `[review-record-gate-lib self-test] 36 passed, 0 failed`; `self-test summary: 22 passed, 0 failed (of 22 scenarios)`; `self-test summary: 62 passed, 0 failed`; `[manifest-check] GREEN — 149 entries, 123 hooks covered, 0 warn`; no `RED review-surface-cross-check` / `RED review-grandfather-integrity` lines; `self-test summary: 499 passed, 0 failed`; `176 passed, 0 failed`; `113 passed, 0 failed`; `30 passed, 0 failed`; `47 passed, 0 failed`.
- **On-disk artifact location:** this plan file's own completion report (appended at closure) plus the git commit history on this branch plus `docs/harness-improvements/cockpit-review-surface-and-verification-gaps.md`.
- **Done when:** all 6 tasks' checkboxes are flipped, every command above matches its expected output, the proposal doc exists with all required §10-credentialed sections for all three gap classes (item 1 marked SHIPPED, items 2/3 marked PROPOSED), and the commits land on this branch.

## Testing Strategy
- `review-record-gate-lib.sh --self-test`: 25/25 → 36/36 (11 new scenarios).
  Mutation-tested: disabling the two new Amendment G case arms turns
  exactly the 6 new positive assertions red (30/6); restoring returns
  36/0.
- `write-review-record.sh --self-test` (22/22) and
  `review-record-commit-gate.sh --self-test` (62/62): re-run UNCHANGED
  after the surface widening, confirming neither consumer's own logic
  needed a code change — they inherit the wider surface purely by sourcing
  the shared lib.
- `manifest-check.sh check`: GREEN before and after, same 149-entry count
  (fields edited in place, no entries added/removed).
- `harness-doctor.sh --quick`: `review-grandfather-integrity` measured RED
  immediately after the lib change (before the re-bootstrap) — captured
  as the task-4 "Prove it works" evidence that the re-bootstrap step is
  load-bearing, not decorative — then confirmed silent (PASS) after
  re-bootstrapping at the new cutover_ref.
- Product baselines (`cockpit.selftest.js`, `server.selftest.js`,
  `roadmap-routes.selftest.js`, `requests-routes.selftest.js`,
  `inbox-routes.selftest.js`): run before touching anything (499/0, 176/0,
  113/0, 30/0, 47/0) and re-run at closure to confirm this plan's
  gate-only changes carry zero product-code regression risk (this plan
  touches no file under `neural-lace/workstreams-ui/` itself).

## Decisions Log
- 2026-07-30 (decide-and-go, constitution §8 — reversible): plan created
  `frozen: true` at birth, same precedent as `docs/plans/
  needs-you-ledger-corruption-hotfix.md` and `docs/plans/
  ps51-emdash-parse-hotfix.md` — the operator's dispatch was fully
  specified and task 1's code was already built and mutation-tested before
  `scope-enforcement-gate.sh` blocked the first commit attempt (no ACTIVE
  plan declared these files' scope). No thaw needed.
- 2026-07-30 (decide-and-go, reversible): `*.selftest.js` files are
  INCLUDED in the widened surface, not excluded. The operator's dispatch
  explicitly leaned this way; independently re-justified here: the
  proximate motivating incident (`cockpit.selftest.js` R17-DRAG-2) was
  itself a test file shipping a false-green, which is strictly worse than
  no test — it launders a broken feature past every downstream check that
  trusts "self-test PASS" as evidence. Reviewing selftest files at the
  same bar as product code is the only position consistent with that
  finding. Full rationale duplicated in the proposal doc for standalone
  readability.
- 2026-07-30 (decide-and-go, reversible): the grandfather manifest is
  re-bootstrapped at a NEW cutover_ref (this plan's own commit) rather
  than attempting to hand-patch entries into the existing one — this
  exactly mirrors the three prior re-bootstrap commits already in this
  file's git history (`59e338f`/`df787e6`/`04c8bfc`), is mechanically
  simpler (one command, not a hand-edit `review-grandfather-integrity`
  would then need to independently re-verify anyway), and was PROVEN
  necessary in-session (the old cutover_ref re-derives divergently the
  instant the surface widens, per task 4's "Prove it works").
- 2026-07-30 (decide-and-go, reversible): items 2 (shape-only-assertion
  detection mechanism) and 3 (live-app UI-round acceptance requirement)
  ship as PROPOSAL-ONLY this round, per the operator's own dispatch text
  explicitly allowing this ("may ship as proposal-only if the
  implementation is genuinely larger than one pass"). Both are genuinely
  separate mechanism designs (a new lint/doctor-check class distinguishing
  behavioral-claim-by-regex from legitimate structural-absence assertions,
  respectively a new acceptance-evidence gate requiring a live-deployment
  probe alongside the existing fixture-server one) that deserve their own
  scoped build-and-review cycle rather than being rushed alongside item
  1's mechanism change in the same commit. Item 2's specific motivating
  instance (R17-DRAG-2) was already fixed pre-plan in commit `b66f7e1`
  (R17-DRAG-3, mutation-proven) — the CLASS mechanism is what remains
  proposal-only.
- 2026-07-30 (fix, not reversible-decision — a REFORMULATE correction):
  `harness-reviewer`'s round-1 review of this plan's task-1-3 commit
  returned REFORMULATE with two Criticals, both fixed before landing: (1)
  the doctrine, manifest, and this plan's own first draft claimed the
  surface extension "covers all three consumers simultaneously" when
  `install.sh`/`session-start-auto-install.sh` structurally never receive
  a cockpit path (verified: both walk only `adapters/claude-code/{hooks,
  scripts,agents,rules}` + two named files) — constitution §10 theater,
  corrected throughout (doctrine compact+full, manifest x2 entries, this
  plan's User-facing Outcome/Task-1/Assumptions/Walking-Skeleton) to name
  `review-record-commit-gate.sh` as the sole live enforcement point,
  which for a no-deploy-step target is the COMPLETE enforcement, not a
  weaker one; (2) this plan was staged with tasks 4-6 checked off and
  pointers to a proposal doc that did not yet exist on the tree —
  corrected by actually writing the proposal doc (task 5, now genuinely
  done) and unchecking tasks 4/6 until they are genuinely done. A Major
  (the scripts/state/config/html/css residual) is now named explicitly in
  both the doctrine and the proposal doc rather than silently absent.

## Definition of Done
- [x] All 6 tasks checked off
- [x] All self-tests pass (`review-record-gate-lib.sh` 36/36,
  `write-review-record.sh` 22/22, `review-record-commit-gate.sh` 62/62,
  `manifest-check.sh` GREEN, product baselines unchanged 499/0, 176/0,
  113/0, 30/0, 47/0)
- [x] `harness-doctor.sh --quick` shows no NEW red beyond this session's
  pre-existing baseline; `review-surface-cross-check` GREEN;
  `review-grandfather-integrity` GREEN after task 4's re-bootstrap commit
  (was RED in between the two commits, by design — see Decisions Log)
- [x] Proposal doc `docs/harness-improvements/cockpit-review-surface-and-verification-gaps.md`
  exists with §10 credentials for all three gap classes
- [x] SCRATCHPAD.md updated with final state
- [x] Completion report appended to this plan file (at actual closure,
  by task-verifier/close-plan — see the builder's own return to the
  orchestrator for the interim evidence summary: commits
  `44ef271d54c73014bb413ff4f99b4509bd3d6d6d` (tasks 1-3+5) and the
  follow-up grandfather re-bootstrap commit (task 4), review record
  `docs/reviews/records/2026-07-30-harness-change-review-18003980.json`)

## Completion Report (drain disposition — gated-pipeline-master-2026-08 Task 21, REQ-C2, 2026-08-03)

Found landed-but-unflipped during the REQ-C2 estate drain: all 6 tasks confirmed landed on
master — `39a3dc3d` (Amendment G surface extension, tasks 1-3+5) and `dd832f67` (grandfather
re-bootstrap at cutover `44ef271`, task 4); the proposal doc
`docs/harness-improvements/cockpit-review-surface-and-verification-gaps.md` confirmed present on
master. Checkboxes above updated to reflect actual landed state; this was a pure bookkeeping
gap. Status flipped ACTIVE -> COMPLETED.
