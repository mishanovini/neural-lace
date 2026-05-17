# Plan: Session-End Protocol + Continuation Enforcer

Status: COMPLETED
Execution Mode: orchestrator
Mode: code
tier: 1
rung: 1
architecture: hybrid (Pattern rule + Mechanism Stop hook)
frozen: true
prd-ref: n/a — harness-development
acceptance-exempt: true
acceptance-exempt-reason: harness-internal work; the hook's --self-test is the acceptance artifact, there is no product runtime to advocate for
Backlog items absorbed: none

## Goal

Sessions repeatedly go idle between sub-tasks without making their terminal
intent explicit, which trains operators to babysit. Add a mechanical Stop-hook
gate that forces every session to end its turn with EXACTLY ONE machine-readable
marker — `DONE:`, `PAUSING:`, or `BLOCKED:` — on the last line of its final
response, plus a sibling Pattern rule documenting the protocol. The marker makes
the model's terminal intent explicit and auditable; the hook makes it
non-optional. Reinforces `narrate-and-wait-gate.sh` (which catches
permission-seeking trail-off) by requiring a positive declaration of why the
turn is ending.

## Scope

- IN: new rule `session-end-protocol.md`; new Stop hook `continuation-enforcer.sh`
  with `--self-test`; wiring into template + live `settings.json`; CLAUDE.md +
  harness-architecture.md doc updates; sync to live `~/.claude/` mirror.
- OUT: changing existing Stop hooks; UserPromptSubmit-side goal extraction;
  downstream-project rollout (NL adopts first per the standard sequence).

## Tasks

- [x] 1. Write `adapters/claude-code/rules/session-end-protocol.md` — Verification: mechanical
- [x] 2. Write `adapters/claude-code/hooks/continuation-enforcer.sh` with `--self-test` (≥5 scenarios: DONE valid, DONE+incomplete-todo, PAUSING valid, PAUSING-without-reason, no-marker) — Verification: mechanical
- [x] 3. Wire `continuation-enforcer.sh` into the Stop chain in `settings.json.template` and live `~/.claude/settings.json` — Verification: mechanical
- [x] 4. Update `adapters/claude-code/CLAUDE.md` (Detailed Protocols list + Autonomy-section pointer) and `docs/harness-architecture.md` (rules table, hooks table, Stop-chain order) — Verification: mechanical
- [x] 5. Sync canonical → live `~/.claude/`; verify byte-identical; run `--self-test` green — Verification: mechanical

## Files to Modify/Create
- `docs/plans/session-end-protocol-enforcer.md` — this plan (self)
- `adapters/claude-code/rules/session-end-protocol.md` — new Pattern rule
- `adapters/claude-code/hooks/continuation-enforcer.sh` — new Stop hook + self-test
- `adapters/claude-code/settings.json.template` — wire the hook into the Stop chain
- `adapters/claude-code/CLAUDE.md` — Detailed Protocols list + Autonomy pointer
- `docs/harness-architecture.md` — rules table row, hooks table row, Stop-chain order, last-updated line
- `SCRATCHPAD.md` — session state pointer (gitignored)

## In-flight scope updates

## Assumptions
- The Claude Code transcript JSONL exposes assistant text via the same
  `(.content // .text // .message.content)` shape `narrate-and-wait-gate.sh`
  already relies on, and TodoWrite tool-use blocks appear as
  `.message.content[].type=="tool_use"` with `.name=="TodoWrite"` and
  `.input.todos[].status` ∈ {pending,in_progress,completed}.
- The Stop chains in `settings.json.template` and live `~/.claude/settings.json`
  are byte-identical for the Stop array (verified at plan time).
- Marker enforcement is universal (not gated on a keep-going directive) per the
  user directive "Every Claude Code session MUST end its turn with a marker";
  the retry-guard library prevents lockout when a session genuinely cannot
  satisfy the gate.

## Edge Cases
- No transcript / no jq → no-op exit 0 (consistent with sibling Stop hooks;
  never block on best-effort text scan).
- Marker present but format-invalid (empty summary, keyword-only) → BLOCK.
- DONE marker but last TodoWrite has incomplete items → BLOCK with the list.
- PAUSING/BLOCKED reason too thin (no articulated specifics) → BLOCK.
- Marker not on the last non-empty line (buried mid-message) → treated as
  absent → BLOCK (the protocol requires it be the terminal line).
- Identical-failure loop → retry-guard downgrades to warn after 3 retries and
  logs to `.claude/state/unresolved-stop-hooks.log`.
- Harness-dev sessions editing the marker vocabulary itself → escape hatch
  env var so the hook does not self-trigger.

## Testing Strategy
- Task 2: `bash continuation-enforcer.sh --self-test` exercises ≥5 scenarios
  with synthetic JSONL transcripts in a tempdir; all must pass.
- Task 3: `jq` confirms the hook appears once in both Stop chains.
- Task 5: `diff -q` confirms canonical and live mirror byte-identical for the
  hook, rule, settings.json, CLAUDE.md, harness-architecture.md; re-run
  `--self-test` from the live path.

## Walking Skeleton
Thinnest end-to-end slice: a synthetic transcript whose last assistant message
is `DONE: shipped X` passes the hook (exit 0); the same transcript with the
marker removed blocks (exit 2). That single PASS/BLOCK pair through the real
jq-parse path is the skeleton; the other scenarios are variations on it.

## Decisions Log

### Decision: Universal enforcement, not keep-going-gated
- **Tier:** 1
- **Status:** proceeded with recommendation
- **Chosen:** the gate fires on every session, not only when a keep-going
  directive is present.
- **Alternatives:** gate only when `narrate-and-wait`-style keep-going
  directive detected (less noisy on short Q&A sessions).
- **Reasoning:** user directive is explicit and universal ("Every Claude Code
  session MUST"); the marker is one cheap line for the model; the retry-guard
  prevents any lockout. Surfaced to user: directive was unambiguous in the
  task brief, no interface-impact ambiguity to surface.

### Decision: Hook is the last GATE in the Stop chain
- **Tier:** 1
- **Status:** proceeded with recommendation
- **Chosen:** insert after `goal-coverage-on-stop.sh`, before the
  `session-wrap.sh refresh` (non-gate) script.
- **Alternatives:** place near `narrate-and-wait-gate.sh` (position 3).
- **Reasoning:** substantive gates (plan integrity, bugs, acceptance,
  deferrals, lies, imperatives, goals) are more actionable when they fire;
  the terminal-intent marker is the explicit final classification once all
  substance passes — it gets the last word. Consistent with the chain's
  actionable-first ordering.

## Definition of Done
- [x] All tasks checked off
- [x] `--self-test` green (≥5 scenarios) from both canonical and live paths
- [x] Hook wired in both Stop chains (jq-verified, single occurrence)
- [x] Canonical ↔ live mirror byte-identical (diff -q)
- [x] SCRATCHPAD.md updated
- [x] Completion report appended

## DoD Artifacts
- `continuation-enforcer.sh --self-test` output (all PASS)
- `jq` Stop-chain confirmation
- `diff -q` mirror-parity confirmation

## Completion Report

_Generated by close-plan.sh on 2026-05-17T18:23:16Z._

### 1. Implementation Summary

Plan: `docs/plans/session-end-protocol-enforcer.md` (slug: `session-end-protocol-enforcer`).

Files touched (per plan's `## Files to Modify/Create`):

- `SCRATCHPAD.md`
- `adapters/claude-code/CLAUDE.md`
- `adapters/claude-code/hooks/continuation-enforcer.sh`
- `adapters/claude-code/rules/session-end-protocol.md`
- `adapters/claude-code/settings.json.template`
- `docs/harness-architecture.md`
- `docs/plans/session-end-protocol-enforcer.md`

Commits referencing these files:

```
0090d4b feat(hook): bug-persistence-gate.sh — mechanical enforcement of testing.md rule
03e4883 feat(harness): credentials inventory mechanism for cross-session auth visibility
0909869 feat(work-shapes): Tranche C — work-shape library + rule + integrations
099d4e2 feat(phase-1d-c-2): Task 9 — wire prd-validity-gate + spec-freeze-gate into settings.json (template + live)
0be6526 feat(hook): A1 — independent goal extraction (UserPromptSubmit + Stop)
0e2c3a6 fix(harness-architecture): restore 8 regressed Phase 1d-C-2/1d-C-3 doc rows + Task 1-3 evidence
0f34109 feat(phase-1d-c-3): Tasks 1+2+6 — Decision 019 + findings-template + findings-ledger rule + docs/findings.md bootstrap
120593c feat(harness): plan-closure-validator gate + /close-plan skill (HARNESS-GAP-16, Phase 1d-H)
167a188 feat(harness): class-aware reviewer feedback contract (Mods 1+3)
17db609 docs(1d-E-1): Decision 021 + backlog cleanup + inventory (Phase 1d-E-1 Task 4)
18d3911 feat(incentive-map): proactive shift — catalog agent incentives + counter-incentive prompts
1900089 feat(harness): static-trace.sh — auto-detect chain tracer for modified files
1a878a5 feat(harness): comprehension-gate rule (Phase 1d-C-4 Task 2)
1e6310c feat(hook): A7 — imperative-evidence linker
2371e97 feat(scripts): harness-hygiene-sanitize helper (GAP-13 Task 4 / Layer 4)
25465b6 feat(phase-1d-c-3): Tasks 5+7 — wire findings-ledger-schema-gate + FM-022 + vaporware-prevention enforcement-map
2a49b11 feat(harness): resolve 3 pending discoveries — sweep hook, divergence detector, worktree-Q workaround
35ee3df feat(harness): mechanical evidence substrate (Tranche B)
393ba6f feat(harness): Phase B template + rule pattern for end-user-advocate acceptance loop
3afa037 feat(phase-1d-c-3): Tasks 3+4 — findings-ledger-schema-gate.sh hook + bug-persistence-gate.sh extension
3e3568f feat(harness): build-harness-infrastructure work-shape — lighter process carve-out for harness work
3f3b2e9 feat(harness): Tranche G — calibration loop bootstrap
440a2d9 feat(rules): spawn-task-report-back convention rule (GAP-08 Task 1)
460519e feat(build-doctrine): Tranche 5a-integration ritual wired audit analyzer pilot template
4627e01 feat(settings): wire spawned-task-result-surfacer SessionStart hook (GAP-08 Task 3)
46616ba feat(build-doctrine): Tranche 6a — propagation engine framework + 8 starter rules + audit log
483f5f6 feat(harness): Gen 5 — design-mode planning + outcome-focused reviewers
50d670d feat(harness): integration-verification gate — plan-time Check 13 + runtime wire-check-gate
51016b9 feat(harness): context-aware permission gates — session-wrap worktree fall-back + local-edit authorization
55742f2 docs(rules): SCRATCHPAD triggers (Rule 2) + review-finding IDs (Rule 4) + memory last_verified (Rule 7)
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
