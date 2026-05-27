# Plan: Conv Tree Auto-Emit Enforcement (Layer B + Layer D)
Status: ACTIVE
Execution Mode: orchestrator
Mode: code
tier: 1
rung: 1
architecture: harness-hook-and-rule
frozen: true
prd-ref: n/a — harness-development
acceptance-exempt: true
acceptance-exempt-reason: Harness-internal hook + rule landing; self-test (6/6 PASS) is the acceptance artifact.
Backlog items absorbed: none

## Goal
Per Misha 2026-05-23: "stay updated automatically without me reminding
you ... add enforcement into the way you work so that you automatically
keep the Conv Tree updated at all times." This plan ships Layer B
(pre-stop reconciliation) and Layer D (rule + agent discipline),
documenting Layers A and C which are already shipped.

## Scope

IN:
- `adapters/claude-code/hooks/conv-tree-emit-reconciler.sh` — new Stop hook (Layer B)
- `adapters/claude-code/rules/conv-tree-orchestrator-emit.md` — new rule (Layer D)
- `adapters/claude-code/settings.json.template` — wire the new hook into Stop chain
- `docs/plans/conv-tree-auto-emit-enforcement-2026-05-23.md` — this plan file

OUT:
- Touching conversation-tree-emit.sh itself (Layer A is shipped; this PR documents it)
- Touching register-heartbeat.ps1 (Layer C is shipped)
- mcp__ccd_session__send_message wrapping (tool not currently exposed; rule documents the discipline for when it is)
- mcp__ccd_session__send_user_message wrapping (same)
- conv-tree-ui code changes (that's the redesign PR's scope)

## Files to Modify/Create
- `adapters/claude-code/hooks/conv-tree-emit-reconciler.sh` — new Layer B hook
- `adapters/claude-code/rules/conv-tree-orchestrator-emit.md` — new Layer D rule
- `adapters/claude-code/settings.json.template` — wire reconciler into Stop chain after --on-stop
- `docs/plans/conv-tree-auto-emit-enforcement-2026-05-23.md` — this file

## In-flight scope updates

## Tasks
- [x] 1. Audit existing wiring; document A and C status; identify B and D gaps — Verification: mechanical
- [x] 2. Write Layer D rule (`rules/conv-tree-orchestrator-emit.md`) — Verification: mechanical
- [x] 3. Write Layer B hook (`hooks/conv-tree-emit-reconciler.sh`) with --self-test — Verification: mechanical
- [x] 4. Run --self-test (6/6 must pass) — Verification: mechanical
- [x] 5. Wire reconciler into settings.json.template Stop chain — Verification: mechanical
- [x] 6. Sync rule + hook to live `~/.claude/` mirror (auto-classifier blocks settings.json live edit; document for user) — Verification: mechanical

## Assumptions
- `conversation-tree-emit.sh` is in `~/.claude/hooks/` (verified).
- $TRANSCRIPT_PATH is set in Stop event input (Claude Code convention).
- The emit hook is idempotent on deterministic event_id (verified — derives event_id from `(session, title, bucket)`).
- jq is available (matches the existing emit hook's assumption; degrades gracefully if absent).

## Edge Cases
- Transcript file missing → reconciler logs and exits 0.
- No session_id in event input → reconciler logs and exits 0.
- Transcript has more spawns than ledger has entries → reconciler re-fires emit for the delta (catch-up).
- Transcript has FEWER spawns than ledger → reconciler does nothing (over-emit is the existing emit hook's domain, not this reconciler's).
- Both hook and reconciler fire on the same Stop → emit hook's idempotency makes the second a no-op.
- Genuine cloud Dispatch sessions: Layers A-C don't fire (no local hook); Layer D agent discipline is the only enforcement.

## Testing Strategy
- Mechanical: `bash hooks/conv-tree-emit-reconciler.sh --self-test` → 6 scenarios (1-spawn matched / 2-spawns with 1-ledger / empty transcript / missing transcript file / no session_id / catch-up log line). Currently 6/6 PASS.
- Manual: Misha will observe normal Dispatch behavior over the next several sessions and confirm the tree stays updated without prompting.

## Walking Skeleton
Smallest end-to-end slice: a Stop event arrives with $TRANSCRIPT_PATH pointing at a JSONL with 1 Dispatch spawn entry. Existing --on-stop runs first (writes concluded for any ledger entries). Then reconciler runs: reads transcript, counts spawns (=1), counts ledger entries (=1), concludes "in sync" → exit 0 with audit-log line. If ledger=0, reconciler re-fires emit hook for the missing spawn (idempotent, exit 0, audit-log line).

## Decisions Log
### Decision: Layer B is a Stop-hook companion, not a replacement for the existing state-gate
- Tier: 1
- Status: implemented
- Chosen: complementary auto-fill reconciler that runs after --on-stop
- Reasoning: conversation-tree-stop-gate.sh REFUSES Stop on ADR-031 r7 Pin mismatch (correct for the gate's enforcement role). Layer B AUTO-FILLS instead — so a transient writer flake doesn't escalate to a user-visible Stop block. The two work together: gate enforces the contract; reconciler heals the gap before the gate sees it.

### Decision: don't wrap send_message / send_user_message yet
- Tier: 1
- Status: implemented
- Chosen: document the discipline in Layer D rule; defer mechanical wrapping until the tools are exposed
- Reasoning: the tools aren't currently exposed in the agent's tool surface. Adding wrapping for nonexistent tools is yagni. Layer D rule binds the agent to emit the appropriate events when the tools land, so the discipline is in place when needed.

### Decision: live settings.json edit blocked by auto-classifier; defer to user
- Tier: 1
- Status: documented in PR body
- Chosen: ship the template change; document in PR that Misha needs to manually merge into ~/.claude/settings.json
- Reasoning: the auto-classifier correctly blocks self-modification of the running session's settings (HARD BLOCK). The template is the source of truth; the live file is synced via install.sh or manual diff-apply.

## Definition of Done
- [x] Layer B reconciler hook lands + --self-test 6/6 PASS
- [x] Layer D rule lands at adapters/claude-code/rules/ + mirror at ~/.claude/rules/
- [x] Hook wired in settings.json.template Stop chain
- [x] PR opened against master (NO MERGE — Misha reviews)
