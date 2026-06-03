# Plan: Plan-Lifecycle Redesign — Mechanical Closure Machine at Creation
Status: ACTIVE
Execution Mode: orchestrator
Mode: design
Backlog items absorbed: none
acceptance-exempt: true
acceptance-exempt-reason: Harness-development plan; the "user" is the maintainer and each shipped component's `--self-test` PASS is its acceptance artifact. No product UI surface exists.
tier: 3
rung: 2
architecture: coding-harness
frozen: false
prd-ref: n/a — harness-development
owner: Misha
target-completion-date: 2026-07-15

<!-- NOTE: `owner:` and `target-completion-date:` above are NEW header fields this
     very plan proposes (sub-decision 036-d). They are included here to model the
     proposed schema; today's plan-reviewer.sh does not yet check them. This is
     deliberate dogfooding, not an error. -->

## Goal

Redesign the plan lifecycle so that a plan's **closure machine is an artifact of
its creation** and **closure is automatic** — eliminating, at the structural root,
both stale ACTIVE plans and the mass acceptance-gate waivers they produce. Today
the closure target (acceptance scenarios, PASS-artifact contract) is defined — if
at all — at closure time, and the Status flip is manual; the result is plans that
ship and stay ACTIVE forever, an acceptance gate demanding artifacts that were
never structured to be producible, and waivers as the default session-end escape.

The redesign is purely mechanical (no advisory "remember to…" rules) and purely
root-cause (no auto-defer, no nag-surfacers). It implements the four locked
sub-decisions of ADR 036: (a) mandatory populated acceptance scenarios before
ACTIVE; (b) PASS-artifact contract defined at creation; (c) auto-closure on
last-task-verify + contract-artifact-present; (d) owner + target-date commitments
with a narrow commitment-breach decision moment, not auto-defer.

**This plan is design-only.** Its deliverable is the design + ADR + roadmap.
Implementation happens in subsequent sessions (R1–R8 in `## Tasks`), each gated on
Misha's authorization and small enough to ship without prompt-too-long risk.

## Scope

- IN: Design of the four mechanisms (acceptance-scenario-designer; Closure
  Contract section + validator; `plan-auto-closure.sh` + `close-plan.sh` auto-path;
  staleness commitment-breach gate); the plan-reviewer creation-time requirement
  changes; the self-test design that proves auto-closure has no false positives;
  the ordered implementation roadmap; the CLAUDE.md "What Done Means" update.
- IN: The 10-section Systems Engineering Analysis (this is a Mode: design plan).
- OUT: Any implementation of the redesign (hooks, scripts, agent files). The only
  files THIS session writes are documentation: this plan, ADR 036, the discovery,
  the DECISIONS.md index row, and the CLAUDE.md "What Done Means" edit.
- OUT: *Re-designing* Pattern 2 (acceptance-gate session-relevance = Part A;
  waiver removal = Part B). Their design lives in the prior waiver root-cause
  session + `docs/backlog.md` HARNESS-GAP-31. This plan SEQUENCES them as roadmap
  sessions R7 (Part A) and R8 (Part B) and documents the coupling — it does not
  re-design them. Both are downstream of R4 (auto-closure); Part B is also
  downstream of Part A. (Per Misha's mid-stream scope clarification 2026-05-25.)
- OUT: Changes to the `acceptance-exempt` carve-out semantics — the exemption is
  preserved exactly; it only shifts the closure target to self-tests.

## Tasks

The tasks below ARE the implementation roadmap. Each is a self-contained future
session. THIS design session checks off NONE of them. They are ordered by
dependency; each ships its component with a `--self-test` (harness-internal →
`Verification: mechanical`).

- [ ] R1. Plan-header accountability fields + creation gate. Add `owner:` and `target-completion-date:` to `plan-template.md` and as `start-plan.sh` flags; extend `plan-reviewer.sh` (new Check 14) to require both present + well-formed on `Status: ACTIVE` plans (grandfather pre-existing plans — see Assumptions). Verification: mechanical
- [ ] R2. `## Closure Contract` section + validator. Define the section format (commands / expected outputs / artifact location / done-when sentence); add it to `plan-template.md`; extend `plan-reviewer.sh` (new Check 15) requiring it populated on ACTIVE, with the `acceptance-exempt` → self-test variant. Verification: mechanical
- [ ] R3. acceptance-scenario-designer (script + agent pair). Build `acceptance-scenario-designer.sh` (deterministic scaffolding + user-observable-surface inference from Goal/Scope/Files-to-Modify) + the agent that authors concrete steps/expected-outputs; extend `plan-reviewer.sh` (new Check 16) to block ACTIVE transition for non-exempt plans whose `## Acceptance Scenarios` is unpopulated/placeholder-only. Verification: mechanical
- [ ] R4. Auto-closure. Build `plan-auto-closure.sh` (PostToolUse on plan-file checkbox-flip edits) that detects all-tasks-`[x]` + Closure-Contract-artifact-present-and-matching, then invokes the deterministic close; extend `close-plan.sh` with the Closure-Contract artifact check + an `--auto` invocation path. Heavily self-tested for no-false-positive (see `## Testing Strategy`). ALSO fix the stale comments at `close-plan.sh` lines 670–686 (flagged by systems-designer re-review 2026-05-25): they wrongly claim the bash `sed` Status-flip "triggers plan-lifecycle.sh archival (PostToolUse)" — it does not (plan-lifecycle.sh matches only Edit/Write tool events); the inline fallback is the sole archival path. Bring the comments into agreement with §8. Verification: mechanical
- [ ] R5. Staleness commitment-breach gate. Build the mechanism that detects a plan past `target-completion-date` with zero in-scope commits (sub-cause b → decision moment: renew/abandon/convert) vs. with in-scope commits (sub-cause c → continue/surface-blocker ping). NOT auto-defer. Resolve open decision §10-D1 (block vs. surface) before building. Verification: mechanical
- [ ] R6. Integration test + rule/doc finalization. End-to-end exercise: create → populate (R3) → declare contract (R2) → work → auto-close (R4); plus the staleness path (R5). Finalize/author `~/.claude/rules/plan-lifecycle.md` (or fold into `planning.md`) and sync the live mirror. Verification: mechanical
- [ ] R7. **Pattern 2 — Part A: session-relevance gate in `product-acceptance-gate.sh`.** Make the Stop gate fire only on plans RELEVANT to the current session (not every `Status: ACTIVE` plan), so it stops storming on orthogonal plans and writing per-session waivers. **Design input is the EXISTING waiver root-cause analysis — `docs/backlog.md` HARNESS-GAP-31 (`waiver-density-alarm.sh` + the 1369-waiver cross-worktree audit) and the "seven structural gaps" section — NOT re-designed here; this roadmap only SEQUENCES it.** Lands after R4/R5 so it is built against the reduced ACTIVE-plan surface those produce (see Roadmap Coupling below). Verification: mechanical
- [ ] R8. **Pattern 2 — Part B: waiver-removal cleanup (downstream / final).** After R7 (Part A) AND R4 (auto-closure) land, remove the accumulated `.claude/state/acceptance-waiver-*` files and any stale ACTIVE plans the redesign now auto-resolves. Design input is the same existing waiver root-cause analysis; sequencing only. Gated on R7 + R4 being live (confirm Part A scope with Misha first — §Questions). Verification: mechanical

### Roadmap Coupling (Pattern 1 ↔ Pattern 2; flagged dependencies on Patterns 3/4/5)

**This plan is "Pattern 1" (plan-lifecycle mechanical closure). R7/R8 are "Pattern 2"
(acceptance-gate session-relevance + waiver removal), sequenced here per Misha's
mid-stream scope clarification (2026-05-25). Pattern 2 is NOT re-designed in this
plan — its design lives in the prior waiver root-cause session + `docs/backlog.md`
HARNESS-GAP-31. Only the ordering and the coupling are made explicit:**

- **Pattern 1's auto-closure (R4) shrinks Pattern 2 Part A's input set.** The
  session-relevance gate's hardest problem is the false-positive: blocking a session
  on a plan that is genuinely orthogonal. Auto-closure removes the largest source of
  orthogonal ACTIVE plans (the "shipped-but-Status-never-flipped" sub-cause a), so by
  the time Part A is built there are materially fewer ACTIVE plans to evaluate for
  relevance → lower false-positive risk and a simpler relevance heuristic. This is
  why R7 is sequenced AFTER R4, not before.
- **Pattern 1's owner-accountability (R5) removes the "filed-never-worked" orphans**
  (sub-cause b) that Part A would otherwise have to special-case. A plan that breached
  its commitment is renewed/abandoned/converted, so it is not sitting ACTIVE-and-
  orthogonal for Part A's gate to mis-fire on.
- **Net effect:** R1–R6 (Pattern 1) reduce Pattern 2's surface area to roughly "plans
  that are genuinely in-flight," which is the set the session-relevance gate is
  actually trying to scope to. Building Part A against that reduced set is both
  lower-risk and lower-effort than building it against today's accumulating pile.
- **Pattern 2 Part B (waiver removal) is safe only after both** R4 (so no NEW waivers
  accrue from un-closed shipped plans) **and** R7 (so the gate that generates waivers
  is session-relevant). Removing waivers before those land would just let them re-accrue.

**Flagged dependencies on the parallel pattern design sessions (NOT addressed here):**
- **Pattern 3 (file lifecycle):** R4's archival relies on `close-plan.sh`'s inline
  `git mv` fallback and the existing `plan-lifecycle.sh` / `plan-status-archival-sweep.sh`
  archival primitives. If Pattern 3 redefines the plan-file archival primitive (move
  semantics, archive directory layout, or the `git mv`-vs-bash-write distinction this
  plan's §8 depends on), R4 must consume Pattern 3's primitive rather than re-implement
  it. **Flag for the Pattern 3 session: do not change the "bash file writes fire no
  PostToolUse event" invariant without coordinating — §8 of this plan depends on it.**
- **Pattern 4 (session resilience):** auto-closure's interrupted-mid-close recovery
  (§8) currently leans on `plan-status-archival-sweep.sh` (SessionStart). If Pattern 4
  introduces a general crash-recovery / resume primitive, R4's recovery path should use
  it instead of the bespoke sweep. **Flag, not a hard dependency.**
- **Pattern 5 (Dispatch coordination):** the staleness gate (R5) and the breach
  decision-moment surface to "the owner." Under Dispatch, the owner reads from a phone/
  web UI where the MC widget does not relay (per CLAUDE.md Autonomy). R5's surfacing
  medium must be Dispatch-conditional (plain text under Dispatch). **Flag for the
  Pattern 5 session: R5's owner-surface is a Dispatch-coordination touchpoint.**

## Files to Modify/Create

(Future-session targets — listed so each roadmap session has a frozen file set.
THIS session writes only the documentation files marked ✎.)

- `docs/plans/plan-lifecycle-redesign.md` — ✎ this design plan (this session)
- `docs/decisions/036-plan-lifecycle-mechanical-closure.md` — ✎ the ADR (this session)
- `docs/DECISIONS.md` — ✎ index row for ADR 036 (this session)
- `docs/discoveries/2026-05-25-plan-staleness-root-cause-chain.md` — ✎ root-cause discovery (this session)
- `adapters/claude-code/CLAUDE.md` — ✎ "What Done Means" update (this session) + future "owner/target" mention
- `adapters/claude-code/templates/plan-template.md` — R1/R2: add `owner:`, `target-completion-date:`, `## Closure Contract`
- `adapters/claude-code/scripts/start-plan.sh` — R1: add `--owner` / `--target-date` flags
- `adapters/claude-code/hooks/plan-reviewer.sh` — R1/R2/R3: Checks 14 (accountability fields), 15 (Closure Contract), 16 (populated acceptance scenarios on ACTIVE)
- `adapters/claude-code/scripts/acceptance-scenario-designer.sh` — R3: NEW generator script
- `adapters/claude-code/agents/acceptance-scenario-designer.md` — R3: NEW agent (or extend `end-user-advocate` plan-time mode)
- `adapters/claude-code/hooks/plan-auto-closure.sh` — R4: NEW PostToolUse auto-closure hook
- `adapters/claude-code/scripts/close-plan.sh` — R4: add Closure-Contract artifact check + `--auto` path
- `adapters/claude-code/hooks/plan-staleness-gate.sh` — R5: NEW commitment-breach mechanism
- `adapters/claude-code/settings.json.template` — R4/R5: wire new hooks
- `adapters/claude-code/rules/plan-lifecycle.md` — R6: NEW (or fold into `planning.md`)
- `docs/harness-architecture.md` — R1–R6: inventory updates per `harness-maintenance.md`

## In-flight scope updates

- 2026-06-03: `adapters/claude-code/hooks/product-acceptance-gate.sh` — refine `find_active_plans` to discover plans cwd-only (it was scanning stale secondary-worktree plan COPIES, surfacing dozens of spurious un-waivered ACTIVE plans on every session-end across a large multi-worktree downstream repo). This is squarely a plan-lifecycle concern: it defines which plans count as ACTIVE for the acceptance gate. Artifact aggregation across worktrees is unchanged. self-test 11/11.
- 2026-06-03: `docs/plans/plan-lifecycle-redesign.md` — this in-flight scope-update entry.

## Assumptions

- The existing `acceptance-exempt: true` carve-out and `product-acceptance-gate.sh`
  semantics remain valid and are extended, not replaced.
- `close-plan.sh`'s per-task verification + report-gen + archival machinery is
  the auto-closure backend, but is NOT drop-in reusable as-is (confirmed by reading
  it this session — `scripts/close-plan.sh`). Three caveats R4 must handle:
  (1) the `--auto` flag does not exist yet and MUST be built (the script rejects
  unknown flags with exit 2 at line 552); (2) `cmd_close` auto-pushes to origin by
  default (line 720) unless `--no-push` — auto-closure MUST pass `--no-push` (an
  unattended PostToolUse hook silently pushing to origin is an unacceptable blast
  radius); (3) `cmd_close` returns exit 2 when Status != ACTIVE (line 581) — the
  no-block PostToolUse caller must handle that exit code, not assume success.
- Status→terminal archival under auto-closure is owned by **`close-plan.sh`'s own
  inline archival fallback** (line 691), NOT by `plan-lifecycle.sh`. Rationale
  (resolved per systems-designer §8 finding): `close-plan.sh` flips Status via a
  bash `sed` write (line 676), which is NOT an Edit/Write tool call and therefore
  fires NO PostToolUse event — so `plan-lifecycle.sh` never sees it. The two
  archival paths cannot race because only one (the inline fallback) ever executes
  in the auto-closure flow. `plan-lifecycle.sh` remains the archival path for
  manual Edit-tool Status flips (the non-auto path).
- Pre-existing ACTIVE plans lack the new fields. The creation gates (R1/R2/R3)
  MUST grandfather them: enforce only on plans whose header lacks a "pre-redesign"
  marker OR created after a cutoff date. Exact grandfather mechanism is an R1
  design decision (§10-D2).
- "Part A" (acceptance-gate session-relevance, from the prior waiver root-cause
  session) exists as referenced; its precise scope is unconfirmed and must be
  confirmed before R7 (§Questions for Misha).
- A PostToolUse hook can reliably observe the checkbox-flip Edit and read the
  plan's post-edit content (confirmed — `plan-lifecycle.sh` already does exactly
  this pattern).

## Edge Cases

- **Last-task flip but artifact missing** → auto-closure must NOT fire; plan stays
  ACTIVE (the artifact is the second gate). This is the primary false-positive
  guard.
- **Artifact present but `plan_commit_sha` stale** → must NOT fire (the artifact
  describes an older plan version).
- **Artifact present, verdict FAIL** → must NOT fire.
- **Plan with zero tasks** → cannot "complete by last-task-flip"; auto-closure
  no-ops; closure only via explicit `close-plan.sh`.
- **Checkbox flip on a non-final task** → auto-closure evaluates "are ALL now
  `[x]`?"; if not, no-op.
- **Re-fire on an already-COMPLETED/archived plan** → idempotent no-op.
- **acceptance-exempt plan** → closure contract is the self-test PASS; auto-closure
  reads the structured `<slug>-evidence/*.evidence.json` set, not the acceptance
  artifact.
- **Staleness: target passed but a commit landed today** → in-progress (sub-cause
  c), ping not breach.
- **Staleness: owner field empty** (legacy plan) → grandfathered; breach gate
  skips until backfilled.
- **Generator run before Goal/Scope populated** → the script has nothing to infer
  from; it must emit "populate Goal/Scope first" rather than empty scaffolding.

## Acceptance Scenarios

(This plan is `acceptance-exempt: true` — harness-development. The closure target
is self-test PASS per component, recorded in `## Closure Contract` below. No
product runtime scenarios apply. Per `acceptance-scenarios.md`, an exempt plan may
record a single n/a entry for auditability:)

- n/a — harness-development; each roadmap component's `--self-test` is its
  acceptance artifact. The integration test (R6) is the end-to-end equivalent.

## Closure Contract

<!-- This section models sub-decision 036-b on this very plan. -->

- **Commands that run (per component, at R-session close):**
  `bash adapters/claude-code/hooks/plan-reviewer.sh --self-test` (R1/R2/R3),
  `bash adapters/claude-code/hooks/plan-auto-closure.sh --self-test` (R4),
  `bash adapters/claude-code/scripts/close-plan.sh --self-test` (R4),
  `bash adapters/claude-code/scripts/acceptance-scenario-designer.sh --self-test` (R3),
  `bash adapters/claude-code/hooks/plan-staleness-gate.sh --self-test` (R5),
  plus the R6 integration test script.
- **Expected outputs:** each `--self-test` exits 0 with "N passed, 0 failed".
- **On-disk artifact location:** structured evidence at
  `docs/plans/plan-lifecycle-redesign-evidence/<R-task-id>.evidence.json` (verdict
  PASS) per the Tranche B mechanical-evidence substrate.
- **Done when:** all of R1–R8 are task-verifier PASS AND every component's
  `--self-test` exits 0 AND the R6 integration test passes end-to-end. (THIS plan
  itself, being design-only, is "done for the design phase" when the design docs
  land and systems-designer PASSes; it stays ACTIVE through implementation.)

## Testing Strategy

Per-component `--self-test` is the verification idiom (harness-internal). The
load-bearing test design is the **auto-closure no-false-positive suite** (R4),
detailed in Systems Analysis §7. Summary of the critical R4 self-test scenarios:

- T1 all-checked + artifact-present + sha-match + PASS → **CLOSES** (true positive)
- T2 one-task-unchecked + artifact-present → **does NOT close** (primary guard)
- T3 all-checked + artifact MISSING → does NOT close
- T4 all-checked + artifact STALE sha → does NOT close
- T5 all-checked + artifact verdict FAIL → does NOT close
- T6 exempt plan: all-checked + self-test-evidence PASS → CLOSES
- T7 exempt plan: all-checked + self-test-evidence MISSING → does NOT close
- T8 zero-task plan → does NOT auto-close
- T9 non-final-task flip → no closure attempt
- T10 re-fire on COMPLETED/archived plan → idempotent no-op
- T11a thin task list (1 task, trivially-satisfiable contract) → **CLOSES**; the
  test documents that auto-closure has no runtime guard against thinness — the guard
  is creation-time (Check 15/16 + plan-time review). (ADR 036 R1 residual, made
  explicit.)
- T11b artifact matches the plan's *committed* SHA while the working tree holds the
  uncommitted final checkbox-flip → **CLOSES** (pins the §7 match basis: compare
  against `git log -1 --format=%H -- <plan-file>`, not the working tree)

R1/R2/R3 creation-gate self-tests: ACTIVE-with-fields PASS; ACTIVE-missing-field
FAIL; placeholder-acceptance-scenarios FAIL; populated PASS; exempt-plan-skips-
acceptance-but-requires-closure-contract. R5 staleness self-tests: past-target-
zero-commits → breach; past-target-with-commit → ping-not-breach; pre-target →
silent; legacy-no-owner → grandfathered-skip.

## Walking Skeleton

The thinnest end-to-end slice that proves the architecture: a single
`acceptance-exempt` plan that (1) is created via `start-plan.sh` with `owner` +
`target-date`, (2) declares a one-line `## Closure Contract` (self-test PASS), (3)
has one task that, when its checkbox flips to `[x]` with a passing
`.evidence.json` present, (4) auto-closes via `plan-auto-closure.sh` → archived.
This slice touches every layer (creation gate, contract, auto-closure, archival)
with the minimum content and is the R6 integration test's core path.

## Decisions Log

### Decision: One bundled ADR with four sub-decisions vs. four separate ADRs
- **Tier:** 2
- **Status:** proceeded with recommendation
- **Chosen:** One ADR (036) with four locked sub-decisions.
- **Alternatives:** Four ADRs (036–039). Rejected — the four decisions are one
  coherent, tightly-coupled redesign; splitting fragments the rationale. Matches
  the repo's established bundled-sub-decision pattern (ADR 015, 020).
- **Reasoning:** Coherence; single refutation criterion; one reviewable artifact.
- **Checkpoint:** N/A (design session)
- **To reverse:** Split 036 into per-decision ADRs; low cost (docs only).

### Decision: Tasks section = implementation roadmap (R1–R8), not this session's deliverables
- **Tier:** 1
- **Status:** proceeded with recommendation
- **Chosen:** The plan's `## Tasks` are the future implementation sessions.
- **Reasoning:** Misha asked the design plan to "design the redesign" and contain
  "an ordered sequence of subsequent implementation sessions." THIS session checks
  off none; future sessions check them off as they ship.

## Definition of Done

- [ ] (design phase) ADR 036 authored + indexed; discovery authored; this plan
  authored and passes plan-reviewer; CLAUDE.md "What Done Means" updated.
- [ ] (design phase) systems-designer returns PASS on this plan's 10-section
  analysis (the gate before implementation begins).
- [ ] (design phase) Misha reviews + authorizes the roadmap.
- [ ] (implementation) R1–R8 each task-verifier PASS with `--self-test` green.
- [ ] (implementation) R6 integration test passes end-to-end.
- [ ] SCRATCHPAD updated.

## Systems Engineering Analysis

### 1. Outcome (measurable user outcome, not output)

Success, measured post-implementation: (1) the count of `Status: ACTIVE` plans at
session end trends toward "only genuinely in-progress plans" rather than an
accumulating pile; (2) fresh `.claude/state/acceptance-waiver-*` files written per
week drops toward zero; (3) every plan that ships its work reaches
`Status: COMPLETED` + archive **without a manual Status flip**; (4) no plan past
its `target-completion-date` with zero in-scope commits persists ACTIVE past the
owner's next session without an explicit renew/abandon/convert. The maintainer
(the "user" here) observes: plans close themselves when done, and unworked plans
force a decision instead of rotting.

### 2. End-to-end trace with a concrete example

**Plan creation (R1–R3 active).** Misha runs
`start-plan.sh start widget-export "Add CSV export to the widget table" --owner Misha --target-date 2026-06-10`.
The scaffold lands with `owner: Misha`, `target-completion-date: 2026-06-10`,
`Status: ACTIVE`, placeholder Goal/Scope. Misha fills Goal/Scope/Tasks/Files. He
runs `acceptance-scenario-designer.sh` (R3): the script reads Files-to-Modify
(`src/app/widgets/page.tsx`, `/api/widgets/export`), infers two user-observable
surfaces (a UI button, an API endpoint), scaffolds two `### scenario` stubs, and
the agent populates concrete steps ("1. Click Export. 2. A CSV downloads with the
visible rows.") + expected outputs. Misha edits one. He writes the
`## Closure Contract`: command `playwright export.spec.ts`, expected "scenario
widget-export-happy-path PASS", artifact `.claude/state/acceptance/widget-export/`.

**Commit.** `plan-reviewer.sh` (commit-time) runs Checks 14/15/16: accountability
fields present ✓, Closure Contract populated ✓, acceptance scenarios populated
(not placeholder) ✓. Commit allowed. (Had any been missing, commit blocked with
the named gap.)

**Work + verify.** Builders ship; `task-verifier` flips checkboxes per the
existing evidence-first protocol. On flipping the LAST task to `[x]`,
`plan-auto-closure.sh` (PostToolUse) fires: reads the post-edit plan, sees all
tasks `[x]`, reads the `## Closure Contract` artifact location, finds
`.claude/state/acceptance/widget-export/<session>-<ts>.json` with verdict PASS and
matching `plan_commit_sha` → invokes `close-plan.sh close widget-export --auto`:
report generated, SCRATCHPAD updated, backlog reconciled, `Status: COMPLETED`,
`git mv` to `docs/plans/archive/widget-export.md`. No human flipped Status.

**Staleness path (R5).** A different plan `foo` was filed 2026-06-01,
`target-completion-date: 2026-06-15`, never worked. On the owner's first session
after 2026-06-15, `plan-staleness-gate.sh` detects: target passed AND
`git log --oneline -- <foo's files-to-modify>` shows zero commits since creation →
**breach** → surfaces the decision moment: "Plan `foo` breached its
2026-06-15 commitment with no work started. Renew (new target) / abandon /
convert to backlog." The owner picks one; the chosen action clears the breach. No
auto-defer occurred.

### 3. Interface contracts between components

| Producer | Consumer | Contract |
|---|---|---|
| `start-plan.sh` | plan file header | Emits `owner:` + `target-completion-date: YYYY-MM-DD` fields (R1). |
| `acceptance-scenario-designer.sh` | `## Acceptance Scenarios` section | Writes ≥1 `### <slug>` stub per inferred surface, each with `**User flow:**` numbered steps + `**Success criteria:**` (R3 agent fills concrete content). |
| plan author | `## Closure Contract` | Declares commands / expected outputs / artifact on-disk path / done-when sentence (R2 format). |
| `plan-reviewer.sh` (Checks 14/15/16) | commit | Blocks commit of an ACTIVE plan missing accountability fields, Closure Contract, or populated acceptance scenarios (non-exempt). |
| `task-verifier` | plan file | Flips the final checkbox `[ ]`→`[x]` via evidence-first protocol (unchanged). |
| `plan-auto-closure.sh` | `close-plan.sh` | On all-`[x]` + contract-artifact-present-and-matching, invokes `close-plan.sh close <slug> --auto --no-push`. Always passes `--no-push` (no unattended origin push from a PostToolUse hook). PostToolUse cannot block, so the hook is fire-and-annotate: if `close-plan.sh` returns non-zero (e.g. exit 2 for Status != ACTIVE, or a verification HOLD), the hook logs the named HOLD reason to stderr and no-ops — the plan stays ACTIVE, nothing is half-closed. |
| `close-plan.sh --auto` | plan file + archive | `--auto` behavioral delta from a manual close: (1) ADDS the `## Closure Contract` artifact check as a precondition the manual close does not require (manual close trusts the operator; auto close must independently confirm the contract artifact exists with verdict PASS and a matching plan SHA — see §7 for the match basis); (2) fully non-interactive (no prompts); (3) implies `--no-push` is honored. On success: verifies per-task evidence + Closure-Contract artifact, generates report, flips Status via inline `sed`, archives via its OWN inline fallback (NOT `plan-lifecycle.sh` — see Assumptions). Exit-code contract: 0 = closed; 2 = HOLD (precondition unmet) with the reason on stderr; the caller treats any non-zero as "leave ACTIVE." |
| `plan-staleness-gate.sh` | owner (session surface) | On past-target + zero-in-scope-commits → breach decision moment; on past-target + commits → ping. Reads `target-completion-date`, `owner`, and `git log` over Files-to-Modify. |

### 4. Environment & execution context

All components run inside Claude Code sessions on the maintainer's machine (Git
Bash on Windows; also Linux/macOS). Hooks fire from `~/.claude/hooks/` (live
mirror of `adapters/claude-code/hooks/`). `plan-reviewer.sh` runs at commit-time
via `pre-commit-gate.sh`. `plan-auto-closure.sh` is PostToolUse on Edit/Write
(same trigger surface as `plan-lifecycle.sh`). `plan-staleness-gate.sh` is
SessionStart (reads ACTIVE plans + `git log`). All have `jq` available (degraded
no-jq fallback per existing hook convention). Ephemeral: nothing — all state is in
the repo (`docs/plans/`, `.claude/state/`). The two-layer config discipline
applies: every `adapters/claude-code/` change is mirrored to `~/.claude/` and
verified byte-identical.

### 5. Authentication & authorization map

No external auth boundaries — **conditional on auto-closure passing `--no-push`**
(without it, `close-plan.sh`'s default `git push origin <branch>` would make an
unattended push the one external boundary; the design suppresses it). The only
"authorization" surfaces are internal: (1) `plan-edit-validator.sh` already
authorizes checkbox flips (only task-verifier with fresh evidence) — auto-closure
runs DOWNSTREAM of an already-authorized flip, so it inherits that authorization
and adds no new write authority of its own beyond the Status flip + archive, which
`close-plan.sh` already performs; (2) the staleness gate's renew/abandon/convert
actions are owner-initiated (the human), not auto-applied. No tokens, no quotas,
no rate limits.

### 6. Observability plan (built before the feature)

- `plan-auto-closure.sh` emits to stderr on every fire: `[auto-closure] plan
  <slug>: tasks N/N checked; contract artifact <found|missing|stale|fail>;
  decision <CLOSE|HOLD>`. The HOLD reason is always named (which guard tripped) so
  a non-closing plan is diagnosable from the transcript alone.
- `close-plan.sh --auto` reuses its existing per-step stderr (`[close-plan] …`).
- `plan-staleness-gate.sh` emits per ACTIVE plan: `[staleness] <slug>:
  target=<date> commits-in-scope=<n> verdict <SILENT|PING|BREACH>`.
- `plan-reviewer.sh` Checks 14/15/16 emit the named gap on block (existing
  `add_finding` convention).
- Reconstruct-from-logs test: from stderr alone one can determine, for any plan,
  why it did or did not auto-close and whether it is in breach.

### 7. Failure-mode analysis per step

| Step | Failure mode | Observable symptom | Recovery / policy | Escalation |
|---|---|---|---|---|
| Auto-closure trigger | Fires on a non-final flip | premature CLOSE | T9 self-test guards: only fires when ALL `[x]` | block ship if T9 red |
| Auto-closure trigger | Closes with artifact missing | unfinished plan archived | T2/T3 guards: artifact must exist | block ship if T2/T3 red |
| Auto-closure trigger | Closes on stale sha / FAIL verdict | wrong-version closure | T4/T5 guards | block ship |
| Auto-closure trigger | Re-fires on archived plan | duplicate close / error | T10 idempotency guard | n/a |
| Auto-closure trigger | SHA match basis ambiguous at fire time | false HOLD or false CLOSE | **Match basis is PINNED (resolving systems-designer §7 finding): the artifact's `plan_commit_sha` is compared against the plan file's last-commit SHA — `git log -1 --format=%H -- <plan-file>` — NOT the working tree.** The triggering checkbox-flip Edit is uncommitted at fire time, so the working tree differs from the committed plan; comparing against the committed SHA is correct because the PASS artifact was written against the committed plan version, and the final `[ ]→[x]` flip changes only task state, not the acceptance scenarios the artifact verified. Add T-scenario T11b (artifact matches committed SHA, working tree has uncommitted final flip → CLOSES). | block ship if T11b red |
| Closure Contract | Artifact path typo in contract | plan never auto-closes (HOLD forever) | **Two real recovery paths (NOT the staleness gate — corrected per §7 finding, since a worked plan has in-scope commits and §10-D1 makes that a PING-not-BREACH that may be non-blocking): (1) Check 15 validates the declared artifact path is well-formed at commit time, catching most typos at creation; (2) `plan-auto-closure.sh` emits the `artifact missing` HOLD reason to stderr on EVERY checkbox-related edit, so the owner sees it in-session and fixes the path.** | in-session HOLD log |
| acceptance-scenario-designer | Script run pre-Goal | empty scaffolding | script emits "populate Goal/Scope first", exits non-zero | n/a |
| acceptance-scenario-designer | Agent skipped | scenarios unpopulated | Check 16 blocks ACTIVE commit | author runs agent |
| Staleness gate | Fires on legacy no-owner plan | spurious breach | grandfather guard: skip when owner empty | backfill owner |
| Staleness gate | Too broad → waiver-bait | new waiver flood | narrowness (target-passed + zero-commits) + owner-scope; §10-D1 block-vs-surface decision | revisit if waivers reappear |
| Creation gates | Block legacy ACTIVE plans on next edit | edit churn blocked | grandfather guard (§10-D2) | one-time backfill |
| Auto-closure | Thin task list "completes" prematurely (ADR 036 R1 residual) | a 1-task plan with a trivially-satisfiable contract auto-closes | **ACCEPTED residual — runtime auto-closure cannot detect a thin-but-satisfied contract; this is NOT guarded at runtime. The only guard is creation-time substance review: Check 16 (acceptance-scenario substance) + Check 15 (Closure-Contract substance) + the systems-designer/end-user-advocate plan-time review reject thin contracts before ACTIVE.** Documented test: T11a (single-task plan, trivially-satisfiable contract → auto-closure WILL close; the test asserts the close happens AND documents that the guard is upstream at creation, not here). | creation-time review |

### 8. Idempotency & restart semantics

- `plan-auto-closure.sh`: idempotent. If it already closed the plan (now
  `Status: COMPLETED` / archived), a re-fire detects terminal status and no-ops
  (T10). If interrupted between Status-flip and archive, the existing
  `plan-status-archival-sweep.sh` SessionStart safety net completes the archive on
  next session — the post-condition is restored without re-running auto-closure.
- **Trigger cascade (resolved per systems-designer §8 finding).** `plan-auto-closure.sh`
  fires on the task-verifier checkbox-flip *Edit tool* call (a real PostToolUse
  event). It then invokes `close-plan.sh` via **Bash**. Every write `close-plan.sh`
  performs — the `sed` Status flip (line 676) and the `git mv` archival (line 691) —
  is a **bash file operation, NOT an Edit/Write tool call, so it fires NO
  PostToolUse event.** Consequences: (1) `plan-auto-closure.sh` does NOT recurse
  (close-plan's writes don't re-trigger it); (2) `plan-lifecycle.sh` does NOT fire
  on close-plan's Status flip (it's a PostToolUse hook; no tool event occurs) — so
  there is **exactly one archival path under auto-closure (close-plan.sh's inline
  fallback) and no double-archive race.** `plan-lifecycle.sh` only archives the
  separate, manual case where a human flips Status via the Edit tool.
- `close-plan.sh --auto`: already idempotent (its archival fallback checks whether
  the file is still under `docs/plans/`).
- `plan-staleness-gate.sh`: read-only per session (surfaces a decision; does not
  mutate). Re-running re-surfaces until the owner acts. Safe.
- Creation gates: pure validators (no state mutation); restart-safe.

### 9. Load / capacity model

Bottleneck: number of ACTIVE plans scanned per SessionStart (staleness gate) and
per commit (plan-reviewer). Current repo has ~4 ACTIVE plans; even at 10× that the
per-session cost is a handful of `git log` invocations over small file sets —
sub-second. Auto-closure fires only on plan-file checkbox-flip Edits (rare events,
not every tool call), so it adds no per-tool-call overhead. No saturation concern
at realistic scale (tens of plans). If ACTIVE plans ever exceeded ~100 the
staleness scan would warrant a cached index, but that is far beyond observed load
and explicitly out of scope.

### 10. Decision records & runbook

**Open decisions to resolve before the relevant R-session builds:**

- **§10-D1 (R5): Does the staleness commitment-breach gate BLOCK or
  surface-without-blocking — and how does it avoid becoming a new waiver source?**

  *The waiver-source risk turns entirely on what artifact SATISFIES the gate.* The
  acceptance-waiver flood happened because the satisfying artifact was a **one-shot
  free-text file** (`.claude/state/acceptance-waiver-<slug>-*.txt`) that (i) did not
  change the plan's state, (ii) was never re-checked, and (iii) cost one sentence to
  write. That is the waiver shape: a write-once escape that buys silence without
  altering reality.

  The commitment-breach gate is designed so its **only** satisfying artifacts are
  **falsifiable structural commitments**, each a plan-header/state change that the
  gate RE-CHECKS mechanically every subsequent session, with a git audit trail:
  - **Renew** = edit `target-completion-date:` to a new future date in the plan
    header. Next session the gate re-evaluates against the new date; if that date
    also passes with no progress, it breaches AGAIN. A renewed date is a new
    falsifiable promise, not an escape.
  - **Abandon** = flip `Status: ABANDONED` (triggers archival; the plan leaves the
    ACTIVE set entirely).
  - **Convert** = flip `Status: SUPERSEDED` + return the absorbed items to the
    backlog (the work is preserved and re-tracked, not buried).

  None of these is a free-text file; each is a state change the gate can verify on
  sight, so none is waiver-shaped. There is deliberately **no free-text-waiver
  escape** for this gate (unlike `product-acceptance-gate.sh`).

  *Recommendation (now decidable):* **BLOCK** the owner's session end on a BREACH
  (target passed, zero in-scope commits) until the plan header reflects one of the
  three structural decisions above. Blocking is acceptable HERE — where it would not
  be for a free-text waiver — precisely because "satisfy the block" means "make a
  falsifiable commitment," not "write an escape sentence." A PING (target passed,
  in-scope commits present → sub-cause c) is NON-blocking: it surfaces "overdue,
  continue or surface the blocker" without demanding a header edit, because work IS
  happening. This makes the gate narrow (BREACH only) and structural (header-edit
  satisfaction only). **Misha's call to ratify: confirm BLOCK-on-breach with
  structural-satisfaction-only, vs. a softer surface-only first pass.** Either way,
  the no-free-text-waiver property is the load-bearing decision and is recommended
  regardless.
- **§10-D2 (R1): Grandfather mechanism for pre-existing ACTIVE plans.** Options:
  (i) enforce new gates only on plans whose header was created after a cutoff
  marker; (ii) one-time backfill of `owner`/`target-date`/`Closure Contract` into
  current ACTIVE plans; (iii) enforce only on the ACTIVE *transition* so existing
  ACTIVE plans are never re-validated. *Recommendation:* (iii) + a one-time
  backfill pass for the handful of current ACTIVE plans. **Needs Misha.**
- **§10-D3 (R3): New `acceptance-scenario-designer` agent vs. extend
  `end-user-advocate` plan-time mode.** The latter already authors scenarios.
  *Recommendation:* extend `end-user-advocate` (it already owns plan-time scenario
  authoring); the new script does the deterministic scaffolding/inference and
  hands off. Avoids a redundant agent. **Confirm with Misha.**

**Runbook (post-implementation):**
- *Symptom: a finished plan didn't auto-close.* Check `plan-auto-closure.sh`
  stderr for the HOLD reason (unchecked task / artifact missing|stale|fail).
  Fix the named gap; the next checkbox-related edit re-fires, or run
  `close-plan.sh close <slug>` manually.
- *Symptom: a plan auto-closed prematurely.* This is a T1–T10 guard failure —
  treat as a P0 harness bug; `git mv` the plan back, re-flip Status, file a finding.
- *Symptom: staleness breach fired on an actively-worked plan.* The in-scope-commit
  detection mis-scoped (Files-to-Modify glob). Widen the scope detection; this is
  the sub-cause-b/c discriminator.

## Pre-Submission Audit

S1 (Entry-Point Surfacing): swept — every behavior change in §1–§10 is cited in a
`## Tasks` R-entry and a `## Files to Modify/Create` line (R1↔accountability fields,
R2↔Closure Contract, R3↔scenario designer, R4↔auto-closure, R5↔staleness); 0
stranded.
S2 (Existing-Code-Claim Verification): swept against the files read this session.
Verified accurate: `plan-lifecycle.sh` (PostToolUse archival on Status→terminal,
fires only on Edit/Write tool events — line 568–571); `plan-reviewer.sh`
(commit-time via `pre-commit-gate.sh` line 58–67, Check 6b 7 required sections);
`start-plan.sh` (scaffolds header, leaves body placeholder); `product-acceptance-
gate.sh` (Stop position 4). **`close-plan.sh` reuse claim corrected (per
systems-designer cross-cutting finding) — it is NOT drop-in reusable; three
verified caveats now stated in Assumptions: (1) `--auto` does NOT exist (line 552
rejects unknown flags, R4 must build it); (2) `cmd_close` auto-pushes by default
(line 720) → auto-closure must pass `--no-push`; (3) Status!=ACTIVE returns exit 2
(line 581) → the no-block PostToolUse caller must handle that exit code.** The Status
flip (line 676) + archival (line 691) are bash writes, NOT tool events — confirmed,
and load-bearing for the §8 no-double-archive analysis.
S3 (Cross-Section Consistency): swept — "auto-closure reuses close-plan.sh / does
not duplicate archival" is consistent across §2/§3/§7/§8; "acceptance-exempt
preserved, target shifts to self-test" consistent across Goal/Scope/036-a/Closure
Contract; 0 contradictions.
S4 (Numeric-Parameter Sweep): swept for params [~4 current ACTIVE plans, 10× scale,
~100-plan ceiling, 10 R4 self-test scenarios T1–T10 (+T11a/T11b), 8 roadmap sessions
R1–R8]; all values consistent across §9, Testing Strategy, and Tasks.
S5 (Scope-vs-Analysis Check): swept — every "Add/Build/Extend" verb in §1–§10
targets a file in `## Files to Modify/Create`; no prescription targets a Scope-OUT
file (Pattern 2 = R7 Part A / R8 Part B are sequencing-only roadmap entries
referencing existing analysis, not re-design; re-designing Pattern 2 is Scope-OUT;
no code shipped this session per Scope OUT).
