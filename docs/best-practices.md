# Best Practices Encoded in Neural Lace

> **Status:** stub. This document outlines the best practices the harness enforces and is actively being expanded with detailed guidance for each. If a practice below lacks a deep-dive section, it still applies — consult the referenced rule/hook for specifics.

Neural Lace is more than an AI harness. It encodes a set of software-engineering and AI-collaboration best practices that an individual developer or team would otherwise have to discover independently over years of practice (and failure). This document is the reader's guide to those practices: what they are, why they're here, and how the harness enforces them.

## Table of contents

- [Core practices](#core-practices)
- [AI-collaboration practices](#ai-collaboration-practices)
- [Security practices](#security-practices)
- [Planning + decision practices](#planning--decision-practices)
- [Testing + verification practices](#testing--verification-practices)
- [Documentation practices](#documentation-practices)

## Core practices

### Two-layer configuration — separate personal from shareable

**Rule:** Never commit personal identifiers, secrets, or machine-specific paths to a shareable harness repo. Personalization lives in a user-local layer (`~/.claude/local/`), shareable defaults live in the harness layer.

**Why:** a harness that contains identity gets harder to share with every contributor. Every team member's personal setup drifts, breaks, and leaks.

**Where:** `principles/harness-hygiene.md`. Enforced by `adapters/claude-code/hooks/harness-hygiene-scan.sh`.

### CLAUDE.md < 200 lines — index, not a book

**Rule:** Keep `CLAUDE.md` a terse index that points at detailed rule files. Anthropic recommends staying under 200 lines; longer files fight with other context in Claude's window and get truncated.

**Why:** `CLAUDE.md` is loaded into every Claude Code session. Bloated files consume context budget that should go to actual work.

**Where:** `adapters/claude-code/CLAUDE.md` models the terse-index pattern. Each `rules/*.md` file owns its topic.

### Orchestrator pattern — multi-task plans delegate to sub-agents

**Rule:** For plans with > 1 task, the main session orchestrates and dispatches build work to `plan-phase-builder` sub-agents (preferring parallel dispatch when tasks are independent). Main session stays lean.

**Why:** context accumulates ~200 tool uses in a long plan, degrading output quality. Sub-agents get fresh context per dispatch; orchestrator's context only grows by Task invocations + concise summaries.

**Where:** `adapters/claude-code/rules/orchestrator-pattern.md`.

## AI-collaboration practices

### Evidence-based task completion — no self-reporting

**Rule:** Plan checkboxes may only be flipped by the `task-verifier` agent. Self-reporting is forbidden.

**Why:** self-report has failed in practice — "done" is too easy to claim without doing. A separate verifier agent cross-checks claims against the actual repo state.

**Where:** `adapters/claude-code/agents/task-verifier.md` + hook `plan-edit-validator.sh`.

### Anti-vaporware — mechanical verification of runtime behavior

**Rule:** Runtime features (UI, API, webhooks, migrations) must have runtime verification: a replayable command that exercises the feature end-to-end. "Typecheck passed" is not verification.

**Why:** features that don't work at runtime have shipped because the build succeeded + code existed. The mechanical gate forces actual exercise before the task checkbox flips.

**Where:** `adapters/claude-code/rules/vaporware-prevention.md`, backed by `runtime-verification-executor.sh` + `runtime-verification-reviewer.sh`.

### Tool-call budget — forced pause every 30 calls

**Rule:** After every 30 Edit/Write/Bash calls, the harness blocks the next tool call until `plan-evidence-reviewer` has been invoked to audit progress.

**Why:** attention degrades in long sessions. An external forcing function catches drift before it accumulates.

**Where:** `adapters/claude-code/hooks/tool-call-budget.sh`.

### Automation mode — opt-in autonomy

**Rule:** Default mode is `review-before-deploy` — Claude pauses before any command matching a deploy-class matcher (`git push`, `gh pr merge`, etc.). Users opt IN to `full-auto` via config or `/automation-mode full-auto`.

**Why:** autonomous execution is powerful, but the safe default is human-in-the-loop for irreversible operations.

**Where:** `adapters/claude-code/hooks/automation-mode-gate.sh` + `adapters/claude-code/commands/automation-mode.md`.

## Security practices

### No secrets in harness code — ever

**Rule:** No passwords, tokens, API keys, or real emails in committed harness files. Even as "placeholder" or "fallback" values.

**Why:** placeholders get copy-pasted into real usage. A hardcoded test-password fallback in this harness's own `verify-ui.mjs` template eventually appeared verbatim in a downstream project's test-user creation script — real-world demonstration of the risk.

**Where:** `principles/harness-hygiene.md`, enforced by `harness-hygiene-scan.sh`.

### Pre-push credential scanner — every push, every repo

**Rule:** A global git `core.hooksPath` runs a credential-pattern scanner on every `git push` in every repo. 18+ credential families blocked by default; teams extend via `~/.claude/business-patterns.d/*.txt`.

**Why:** credentials should never reach a remote. The last-line defense catches slip-throughs.

**Where:** `adapters/claude-code/hooks/pre-push-scan.sh`, wired globally by `install.sh`.

### Account-aware public-repo block

**Rule:** When the current account has `public_blocked: true` in `accounts.config.json`, all public-repo creation and visibility-change operations are blocked. Pairs with the GitHub-org-level setting.

**Why:** public is a one-way door. Accidental public creation on a work account can't be undone quietly.

**Where:** `adapters/claude-code/settings.json.template` PreToolUse hook, config in `~/.claude/local/accounts.config.json`.

### Decision records for Tier 2+ — mechanical atomicity

**Rule:** Every significant decision (schema change, cross-file pattern, choice between alternatives) requires a standalone `docs/decisions/NNN-*.md` record committed alongside the implementation. An index `docs/DECISIONS.md` tracks all records. Gate hook enforces atomicity: record and index must be staged together.

**Why:** decisions lose context fast. A dedicated record preserves the reasoning; the index provides navigability.

**Where:** `adapters/claude-code/rules/planning.md` + `adapters/claude-code/hooks/decisions-index-gate.sh`.

## Planning + decision practices

### Planning before building, completeness over speed

**Rule:** For work > 15 min or involving architectural decisions, enter plan mode. Write a plan file. Surface decisions with alternatives + recommendation. Only start implementing after ambiguities are resolved.

**Rule (stronger):** Never prioritize speed over completeness. Scope is mechanical — whatever is in the plan's task list. Deferral is only legitimate for dependency-blocked or user-explicitly-deferred tasks.

**Where:** `adapters/claude-code/rules/planning.md`.

### Mid-build decision tiering

**Rule:** Classify every mid-build decision by reversibility:
- **Tier 1** (isolated, trivially reversible): continue + document in plan's Decisions Log
- **Tier 2** (multi-file, revertible): commit checkpoint first, continue + document with SHA
- **Tier 3** (DB schema, public API, auth, production): pause, document tradeoffs, wait for approval

**Why:** the cost of an unwanted irreversible action is much higher than the cost of pausing to confirm.

**Where:** `adapters/claude-code/rules/planning.md` Mid-Build Decisions section.

## Testing + verification practices

### Link validation + consistency audit — mechanical

**Rule:** Every commit that adds or modifies hrefs runs `npm run test:links`. Every significant commit runs `npm run audit:consistency` which catches raw string formatting, unapproved colors, outline-only buttons, missing loading states.

**Where:** `adapters/claude-code/rules/testing.md`, scripts in `adapters/claude-code/scripts/`.

### UX validation after substantial builds — three audience-aware agents

**Rule:** Run `ux-end-user-tester`, `domain-expert-tester`, and `audience-content-reviewer` after new features, page redesigns, or workflow changes. All P0 and P1 findings must be fixed.

**Why:** UX issues shipped to production cost 10x to fix vs. catching them pre-commit.

**Where:** `adapters/claude-code/rules/testing.md` UX Validation section.

### Visual regression via screenshots — layout that matters

**Rule:** For pages where spatial layout matters (funnels, dashboards, detail panels), use Playwright's `toHaveScreenshot()` to baseline-and-diff. Catches CSS class on the wrong container, SVG overlap, responsive breakpoint regressions.

**Where:** `adapters/claude-code/rules/testing.md`.

## Documentation practices

### Status documents update with work, not later

**Rule:** Update `SCRATCHPAD.md`, backlog, and plan status **immediately** when work completes. "I'll update docs later" means "docs will be stale."

**Where:** `adapters/claude-code/CLAUDE.md` Execution section.

### Documentation staleness checks — weekly harness review

**Rule:** A `/harness-review` skill runs weekly (scheduled) and checks: enforcement-map integrity (every referenced hook/agent/skill exists), dead internal links in docs, rule-reference integrity, stale decision records, ungitignored sensitive files, harness-repo drift.

**Where:** `adapters/claude-code/skills/harness-review.md`.

### Code-to-docs atomicity (coming in `document-freshness-system.md` plan)

**Rule (planned):** When a harness-layer file is created/deleted/renamed, `docs/harness-architecture.md` or `docs/harness-guide.md` must also be staged in the same commit.

**Status:** proposed; tracked in `document-freshness-system.md` plan. See that plan for rationale.

## References

- `principles/harness-hygiene.md` — the load-bearing hygiene rule
- `adapters/claude-code/rules/planning.md` — decisions, scope, mid-build protocol
- `adapters/claude-code/rules/testing.md` — E2E, UX validation, deployment validation
- `adapters/claude-code/rules/vaporware-prevention.md` — anti-vaporware enforcement map
- `adapters/claude-code/rules/orchestrator-pattern.md` — sub-agent dispatch for long plans
- `docs/harness-architecture.md` — detailed enforcement map + hook chains
- `docs/harness-guide.md` — file-by-file reference

## Contributing

Propose new best practices by opening an issue. The bar: the practice must be (a) generally applicable to more than one project, (b) enforceable or checkable (not just aspirational), (c) worth the friction it adds.
