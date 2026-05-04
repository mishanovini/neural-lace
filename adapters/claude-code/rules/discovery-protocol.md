# Discovery Protocol — Capture Mid-Process Learnings, Surface for Decision, Apply-and-Track

**Classification:** Hybrid. Pattern (the discovery typology, the file format, the recommendation discipline, the propagation routing) self-applied by the orchestrator, builders, and review agents. Mechanism (durable capture detection by the extended `bug-persistence-gate.sh`; surfacing of pending discoveries by the new `discovery-surfacer.sh` SessionStart hook). The decide-and-apply discipline is Pattern-only — it lives in the agent's behavior, not in a hook — but is bracketed by mechanical capture upstream and mechanical surfacing downstream.

## Why this rule exists

The harness has been overwhelmingly **reactive**. `~/.claude/rules/diagnosis.md`'s "After Every Failure: Encode the Fix" loop turns observed failures into mechanisms; `docs/failure-modes.md` is the durable catalog of those failure classes; `bug-persistence-gate.sh` makes sure observed bugs reach durable storage before session end. This is a strong substrate for failures that are bug-shaped — something visibly broke, the broken-thing has a phenotype, the catalog grows.

But sessions repeatedly surface mid-process realizations that **aren't bug-shaped**: an architectural learning ("NL implementation plans belong in `docs/plans/`, not `~/.claude/plans/`"), a scope expansion ("this rule needs an adapter mirror that wasn't in the plan"), a dependency surprise ("the hook can't read the file because it's gitignored"), a performance discovery ("the planned approach won't fit in the rate-limit envelope"), a failure-mode discovery (a new class — not yet a `FM-NNN` entry), a process discovery ("the harness has a structural gap"), or a user-experience discovery ("the user will react in an unanticipated way to this scenario"). None of these are failures the existing reactive loop catches; they are **proactive learnings** the agent has during the work.

Today these discoveries get reasoned about in commit messages, narrated in chat, or scattered across half a dozen artifact types — and most then evaporate. The 2026-05-03 session that motivated this rule produced at least six in a single working day. Per the user directive that day: the harness needs (a) durable capture on a single canonical surface, (b) surfacing to the decision-maker without depending on agent recall, (c) decide-and-apply autonomous flow for reversible decisions, (d) audit-trail tracking with conclusion-summary visibility for retrospective review. This rule encodes all four.

## Discovery typology

Every discovery file declares one of seven types in its frontmatter. The type drives the propagation pattern (where the resolved decision ultimately lands).

1. **architectural-learning** — system structure violates an unstated invariant, OR a previously-implicit invariant has become explicit. Downstream effect: may invalidate plans, existing code, or prior decisions. Promotes to `docs/decisions/NNN-*.md` (an ADR) or to plan-file restructuring.
2. **scope-expansion** — current work needs additional work to be coherent. The plan as written is too narrow. Downstream: re-plan, plan-file edit adding tasks/files, or a new plan covering the expansion.
3. **dependency-surprise** — feature requires a tool, library, permission, file, environment, or precondition unaccounted for in the plan. Downstream: BLOCKED until provided, OR plan-file dependency note + procurement task.
4. **performance** — current approach won't scale, has unforeseen cost, or violates a rate-limit / capacity budget. Downstream: architectural decision; promotes to `docs/decisions/NNN-*.md`.
5. **failure-mode** — a new class of failure has been observed that does not match any existing `FM-NNN` in `docs/failure-modes.md`. Downstream: new catalog entry plus possibly a new mechanism/gate proposal.
6. **process** — the harness or the team's process itself has a gap. Downstream: new `HARNESS-GAP-N` entry in `docs/backlog.md` plus possibly a new mechanism.
7. **user-experience** — the user will react in unanticipated ways to a built behavior, an error message, an empty state, a default, etc. Downstream: revision of the active plan's `## Acceptance Scenarios` section.

If a discovery genuinely fits two types, pick the one whose downstream effect is heaviest and note the second in the body. Don't split one realization into multiple files.

## Discovery file format

Discovery files live at `docs/discoveries/YYYY-MM-DD-<slug>.md` (project-local). Slug is kebab-case, ASCII only, ≤ 60 chars, descriptive of the realization (`gitignore-blinds-bug-persistence-gate`, not `discovery-3`).

### Frontmatter

```yaml
---
title: <imperative description, ≤60 chars>
date: 2026-05-03
type: architectural-learning | scope-expansion | dependency-surprise | performance | failure-mode | process | user-experience
status: pending | decided | implemented | rejected | superseded
auto_applied: true | false
originating_context: <plan path or session description where surfaced>
decision_needed: <specific question; populated for pending; "n/a — auto-applied" for decided autonomous>
predicted_downstream:
  - <artifact path or type that this affects>
  - <another, if multiple>
---
```

### Body sections

- **What was discovered** — concrete description with file:line citations where possible. The realization itself, not the resolution.
- **Why it matters** — what fails, drifts, or stays broken if not addressed. Concrete cost.
- **Options** — paths forward with tradeoffs. Required for `Status: pending`; archived as historical context for `Status: decided`.
- **Recommendation** — proposed direction with one-sentence justification. Required.
- **Decision** — populated after resolution. For auto-applied decisions, names the decision and cites why it was reversible. For user-decided, cites the user's response.
- **Implementation log** — populated after downstream effects land. Lists the artifacts that were touched (commit SHAs, plan file paths, ADR numbers). Empty until `Status: implemented`.

### Template-ready example

```markdown
---
title: Settings.json template vs live divergence
date: 2026-05-03
type: process
status: decided
auto_applied: true
originating_context: build-doctrine-integration session adding C7-DAG waiver wiring
decision_needed: n/a — auto-applied
predicted_downstream:
  - adapters/claude-code/settings.json.template
  - ~/.claude/settings.json
---

## What was discovered

Wiring a new SessionStart hook required edits in two files: the committed
template at `adapters/claude-code/settings.json.template` and the live
gitignored copy at `~/.claude/settings.json`. The first edit-pass touched
only the template; the live copy was missed and the hook didn't fire on
the next session start.

## Why it matters

Two-layer config means a single-file edit silently leaves one layer stale.
The template is the source of truth for the install; the live copy is what
the running session reads. Future maintainers will hit the same trap.

## Options

A. Always edit both files in any settings.json change.
B. Make `install.sh` re-sync live from template on every run.
C. Symlink live to template (rejected — Windows + per-machine local config).

## Recommendation

A — make it a documented discipline; the install symlink path is blocked
by Windows + per-machine local-only fields.

## Decision

A. Auto-applied: when wiring the C10/C7-DAG waiver, both files were touched
in the same commit. Reversible — any future divergence is caught by the
next install or session-start.

## Implementation log

- adapters/claude-code/settings.json.template — wired (commit b7ceb2d)
- ~/.claude/settings.json — wired (uncommitted local; survives across sessions)
```

## Capture pathways

There are three pathways by which a discovery becomes a file on disk.

1. **Orchestrator-initiated.** When the orchestrator (or any agent during execution) notices a discovery — a trigger phrase fires in their reasoning ("turns out", "this is a different abstraction than I assumed", "we should also", "the existing code actually does X not Y") — they write the file directly to `docs/discoveries/YYYY-MM-DD-<slug>.md`. Status starts at `pending` if a decision is needed, OR `decided` with `auto_applied: true` if the decision is reversible per the auto-apply discipline below.

2. **Builder-return-derived (Phase 1d-D-2 deferred).** Future iteration: builders' return shape will include an optional `Discoveries:` array, and a PostToolUse hook will auto-stub discovery files from those entries. **Not shipped in Phase 1d-D-1.** Documented here so future implementers know the destination shape and the surfacing mechanism is already in place.

3. **bug-persistence-gate-extended.** The Stop hook `bug-persistence-gate.sh` accepts a new file in `docs/discoveries/YYYY-MM-DD-*.md` as legitimate persistence (alongside the existing acceptance of `docs/backlog.md` entries and `docs/reviews/` files). Trigger phrases that fire in-session but don't fit the bug-shape ("turns out", "this is a different abstraction", "we should also", "I'll document this later") satisfy the gate via a discovery file. The gate's job is unchanged — durable storage before session end — but the surface of acceptable durable storage has widened to include the discovery substrate.

## Surfacing mechanism

`discovery-surfacer.sh` is a SessionStart hook. On every session start, it scans the working directory's `docs/discoveries/` for files with `Status: pending` in their frontmatter (top 30 lines). For each pending discovery, it emits a system-reminder block containing the title, type, date, decision_needed, originating_context, and a recommendation excerpt.

The user (or, in autonomous-mode runs, the orchestrator at the start of its dispatch loop) sees pending discoveries before any further work begins. If no pending discoveries exist, the surfacer is silent. If `docs/discoveries/` does not exist, the surfacer exits 0 silently — projects that have not adopted the protocol see no churn.

The surfacer does NOT re-surface decided / implemented / rejected / superseded discoveries. The "audit trail" view of historical discoveries is via the conclusion-of-work summary (for in-session review) or by browsing the directory directly (for retrospective review).

## Decide-and-apply discipline (per user directive 2026-05-03)

When a discovery requires a decision, the orchestrator follows this protocol:

1. **Lay out options.** Enumerate the realistic paths forward in the discovery file's `Options` section. At least two; ideally three. Each option carries a one-sentence tradeoff.
2. **Make a recommendation with justification.** Mark the recommended option in the `Recommendation` section. State the principle that drove the choice (reversibility, blast radius, alignment with prior decisions, etc.) — not just "this seems best."
3. **Alert the user.** Surface the discovery via the surfacing channels — SessionStart for next session if the work is paused; orchestrator's end-of-batch summary or conclusion-of-work summary for in-session visibility.
4. **Determine reversibility.**
   - **Reversible:** Auto-apply the recommendation. Mark `Status: decided` with `auto_applied: true`. Continue autonomous delivery without waiting. The decision is captured in the file so the user can review (and amend) at session end or later.
   - **Irreversible:** PAUSE. Surface to user via `AskUserQuestion` (or equivalent structured-question mechanism) with the same option/tradeoff/recommendation block from the file. Wait for explicit decision before proceeding.

### What counts as reversible vs irreversible

**Reversible (auto-apply):**

- File location and naming choices for new artifacts.
- Per-task implementation approaches when multiple valid approaches exist.
- Mechanism design choices for new hooks/agents (subsequent commits can revise).
- Internal harness configuration (regex thresholds, timeout values, sentinel strings — tunable).
- Rule wording within an established mechanism class.
- Cross-doc consistency cleanups (sweeping a stale phrase across N files).
- Discovery decisions where the decided path can be reversed by a single revert.

**Irreversible (pause and wait):**

- Force-pushes, master pushes, deletions of committed work, account-level changes (per `~/.claude/rules/git.md`).
- Schema migrations, auth-boundary changes, production-data mutations (per the Tier 3 rule in `~/.claude/rules/planning.md`).
- Material structural changes to load-bearing doctrine (e.g., redefining what "complete" means, replacing the verifier-mandate model).
- Adoption of a new third-party service that incurs recurring cost.
- Cross-project propagations beyond NL itself (e.g., touching a downstream consumer repo).
- Decisions that delete audit trail or rewrite git history irrevocably.

The boundary is sharper than it sounds: if the worst-case correction is "git revert one commit and re-edit a few lines," the decision is reversible. If the worst case requires re-provisioning a service, restoring from backup, or asking a third party to roll something back, it is irreversible.

5. **Capture for retrospective review.** Every auto-applied decision is recorded in its discovery file (`Decision` section names the choice and cites the reversibility justification). Every auto-applied decision is also surfaced in the conclusion-of-work summary at the end of the autonomous run. The user reviews these at session end (or at their convenience) and may amend or reject any auto-applied decision retroactively — the file's `Status` may be flipped to `rejected` post-hoc, with the rejection's downstream effects captured in a follow-up discovery.

## Propagation per discovery type

Once a discovery is `Status: decided`, the orchestrator routes the decided outcome to the appropriate artifact. In Phase 1d-D-1 this routing is **manual** (the orchestrator updates the target artifact when applying the decision); Phase 1d-D-2 will automate the routing via PostToolUse hooks.

| Type | Propagation target | Action |
|---|---|---|
| architectural-learning | `docs/decisions/NNN-*.md` | New ADR shell with discovery as context |
| scope-expansion | active plan's `## Files to Modify/Create` + `## Tasks` | Plan edit |
| dependency-surprise | active plan's Dependencies section | Plan edit + possibly BLOCKED |
| performance | `docs/decisions/NNN-*.md` (ADR) | New ADR for the architectural choice |
| failure-mode | `docs/failure-modes.md` + possibly new gate | New catalog entry + mechanism proposal |
| process | `docs/backlog.md` `HARNESS-GAP-N` | New HARNESS-GAP entry |
| user-experience | active plan's `## Acceptance Scenarios` | Scenario revision |

## Lifecycle

`pending` → `decided` (with `auto_applied: true|false`) → `implemented` (downstream artifacts have landed) → archived after 30 days.

Alternative paths:

- `pending` → `rejected` — user explicitly rejected the recommendation; the file is preserved for audit and does NOT propagate to its predicted_downstream targets.
- `pending` → `superseded` — a later discovery replaced this one; the superseding discovery's slug is cited in the `Decision` section.
- `decided` → `rejected` — user retroactively reverses an auto-applied decision; the rejection's mechanical revert is captured in the `Implementation log`.

Archiving (after 30 days at `Status: implemented`) is a future maintenance task; until then, implemented discoveries simply stay in the directory as historical record.

## Cross-references

- `~/.claude/rules/diagnosis.md` — reactive failure-correction (the loop the discovery protocol composes with proactively). Discoveries of type `failure-mode` ALSO trigger `diagnosis.md`'s "After Every Failure: Encode the Fix" loop and update `docs/failure-modes.md`.
- `~/.claude/rules/planning.md` — the Tier 1/2/3 mid-build decision protocol; the "Plan-Time Decisions With Interface Impact — Surface To User" section. The decide-and-apply discipline above is consistent with Tier 1 (continue + document) for reversible decisions and Tier 3 (pause + wait) for irreversible ones; Tier 2 (continue + checkpoint) maps to reversible decisions whose blast radius is large enough to want a commit checkpoint.
- `~/.claude/rules/vaporware-prevention.md` — the enforcement-map this rule extends. Two new rows are added: discovery-protocol persistence (extended `bug-persistence-gate.sh`) and discovery surfacing (new `discovery-surfacer.sh`).
- `~/.claude/rules/observed-errors-first.md` — adjacent durable-observation discipline for runtime error bodies. Discoveries are the broader category; observed errors are a specific bug-shaped subset captured in a different substrate.
- `~/.claude/hooks/bug-persistence-gate.sh` — extended in Phase 1d-D-1 to accept `docs/discoveries/`.
- `~/.claude/hooks/discovery-surfacer.sh` — new SessionStart hook in Phase 1d-D-1.

## Enforcement

- **Pattern-enforced:** the orchestrator, builders, and review agents self-apply the file format, the typology, the propagation routing, and the decide-and-apply discipline. None of these are mechanically checked; they rely on agent discipline and on the surfacing hook making the cost of forgetting visible at the next session start.
- **Mechanism-enforced (durable capture):** `bug-persistence-gate.sh` extended to accept `docs/discoveries/`. The trigger-phrase persistence requirement is mechanical — a session that mentions "turns out" or "we should also" cannot stop without having persisted the realization to the backlog, a review, or a discovery file.
- **Mechanism-enforced (surfacing):** `discovery-surfacer.sh` SessionStart hook surfaces pending discoveries automatically, every session, for every project that has the directory.

## Scope

This rule applies in any project whose Claude Code installation has the `discovery-surfacer.sh` SessionStart hook wired in `settings.json` and the extended `bug-persistence-gate.sh` Stop hook installed. Project-level: any project with a `docs/discoveries/` directory honors the protocol; projects without the directory see the surfacer exit silently and the bug-persistence gate's behavior is unchanged. Adoption is per-project — the harness ships the substrate; downstream projects opt in by creating the directory.
