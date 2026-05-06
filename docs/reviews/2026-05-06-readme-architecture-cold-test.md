# Cold-test review — README + docs/architecture-overview.md

**Date:** 2026-05-06
**Tester:** research subagent simulating a fresh public-repo reader (Claude Code experience, no Neural Lace exposure)
**Subjects:** `README.md` (commit `bdc1240`), `docs/architecture-overview.md` (commit `228c7fa`)
**Triggered by:** Task 5 of `docs/plans/archive/docs-refresh-tech-team-architecture.md`
**Verdict:** NEEDS-REVISION

## Summary

15 findings. Front-of-funnel issues: README abstracts what the harness physically is; user-visible benefits buried at line 100; multiple domain terms used before defined. The team-role analogy and end-to-end flow land well; the layered-architecture compression in README is too dense for a cold reader.

## Top 3 fixes (highest leverage)

1. Define what Neural Lace IS in physical terms in the first 50 words of README (a set of rules + hooks + agent definitions + scripts installed into `~/.claude/`). Don't make readers infer the artifact shape from prose about "discipline."
2. Move README's "What it does" section to be second on the page (immediately after the tagline). User-visible benefits land before structural taxonomy.
3. Define every domain term on first use: rung, ADR, Build Doctrine, FM-NNN, A1/A3/A5/A7/A8, Gen 4/5/6. The harness has a definition-on-first-use rule for doctrine docs; the front-door docs should follow the same discipline.

## All 15 findings

### Finding 1 — Tagline doesn't say what this IS — P0
**Location:** README.md > tagline
"Wraps AI coding tools with mechanically-enforced..." is 23 words but doesn't anchor what shape Neural Lace takes on disk.
**Fix:** add concrete sentence: "A set of rules, hooks, agent definitions, and scripts installed into `~/.claude/`. Once installed, every Claude Code session inherits the discipline."

### Finding 2 — "Mechanically-enforced" repeated 6+ times before "what's a hook" is explained — P0
**Location:** README.md > tagline + paragraph 1 + "What it does"
Cold reader doesn't know if "hook" means git pre-commit or Claude Code lifecycle event. Clarification doesn't land until line 156.
**Fix:** early explanation: "Hooks are scripts Claude Code runs at lifecycle events (PreToolUse, PostToolUse, Stop, SessionStart). They can block actions before they execute or refuse to let a session end."

### Finding 3 — Three layer systems dumped on cold reader at once — P1
**Location:** README.md > "Three layered architectures, each answering a different question"
30 seconds in, three numbering schemes (L0/L1/L2/L3, Gen 1-6, ADR-027 Layer 1-5). Too much for a front-door doc.
**Fix:** README shows only Layer 0/1/2/3 (the one affecting "is this useful for me?"). Defer Gen 1-6 and ADR-027 to architecture-overview.

### Finding 4 — "ADR-027" appears in README without expansion — P1
**Location:** README.md line 52
**Fix:** first use should expand: "ADR-027 (Architecture Decision Record #027 — see `docs/decisions/`)." Per the harness's own definition-on-first-use rule.

### Finding 5 — End-to-end flow's 10 numbered steps lack actor labels — P1
**Location:** README.md > "How a feature ships through the team"
"Planner drafts plan → start-plan.sh creates scaffold." Who's the planner? Me? The AI? Is `start-plan.sh` something I run or Claude runs?
**Fix:** prefix with "Here's what happens after you type 'build feature X' in a Claude Code session." Label each step's actor.

### Finding 6 — User-visible benefits buried — P0
**Location:** README.md overall structure
By line 100 reader still doesn't have an elevator-pitch answer to "what does Neural Lace do?" because structure-talk dominates the first 80 lines.
**Fix:** move "What it does" (line 100) to immediately after the tagline. New order: (1) what it does, (2) how it's organized, (3) where to install.

### Finding 7 — 17-row Documentation table overwhelms — P2
**Location:** README.md > Documentation
14 documents listed; cold reader doesn't know which audience tier describes them.
**Fix:** cut top table to 4-5 staircase entries (README → SETUP → architecture-overview → best-practices → harness-architecture). Move the rest to a "Further reading" subsection.

### Finding 8 — "rung 2+" used without definition in architecture-overview — P1
**Location:** architecture-overview.md > Section II step 5, multiple places
Term never defined; reader confuses with `tier:`.
**Fix:** first mention needs parenthetical definition: "rung (the diff complexity score declared in the plan header — R0 = single-file trivial; R2+ = multi-file with behavioral contracts; see `comprehension-gate.md`)."

### Finding 9 — "Build Doctrine" repeated but never defined — P0
**Location:** Both docs
"Build Doctrine integration arc," "Build Doctrine Tranches" — what IS Build Doctrine?
**Fix:** first mention needs one sentence: "Build Doctrine — a separate methodology repository at `~/claude-projects/Build Doctrine/` whose principles (failsafe-first, work-shapes, risk-tiered verification) were integrated into Neural Lace in May 2026."

### Finding 10 — Agent count contradicts itself — P2
**Location:** README line 32 vs architecture-overview line 31
README says "10 + 9 = 19"; architecture-overview opens "19 of them"; role table shows 20 entries (counting orchestrator).
**Fix:** pick canonical count: "20 specialized agents (19 sub-agents + the orchestrator main session)" everywhere.

### Finding 11 — Filesystem map insufficient as a topic-lookup tool — P1
**Location:** architecture-overview.md > Section IV
Tree shows directories well; doesn't help find COMPONENTS by topic ("where does spawn_task report-back live?").
**Fix:** add "Find by topic" subsection with ~15 topic→path entries.

### Finding 12 — "Originating incident" stories lack links — P2
**Location:** architecture-overview.md > Generation table
Compelling but unlinked. Reader can't follow breadcrumbs to the post-mortem.
**Fix:** each incident sentence links to `docs/sessions/`, ADR, or `docs/failure-modes.md` entry.

### Finding 13 — Quick Start prescribes `~/claude-projects/` without explaining why — P2
**Location:** README.md > Quick Start
Path may not exist; not clear if required or convention.
**Fix:** add: "Create `~/claude-projects/` if it doesn't exist (this is where the multi-account auto-switcher expects projects)."

### Finding 14 — A1/A3/A5/A7/A8 labels never expanded — P2
**Location:** architecture-overview.md > deployment-artifact tree
"A1 first-message goal extraction" — what does A1 stand for?
**Fix:** first mention expands: "A1 (Audit-1, the first of the Gen 6 narrative-integrity hooks — first-message goal extraction)." Or small table near Gen 6 row.

### Finding 15 — No "Is this for me?" qualifier — P1
**Location:** Both docs
Cold reader has to absorb 700+ lines before deciding adoption fit.
**Fix:** Add "Is this for me?" section near top of README: bullet list of fit-criteria + comparison row to project-only `CLAUDE.md` / aider / cursor rules.

## Tester's first-30-seconds result

> "Neural Lace is... a thing that wraps Claude Code with enforcement of best practices? It has agents that do tech-team roles. There are hooks. There are layers. I think it's installable but I'm not sure where the actual installable artifact lives."

I.e., the tester would NOT confidently describe this to a colleague after 30 seconds. The team-role analogy is sticky; the artifact shape is not.

## Tester's ratings

| Test | Rating |
|---|---|
| Navigation (find specific topics) | 3/5 |
| Architecture-shape (sketch the structure) | 4/5 |

## Status

This review is the input to the doc-refresh plan's iteration loop. P0 + high-impact P1 fixes will be applied; P2 fixes deferred unless trivial. After fixes land, plan closes via `close-plan.sh`.

**Fixes to apply (this session):**
- All P0s (Findings 1, 2, 6, 9)
- High-impact P1s (Findings 3, 4, 5, 8, 11, 15)

**Deferred to backlog (P2 + lower-impact P1):**
- Finding 7 (doc table compression)
- Finding 10 (agent count reconcile — applied if trivial)
- Finding 12 (incident links)
- Finding 13 (path explanation — applied if trivial)
- Finding 14 (A1-A8 expansion — applied if trivial)
