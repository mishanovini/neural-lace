---
title: Flat-.md skills (incl. orchestrator-prime) are not Skill-tool invocable
date: 2026-06-02
type: failure-mode
status: pending
auto_applied: false
originating_context: orchestrator-prime-keepalive scheduled-task run (2026-06-02 ~21:30). The keepalive found no orchestrator-prime alive and tried to cold-start it via `Skill(skill="orchestrator-prime")` per its task definition; the Skill tool returned "Unknown skill".
decision_needed: Should the 13 flat-`<name>.md` skills under `~/.claude/skills/` be migrated to the directory form `~/.claude/skills/<name>/SKILL.md` (and the canonical `adapters/claude-code/skills/` mirror updated + install.sh adjusted) so the Skill tool can invoke them — restoring the keepalive's autonomous orchestrator-prime restart path?
predicted_downstream:
  - adapters/claude-code/skills/*.md (canonical mirror — 13 flat skills)
  - ~/.claude/skills/*.md (live mirror — 13 flat skills)
  - install.sh (skill install/registration path)
  - ~/.claude/scheduled-tasks/orchestrator-prime-keepalive/SKILL.md (its cold-start step assumes Skill-tool invocability)
  - adapters/claude-code/rules/*.md (rules that reference these skills as `/skill` invocations)
---

## What was discovered

The orchestrator-prime keep-alive scheduled task's entire cold-start mechanism is broken.
Its task definition says: if no orchestrator-prime is running, `Skill(skill="orchestrator-prime")`.
That call returned **`Unknown skill: orchestrator-prime`** — even though the skill file is present
and valid at the canonical live path `~/.claude/skills/orchestrator-prime.md` (correct
`name:`/`description:` frontmatter, full body).

Root-cause investigation (by inspection of `~/.claude/skills/` vs this session's
available-skills registry):

- **PROVEN:** The Skill tool rejected `orchestrator-prime` with "Unknown skill".
- **PROVEN:** Of the entries in `~/.claude/skills/`, the **directory-form** skills
  (`<product>-doc-reviewer/`, `<product>-docs-designer/`, `new-project-setup/`, and the
  `find-skills` symlink→dir) ARE present in the session's available-skills list and are
  Skill-invocable. **All 13 flat `<name>.md` files are ABSENT** from the available-skills
  list: `calibrate.md`, `close-plan.md`, `find-bugs.md`, `grant-local-edit.md`,
  `harness-lesson.md`, `harness-review.md`, `orchestrator-prime.md`, `pt-implement.md`,
  `pt-test.md`, `teaching-moments.md`, `verbose-plan.md`, `verify-feature.md`,
  `why-slipped.md`.
- **HYPOTHESIZED** (cause): current Claude Code registers skills only in the directory form
  `~/.claude/skills/<name>/SKILL.md` (the same convention the scheduled-tasks use:
  `~/.claude/scheduled-tasks/<name>/SKILL.md`). The legacy flat-`<name>.md` form is no
  longer auto-registered, so every flat-`.md` NL skill is silently non-invocable.
  **Refutation criterion:** convert one flat skill (e.g. `orchestrator-prime.md` →
  `orchestrator-prime/SKILL.md`), start a fresh session, and check the available-skills
  list / try `Skill(orchestrator-prime)`. If it STILL doesn't register, the
  format hypothesis is refuted and the cause lies elsewhere (registry snapshot timing,
  install.sh wiring, frontmatter schema).

Compounding constraint discovered the same run: the keep-alive has **no autonomous
session-launch primitive** as a fallback. `mcp__ccd_session__spawn_task` only surfaces a
clickable CHIP that Misha must click to spin off a session; `mcp__ccd_session_mgmt__start_code_task`
is not exposed in the keep-alive's tool surface. So the ONLY autonomous restart path was the
Skill-tool route — which is the broken one.

## Why it matters

The keep-alive's whole purpose is reboot-resilient, always-on, autonomous orchestrator-prime
uptime. With the Skill route broken and no autonomous launch fallback, **the keep-alive cannot
revive orchestrator-prime without Misha present** to click a chip. The "always-on" guarantee is
currently false. Beyond orchestrator-prime, 12 other NL skills (`/harness-review`, `/close-plan`,
`/verify-feature`, `/calibrate`, `/grant-local-edit`, `/find-bugs`, `/why-slipped`,
`/harness-lesson`, `/teaching-moments`, `/verbose-plan`, `/pt-implement`, `/pt-test`) are
referenced by harness rules as `/skill` invocations but are likewise non-invocable — a broad
silent gap.

## Options

A. **Migrate all 13 flat skills to `<name>/SKILL.md` directory form** in both the canonical
   `adapters/claude-code/skills/` and the live `~/.claude/skills/` mirror, update `install.sh`
   to emit/register the directory form, and verify each appears in a fresh session's
   available-skills list. Class-fix; restores the Skill route for every flat skill. Cost: a
   real harness-maintenance plan (13 skills × two mirrors + install.sh + verification).
B. **Migrate only `orchestrator-prime`** now (narrow fix), defer the other 12. Restores the
   keep-alive's restart path fastest; leaves the broader gap open (and is an instance-fix, not
   a class-fix — see `diagnosis.md`).
C. **Give the keep-alive an autonomous launch fallback** independent of the Skill registry —
   e.g. a durable `CronCreate`/`start_code_task`-style primitive, or have the keep-alive read
   the skill body and self-drive inline (with a session-rename so it's correctly identified as
   orchestrator-prime, avoiding duplicate-spawn). Addresses the "no autonomous fallback"
   half of the problem.
D. **Confirm the format hypothesis first** (run the refutation criterion) before committing to
   a migration plan, so the fix targets the real cause.

## Recommendation

**D then A.** First run the cheap refutation check (convert one skill, fresh session, observe)
to confirm the flat-vs-directory format is genuinely the cause — this is a ~5-minute,
fully-reversible check and avoids a 13-skill migration built on a wrong premise. If confirmed,
do A (the class-fix) via a proper harness-maintenance plan, since the gap silently affects all
13 flat skills and the rules that invoke them, not just orchestrator-prime. B is acceptable as a
stopgap if orchestrator-prime uptime is urgent before the full migration lands. C is worth
considering regardless, because even a registry-fixed Skill route still can't relaunch
orchestrator-prime when Misha is away unless an autonomous launch primitive exists.

This is NOT auto-applied: migrating skill formats is a harness-architecture change touching 13
skills across two config layers + install.sh, warranting Misha's decision and a real plan rather
than a keep-alive side-effect. Surfaced to Misha this run via a `spawn_task` chip.

## Secondary breakage observed the same run (compounding)

When the keep-alive fell back to surfacing a cold-start chip via `mcp__ccd_session__spawn_task`,
the `conversation-tree-state-gate` PreToolUse hook BLOCKED it: "verified snapshot has no live
node naming this spawn's branch." The keep-alive is structurally NOT a conversation-tree writer
(orchestrator-prime is), and the SessionStart hook had already warned the settings template/live
copies diverge (`[settings-divergence]` — HARNESS-GAP-14), so `conversation-tree-emit.sh
--on-spawn` did not auto-populate a matching `branch-opened` node before the gate checked.
Remediation used: the gate's own first-class release valve — a fresh substantive
`.claude/state/conv-tree-spawn-waiver-*.txt` (mirrors `bug-persistence-gate.sh`); the chip then
surfaced. So BOTH of the keep-alive's restart paths required a workaround this run: the primary
(Skill tool) is hard-broken, and the fallback (spawn_task chip) needed a conv-tree waiver. Worth
considering when fixing: either wire `conversation-tree-emit.sh --on-spawn` so non-orchestrator
sessions' legitimate spawns auto-emit, or exempt the keep-alive's cold-start spawn from the
conv-tree gate (it is bootstrapping the very orchestrator that will own the tree).

## Decision

(pending — awaiting Misha)

## Implementation log

(empty — no fix applied this session)
