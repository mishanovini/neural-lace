# Plan: Builder-dispatch work-item auto-emission + tracking-substrate gate
Status: COMPLETED
Execution Mode: orchestrator
Mode: code
Backlog items absorbed: none
acceptance-exempt: true
acceptance-exempt-reason: harness-internal hook/gate work; self-tests are the acceptance artifact (build-harness-infrastructure work-shape)
tier: 2
rung: 1
architecture: coding-harness
frozen: true
prd-ref: n/a — harness-development

## Goal
Misha's directive (2026-06-10, verbatim intent): "we need a mechanism to force
you to actually do what it is you're supposed to do... track everything in the
Workstreams UI... built into our process so that it always happens
automatically, even when you don't want to listen to me." The surface ADR-034
deliberately scoped OUT of the Dispatch-only emit hooks — orchestrator BUILDER
dispatches via the `Task` / `Agent` / `Workflow` tools — is today completely
untracked: a session can dispatch ten builders and the Workstreams UI shows
nothing in motion. This plan adds automatic WORK-ITEM emission (not
conversation branches — ADR-034's branch scoping stands) for every builder
dispatch, a completion transition on the surfaces that genuinely provide one,
a Stop-time reconciler catch-up, and a thin fail-closed gate that BLOCKS a
builder dispatch when tracking is possible but the canonical state file is
missing/unwritable (forcing-first, gate-second).

## User-facing Outcome
After this ships, every `Task`/`Agent`/`Workflow` builder dispatch from a local
session automatically appears in the Workstreams UI as an in-flight work-item
under the session's node, flips to done when the dispatch completes
(foreground surfaces), and a dispatch CANNOT proceed untracked when the
tracking substrate is present — without the orchestrator doing anything.

## Scope
- IN: `workstreams-emit.sh` new modes `--on-builder-dispatch` (PreToolUse
  Task|Agent|Workflow → action-added work-item on the session node) and
  `--on-builder-complete` (PostToolUse → action-done for foreground
  dispatches); builder correlation ledger; `workstreams-state-gate.sh` new
  thin mode `--builder-tracking` (block when state file missing/unwritable
  while subsystem present; degrade-open when subsystem absent);
  `workstreams-emit-reconciler.sh` builder catch-up sweep at Stop;
  settings.json.template wiring (Pre + Post + existing Stop);
  ADR 054 + DECISIONS.md row; rules updates (workstreams-state.md,
  conv-tree-orchestrator-emit.md); harness-architecture.md row updates;
  self-tests for every touched hook.
- OUT: emitting conversation BRANCH nodes for Task/Agent/Workflow (ADR-034's
  branch scoping is unchanged); the Dispatch-tool spawn surfaces (already
  enforced); background-dispatch completion beyond the documented ceiling
  (no stable hook/transcript contract exists — named gap, not papered over);
  GUI changes; the state library (frozen A2 — called, never modified);
  `~/.claude/` live-mirror sync + live settings wiring (per-machine install
  step, executed in-session but not a committed artifact).

## Tasks

- [ ] 1. `workstreams-emit.sh`: add `--on-builder-dispatch` + `--on-builder-complete` modes + builder ledger + self-tests (BD1-BD9) — Verification: mechanical
- [ ] 2. `workstreams-state-gate.sh`: add `--builder-tracking` thin gate mode + waiver valve + disable env + self-tests (BT1-BT6) — Verification: mechanical
- [ ] 3. `workstreams-emit-reconciler.sh`: builder-dispatch catch-up sweep (missed PreToolUse emits + foreground completion catch-up) + self-tests — Verification: mechanical
- [ ] 4. Wiring (settings.json.template Pre/Post matchers) + ADR 054 + DECISIONS.md row + rules updates + harness-architecture.md rows — Verification: mechanical

## Files to Modify/Create
- `adapters/claude-code/hooks/workstreams-emit.sh` — new builder-dispatch emit modes
- `adapters/claude-code/hooks/workstreams-state-gate.sh` — new `--builder-tracking` thin gate mode
- `adapters/claude-code/hooks/workstreams-emit-reconciler.sh` — builder catch-up sweep
- `adapters/claude-code/settings.json.template` — PreToolUse + PostToolUse `Task|Agent|Workflow` wiring (claimed in-flight by plan-lifecycle-redesign; edit applied via the spec-freeze gate's documented non-Edit/Write emergency valve, recorded in the commit message)
- `docs/decisions/054-builder-dispatch-work-item-emission.md` — NEW ADR
- `docs/DECISIONS.md` — index row for ADR 054 (multi-claimed by other ACTIVE plans; same documented valve)
- `adapters/claude-code/rules/workstreams-state.md` — builder-dispatch work-item section
- `adapters/claude-code/rules/conv-tree-orchestrator-emit.md` — tool-surface matrix row update
- `docs/harness-architecture.md` — hook-row description updates (same documented valve)
- `docs/plans/builder-dispatch-work-item-emission.md` — this plan

## In-flight scope updates
(no in-flight changes yet)

## Assumptions
- PreToolUse/PostToolUse hooks fire on `Task` and `Agent` tool calls in local
  sessions (the template already wires `teammate-spawn-validator.sh` on
  `Task|Agent`); `Workflow` is matched defensively — if the runtime never
  emits that tool name the matcher entry is inert.
- PostToolUse fires at tool RETURN: for foreground Task/Agent dispatches the
  return IS sub-agent completion; for `Workflow` launches and
  `run_in_background: true` Agent dispatches the return is a launch-ack only.
- The state library facade (`state.js appendEvent`) is frozen A2 and creates
  the state file on first append; an unchecked `action-added` item with no
  explicit state derives `in-flight` in the GUI (`itemState` default), and a
  `details._category` outside the Misha-ask set keeps it out of Awaiting-me.
- `concluded` is rejected by the reducer while a node has unchecked items
  (FR-7) — an open builder item therefore keeps its session node visibly open
  (intentional: un-dispositioned work stays surfaced).

## Edge Cases
- Background dispatch (`Workflow`, `run_in_background: true`): NO completion
  emit at PostToolUse (would be a false done); the item honestly stays
  in-flight. Documented ceiling — see ADR 054.
- Dispatch tools (`mcp__ccd_session__spawn_task` / start_code_task) reaching
  `--on-builder-dispatch`: explicit no-op (those are `--on-spawn`'s surface).
- Same (session, tool, title) re-dispatch: deterministic item_id dedupes to
  one work-item; the later completion resolves it.
- Emit failure of any kind: exit 0 (writer isolation) — the dispatch is never
  blocked by the writer; the thin gate blocks only on substrate absence.
- Fresh machine without the workstreams subsystem (no state lib / no node):
  gate degrades OPEN (bootstrap rule — tracking is not possible).
- State file present but unwritable: gate BLOCKS (tracking possible but
  broken — the force).
- jq/node missing in the emit but present in the gate: gate blocks only on
  missing/unwritable state file, not on per-dispatch emit success — a single
  flaked emit is the reconciler's catch-up territory, not a gate block.

## Acceptance Scenarios
- n/a — acceptance-exempt harness-internal mechanism work; the self-test
  suites of the three touched hooks are the acceptance artifacts.

## Out-of-scope scenarios
- n/a

## Testing Strategy
- Every touched hook ships extended `--self-test` coverage run green locally:
  emit (existing STs + new BD scenarios), state-gate (existing scenarios + new
  BT scenarios), reconciler (existing ST1-ST5 + new builder scenarios).
- All tasks are `Verification: mechanical` — structured evidence via
  self-test exit codes + commit SHAs; closure via `close-plan.sh`.

## Walking Skeleton
- The thinnest slice is BD1: a synthetic `Task` PreToolUse JSON piped into
  `--on-builder-dispatch` with `CONV_TREE_STATE_PATH` pointed at a temp file
  produces an `action-added` item on the session node — exercised first in
  the self-test before any other scenario.

## Decisions Log
- Completion-signal surfaces (Tier 1, reversible): PostToolUse chosen over
  SubagentStop for foreground completion (same firing moment, simpler
  correlation — tool_input is present to recompute the deterministic
  item_id); background completion left untracked as a NAMED gap (no stable
  contract). Recorded in ADR 054.
- Thin gate semantics (Tier 1): substrate-presence check only (state file
  exists + writable), NOT per-dispatch ledger verification — a ledger check
  would false-positive-block every dispatch on any transient emit flake
  (harness-DoS). Recorded in ADR 054.

## Definition of Done
- [ ] All tasks checked off
- [ ] All self-tests pass
- [ ] Merged to master, both remotes pushed
- [ ] Completion report appended to this plan file

## Completion Report

_Generated by close-plan.sh on 2026-06-10T18:00:43Z._

### 1. Implementation Summary

Plan: `docs/plans/builder-dispatch-work-item-emission.md` (slug: `builder-dispatch-work-item-emission`).

Files touched (per plan's `## Files to Modify/Create`):

- `adapters/claude-code/hooks/workstreams-emit-reconciler.sh`
- `adapters/claude-code/hooks/workstreams-emit.sh`
- `adapters/claude-code/hooks/workstreams-state-gate.sh`
- `adapters/claude-code/rules/conv-tree-orchestrator-emit.md`
- `adapters/claude-code/rules/workstreams-state.md`
- `adapters/claude-code/settings.json.template`
- `docs/DECISIONS.md`
- `docs/decisions/054-builder-dispatch-work-item-emission.md`
- `docs/harness-architecture.md`
- `docs/plans/builder-dispatch-work-item-emission.md`

Commits referencing these files:

```
0090d4b feat(hook): bug-persistence-gate.sh — mechanical enforcement of testing.md rule
0291279 feat(workstreams): shared canonical-state-path resolver — converge 9-file scatter onto one file
03e4883 feat(harness): credentials inventory mechanism for cross-session auth visibility
07691d5 feat(conv-tree): Claude-side event emitter — Dispatch conversations auto-populate the GUI
0909869 feat(work-shapes): Tranche C — work-shape library + rule + integrations
099d4e2 feat(phase-1d-c-2): Task 9 — wire prd-validity-gate + spec-freeze-gate into settings.json (template + live)
0be6526 feat(hook): A1 — independent goal extraction (UserPromptSubmit + Stop)
0c1c4d8 docs(adr): ADR-032 — conversation-tree JSON state-schema field-layout contract (Task A1)
0d6bc43 feat(scope-gate): full-skip scope check during rebase/merge conflict resolution (#26)
0e2c3a6 fix(harness-architecture): restore 8 regressed Phase 1d-C-2/1d-C-3 doc rows + Task 1-3 evidence
0f34109 feat(phase-1d-c-3): Tasks 1+2+6 — Decision 019 + findings-template + findings-ledger rule + docs/findings.md bootstrap
120593c feat(harness): plan-closure-validator gate + /close-plan skill (HARNESS-GAP-16, Phase 1d-H)
14c4dfc feat(hook): session-start-git-freshness — fetch + behind + WIP-branch warns (#46)
15496c3 feat(rules+hook): branch-hygiene + stale-local-branch surfacer (#49)
167a188 feat(harness): class-aware reviewer feedback contract (Mods 1+3)
17db609 docs(1d-E-1): Decision 021 + backlog cleanup + inventory (Phase 1d-E-1 Task 4)
18d3911 feat(incentive-map): proactive shift — catalog agent incentives + counter-incentive prompts
1900089 feat(harness): static-trace.sh — auto-detect chain tracer for modified files
19a7ab7 Component B reconciler v1 — orchestrator wake-trigger + reconcile loop (single-machine, surface-first) (#58)
19bb3fc feat: B-DEC-D — resolve NL-FINDING-003 per DEC-D = option (d) snapshot-integrity attestation (REPLACES (b))
1a878a5 feat(harness): comprehension-gate rule (Phase 1d-C-4 Task 2)
1e6310c feat(hook): A7 — imperative-evidence linker
2371e97 feat(scripts): harness-hygiene-sanitize helper (GAP-13 Task 4 / Layer 4)
25465b6 feat(phase-1d-c-3): Tasks 5+7 — wire findings-ledger-schema-gate + FM-022 + vaporware-prevention enforcement-map
2590947 feat(hook): pre-push-divergence-check — block stale-fetch pushes to master (#47)
2991bdf feat(harness): cross-repo mirror automation (ADR 044) (#30)
2a49b11 feat(harness): resolve 3 pending discoveries — sweep hook, divergence detector, worktree-Q workaround
2dc69a5 feat(drift-detection): 3-component harness-internal cross-repo drift detection (#34)
2fa15d8 docs(adr): ADR-031 r2 — harden after systems-designer Phase-3 FAIL
3203d01 fix(hooks): scope-enforcement-gate evaluates the commit's TARGET repo + gates PowerShell (HARNESS-GAP-47)
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
