# Plan: Session-End Protocol + Continuation Enforcer

Status: ACTIVE
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

- [ ] 1. Write `adapters/claude-code/rules/session-end-protocol.md` — Verification: mechanical
- [ ] 2. Write `adapters/claude-code/hooks/continuation-enforcer.sh` with `--self-test` (≥5 scenarios: DONE valid, DONE+incomplete-todo, PAUSING valid, PAUSING-without-reason, no-marker) — Verification: mechanical
- [ ] 3. Wire `continuation-enforcer.sh` into the Stop chain in `settings.json.template` and live `~/.claude/settings.json` — Verification: mechanical
- [ ] 4. Update `adapters/claude-code/CLAUDE.md` (Detailed Protocols list + Autonomy-section pointer) and `docs/harness-architecture.md` (rules table, hooks table, Stop-chain order) — Verification: mechanical
- [ ] 5. Sync canonical → live `~/.claude/`; verify byte-identical; run `--self-test` green — Verification: mechanical

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
- [ ] All tasks checked off
- [ ] `--self-test` green (≥5 scenarios) from both canonical and live paths
- [ ] Hook wired in both Stop chains (jq-verified, single occurrence)
- [ ] Canonical ↔ live mirror byte-identical (diff -q)
- [ ] SCRATCHPAD.md updated
- [ ] Completion report appended

## DoD Artifacts
- `continuation-enforcer.sh --self-test` output (all PASS)
- `jq` Stop-chain confirmation
- `diff -q` mirror-parity confirmation
