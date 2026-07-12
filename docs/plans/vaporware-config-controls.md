<!-- scaffold-created: 2026-07-12T23:36:21Z by start-plan.sh slug=vaporware-config-controls -->
# Plan: Vaporware Config Controls
Status: ACTIVE
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

- [ ] 1. Name the config-control vaporware class in `adapters/claude-code/doctrine/vaporware-prevention.md`: add a "Decorative config control" clause (a control that renders/persists but provably changes no behavior is vaporware; done-criterion = changing it changes observable behavior at the governed surface; shadow-mode never flipped to enforce = still vaporware) + a pattern-recognition bullet ("the toggle renders and saves, so the permission works") + pointer to the -full companion for the registry-vs-callsite invariant. File must stay ≤3000 bytes. — Verification: mechanical — Docs impact: the doctrine edit IS the doc delta.
- [ ] 2. Create `adapters/claude-code/doctrine/vaporware-prevention-full.md` (companion, precedent: frontend-conventions-full / observability-full): the generalizable registry-vs-callsite invariant pattern — definition (any code maintaining a capability registry + a separate UI to configure entries must have a check that every entry is wired to enforcement), the originating 6-of-16 decorative-toggles case (product name scrubbed per harness-hygiene), how to instantiate a project-level mechanical drift check (fail on any registry ID with no enforce-mode call site), shadow-mode rollout guidance (a legitimate state that must carry an expiry/flip obligation), and cross-refs (FM-038, functionality-verifier config-control protocol, functionality-auditor sweep). — Verification: mechanical — Docs impact: new doctrine file, linked from the compact.
- [ ] 3. Add the config-control clause to FUNCTIONALITY-OVER-COMPONENTS: one sentence in `adapters/claude-code/doctrine/planning.md` (bullet at ~line 5; file stays ≤3000 bytes) and a short sub-section in `adapters/claude-code/doctrine/planning-full.md` under the FUNCTIONALITY OVER COMPONENTS heading — a configurable control (permission toggle, feature flag, setting, dropdown) is done only when changing it is PROVEN to change observable behavior; rendering ≠ done; wired-to-shadow-mode ≠ done. — Verification: mechanical — Docs impact: the doctrine edits ARE the doc delta.
- [ ] 4. Extend `adapters/claude-code/agents/functionality-verifier.md` with config-control as a first-class checked class: (a) invocation-trigger bullet ("a configurable control — toggle, flag, setting, permission cell — whose task claims it governs behavior"), (b) a Config-control row in the task-class table, (c) a "Config-control protocol" section (exercise ≥2 values of the control; observe the GOVERNED surface, not the settings page; a persisted-but-behavior-identical toggle is FAIL; shadow-mode is FAIL unless the task explicitly declares shadow-mode as scope), (d) cross-ref FM-038. Keep the existing Counter-Incentive bullet (line ~147) — the protocol operationalizes it. — Verification: mechanical — Docs impact: agent remit doc updated in place.
- [ ] 5. Extend `adapters/claude-code/agents/functionality-auditor.md` with the registry-vs-callsite sweep: in Phase 1 (element inventory), when the audited surface includes a capability registry (permission list, flag list, event-type registry) with a config UI, enumerate EVERY registry entry and trace each to an enforce-mode call site; a registry entry with no enforcement consumer is a decorative config control (severity: silent-wrong-outcome — the worst class, already Framework 6 rank 1); recommend the project instantiate the registry-vs-callsite drift check from vaporware-prevention-full.md. — Verification: mechanical — Docs impact: agent remit doc updated in place.
- [ ] 6. Add FM-038 `vaporware-config-control` to `docs/failure-modes.md` (Symptom / Root cause / Detection / Prevention / Example per catalog format; Example = the scrubbed 6-of-16 permissions-matrix case; Prevention cites the surfaces landed by tasks 1-5 + the manifest row from task 7). — Verification: mechanical — Docs impact: catalog entry IS the doc delta.
- [ ] 7. Add a `vaporware-config-control` row to `adapters/claude-code/manifest.json` (kind: pattern, doctrine_file: doctrine/vaporware-prevention.md, hooks: [], blocking: false, honest_status naming the real enforcement path: "pattern — checked via functionality-verifier's config-control protocol inside the runtime-verification Stop chain on Verification: full tasks; standing surfaces via functionality-auditor sweep; no dedicated hook by design, see plan D-2") and regenerate `doctrine/INDEX.md` via the manifest generator; `manifest-check.sh` must pass. — Verification: mechanical — Docs impact: INDEX.md regenerated from manifest.
- [ ] 8. harness-reviewer adversarial review of the full diff (mandatory before landing any rule/agent change); address every Critical/Major finding; record verdict + findings disposition in this plan. — Verification: mechanical — Docs impact: none — review step, findings land in this plan file.

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

(no in-flight changes yet)

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

- **Commands that run:**
  - `grep -c "config control" adapters/claude-code/doctrine/vaporware-prevention.md` (≥1) and equivalent named-class greps on planning.md, planning-full.md, functionality-verifier.md, functionality-auditor.md, docs/failure-modes.md (FM-038), manifest.json (vaporware-config-control)
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
