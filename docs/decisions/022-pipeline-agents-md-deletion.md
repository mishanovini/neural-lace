# Decision 022 — `pipeline-agents.md` deleted from global rules

**Date:** 2026-05-04
**Status:** Implemented (commit d8b30f3)
**Stakeholders:** Maintainer (sole)
**Related plan:** `docs/plans/phase-1d-e-2-audit-cleanup.md` (Status: ACTIVE → COMPLETED)
**Related backlog item:** Sub-gap B of the Build Doctrine integration analysis batch (closed by this plan)

## Context

Sub-gap B of the Build Doctrine integration analysis noted that
`~/.claude/rules/pipeline-agents.md` referenced roles and failure
patterns specific to one downstream project. The rule was authored at
a time when a single downstream project pinned the role framing
(`BUILDER` / `VERIFIER` / `DECOMPOSER`) and a tech-stack-specific set
of failure patterns (Trigger.dev job registration, Supabase RLS,
Next.js auth-middleware matchers, etc.). It lived in global rules so
every Claude Code session loaded it on startup, regardless of which
project the session targeted.

Phase 1d-E-2 Task 2 audited the file. Findings:

1. **Three role definitions are stale.** The orchestrator pattern
   (`~/.claude/rules/orchestrator-pattern.md`) supersedes the
   `BUILDER` / `VERIFIER` / `DECOMPOSER` framing entirely. The
   orchestrator dispatches to `plan-phase-builder` sub-agents which
   self-invoke `task-verifier`. Decomposition lives inside the plan
   file's `## Tasks` section, not in a separate decomposer role. The
   pipeline-agents framing has no current consumer in the harness or
   any active downstream project.
2. **Six failure patterns are tech-stack-specific.** Each pattern
   names a concrete tool (Trigger.dev), a concrete service (Supabase
   RLS), or a concrete framework feature (Next.js auth middleware
   matchers). None of these failure patterns generalize beyond the
   one downstream project's tech stack. They cannot be sanitized into
   tool-agnostic guidance without losing their concrete actionability.
3. **No active consumer.** Grep across the harness and all open plans
   surfaced zero references to `pipeline-agents.md`'s rule body. The
   orchestrator pattern is the live execution-mode rule; it makes no
   reference to the role names this file defined.

The hygiene rule (`~/.claude/rules/harness-hygiene.md`) prohibits
real codenames and project-specific content in committed harness
code. Even though `pipeline-agents.md` did not name a specific
codename, its tech-stack-specific failure patterns coupled the global
rules to one downstream project's accumulated lessons — exactly the
"kit becomes a personal snapshot" failure mode hygiene is meant to
prevent.

## Decision

Delete `pipeline-agents.md` from both layers:

- `adapters/claude-code/rules/pipeline-agents.md` (committed)
- `~/.claude/rules/pipeline-agents.md` (live mirror)

The deletion is final — the file is not relocated, not generalized,
and not preserved in any project's `.claude/rules/`. References to
the file in `docs/harness-architecture.md` and `docs/harness-guide.md`
were removed in the same commit (d8b30f3).

Future projects that encounter similar pipeline-agent failure modes
should document them in their own project's `.claude/rules/`
(per harness-hygiene's "project-specific content lives in project
repos") with the project's specific tech-stack context preserved.

## Alternatives considered

- **Alt 1 — Sanitize codenames + keep the file in global rules.**
  Rejected. The codenames were never the problem — the role-framing
  staleness and the tech-stack-specific failure patterns are the
  problem. Sanitizing wouldn't unstick the orchestrator-pattern
  supersession. Future Claude Code sessions would still load three
  superseded role definitions on startup.
- **Alt 2 — Relocate to a project's `.claude/rules/`.** Rejected.
  The content's freshness depends on the downstream project's
  current state of practice. Moving the file as-is would propagate
  the orchestrator-pattern-superseded role framing into a downstream
  repo where it would be live (loaded on every session) but stale.
  If a project genuinely wants pipeline-agent role definitions, the
  project's maintainer should author them fresh against the
  project's current architecture, not inherit a stale snapshot.
- **Alt 3 — Generalize the failure patterns into a harness-level
  rule.** Rejected. The failure patterns are tied to specific tools
  (Trigger.dev's job-registration semantics, Supabase RLS
  enforcement, Next.js middleware matcher syntax). Generalizing
  them would erase the concrete actionability that made them useful
  in the first place. A general rule like "always check that your
  job framework's registration step is wired" carries no signal a
  reader doesn't already have.

## Consequences

**Enables:**
- Global rules no longer carry tech-stack-specific failure patterns
  from one downstream project. The harness hygiene boundary is
  cleaner.
- New downstream projects start without a stale role-framing rule
  competing with the orchestrator pattern. Sessions load only the
  current execution-mode guidance.
- `docs/harness-architecture.md` and `docs/harness-guide.md`
  inventories shrunk by one rule entry; the harness's documented
  surface matches its actual surface.

**Costs:**
- Sessions that historically depended on the role-framing language
  for verifier-mandate context now must rely on the orchestrator
  pattern + `task-verifier` agent description instead. The
  task-verifier mandate in `planning.md` already covers this; the
  loss is purely the historical role-name vocabulary.
- The six failure patterns documented in the deleted file are no
  longer surfaced at session start. Anyone starting a fresh session
  on a similar tech stack will not be reminded of those specific
  failure modes. Mitigation: the harness's `docs/failure-modes.md`
  catalog continues to grow as new failure classes are observed in
  practice; the broad lesson (verify the registration step, verify
  the auth-middleware matcher, verify the RLS policy) survives in
  the per-feature audit rules (`api-routes.md`,
  `database-migrations.md`, `ui-components.md`) which are still
  present.

**Depends on:**
- The orchestrator pattern remains the canonical multi-agent
  execution mode. If a future Anthropic feature introduces a
  different role framing that needs documentation, a fresh rule
  would be authored — not a relocation of the deleted file.
- The harness-hygiene rule and its scanner remain active. Future
  attempts to re-introduce tech-stack-specific failure patterns
  into global rules should be caught in review.

**Propagates downstream:**
- `docs/harness-architecture.md` already updated in commit d8b30f3.
- `docs/harness-guide.md` already updated in commit d8b30f3.
- No downstream project repo references the file (verified by grep
  across `~/claude-projects/`).

**Blocks:** nothing.

## Cross-references

- `docs/plans/archive/phase-1d-e-2-audit-cleanup.md` — the
  implementing plan (Task 2 shipped the deletion in commit d8b30f3)
- `~/.claude/rules/orchestrator-pattern.md` — the rule that
  superseded the role-framing this file defined
- `~/.claude/rules/harness-hygiene.md` — the rule that motivates
  keeping global rules free of tech-stack-specific content
- `~/.claude/agents/task-verifier.md` — the canonical verifier-role
  documentation, replacing the `VERIFIER` framing
- `docs/failure-modes.md` — the durable catalog where future
  observed failure classes are recorded (versus the stale
  per-tool list in the deleted rule)
- HARNESS-GAP-10 sub-gap B — the backlog entry closed by this
  decision
