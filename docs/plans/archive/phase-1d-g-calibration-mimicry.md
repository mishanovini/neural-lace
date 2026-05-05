# Plan: Phase 1d-G — Calibration Mimicry (RL-Shaped Agent Calibration via Prompt Conditioning)

Status: DEFERRED
Status-rationale: Dependencies not yet shipped — telemetry (HARNESS-GAP-10 sub-gap D, 2026-08 target) and findings-ledger schema gate (C9 in Phase 1d-C-3 plan, not yet drafted). Plan is durable; execute when dependencies meet.
Execution Mode: orchestrator
Mode: code
Backlog items absorbed: HARNESS-GAP-11 (reviewer accountability is one-way) — this plan IS the proposed mechanism for that gap.
acceptance-exempt: true
acceptance-exempt-reason: Harness-development plan; deliverable is hooks + agents + state-format + dashboard. Verification is per-mechanism self-test plus observed cross-session behavior over time.

## Context

Per user's Munger-frame request (2026-05-03): "Show me the incentive and I'll show you the outcome" applied to AI agents. Reactive failure-correction (`diagnosis.md`'s "After Every Failure: Encode the Fix") catches strays one at a time. Phase 1d-incentive-map (commit 18d3911) shipped the proactive prompt-injection layer. This plan ships the FEEDBACK-LOOP layer that approximates RL through prompt conditioning rather than weight updates.

We don't have access to weight updates from the harness. But we have strong attention from agents to their prompts. The mechanism: track each agent's calibration history outside the model; inject the calibration profile into the agent's prompt at invocation; let the agent see its own miscalibration as context; let the agent see meta-consequences (auto-downgrade, replacement, demotion). This isn't RL but produces RL-shaped outcomes.

This plan ships in three sub-phases (1d-G-1 tracking, 1d-G-2 injector, 1d-G-3 scoreboard-and-dashboard) sequenced after Phase 1d-C ships the dependencies.

## User-confirmed decisions (2026-05-03)

These are LOCKED design constraints for this plan. Implementation must conform.

**Decision G-1 — Approximation acceptable; no fine-tuning.** RL-shaped via prompt conditioning is the design. No agent's model weights change. The mechanism produces calibration adjustment via injected prompts plus structural consequences (auto-downgrade) — NOT via fine-tuning any model. Lower implementation cost, faster iteration, no API-level fine-tuning dependency.

**Decision G-2 — Scope: high-stakes agents first.** Initial agents under calibration tracking: `task-verifier`, `harness-reviewer`, `end-user-advocate` (runtime mode). Expansion to other agents based on empirical drift evidence. Lower-stakes agents (`explorer`, `research`) deferred indefinitely unless evidence justifies.

**Decision G-3 — Visibility: all three channels.** (a) Internal-to-NL state at `~/.claude/state/agent-calibration/<agent-name>.jsonl`; (b) agents-see-it via injected calibration profiles in their prompts at invocation time; (c) public visibility via `docs/agent-calibration.md` regenerated weekly; (d) [extended per user 2026-05-03] dashboard surface for harness-stats per project.

**Decision G-4 — Dashboard surface (eventual expansion).** A dashboard surface for harness calibration AND additional harness-stats per project is desired by the user. Specific format/tooling deferred — could be a static HTML page generated from state files, a TUI, a web dashboard, or extension of existing dashboards. This decision captures the FORWARD-LOOKING SCOPE rather than a current implementation directive. Sub-phase 1d-G-3 includes the static-HTML version as MVP; later expansion is its own phase.

## Goal

Three sub-phases delivering calibration-mimicry end-to-end:

### Phase 1d-G-1 — Calibration tracking (~6-10 hours)

- New state directory `~/.claude/state/agent-calibration/<agent-name>.jsonl` (one file per agent, JSONL append-only)
- `calibration-logger.sh` — new PostToolUse hook on `Task` tool that captures every agent verdict with: timestamp, session_id, task_id, agent_name, self_verdict, self_confidence, claimed-evidence-summary
- Independent grader integration: `plan-evidence-reviewer` extended to write the independent verdict to the calibration log when re-verifying task-verifier's claims at session end. For each PASS/FAIL pair, writes the agreement/disagreement signal.
- Tracking only — no consequence yet. Phase produces data; Phase 2 acts on it.

### Phase 1d-G-2 — Calibration injector (~8-15 hours)

- `calibration-injector.sh` — wrapper that runs at agent invocation time. Reads the agent's recent calibration history (rolling 30-day window), computes summary statistics (PASS rate, agreement rate, bias direction, threshold status), formats as a calibration-profile prompt block, prepends to the agent's invocation prompt.
- Calibration-profile format:
  ```
  ## Your calibration profile (auto-generated from .claude/state/agent-calibration/<agent>.jsonl)
  Last 30 days: N invocations.
  Self-graded PASS: X%.
  Independent grader agreed: Y% of those PASSes.
  Disagreement direction: +Z severity-levels (you over-grade) OR -Z (you under-grade).
  Calibration adjustment: <directive based on bias direction and threshold>.
  Threshold status: counter at K of T; auto-downgrade applies if exceeded.
  ```
- Auto-downgrade mechanism: when an agent's bias counter exceeds threshold, the harness auto-downgrades the agent's verdict by 1 severity level until calibration recovers (3 consecutive agreed verdicts).
- Per-agent threshold tuning per Decision G-2 — start with conservative thresholds for the 3 high-stakes agents, expand later.

### Phase 1d-G-3 — Public scoreboard + dashboard MVP (~8-15 hours)

- `docs/agent-calibration.md` — auto-regenerated weekly by `/harness-review`. One section per tracked agent. Shows: current calibration profile, historical bias direction, recent miscalibrations with examples, current routing/demotion status.
- `/harness-review` skill extension to call the regeneration script.
- Static HTML dashboard MVP at `docs/dashboard.html` (or similar) showing per-project harness-stats: gates fired this week, hooks blocked, plans completed/active/deferred, agent calibration per agent. Generated from telemetry (HARNESS-GAP-10 sub-gap D dependency).
- Per Decision G-4: dashboard expansion to provide additional harness-stats per project deferred to its own future phase; this sub-phase ships the MVP scaffold.

## Scope

**IN:**
- Three sub-phases above with their deliverables
- Hook self-tests
- Agent prompts updated to acknowledge calibration profiles in their prompts (counter-incentive section extension)
- Documentation updates: vaporware-prevention.md enforcement map, harness-architecture.md preface, backlog.md HARNESS-GAP-11 status

**OUT:**
- Fine-tuning any model (per Decision G-1)
- Lower-stakes agents (explorer, research, etc.) — added later based on evidence
- Full dashboard expansion beyond MVP (per Decision G-4)
- Real-time UI updates (the dashboard regenerates on schedule, not live)

## Dependencies

This plan CANNOT execute until both:
1. **Telemetry shipped** (HARNESS-GAP-10 sub-gap D, 2026-08 target). The calibration-logger needs telemetry's collection substrate. Without it, the logger writes JSONL but no aggregation/regeneration happens.
2. **Findings-ledger schema gate (C9) shipped** (Phase 1d-C-3 plan). The independent grader's verdict format needs the structured findings-ledger entries to compare against.

When both ship, this plan transitions from `Status: DEFERRED` to `Status: ACTIVE` and execution begins with Phase 1d-G-1.

## Tasks

(Tasks specified at task-level for each sub-phase; full breakdown deferred until plan transitions to ACTIVE. The structural shape — three sub-phases — is fixed per the user-confirmed decisions.)

- [ ] **G-1.1** Design calibration-log JSONL schema; create state directory.
- [ ] **G-1.2** Implement `calibration-logger.sh` PostToolUse hook on Task.
- [ ] **G-1.3** Extend `plan-evidence-reviewer` to write independent grader verdicts.
- [ ] **G-1.4** Wire into settings.json.template and ~/.claude/settings.json; commit.

- [ ] **G-2.1** Design calibration-profile prompt format.
- [ ] **G-2.2** Implement `calibration-injector.sh`.
- [ ] **G-2.3** Implement auto-downgrade mechanism.
- [ ] **G-2.4** Tune thresholds per high-stakes agent (3 agents).
- [ ] **G-2.5** Wire and commit.

- [ ] **G-3.1** Implement `docs/agent-calibration.md` regeneration script.
- [ ] **G-3.2** Extend `/harness-review` skill to call regeneration.
- [ ] **G-3.3** Implement static HTML dashboard MVP at `docs/dashboard.html`.
- [ ] **G-3.4** Wire and commit.

## Files to Modify/Create (preview, expanded when plan transitions to ACTIVE)

(Listed for forward planning; not staged today since plan is DEFERRED.)

**Sub-phase 1d-G-1:**
- `adapters/claude-code/hooks/calibration-logger.sh` (NEW)
- `~/.claude/hooks/calibration-logger.sh` (mirror)
- `adapters/claude-code/agents/plan-evidence-reviewer.md` (MODIFIED — extend for independent grader role)
- `~/.claude/agents/plan-evidence-reviewer.md` (mirror)
- `~/.claude/state/agent-calibration/.gitignore` (created on first run)
- `adapters/claude-code/settings.json.template` (MODIFIED — wire calibration-logger)
- `~/.claude/settings.json` (mirror)

**Sub-phase 1d-G-2:**
- `adapters/claude-code/hooks/calibration-injector.sh` (NEW)
- `~/.claude/hooks/calibration-injector.sh` (mirror)
- 3 agent prompt files (task-verifier, harness-reviewer, end-user-advocate) extended with calibration-profile awareness in their Counter-Incentive Discipline section
- 3 mirrors

**Sub-phase 1d-G-3:**
- `docs/agent-calibration.md` (auto-generated)
- `docs/dashboard.html` (MVP)
- `adapters/claude-code/skills/harness-review.md` (MODIFIED — extend for calibration-regen)
- `~/.claude/skills/harness-review.md` (mirror)

## Assumptions

- Telemetry-collection substrate (HARNESS-GAP-10 sub-gap D) has shipped before this plan executes.
- Findings-ledger schema (C9 from Phase 1d-C-3) has shipped before this plan executes.
- High-stakes agent list (task-verifier, harness-reviewer, end-user-advocate) is correct; can expand based on empirical evidence.
- Auto-downgrade thresholds need empirical tuning; initial conservative defaults will be revised after first month of data.
- The dashboard MVP is static HTML; full interactive dashboard is a separate future phase.

## Edge Cases

- **An agent has fewer than 10 historical invocations:** calibration-injector falls back to conservative-default prompt instead of computed profile. Avoids high-variance calibration on low-N data.
- **Auto-downgrade applied incorrectly:** every auto-downgrade is logged; user can revert with manual override (`.claude/state/calibration-override-<agent>.txt`).
- **Calibration data gets stale (agent retired or model swapped):** rolling 30-day window aging discards old data automatically; new model = fresh tracking.
- **Disagreement-class ambiguity:** when self-verdict and independent verdict disagree, the disagreement classification (over-grade / under-grade / different-axis) requires structured comparison. The findings-ledger schema dependency provides this.

## Acceptance Scenarios

n/a — `acceptance-exempt: true`. Verification is empirical (cross-session behavior change after deployment).

## Decisions Log

### Decision G-1 (locked, 2026-05-03)
- **Tier:** 3 (architectural — affects all future agent invocations)
- **Status:** confirmed
- **Chosen:** Calibration mimicry via prompt conditioning, no fine-tuning.
- **Reasoning:** Per user 2026-05-03: "I'm not going to fine-tune any models." RL-shaped via context-conditioning is acceptable. Cheaper, faster iteration.

### Decision G-2 (locked, 2026-05-03)
- **Tier:** 2
- **Status:** confirmed
- **Chosen:** High-stakes agents first (task-verifier, harness-reviewer, end-user-advocate runtime).
- **Reasoning:** Per user agreement. Lowest-risk-highest-leverage start.

### Decision G-3 (locked, 2026-05-03)
- **Tier:** 2
- **Status:** confirmed
- **Chosen:** All three visibility channels (internal state, agents-see-it, public scoreboard).
- **Reasoning:** Per user "Agreed. All three." The agents-see-it channel is load-bearing for the calibration-injector to work.

### Decision G-4 (locked, 2026-05-03; partial — MVP scope)
- **Tier:** 2
- **Status:** captured for future expansion
- **Chosen:** Dashboard surface for harness calibration + harness-stats per project. MVP = static HTML in sub-phase 1d-G-3. Full expansion deferred.
- **Reasoning:** Per user "I'll probably want a dashboard for easy visibility that will eventually expand to provide additional stats about the harness in each project."

## Definition of Done

(Per sub-phase, populated at execution time)

- [ ] G-1: tracking active for 3 high-stakes agents; data accumulating in JSONL
- [ ] G-2: calibration-injector wired and tested; auto-downgrade verified empirically
- [ ] G-3: scoreboard auto-regenerated weekly; dashboard MVP visible; harness-review skill extended
- [ ] All commits land on a feature branch; merge to master after observed-stability period

## Status transition checklist

Before flipping `Status: DEFERRED` → `Status: ACTIVE`:
- [ ] Telemetry collector live (HARNESS-GAP-10 sub-gap D resolved)
- [ ] Findings-ledger schema gate (C9) shipped (Phase 1d-C-3 complete)
- [ ] User confirms readiness to begin

When all three confirmed, the plan transitions to ACTIVE and Sub-phase 1d-G-1 begins.
