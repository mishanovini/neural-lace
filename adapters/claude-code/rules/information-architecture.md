# Information Architecture — Where Each Kind of Harness Content Belongs

**Classification:** Hybrid. The "where content belongs" discipline is Pattern (the maintainer and agent self-apply when authoring or routing content). The mechanical layers backing it are siblings: `claude-md-hygiene-gate.sh` (size + rule-body-shape + duplication detection on CLAUDE.md), `evals/golden/rules-index-coverage.sh` (rule-file ↔ INDEX.md bidirectional sync), `definition-on-first-use-gate.sh` (acronym discipline in doctrine docs), `plan-lifecycle.sh` (plan auto-archival on terminal status), and the weekly hygiene cadence. Each surface has its own mechanism; this rule is the *router* that says where a given new piece of content should land.

**Originating context:** the harness has accumulated content across 40+ rules, dozens of ADRs, dozens of plans, discoveries, reviews, audit docs, templates, hooks, agents, skills, and several machine-local config files. Two recurring failure modes drove the need to codify the routing:

1. **CLAUDE.md bloat.** Content of all kinds — operating rules, enforcement detail, examples, edge cases, decision rationale — accumulated in CLAUDE.md because it was the most-loaded context. Result: CLAUDE.md became the place to put anything, indistinguishable from a generic doctrine dump, and the actual canonical files (`rules/*.md`, `docs/decisions/*.md`) were duplicated rather than referenced.
2. **Orphaned content.** Information that genuinely existed in the harness — credential reference, persona files, audit reports — was not discoverable from CLAUDE.md or any session-boundary surface, so agents asked for credentials/personas/details that were already documented. Result: friction and embarrassment ("the doc exists, why didn't you read it?") when the lookup failure traces back to the agent having no map of where things live.

The rule below is the canonical map. It names where each content kind belongs, what CLAUDE.md is FOR (routing only, ≤ 200 lines), and the anti-patterns the sibling mechanisms detect.

## Canonical locations by content kind

When you have a piece of content to land — a new principle, a new gate, a decision record, a discovery, an audit finding, a piece of state — match its **kind** to the canonical location below. Do NOT duplicate body content into CLAUDE.md; CLAUDE.md routes, it does not store.

| Content kind | Canonical location | Lifetime | Discoverability |
|---|---|---|---|
| **Operating principles** (Rules 0–7, Decision Principles, Design Philosophy) | `adapters/claude-code/rules/principles.md` | Permanent | Loaded by `@~/.claude/rules/principles.md` at the top of CLAUDE.md; Stop-hook companion `principles-compliance-gate.sh` |
| **Per-surface rules** (per-language, per-tool, per-lifecycle-stage) | `adapters/claude-code/rules/<rule-name>.md` (one rule per concern; ≤ ~300 lines per file is a soft target) | Permanent | `rules/INDEX.md` (CI-enforced bidirectional sync via `evals/golden/rules-index-coverage.sh`) |
| **Enforcement substrate** (gates, scanners, validators, surfacers) | `adapters/claude-code/hooks/<hook-name>.sh` (one hook per concern) | Permanent | `docs/harness-architecture.md` live inventory; `adapters/claude-code/rules/vaporware-prevention.md` enforcement-map |
| **Sub-agent prompts** (reviewers, builders, verifiers) | `adapters/claude-code/agents/<agent-name>.md` | Permanent | `docs/harness-architecture.md` agent-inventory section |
| **Skills** (slash-commands, user-invocable workflows) | `adapters/claude-code/skills/<skill-name>.md` | Permanent | Skill discovery via `Skill` tool + session-start cheatsheet |
| **Templates** (plan / decision / completion / PRD / scratchpad shapes) | `adapters/claude-code/templates/<template-name>.md` | Permanent | Referenced by rules that consume them (`planning.md` → `plan-template.md`, etc.) |
| **Architectural decisions (Tier 2+)** | `docs/decisions/NNN-<slug>.md` (numbered, immutable history) | Permanent | `docs/DECISIONS.md` index |
| **Implementation plans** (Mode: code / Mode: design) | `docs/plans/<slug>.md` (active) → `docs/plans/archive/<slug>.md` (terminal) | Lifecycle-managed by `plan-lifecycle.sh` | Active plans surfaced by `stale-active-plan-surfacer.sh` SessionStart |
| **Mid-process discoveries** (architectural realizations, scope expansions, dependency surprises) | `docs/discoveries/YYYY-MM-DD-<slug>.md` | Permanent | Pending discoveries surfaced by `discovery-surfacer.sh` SessionStart |
| **Audit / review passes** (UX agent runs, code-review batches, retrospectives) | `docs/reviews/YYYY-MM-DD-<slug>.md` | Permanent | Indexed by date; referenced from the work that consumed the findings |
| **Class-aware findings** (six-field schema entries) | `docs/findings.md` | Permanent | Schema-validated at commit time by `findings-ledger-schema-gate.sh` |
| **Failure-mode catalog** (named recurring failure classes) | `docs/failure-modes.md` (single file, FM-NNN entries) | Permanent | DIAGNOSTIC-FIRST PROTOCOL grep target per `~/.claude/rules/diagnosis.md` |
| **Sessions / handoffs** (multi-day initiative continuity) | `docs/sessions/YYYY-MM-DD-<slug>.md`, `docs/handoffs/<topic>-<date>.md` | Permanent | Manual reference; not surfaced at session start (intentional — these are large) |
| **Backlog** (open work not yet claimed by a plan) | `docs/backlog.md` (single file, P0/P1/P2 sections) | Updated continuously; items move to `Completed` section when shipped | SessionStart staleness check |
| **Ephemeral session state** (working memory, in-flight notes) | `SCRATCHPAD.md` (gitignored, per-session, hard cap 30 lines per `templates/scratchpad-template.md`) | Cleared at `/clear` or `/compact` | Read first on session start |
| **Machine-local config** (credentials, accounts, projects, automation-mode, dispatch-mode) | `~/.claude/local/*.json` + `~/.claude/local/*.md` (gitignored, per-machine) | Permanent (per-machine) | `~/.claude/local/credentials-reference.md` cited in CLAUDE.md `## Credentials Reference` |
| **Operational state** (waivers, retry-guard logs, calibration entries, propagation audit log) | `.claude/state/` (project-local, gitignored) or `~/.claude/state/` (machine-local) | Operational lifetime (rotation policies vary per substrate) | Surfaced when relevant (e.g., unresolved-stop-hooks.log on hook FAIL) |
| **Canonical discovery index** (the navigation aid for the rules system itself) | `adapters/claude-code/rules/INDEX.md` | Permanent | CI-enforced sync via `evals/golden/rules-index-coverage.sh` |

## What CLAUDE.md is FOR

CLAUDE.md is **a routing index**, not a content store. Its job is to make the canonical files above discoverable from the loaded-on-every-session context. Concretely, CLAUDE.md should contain:

- **The principles `@`-reference line** (`@~/.claude/rules/principles.md`) — the load-bearing canonical-reference inclusion.
- **The short-form principle list** (Rules 0–7, one line each) — enough for the agent to recognize Rule N by number in conversation without re-loading the principles doc.
- **The standing directives that bind every session** (autonomy posture, credentials-reference pointer, drive-to-completion mandate, machine setup, session-end protocol pointer) — short paragraphs that name WHERE the detail lives.
- **A `## Detailed Protocols` section** that lists each `rules/*.md` file with a one-line description — so a session knows what rules exist and can read the per-rule file for substance.

CLAUDE.md should NOT contain:

- **Multi-paragraph rule bodies.** If a rule is more than ~4 lines, it belongs in `rules/<rule-name>.md`. The CLAUDE.md entry is a pointer, not a copy.
- **Examples or edge cases.** Those live in the per-rule file's body.
- **Decision rationale.** That lives in `docs/decisions/NNN-*.md`.
- **Changelog / version history.** That lives in git history and ADRs.
- **Enforcement-map detail.** That lives in `vaporware-prevention.md` and `docs/harness-architecture.md`.
- **Duplicated content** that also exists in a `rules/*.md` file. Duplication drifts; one source of truth or nothing.

**Size target: ≤ 200 lines.** This is a soft ceiling that the `claude-md-hygiene-gate.sh` hook surfaces as a warning above the threshold. Above ~250 lines the file has become a content dump; the cure is to extract bodies into `rules/*.md` and leave one-line pointers behind.

## Anti-patterns (what the sibling mechanisms detect)

The information architecture is defended by mechanisms at the boundaries where drift is most likely. The anti-patterns each mechanism catches:

1. **CLAUDE.md grows past the line ceiling.** Surfaced by `claude-md-hygiene-gate.sh` as a warn (initial) → block (after calibration). The remedy is extraction-then-pointer, not deletion.
2. **CLAUDE.md acquires rule-body-shaped content.** New content matching multi-line numbered lists, `Rule X:` headers, or > 5-line paragraphs without a `rules/*.md` pointer is flagged by the same hook. The remedy is to author the content in a new `rules/<name>.md` file and leave a one-line pointer in CLAUDE.md.
3. **CLAUDE.md duplicates content with a `rules/*.md` file.** The hook detects 5+ consecutive matching words between CLAUDE.md and any `rules/*.md` file and surfaces the duplication. The remedy is to delete the duplicated body in CLAUDE.md and reference the rule file.
4. **A new `rules/*.md` file lands without an INDEX.md row.** Caught by `evals/golden/rules-index-coverage.sh` (CI). The remedy is to add the row in the same commit.
5. **An INDEX.md row points at a deleted file.** Caught by the same golden test. The remedy is to remove the stale row when retiring a rule.
6. **A plan with `Status: COMPLETED` lingers under `docs/plans/`.** Caught by `plan-lifecycle.sh` (PostToolUse on plan-file edit) and `plan-status-archival-sweep.sh` (SessionStart safety net). The remedy is automatic — terminal-status flips trigger `git mv` to `docs/plans/archive/`.
7. **Acronyms in `build-doctrine/**/*.md` used without definition.** Caught by `definition-on-first-use-gate.sh` at commit time. The remedy is glossary entry or parenthetical definition.
8. **The agent asks for a credential that is already configured.** This is the orphaned-content failure mode. Detection is partial (extension of `principles-compliance-gate.sh` flags credential-asking phrases against the credentials-reference doc). The remedy is to consult `~/.claude/local/credentials-reference.md` BEFORE asking.

## How to add a new content kind

When a new content kind emerges (e.g., the harness adds a "personas" surface, or a "playbooks" library), the routing decision must be explicit:

1. **Identify the canonical location.** Pick the directory + filename pattern. Cite the lifetime (permanent / lifecycle-managed / ephemeral).
2. **Identify the discoverability mechanism.** Is it surfaced at session start? At a specific tool call? Indexed in another file? Without a discoverability mechanism the content is orphaned.
3. **Update this rule** to add the new kind to the table above.
4. **Update CLAUDE.md** (only if the discoverability path includes CLAUDE.md as a routing target) to add a one-line pointer.
5. **If the new kind needs a CI-enforced index** (like `rules/INDEX.md`), add the golden test under `evals/golden/`.

The cost of routing a new kind correctly at introduction is small. The cost of discovering, a year later, that all the personas are in CLAUDE.md instead of `adapters/claude-code/personas/` is the cleanup effort that motivated this rule.

## Cross-references

- `adapters/claude-code/CLAUDE.md` — the routing index this rule governs.
- `adapters/claude-code/rules/INDEX.md` — the canonical rule discovery index.
- `evals/golden/rules-index-coverage.sh` — CI-enforced rules/INDEX bidirectional sync.
- `adapters/claude-code/hooks/claude-md-hygiene-gate.sh` — the size + rule-body-shape + duplication gate (sibling, lands in the same hygiene-2 initiative).
- `adapters/claude-code/hooks/session-start-discovery-cheatsheet.sh` — surfaces the where-to-find map at every session start (sibling, lands in the same hygiene-2 initiative).
- `adapters/claude-code/rules/harness-maintenance.md` — global-first rule changes, commit to neural-lace, update architecture doc.
- `adapters/claude-code/rules/harness-hygiene.md` — what NEVER ships (the perimeter); this rule names where what DOES ship belongs.
- `adapters/claude-code/rules/workstream-memory-ecology.md` — sibling rule for cross-project memory tiers (T1–T4). This rule is the per-project-tier (mostly T2) content-kind router.
- `docs/harness-architecture.md` — live inventory of hooks, agents, skills, templates (the *what exists*); this rule is the *where each kind goes*.
- `docs/best-practices.md` — narrative explanation of why each practice exists; this rule is the structural inventory of where they live.

## Enforcement

| Layer | What it enforces | File |
|---|---|---|
| Rule (this doc) | Canonical location for each content kind; CLAUDE.md is routing-only; anti-patterns the mechanisms detect | `adapters/claude-code/rules/information-architecture.md` |
| Hook (sibling) | CLAUDE.md size ceiling + rule-body-shape detection + duplication detection | `adapters/claude-code/hooks/claude-md-hygiene-gate.sh` |
| Hook (sibling) | Session-start discoverability — surface the where-to-find map at every session boundary | `adapters/claude-code/hooks/session-start-discovery-cheatsheet.sh` |
| Golden test | Rules ↔ INDEX bidirectional sync | `evals/golden/rules-index-coverage.sh` |
| Existing hooks | Plan lifecycle / discovery surfacing / definition-on-first-use / findings schema (each at its own surface) | various, indexed in `vaporware-prevention.md` |
| User authority | The maintainer reads the surfaced cheatsheet, applies the routing decision when authoring new content | (Pattern) |

The rule is the routing map. The sibling mechanisms defend the boundaries where drift is most likely (CLAUDE.md, INDEX.md sync, session-start discoverability). Together they make orphaned content and bloated-CLAUDE.md the rare cases that get caught rather than the common cases that accumulate silently.

## Scope

Applies in every project whose Claude Code installation has this rule file present at `~/.claude/rules/information-architecture.md`. Loaded contextually by the harness; no opt-in or hook wiring is required for the rule itself. The sibling mechanisms (CLAUDE.md hygiene gate, session-start cheatsheet) have their own scope conditions (gate fires on `git commit` touching `adapters/claude-code/CLAUDE.md`; cheatsheet fires at every SessionStart). The rule binds the harness-development workflow specifically — it does not govern the structure of downstream products that consume the harness, which retain their own information-architecture conventions.
