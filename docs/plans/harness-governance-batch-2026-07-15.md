# Plan: harness-governance batch — review-before-deploy + evidence-before-fix + artifact-evidence-bar

Status: ACTIVE
Mode: design
acceptance-exempt: true (harness-internal; the maintainer is the user, self-tests are the demonstration)
Created: 2026-07-15
Owner: handed off — a fresh session ORCHESTRATES this end-to-end (see docs/handoffs/2026-07-15-followup-batch-handoff.md)

**Execution contract (non-negotiable — constitution §8 + orchestrator pattern):** the executing
session is the ORCHESTRATOR. It dispatches worktree-isolated builder/reviewer subagents, integrates
their commits, verifies on-disk evidence (never trusts a builder's claim), and does NOT do the
build work itself. It runs until EVERY task is completed, reviewed, AND deployed (merged to BOTH
masters + live-synced + verified live) — it never pauses to ask whether to continue; continuing to
full completion is the only acceptable end state. The sole exception is a genuinely irreversible
operator-only action, which it surfaces while continuing all parallel work.

## Problem

The originating session (model-enforcement, archived) surfaced that **§10 "harness-review before
a change lands" is a Pattern, not a Mechanism** — nothing deterministically requires a harness
change to be reviewed before it is committed, merged, or deployed. This failed twice in that one
workstream: a prior session live-synced a buggy gate with zero review, and the session itself
deployed a fix (`install.sh`) before its re-review returned. Three follow-ups share ONE root
primitive — **a review/evidence record keyed to a change that gates the next step** — so they are
batched here to design that primitive once. This plan is the tracked home; the portable,
copy-into-a-fresh-session brief with full context is
`docs/handoffs/2026-07-15-followup-batch-handoff.md`.

## Decisions already made (do NOT re-litigate)

- **Decision 063:** `model-pin-gate` BLOCKS rather than auto-assigns a model, because Claude Code
  excludes Task/Agent spawns from PreToolUse `updatedInput` (verified vs official docs). Recorded in
  `docs/decisions/063-model-pin-gate-blocks-not-injects.md`.
- **Batch, not standalone** (operator, 2026-07-15): the three Mechanisms share one review-record
  substrate; design it once.

## Tasks

FOUNDATION — do FIRST; the batch builds on a unified, clean master. Full procedure:
`docs/runbooks/master-reconcile-and-estate-cleanup.md`.

- [ ] R1. **Reconcile the two masters to convergence (0/0).** Runbook Part A: fetch pt on the work
  account, merge (only manifest.json + backlog.md conflict — resolve by UNION), pin the
  architecture-reviewer that arrives from pt (`model: fable` + add to config/model-policy.json),
  verify (self-tests + doctor), harness-review BEFORE push, push BOTH remotes. Verification: full —
  `git rev-list --left-right --count pt/master...master` == `0 0` AND doctor green live.
- [ ] R2. **Clean the branch/worktree estate.** Runbook Part B: remove only merged/stale UNOWNED
  worktrees + branches; respect the ownership broadcast + concurrent-ownership gate (never force).
  Verification: full — a report of what was removed vs kept, with the reason for each keep.
- [ ] R3. **Never-diverge design fix.** Diagnose why the masters diverged and why the fork-sync
  isn't running (PT-FORK-SYNC-NOT-RUNNING-01); DECIDE the design that makes recurrence structurally
  impossible (decision-log entry, decide-and-go per §8); architecture-review it; build + review +
  deploy. Verification: full.

BATCH — after the foundation lands (unified master):

- [ ] 1. **Design the review-record primitive** — a structured record (à la close-plan's
  `.evidence.json`) keyed to a change/commit, carrying a `harness-reviewer` PASS verdict. Decide the
  identity key and the trigger surface (all `adapters/claude-code/**`, or only gate/hook/rule files).
  MUST go through `architecture-reviewer` (design SHAPE review) before any build — high blast radius.
  Verification: design
- [ ] 2. **Review-before-deploy gate** — a gate on the DEPLOY step (`install.sh` +
  `session-start-auto-install.sh`) that blocks harness changes lacking a PASS review record. Own
  golden scenario, fp_expectation, retirement condition (§10). Verification: full (self-test + a live
  deploy-blocked demonstration).
- [ ] 3. **Directive 1 — evidence-before-fix commit gate** — require an evidenced
  `## Root cause (evidenced)` block (PROVEN/INFERRED-tagged) before a `fix(...)` commit; reject an
  inferred-not-observed cause. Broaden `diagnosis.md` beyond prod-crashes to data/behavior bugs.
  Lesson: `docs/lessons/2026-07-14-root-cause-must-be-evidenced-before-fix.md`. Verification: full.
- [ ] 4. **Integrate pt/master `artifact-evidence-bar`** — fold pt's §10-generalization (evidence for
  gates/AGENTS/DESIGNS/reviews) into the primitive; land during the pt reconcile. Verification: contract.
- [ ] 5. **Evidence-bar evasion-by-omission** — backfill `added_after` on the 31 legacy `blocking:true`
  manifest entries, THEN assert its presence on every `blocking:true` entry in `check_new_gate_evidence_bar`.
  Verification: full (doctor self-test RED-then-GREEN).
- [ ] 6. **Commit-capture (this session's residue)** — commit the on-disk `docs/decisions/063*` +
  `doctrine/model-selection.md` note + this plan + the handoff + the ws-UI design-note + backlog row.
  Verification: mechanical (files in commit).

## Out of scope / separate tracks

- Built-in-strictness operator decision (live default STRICT) — handoff §6. (Now folded into the
  execution contract: the orchestrating session surfaces it but does not block; default stays STRICT.)
- Status-page → Workstreams-UI adoption — `docs/design-notes/status-page-for-ws-ui-adoption.md`,
  backlog `WS-UI-STATUS-PAGE-ADOPTION-01`. Unrelated track.

## Files to Modify/Create

- `docs/plans/harness-governance-batch-2026-07-15.md` — this plan.
- `docs/handoffs/2026-07-15-followup-batch-handoff.md` — the portable brief.
- `docs/design-notes/status-page-for-ws-ui-adoption.md` — ws-UI reference (separate track).
- `docs/decisions/063-model-pin-gate-blocks-not-injects.md` — the block-not-inject decision.
- `adapters/claude-code/doctrine/model-selection.md` — the "why block not inject" note.
- `docs/backlog.md` — the ws-UI adoption row.
- `docs/runbooks/master-reconcile-and-estate-cleanup.md` — the reusable reconcile+cleanup procedure (tasks R1–R2).
- `docs/handoffs/2026-07-14-model-enforcement-and-rootcause-gate-checkpoint.md` — task 6 residue.
- `docs/lessons/2026-07-14-credentials-are-available-inject-dont-surrender.md` — task 6 residue.
- `docs/plans/model-enforcement-2026-07-14-evidence/1.evidence.json` — task 6 residue.
- `docs/plans/model-enforcement-2026-07-14-evidence/2.evidence.json` — task 6 residue.
- `docs/plans/model-enforcement-2026-07-14-evidence/3.evidence.json` — task 6 residue.
- `docs/plans/model-enforcement-2026-07-14-evidence/4.evidence.json` — task 6 residue.
- `docs/plans/model-enforcement-2026-07-14-evidence/5.evidence.json` — task 6 residue.
- `docs/decisions/064-never-diverge-single-canonical-master.md` — R3 decision (amended per review).
- `docs/design-notes/review-record-primitive.md` — batch task 1 design draft.
- `adapters/claude-code/hooks/harness-doctor.sh` — batch task 5 assertion + task-2 doctor checks.
- `adapters/claude-code/hooks/session-start-auto-install.sh` — batch task 2 deploy-gate (fail-open path).
- `adapters/claude-code/install.sh` — batch task 2 deploy-gate (hard-block path) + R3 prune step.
- `adapters/claude-code/scripts/write-review-record.sh` — batch task 2 record writer.
- `adapters/claude-code/hooks/gh-merge-canonical-gate.sh` — R3 write-discipline gate (name may vary).
- `adapters/claude-code/hooks/cross-repo-drift-postpush-gate.sh` — R3 block-message repoint.
- `adapters/claude-code/attic/**` — R3 sync-pt-to-personal retirement.
- `adapters/claude-code/scripts/sync-pt-to-personal.sh` — R3 retirement (moved to attic).
- `adapters/claude-code/sync.sh` — R3 A5 posture-comment reconcile.
- `adapters/claude-code/settings.json.template` — R3 + task-2 hook wiring.
- (build tasks R3 + 1–5 create their own files in the executing session.)

## In-flight scope updates

- 2026-07-15 (R3): `docs/decisions/064-never-diverge-single-canonical-master.md` — the R3
  design decision record (decide-and-go per §8).
- 2026-07-15 (R1/R3/batch, executing session): `adapters/claude-code/manifest.json`,
  `adapters/claude-code/config/model-policy.json`, `adapters/claude-code/agents/architecture-reviewer.md`,
  `docs/harness-architecture.md` — R1 merge-invariant surface (union + pins + regenerated doc).
- 2026-07-16 (R1 merge-fix, reviewer-REJECT remediation): the 11 pt-side files dropped from
  `937e8cb` by the stash/index corruption — `adapters/claude-code/doctrine/INDEX.md`,
  `adapters/claude-code/hooks/lib/merge-scan-lib.sh`, `adapters/claude-code/hooks/lib/progress-log-lib.sh`,
  `adapters/claude-code/hooks/plan-lifecycle.sh`, `adapters/claude-code/hooks/workstreams-emit.sh`,
  `adapters/claude-code/schemas/progress-log-event.schema.json`, `adapters/claude-code/scripts/dispatch-provenance.sh`,
  `docs/plans/ask-rooted-workstreams-p1-evidence.md`, `docs/plans/ask-rooted-workstreams-p1.md`,
  `docs/runbooks/ask-workstreams.md`, `neural-lace/workstreams-ui/server/auditor.js` — plus the
  manifest 123-union, the model-policy entry, and the runbook verification hardening.
- 2026-07-15 (residue capture, task 6): `docs/handoffs/2026-07-14-model-enforcement-and-rootcause-gate-checkpoint.md`,
  `docs/lessons/2026-07-14-credentials-are-available-inject-dont-surrender.md`,
  `docs/plans/model-enforcement-2026-07-14-evidence/**` — prior-session on-disk artifacts needing a home.
- 2026-07-16: `adapters/claude-code/hooks/gh-merge-canonical-gate.sh` — R3 new gate (decision 064).
- 2026-07-16: `adapters/claude-code/doctrine/gh-merge-canonical.md` — R3 new doctrine for the gate.
- 2026-07-16: `adapters/claude-code/settings.json.template` — R3 PreToolUse Bash wiring for the gate.
- 2026-07-16: `adapters/claude-code/attic/sync-pt-to-personal.sh` — R3 retirement (A6), git mv from scripts/.
- 2026-07-16: `adapters/claude-code/install.sh` — R3 prune_retired_files mechanism (A6).
- 2026-07-16: `adapters/claude-code/hooks/cross-repo-drift-postpush-gate.sh` — R3 message repointed to the runbook (A6).
- 2026-07-16: `adapters/claude-code/sync.sh` — R3 A5 posture-comment update (PT-canonical -> personal-canonical).
- 2026-07-16: `adapters/claude-code/attic/README.md` — R3 non-hook-retirement clarifying note.
- 2026-07-16: `adapters/claude-code/doctrine/INDEX.md` — R3 regenerated (new gate entry).
- 2026-07-16: `docs/harness-architecture.md` — R3 regenerated (new gate entry).
- 2026-07-16 (task 5 fixup, harness-review REJECT remediation): `adapters/claude-code/scripts/manifest-check.sh`
  — it carries an INDEPENDENT copy of the same new-gate-evidence-bar rule as
  `harness-doctor.sh`'s `check_new_gate_evidence_bar` (task 5's target). Correcting the 5
  under-dated `manifest.json` entries to their true "2026-07" landing month regressed this
  script's own copy of the rule (it started RED-ing on all 5), so the same closed
  `PRE_BAR_GRANDFATHERED` exempt-list had to be mirrored into it (both node and jq paths) plus
  two self-tests (S10c/S10d) to keep task 5's own "manifest-check.sh must not regress"
  constraint honest.
- 2026-07-16: `adapters/claude-code/hooks/session-start-git-freshness.sh` — R3 harness-review fixup: dropped the dangling `sync-pt-to-personal` entry from WIP_BRANCH_PATTERN (retired script, dead reference).

- 2026-07-16 (task 2 build, review-before-deploy gate): `adapters/claude-code/hooks/lib/review-record-gate-lib.sh` — shared trigger-surface + coverage lib.
- 2026-07-16 (task 2 build): `adapters/claude-code/scripts/write-review-record.sh` — orchestrator-invoked record writer.
- 2026-07-16 (task 2 build): `adapters/claude-code/install.sh` — hard-block wiring.
- 2026-07-16 (task 2 build): `adapters/claude-code/hooks/session-start-auto-install.sh` — fail-open skip+warn wiring.
- 2026-07-16 (task 2 build): `adapters/claude-code/manifest.json` — new `review-before-deploy` entry.
- 2026-07-16 (task 2 build): `adapters/claude-code/hooks/harness-doctor.sh` — two new checks (surface cross-check + index consistency).
- 2026-07-16 (task 2 build): `docs/harness-architecture.md` — regenerated.
- 2026-07-16 (task 2 build): `docs/reviews/records/index.json` — bootstrap content-keyed index.
- 2026-07-16 (task 2 build): `docs/reviews/records/grandfather-manifest.json` — cutover grandfather snapshot.
- 2026-07-16 (task 2 build): `docs/reviews/records/2026-07-16-harness-change-review-513a1f66.json` — bootstrap exercise record for this batch's own changes (written-by-orchestrator-pending-review placeholder).
- 2026-07-16 (task 2 build): `.gitignore` — un-ignore `docs/reviews/records/` (a blanket `docs/reviews/*` rule was silently excluding the committed-by-design records dir).
- 2026-07-16 (task 2 build): `docs/backlog.md` — anti-fabrication-anchor follow-up row.
- 2026-07-16 (task 2 build): `adapters/claude-code/doctrine/INDEX.md` — regenerated (new manifest entry).
- 2026-07-16 (task 2 build): `adapters/claude-code/doctrine/review-before-deploy.md` — new compact doctrine note for the gate.
- 2026-07-16 (task 5 residual, coordinator-directed): `adapters/claude-code/scripts/manifest-check.sh`, `adapters/claude-code/schemas/manifest.schema.json`, `adapters/claude-code/manifest.json`, `docs/harness-architecture.md` — a second, later touch of the same four files.
  Fixed 3 pre-existing manifest-check.sh false REDs on the session-start-auto-install entry's
  hooks/lib/sessionstart-singleflight.sh reference (a sourced library under hooks/lib/, never
  wired, mis-handled by the schema/existence/wired-template checks as if it were a plain wired
  hook). Checker now recognizes a lib/name.sh hooks[] entry as a sourced-library reference
  (schema accepts it, existence check resolves it without a double hooks/hooks/ prefix,
  wired-template check exempts it); corrected the one entry's redundant hooks/lib/... value to
  the canonical lib/... form to match; regenerated the architecture doc for the resulting
  table-row diff. 4 new self-tests (S11/S12/S13 + inline no-leak assertion).

## Evidence Log

### R1 (2026-07-15, orchestrating session)
- pt reachable on the work gh account (active at session start); `git fetch pt master` OK. Divergence pre-merge: `14 10` (pt-only / local-only).
- Conflict surface pre-verified via merge-base `974aa22` + `comm -12`: exactly `adapters/claude-code/manifest.json` + `docs/backlog.md` (as runbook predicted).
- Merge commit **`937e8cb`** (parents `0085781` local + `6db4c3e` pt). Unions: manifest kept BOTH new entries (model-pin + artifact-evidence-bar), JSON validated; backlog kept HEAD's GUARD-REFORMULATE-01 superset + WS-UI row, dropped pt's older duplicate.
- Invariant fixes in the merge commit: `agents/architecture-reviewer.md` pinned `model: fable`; `config/model-policy.json` + architecture-reviewer (design, [fable,opus]); `docs/harness-architecture.md` regenerated (gen --check GREEN).
- Verify: model-pin-gate self-test 13/13; harness-doctor self-test 105/105. doctor --quick REDs triaged: all pre-existing on BOTH parents (manifest-check path-join bug on sessionstart-singleflight — **nl-issue filed**), or clear-on-install (manifest-freshness), or R2 scope (worktree budget), or environmental (cockpit port / ask-capture / needs-you headers / live Stop-chain budget).
- Incident (self-caused, resolved): a baseline `git stash` snapshot destroyed MERGE_HEAD mid-merge; restored via `git rev-parse pt/master > .git/MERGE_HEAD` before committing, so `937e8cb` has correct dual parents. Gates behaved correctly throughout (scope gate's merge full-skip resumed once MERGE_HEAD was restored; docs-freshness correctly demanded the regenerated architecture doc).
- harness-reviewer (FRESH dispatch, model: opus — Fable spend-capped) dispatched on `937e8cb` BEFORE push, per runbook step 7. Verdict: (pending)
- PUSH: (pending review PASS)

### R2 (executed 2026-07-16)
- Classification (explorer, PROVEN): broadcast signals 1-4 are existence-only (`git worktree list`);
  the concurrent-ownership gate blocks only fresh claims (<2h mtime) or checked-out branches. Only
  sleepy-albattani had a fresh claim.
- REMOVED: worktree `agent-afdcb7239ab5755d9` + its branch (ancestry-merged into master; plan
  model-enforcement COMPLETED+archived; no claim; clean). `git worktree prune` run.
- KEPT with reasons: `sleepy-albattani-0d9012` (fresh claim, live session); `workstreams-ui-server`
  (operator-designated hands-off server checkout); `agent-aeed9a16399bf88e6` (vaporware-cc COMPLETED,
  content landed via PR#100, but not ancestry-merged and only 3d old — qualifies under >7d rule
  2026-07-19); `beautiful-mcnulty-e8bc42` worktree+branch (PR#100 MERGED, content in master, but
  unmerged-by-ancestry local tip + only 3d old — revisit 2026-07-20); `close-100` branch (12 unpushed
  commits, content landed via pt merge, not stale); `agent-af4788a454e6087f0` (this session's batch-1
  design builder — removed after cherry-pick).
- OPERATOR ITEMS (classifier-denied, not retried): (a) `nl-ux-wt` is a husk — Temp-dir contents wiped,
  1205 phantom deletions, ZERO modified/untracked, branch `feat/prerequisite-unblocking-pattern`
  pushed+in-sync; needs `git worktree remove --force "$LOCALAPPDATA/Temp/claude-scratch/nl-ux-wt"`
  run by the operator (auto-mode classifier denies both --force removal and the restore-then-remove
  path). (b) `git push -u origin ws-ui-server-stable` (doctor-recommended upstream creation for the
  27d-unpushed server branch) — classifier-denied, operator to run or decline.
- nl-issues filed: broadcast should label claim-backed vs existence-only signals; no reaper for
  completed-plan builder worktrees (cite reap-what-you-spawn doctrine).

### R3 + batch design reviews (2026-07-16)
- Decision 064 architecture-review: SOUND-WITH-AMENDMENTS; A1-A6 folded (branch protection on the
  work repo PROMOTED to primary mechanism — operator-only, NEEDS-YOU; gh-merge gate demoted to
  defense-in-depth with honest residual-writer coverage + A4 target resolution). Committed e2cf8b8.
- Review-record primitive architecture-review: SOUND-WITH-AMENDMENTS; amendments A-F handed to the
  task-2 builder verbatim (path-glob surface NOT manifest-union — 3 of the 5 files 937e8cb reverted
  are in no manifest hooks[]; content-presence-only coverage contract; anti-fabrication downgraded to
  audit-anchor; index read path; grandfather cutover; fail-open posture stated).
- Batch 5 build: engine BLESSED by harness-review but verdict REJECT on data honesty — 5 July-landing
  entries were encoded added_after "2026-06" to sit below the bar cutoff PER A WRONG ORCHESTRATOR
  INSTRUCTION (owned: the dispatch prompt said "use a pre-bar sentinel month"; §1 violation). Fix in
  flight: true 2026-07 months + explicit documented grandfather exempt-list in the doctor check +
  remedy-string reword (no more under-dating invitation) + jq type-guard parity. Original commit
  message amended with the true record (e546ed9). Builder-report mismatch also noted (report said
  sentinel "2026-04", artifact carried "2026-06") — calibration note for plan-phase-builder.

### R2 (inventory so far)
- 7 worktrees; broadcast marks 5 signals live-owned (main, nl-ux-wt, agent-aeed9a16, agent-afdcb723, workstreams-ui-server) + sleepy-albattani claim. Non-owned candidates: `beautiful-mcnulty-e8bc42` worktree (clean, detached @6149a45, PR #100 MERGED on pt 2026-07-13) and branches `claude/beautiful-mcnulty-e8bc42` (ahead-of-origin by 1 doc commit) + `close-100` (12 commits, unpushed, content landed via PR 100→pt→master — verified: archived plan + FM-038 + vaporware doctrine present in master). Neither branch is ancestry-merged nor stale >7d → runbook says KEEP; revisit via estate coordination (are the broadcast signals themselves stale?).

### R3 (built 2026-07-16, PARALLEL worktree builder, per amended decision 064 A1-A6)
- **Gate:** `hooks/gh-merge-canonical-gate.sh` (PreToolUse Bash) blocks `gh pr merge` / `gh api
  .../pulls/N/merge` when the RESOLVED target repo == the `pt` remote's repo (`git remote get-url pt`
  at runtime, never hardcoded). Target resolution (A4), fully offline (no `gh api`/network call in the
  hook path): explicit `--repo`/`-R`/API-path repo wins; else `gh repo set-default` state
  (`remote.<name>.gh-resolved base`); else the sole github.com-hosted remote (an SSH host-alias remote
  like `pt` via `github-pt` is NOT a candidate here — empirically verified: `gh repo view` in this repo
  resolves to the personal repo despite `pt` existing, because gh itself doesn't recognize the alias
  host); 0 or >1 candidates -> AMBIGUOUS -> loud fail + block (never guess either direction).
- **Self-test: 17/17 PASS** (`bash adapters/claude-code/hooks/gh-merge-canonical-gate.sh --self-test`)
  — explicit --repo pt/personal (BLOCK/ALLOW), `gh api` explicit-path pt/personal (BLOCK/ALLOW),
  case-insensitive pt match, non-merge `gh` commands, non-Bash tool, malformed/empty input (fail-open),
  bare merge via sole-github-remote resolving to pt (BLOCK) and to personal (ALLOW — the FP the design
  fears), 2-remote ambiguous (BLOCK, distinct message asserted via grep), `gh-resolved` default among 2
  candidates resolving to pt (BLOCK) and to personal (ALLOW), and no-`pt`-remote-configured (fail-open
  ALLOW — an unrelated repo elsewhere on the estate is never blocked).
- **Manual smoke (verification-bar requirement):** piped a fabricated PreToolUse JSON
  (`{"tool_name":"Bash","tool_input":{"command":"gh pr merge 100 --repo <work-org>/neural-lace"}}`)
  through the hook against a throwaway fixture repo with `pt`/`origin` remotes shaped like the real
  dual-hosted setup (an SSH host-alias `pt` remote + a github.com `origin`) — printed the full BLOCK
  teaching message (canonical flow, branch-protection-primary note, in-flight-PR migration note) and
  exited 2.
- **Manifest + wiring:** `manifest.json` `gh-merge-canonical` entry (kind gate, blocking true,
  `added_after: "2026-07"`, `golden_scenario`/`fp_expectation` defined against the RESOLVED target per
  A4, `retirement_condition` = pt archived OR branch protection enabled) — 124 entries total.
  `settings.json.template` PreToolUse Bash wiring added (JSON-validated). `doctrine/gh-merge-canonical.md`
  new compact doctrine file; `doctrine/INDEX.md` + `docs/harness-architecture.md` regenerated (`gen-
  architecture-doc.sh --check` GREEN).
- **Retirement (task 4/A6):** `git mv adapters/claude-code/scripts/sync-pt-to-personal.sh
  adapters/claude-code/attic/` — NO exit-0 shim (attic/README.md's shim rule is scoped to
  settings.json-wired `hooks/`; this was an unwired `scripts/` utility with no live invocation path a
  session could have pre-loaded — added a short clarifying note to attic/README.md). `install.sh` gained
  a minimal `PRUNED_FILES` / `prune_retired_files` mechanism (none existed before for single-file, as
  opposed to whole-directory, retirements) naming this path so a stray live copy at
  `~/.claude/scripts/sync-pt-to-personal.sh` is removed on next install. `cross-repo-drift-postpush-
  gate.sh`'s block message (~line 126) repointed from the retired script to
  `docs/runbooks/master-reconcile-and-estate-cleanup.md` — re-ran that hook's own self-test (7/7 PASS)
  to confirm the message edit didn't regress it. Chesterton check: grepped all live (non-archive,
  non-attic) references to `sync-pt-to-personal`; the only other hits
  (`master-drift-autocorrect.sh`, `session-start-git-freshness.sh`, `session-resumer.sh`) are historical/
  pattern-naming comments, not functional callsites — left untouched.
- **A5 posture sweep:** grepped the live repo (excluding archived plans/decisions, which are historical
  record) for "PT is canonical"/"PT canonical" framing. Found and updated one live hit:
  `sync.sh:67-74`'s header comment (WHY TREE HASH AND NOT COMMIT SHA) — reworded from "PT canonical;
  personal receives content via cherry-pick" to cite decision 064 and frame the cherry-pick-produces-
  divergent-SHAs fact as a property of a MANUAL RECONCILE (via the runbook), not of the (now-retired)
  PT-canonical sync direction. Re-ran `sync.sh --self-test` (7/7 PASS) after the edit. `docs/backlog.md`
  and `docs/harness-architecture-history.md` had only unrelated "canonical" substring matches (not
  posture claims) — no change needed. `docs/RESUME-HERE.md` already routes cross-machine work through
  `origin/master` (per decision 064's own note) — verified consistent, left as-is.
- **Verify:** `manifest-check.sh` — 3 pre-existing RED (sessionstart-singleflight path-join bug, filed
  as an nl-issue by the R1 session; unrelated to this task, added none) — 124 entries, no new REDs.
  `harness-doctor.sh --self-test` — **105/105 PASS**. `harness-doctor.sh --quick` (against the currently-
  installed LIVE `~/.claude`, pre-deploy) shows the expected not-yet-installed drift for a worktree
  builder (`template-live-drift` for the new hook, `manifest-freshness` live-vs-repo hash mismatch) —
  both clear once this branch merges to master and `install.sh` runs; the remaining REDs/WARN (obs-
  cockpit-fresh, obs-ask-capture-completeness, budget-chains, budget-worktrees-branches) are pre-existing
  and unrelated to this task (matches the R1 session's own triage of the same classes).
- **Deferred (named, not silently dropped):** the decision's "new doctor check candidate" (assert the
  post-commit dual-push hook / `core.hooksPath` is installed) is explicitly a *candidate* in decision
  064's Consequences section, not one of the 6 build items dispatched for R3 — left as a follow-up
  rather than scope-expanded into this build.

### R3 harness-review fixup (2026-07-16, same worktree, commit after review REJECT)
- **Verdict on the R3 commit:** REJECT with narrow, exactly-specified fixes — design, FP-restraint,
  ambiguity fail-loud, retirement safety, docs coupling, and honesty framing all explicitly PASSED
  (not reworked). Fixed:
- **CRITICAL** (`hooks/gh-merge-canonical-gate.sh`): the command read only checked
  `.tool_input.command`; a flat-shape payload (`.command` directly on the tool-call object, no nested
  `tool_input`) silently fail-opened on EVERY merge while self-test stayed green. Fixed to
  `jq -r '.tool_input.command // .command // ""'`; added a self-test fixture feeding exactly that flat
  shape, asserting BLOCK.
- **MAJOR — parser coverage:** (i) `_is_merge_command` matched a literal single-space glob
  (`*gh\ pr\ merge*`); a multi-space/tab-spaced command (`gh  pr  merge`) silently fell through to
  ALLOW. Fixed to `grep -qE 'gh[[:space:]]+pr[[:space:]]+merge'`. (ii) `_resolve_target_repo` had no
  positional-target parsing; a pasted PR URL (`https://HOST/OWNER/REPO/pull/N` — the natural
  copy-paste idiom) or `OWNER/REPO#N` shorthand fell straight to default-repo resolution, which could
  resolve to the WRONG (non-pt) repo even when the positional itself named pt. Added
  `_extract_positional_target`, spliced into `_resolve_target_repo` between the explicit `--repo`/`-R`
  step and the `gh-resolved`/heuristic steps (gh itself honors a positional target over the default
  repo). (iii) Added self-test fixtures: pt-PR-URL -> BLOCK, `<pt-owner>/<repo>#42` -> BLOCK,
  multi-space `gh  pr  merge --repo <pt>` -> BLOCK, personal-PR-URL -> ALLOW.
- **MINOR** (`_extract_api_merge_owner_repo`): a literal gh-api `{owner}/{repo}` template placeholder
  (gh substitutes these from the CURRENT repo context, not from the string) was being read as if it
  were the resolved owner/repo — which can never equal the real pt owner/repo, so a templated
  pt-targeting command would silently ALWAYS ALLOW. Fixed: if the extracted owner or repo contains
  `{`, treat as NOT-explicit and fall through to default-repo resolution. Self-test fixture added.
- **MINOR** (`doctrine/gh-merge-canonical.md`): added a line noting the gate scopes itself by the
  remote NAME `pt` (a neural-lace-specific convention) and is wired estate-wide — on any other
  dual-hosted repo that names its mirror remote something else, the gate is a silent no-op for that
  repo, not a guarantee.
- **OPTIONAL** (`hooks/session-start-git-freshness.sh`): dropped the dangling `sync-pt-to-personal`
  entry from `WIP_BRANCH_PATTERN` (a dead reference to the retired script's old temp-branch prefix; no
  behavioral effect since that prefix can never be created again). Self-test re-run: 15/15 PASS.
- **manifest.json `honest_status`/`fp_expectation` updated** (not merely bumped) to name the parser's
  new reach exactly AND the residual that remains uncovered even after the fixup: a
  runtime-interpolated value (`gh pr merge $N --repo "$REPO_VAR"` — invisible to a static-string
  check), a bundled short flag with no space (`-Rowner/repo`), and a `gh pr merge` invoked via a shell
  alias/function whose name doesn't literally contain adjacent `gh`/`pr`/`merge` tokens. All three
  fall through to (or past) default-repo resolution rather than being silently misread as a false
  ALLOW/BLOCK — named explicitly rather than left as an implicit gap.
- **Verify (fixup):** `gh-merge-canonical-gate.sh --self-test` — **23/23 PASS** (17 original + 6 new:
  flat-shape BLOCK, multi-space BLOCK, pt-PR-URL BLOCK, personal-PR-URL ALLOW, `OWNER/REPO#N` BLOCK,
  `{owner}/{repo}` placeholder ALLOW). `session-start-git-freshness.sh --self-test` — 15/15 PASS
  (unchanged, confirms the WIP-pattern edit didn't regress it). `manifest-check.sh` — 124 entries, same
  3 pre-existing sessionstart-singleflight REDs, no new REDs. `gen-architecture-doc.sh --check` —
  GREEN after regenerating `doctrine/INDEX.md` + `docs/harness-architecture.md` (honest_status text
  changed). `harness-doctor.sh --self-test` — **105/105 PASS** (this worktree's base does not carry
  batch-5's doctor-check addition — that would bring the count to 107; noting explicitly per the
  reviewer's ask rather than implying a mismatch is a regression).
