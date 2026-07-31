<!-- scaffold-created: 2026-07-12T23:36:21Z by start-plan.sh slug=vaporware-config-controls -->
# Plan: Vaporware Config Controls
Status: COMPLETED
Execution Mode: orchestrator
Mode: code
Backlog items absorbed: none
acceptance-exempt: true
acceptance-exempt-reason: Harness-development plan with no product user; the deliverable is doctrine/agent-remit/catalog text whose closure target is mechanical greps + manifest-check + harness-reviewer PASS.
tier: 2
rung: 1
architecture: coding-harness
frozen: true
lifecycle-schema: v2
owner: misha
target-completion-date: 2026-07-13
prd-ref: n/a — harness-development
ask-id: none — no linked ask

<!--
Origin: HARNESS-GAP-45 (docs/backlog.md, added 2026-06-03, priority:high),
operator-scheduled via the 2026-07-12 digest escalation ("schedule" reply,
39d undisposed). Backlog row is marked "disposition: SCHEDULED ->
docs/plans/vaporware-config-controls.md" rather than absorbed-and-deleted —
the operator's dispatch instruction prescribed the SCHEDULED disposition
marker, so the row remains the tracking record until this plan completes
(see Decisions Log D-1).
-->

## Goal

The anti-vaporware policy catches dead UI and unbuilt features but NOT decorative
config controls: toggles, flags, settings, and permission matrix cells that render
as configurable while hardcoded logic (or nothing) actually governs behavior. The
originating case: a downstream product's per-org permissions matrix had 6 of 16
toggles decorative — they rendered, persisted, and did nothing, because hardcoded
role checks governed the behavior. The actions worked and were access-controlled;
the RBAC admin surface lied. No standing invariant asserts that a registry entry
(permission / feature-flag / event-type) is actually wired to enforcement.

This plan makes "decorative config control" a NAMED, CHECKED vaporware class across
the whole prevention surface: the vaporware doctrine (compact + new full companion
carrying the generalizable registry-vs-callsite invariant pattern), the
FUNCTIONALITY-OVER-COMPONENTS clause in planning doctrine, the functionality-verifier
rubric (the checked path — it fires inside the blocking runtime-verification Stop
chain), the functionality-auditor remit (the standing-surface audit path), the
failure-mode catalog (FM-038), and the enforcement inventory (manifest.json row).

## User-facing Outcome

n/a — harness-internal: the user is the maintainer. After this plan ships, a
builder shipping a toggle that renders but does not change behavior is caught by
name: the functionality-verifier rubric instructs "exercise both/all values of the
control and observe the governed surface" as a first-class task class (not a buried
bullet), the auditor sweeps capability registries for decorative entries, planning
doctrine defines a configurable control's done-criterion as "changing it provably
changes observable behavior," and FM-038 gives the class a citable name. The
demonstration is mechanical: greps confirming each surface names the class,
compact byte-caps respected, manifest-check green, harness-reviewer PASS.

## Scope

- IN: `adapters/claude-code/doctrine/vaporware-prevention.md` (name the class,
  stay ≤3000 bytes); NEW `adapters/claude-code/doctrine/vaporware-prevention-full.md`
  (registry-vs-callsite invariant pattern — the "larger piece" from the backlog row);
  `adapters/claude-code/doctrine/planning.md` + `planning-full.md`
  (FUNCTIONALITY-OVER-COMPONENTS config-control clause);
  `adapters/claude-code/agents/functionality-verifier.md` (config-control task class:
  trigger + class-table row + protocol); `adapters/claude-code/agents/functionality-auditor.md`
  (registry-vs-callsite sweep discipline); `docs/failure-modes.md` (FM-038);
  `adapters/claude-code/manifest.json` (new `vaporware-config-control` pattern row)
  + regenerated `adapters/claude-code/doctrine/INDEX.md`; harness-reviewer review
  before landing.
- OUT: any new hook or blocking gate (constitution §10 requires golden scenario +
  FP rate + retirement condition; the class is checkable through the EXISTING
  blocking chain — task-verifier → functionality-verifier inside the
  runtime-verification Stop gate — so no new mechanism is justified; see D-2);
  changes to `vaporware-volume-gate.sh` (retired to CI, content-volume check,
  wrong axis for this class); changes to `runtime-verification-executor/reviewer.sh`
  (they replay declared scenarios; the fix is that scenarios/rubrics now DECLARE
  config-control exercise); the downstream product's own `check-permission-drift.ts`
  (project-level instance, tracked under that product's #437, not harness scope);
  JIT trigger paths for the vaporware doctrine row (path-based triggers cannot
  reliably signal "session is building a config control" in arbitrary product
  repos — over-fire risk; see D-3).

## Tasks

- [x] 1. Name the config-control vaporware class in `adapters/claude-code/doctrine/vaporware-prevention.md`: add a "Decorative config control" clause (a control that renders/persists but provably changes no behavior is vaporware; done-criterion = changing it changes observable behavior at the governed surface; shadow-mode never flipped to enforce = still vaporware) + a pattern-recognition bullet ("the toggle renders and saves, so the permission works") + pointer to the -full companion for the registry-vs-callsite invariant. File must stay ≤3000 bytes. — Verification: mechanical — Docs impact: the doctrine edit IS the doc delta.
- [x] 2. Create `adapters/claude-code/doctrine/vaporware-prevention-full.md` (companion, precedent: frontend-conventions-full / observability-full): the generalizable registry-vs-callsite invariant pattern — definition (any code maintaining a capability registry + a separate UI to configure entries must have a check that every entry is wired to enforcement), the originating 6-of-16 decorative-toggles case (product name scrubbed per harness-hygiene), how to instantiate a project-level mechanical drift check (fail on any registry ID with no enforce-mode call site), shadow-mode rollout guidance (a legitimate state that must carry an expiry/flip obligation), and cross-refs (FM-038, functionality-verifier config-control protocol, functionality-auditor sweep). — Verification: mechanical — Docs impact: new doctrine file, linked from the compact.
- [x] 3. Add the config-control clause to FUNCTIONALITY-OVER-COMPONENTS: one sentence in `adapters/claude-code/doctrine/planning.md` (bullet at ~line 5; file stays ≤3000 bytes) and a short sub-section in `adapters/claude-code/doctrine/planning-full.md` under the FUNCTIONALITY OVER COMPONENTS heading — a configurable control (permission toggle, feature flag, setting, dropdown) is done only when changing it is PROVEN to change observable behavior; rendering ≠ done; wired-to-shadow-mode ≠ done. — Verification: mechanical — Docs impact: the doctrine edits ARE the doc delta.
- [x] 4. Extend `adapters/claude-code/agents/functionality-verifier.md` with config-control as a first-class checked class: (a) invocation-trigger bullet ("a configurable control — toggle, flag, setting, permission cell — whose task claims it governs behavior"), (b) a Config-control row in the task-class table, (c) a "Config-control protocol" section (exercise ≥2 values of the control; observe the GOVERNED surface, not the settings page; a persisted-but-behavior-identical toggle is FAIL; shadow-mode is FAIL unless the task explicitly declares shadow-mode as scope), (d) cross-ref FM-038. Keep the existing Counter-Incentive bullet (line ~147) — the protocol operationalizes it. — Verification: mechanical — Docs impact: agent remit doc updated in place.
- [x] 5. Extend `adapters/claude-code/agents/functionality-auditor.md` with the registry-vs-callsite sweep: in Phase 1 (element inventory), when the audited surface includes a capability registry (permission list, flag list, event-type registry) with a config UI, enumerate EVERY registry entry and trace each to an enforce-mode call site; a registry entry with no enforcement consumer is a decorative config control (severity: silent-wrong-outcome — the worst class, already Framework 6 rank 1); recommend the project instantiate the registry-vs-callsite drift check from vaporware-prevention-full.md. — Verification: mechanical — Docs impact: agent remit doc updated in place.
- [x] 6. Add FM-038 `vaporware-config-control` to `docs/failure-modes.md` (Symptom / Root cause / Detection / Prevention / Example per catalog format; Example = the scrubbed 6-of-16 permissions-matrix case; Prevention cites the surfaces landed by tasks 1-5 + the manifest row from task 7). — Verification: mechanical — Docs impact: catalog entry IS the doc delta.
- [x] 7. Add a `vaporware-config-control` row to `adapters/claude-code/manifest.json` (kind: pattern, doctrine_file: doctrine/vaporware-prevention.md, hooks: [], blocking: false, honest_status naming the real enforcement path: "pattern — checked via functionality-verifier's config-control protocol inside the runtime-verification Stop chain on Verification: full tasks; standing surfaces via functionality-auditor sweep; no dedicated hook by design, see plan D-2") and regenerate `doctrine/INDEX.md` via the manifest generator; `manifest-check.sh` must pass. — Verification: mechanical — Docs impact: INDEX.md regenerated from manifest.
- [x] 8. harness-reviewer adversarial review of the full diff (mandatory before landing any rule/agent change); address every Critical/Major finding; record verdict + findings disposition in this plan. — Verification: mechanical — Docs impact: none — review step, findings land in this plan file.

## Files to Modify/Create

- `adapters/claude-code/doctrine/vaporware-prevention.md` — name the decorative-config-control class (≤3000B)
- `adapters/claude-code/doctrine/vaporware-prevention-full.md` — NEW: registry-vs-callsite invariant pattern detail
- `adapters/claude-code/doctrine/planning.md` — FUNCTIONALITY-OVER-COMPONENTS config-control clause (≤3000B)
- `adapters/claude-code/doctrine/planning-full.md` — same clause, full-prose section
- `adapters/claude-code/agents/functionality-verifier.md` — config-control task class: trigger, table row, protocol, FM-038 xref
- `adapters/claude-code/agents/functionality-auditor.md` — registry-vs-callsite sweep in Phase 1 + recommendation hook
- `docs/failure-modes.md` — FM-038 vaporware-config-control
- `adapters/claude-code/manifest.json` — vaporware-config-control pattern row
- `adapters/claude-code/doctrine/INDEX.md` — regenerated from manifest
- `docs/backlog.md` — HARNESS-GAP-45 row disposition marker (kickoff commit)
- `docs/plans/vaporware-config-controls.md` — this plan
- `docs/decisions/queued-vaporware-config-controls.md` — scaffolded decision queue

## In-flight scope updates

- 2026-07-12: `adapters/claude-code/agents/task-verifier.md` — harness-reviewer Finding 3 (Major): the caller's normative class list at :155 omitted Config-control; one-line enumeration fix so task-verifier routes config-control tasks to functionality-verifier dispatch.

## Review record (task 8)

- **harness-reviewer round 1 (agent aa2460edec78938df): REFORMULATE** — 1 Critical, 2 Major, 1 Minor, all PROVEN. Dispositions:
  - **F1 Critical (enforcement theater):** landed text claimed the class is checked "inside the blocking runtime-verification Stop chain" — that chain is dead wiring since Wave D.5 (pre-stop-verifier.sh is an exit-0 shim; no live invoker of runtime-verification-executor/reviewer). FIXED: reworded to the true path (functionality-verifier dispatched by task-verifier pre-flip; backstops plan-edit-validator.sh PreToolUse + work-integrity via stop-verdict-dispatcher.sh Stop) in manifest.json row, FM-038 Detection, vaporware-prevention-full.md; INDEX regenerated. Sweep `runtime-verification Stop chain` → 0 hits.
  - **F2 Major (pre-existing stale inventory):** planning.md:2 Enforcement header named the retired shim — FIXED (stop-verdict-dispatcher.sh). The upstream `runtime-verification` manifest row's stale honest_status + the 22-retired-shims sweep class: FILED via nl-issue.sh (out of this plan's scope; row is load-bearing ADR 059 D2 — re-wiring is its own scoped decision per reviewer).
  - **F3 Major (stale class enumerations):** Config-control added to task-verifier.md:155 parenthetical, verifier frontmatter description, escalation list, and dependency-order line. Sweep `UI / API / AI / Data)` → 0 hits.
  - **F4 Minor (pointer to superseded section):** planning.md mid-build-decisions pointer → "(constitution §8)". FIXED.
  - planning.md re-trimmed to 2998 bytes after the header fix (cap 3000).
- **harness-reviewer round 2 (same agent, re-verified at cf35399): PASS — no remaining findings.** All four dispositions independently re-verified with its own commands: F1 sweep 0 hits and the replacement wording confirmed true at runtime on all three legs (task-verifier pre-flip dispatch per task-verifier.md:153-166; plan-edit-validator.sh blocking PreToolUse; work-integrity-gate via stop-verdict-dispatcher.sh at Stop); F2 planning.md:2 true-at-runtime + nl-issues.jsonl line 49 confirmed; F3 all four enumerations present, sweep 0 hits; F4 verified. Byte caps hold (2401/2998); manifest-check GREEN 113; INDEX regen drift-free.

## Assumptions

- The 3000-byte compact authoring cap (Wave C.4; cited in doctrine-jit.sh header and the 9b60475 frontend-conventions split precedent) applies to `vaporware-prevention.md` and `planning.md`; the -full companion carries unbounded detail.
- `manifest-check.sh` (or the doctor's manifest check) validates entry shape and regenerates `doctrine/INDEX.md`; a `kind: pattern` row with empty hooks and `blocking: false` is valid (precedent: `observability`, `waiver-density-alarm` rows).
- Two manifest entries may share one `doctrine_file` (precedent: `runtime-verification` + `vaporware-volume` both point at vaporware-prevention.md).
- No hook file changes ⇒ no `--self-test` obligations beyond leaving existing suites untouched; the dispatch instruction's "--self-test where a hook changes" clause is satisfied vacuously (verified by the diff containing no `hooks/*.sh`).
- The existing blocking chain (task-verifier → functionality-verifier within runtime-verification, Stop event, blocking: true per manifest.json:1504-1524) is the enforcement path for the new class on future `Verification: full` tasks; this plan's own tasks are all doc-surface mechanical.
- Live-mirror sync (`~/.claude/doctrine/`, `~/.claude/agents/`) happens via merge-to-master + session-start-auto-install; this plan does not hand-edit `~/.claude/`.

## Edge Cases

- **Compact overflows 3000 bytes after the edit** → move prose to the -full companion, keep only the class name + one-line criterion + pointer in the compact (the frontend-conventions precedent).
- **Legitimate shadow-mode rollout** — a control intentionally wired to log-only during rollout is NOT vaporware while the rollout is declared and time-bounded; the doctrine text must carve this out explicitly (shadow-mode with no flip obligation = vaporware; declared shadow-mode with expiry = legitimate) so the class doesn't false-positive every staged rollout.
- **Controls that legitimately change nothing observable for some values** (e.g., a threshold setting where two test values fall in the same bucket) — the verifier protocol must say "choose values that the spec claims produce DIFFERENT behavior," not "any two values."
- **INDEX.md regeneration reordering** — regen may reflow unrelated rows; commit the INDEX delta as generated, do not hand-edit.
- **Auditor false-DEAD risk** — the registry sweep must inherit the agent's existing soundness asymmetry (a registry entry consumed via string-keyed dispatch looks decorative to naive grep); the sweep text must route through the existing indirect-consumption checklist before any decorative verdict.

## Acceptance Scenarios

n/a — acceptance-exempt harness-development plan (no product user); closure via mechanical checks + harness-reviewer PASS, see Closure Contract.

## Out-of-scope scenarios

None — all advocate-proposed scenarios are in scope above (acceptance-exempt; no advocate pass runs).

## Closure Contract

- **Commands that run:** named-class greps + byte caps + manifest-check + empty hook diff, itemized below:
  - `grep -Eci "config[- ]control|configurable control" adapters/claude-code/doctrine/vaporware-prevention.md` (≥1) and equivalent named-class greps on planning.md, planning-full.md, functionality-verifier.md, functionality-auditor.md, docs/failure-modes.md (FM-038), manifest.json (vaporware-config-control)
  - `wc -c adapters/claude-code/doctrine/vaporware-prevention.md adapters/claude-code/doctrine/planning.md` (each ≤3000)
  - `bash adapters/claude-code/scripts/manifest-check.sh` (or doctor quick manifest check)
  - `git diff --name-only <base>..HEAD -- 'adapters/claude-code/hooks/'` (empty — no hook changes)
- **Expected outputs:** every grep ≥1 hit; both compacts ≤3000 bytes; manifest-check PASS/exit 0; empty hook diff; harness-reviewer verdict PASS (or PASS after Critical/Major fixes) recorded in this plan.
- **On-disk artifact location:** `docs/plans/vaporware-config-controls-evidence/<task-id>.evidence.json` (write-evidence.sh capture, one per task).
- **Done when:** all 8 tasks are task-verifier PASS with evidence artifacts on disk AND the harness-reviewer PASS verdict is recorded in this plan AND Status flips to COMPLETED.

## Testing Strategy

- Tasks 1-6: `Verification: mechanical` — grep-based named-class presence checks + byte-cap `wc -c` + (task 2) file-exists + cross-ref greps, captured as `.evidence.json` via `write-evidence.sh capture`.
- Task 7: `bash adapters/claude-code/scripts/manifest-check.sh` exit 0 + `jq -e '.entries[] | select(.id=="vaporware-config-control")' adapters/claude-code/manifest.json` + regenerated INDEX contains the row.
- Task 8: harness-reviewer dispatch on the full diff; PASS or findings-addressed-then-PASS recorded here.
- No hook is modified, so no `--self-test` runs are owed; the closure contract's empty-hook-diff check proves the vacuous satisfaction.

## Walking Skeleton

Walking Skeleton: n/a — doctrine/agent-remit/catalog extension with no runtime flow; the class-naming lands in the compact first (task 1) and every other surface cross-references it.

## Decisions Log

- **D-1 (2026-07-12, reversible):** Backlog row HARNESS-GAP-45 gets a `disposition: SCHEDULED → docs/plans/vaporware-config-controls.md` marker instead of absorb-and-delete. The operator's dispatch instruction prescribed the SCHEDULED marker explicitly; `Backlog items absorbed: none` keeps `backlog-plan-atomicity.sh` out of play. On COMPLETION the row is updated to dispositioned-done with the completion SHA. Undo = one edit.
- **D-2 (2026-07-12, reversible):** No new hook/gate. Constitution §10 requires a golden scenario + expected FP rate + retirement condition for any new blocking gate; the decorative-control class is enforceable through the EXISTING blocking chain (functionality-verifier fires inside runtime-verification, Stop, blocking:true) once the rubric names the class — a new gate would duplicate that path with real FP risk (e.g., blocking on every settings-page edit). The manifest row (task 7) makes the pattern's enforcement path honest and discoverable instead. Undo = author a gate later under §10 if the pattern proves insufficient (retirement/escalation condition: a decorative control ships past a `Verification: full` task-verifier PASS after this plan lands — that recurrence is the golden scenario a future gate would be built on).
- **D-3 (2026-07-12, reversible):** No JIT trigger paths added to the vaporware doctrine rows. doctrine-jit.sh matches file PATHS only (keywords are reserved/unmatched in v1); no path pattern reliably means "editing a config control" across arbitrary product repos (`settings`/`flags`/`permissions` substrings over-fire on unrelated files). Undo = add paths later if a concrete recurring path shape emerges.

## Definition of Done

- [ ] All tasks checked off (task-verifier only)
- [ ] Closure Contract commands green
- [ ] harness-reviewer PASS recorded
- [ ] SCRATCHPAD.md updated with final state
- [ ] Completion report appended to this plan file

## Completion Report

_Generated by close-plan.sh on 2026-07-13T01:11:08Z._

### 1. Implementation Summary

Plan: `docs/plans/vaporware-config-controls.md` (slug: `vaporware-config-controls`).

Files touched (per plan's `## Files to Modify/Create`):

- `adapters/claude-code/agents/functionality-auditor.md`
- `adapters/claude-code/agents/functionality-verifier.md`
- `adapters/claude-code/doctrine/INDEX.md`
- `adapters/claude-code/doctrine/planning-full.md`
- `adapters/claude-code/doctrine/planning.md`
- `adapters/claude-code/doctrine/vaporware-prevention-full.md`
- `adapters/claude-code/doctrine/vaporware-prevention.md`
- `adapters/claude-code/manifest.json`
- `docs/backlog.md`
- `docs/decisions/queued-vaporware-config-controls.md`
- `docs/failure-modes.md`
- `docs/plans/vaporware-config-controls.md`

Commits referencing these files:

```
00293c4 docs(discoveries): triage remaining pending — 4 status flips + 1 current-state note + HARNESS-GAP-50
00a08a2 docs(F.2): regenerate doctrine/INDEX.md — fold in the 6 previously-uncovered doctrine files
00f8173 feat(agents): encode validation-discipline lesson into verifier/builder agents (#65)
038503e fix(D.5 remediation): doctor --full REDs — pr-template repo-root class fix + pin-d command repair, extract-pending runtime repoint (feature was dead live), heartbeat-theater doc honesty — findings 022/023
03a7827 evidence(D.5 addendum): doctor --full LITERAL GREEN 8/8 — first full-sweep green; backlog v64
05db587 chore(wave-o): orchestrator fragment application — manifest, template, consumer-map
0658758 feat(phase-1d-c-2): Task 10 — failure-mode catalog +4 entries (unfrozen-spec-edit, missing-PRD, missing-plan-header-field, missing-behavioral-contracts-at-r3+)
086fcd5 NL Overhaul §E.W integration cutover: template wiring + manifest merge (Wave-E live wiring) (#86)
0b14705 fix(scope-gate): Windows drive-letter git-dir recognized as absolute (+ HARNESS-GAP-27 docs superseded) (#27)
0b56c31 docs(strategy): capture Claude Code quality strategy + backlog gaps
10adac2 feat(plan-reviewer): land Check 8A — Pre-Submission Audit gate on Mode: design plans
10effe9 verify(wave-o): O.6 flipped by task-verifier — PASS conf 9 (hb_classify fix proven 3 ways; 2 live REDs = truthful estate debt, filed) + auto-triage row
11c9d13 docs(backlog): correct decision-context finding — bug #3 (Windows node-path) REFUTED; gate core verified working post path-fix + zod (P1->P2)
1505d27 fix(gate): repo-scope ownership claims + reviewer minors (harness-review round 1)
17db609 docs(1d-E-1): Decision 021 + backlog cleanup + inventory (Phase 1d-E-1 Task 4)
18270b9 overhaul(B.9): backlog reconciliation pass 1 — mark absorbed items, close 2 already-fixed
18d3911 feat(incentive-map): proactive shift — catalog agent incentives + counter-incentive prompts
19af838 plan(amend): capture-codify — pass-5 generalization sweep + harness-improvement backlog
1a67d05 docs(handoff): SCRATCHPAD + roadmap + backlog + discovery state for next-session pickup
1d485de plan(1d-F): definition-on-first-use enforcement (sub-gap G absorbed)
2068db5 docs(backlog): file harness gap 23 — gate reads stale commit message file
20fd90e feat(ask-workstreams): Task 10 — plan-ask linkage convention + ADR 062
243c675 backlog: P1 — harness-work plans have no tracked home (2026-04-22)
24efc14 build(docs): F.2 docs regeneration + F.2b docs-as-process (Wave F task F.2)
25465b6 feat(phase-1d-c-3): Tasks 5+7 — wire findings-ledger-schema-gate + FM-022 + vaporware-prevention enforcement-map
25ed7f5 docs(handoff): refresh backlog + roadmap to reflect closed Tranche 1.5 + add HARNESS-GAP-19
2632c0a NL Overhaul Wave C tail: C.6 reference sweep, findings, verification records — Wave C complete (#70)
2987804 docs(backlog): mark bug-persistence-gate as delivered (shipped 0090d4b)
2a49b11 feat(harness): resolve 3 pending discoveries — sweep hook, divergence detector, worktree-Q workaround
2c272c6 backlog: HARNESS-GAP-27 — scope-enforcement-gate merge-aware
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
