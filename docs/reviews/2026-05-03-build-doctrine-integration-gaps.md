# Neural Lace gaps surfaced during Build Doctrine integration analysis

**Date:** 2026-05-03
**Source:** Build Doctrine + Neural Lace deep comparative review (`~/claude-projects/Build Doctrine/outputs/`). See `outputs/analysis/03-comparative-analysis.md` and `outputs/unified-methodology-recommendation.md`.
**Owner:** misha
**Status:** open — addressed in Phase 1d-E (harness-cleanup) per the unified methodology recommendation.

## Context

While conducting the deep review of Build Doctrine vs Neural Lace (plan `build-doctrine-cheerful-hearth`, sessions 2026-05-03), several Neural Lace–side gaps surfaced. They are not blocking the integration but should be addressed during or after Phase 1d to keep the harness clean as new doctrine-driven mechanisms land. Consolidated here per the bug-persistence rule rather than scattered in the methodology recommendation.

## Findings

### NL-GAP-A — Stop-hook overlap analysis

**Observation.** Five Stop hooks all fire to detect narrative-integrity failures: `narrate-and-wait-gate.sh`, `transcript-lie-detector.sh`, `goal-coverage-on-stop.sh`, `imperative-evidence-linker.sh`, `deferral-counter.sh`. Each is documented as catching a distinct class, but the classes are adjacent.

**Why this is a gap.** Adjacent classes invite duplicate firings (the same session-end issue triggering multiple hooks with overlapping messages) and make it hard to tell which hook is doing load-bearing work. During this session the `narrate-and-wait-gate` and the `bug-persistence-gate` both fired in close succession; they're catching distinct things but the experience reads as "multiple hooks complaining about the same response."

**Proposed action.** Phase 1d-E task — produce a written orthogonality matrix. For each pair of the five hooks, document one example the first catches that the second misses, and vice versa. If any pair has no clear separation, consolidate. This is verification, not necessarily deletion — most likely all five are genuinely orthogonal but the documentation is missing.

### NL-GAP-B — `pipeline-agents.md` is project-specific in the global rules directory

**Observation.** `~/.claude/rules/pipeline-agents.md` references roles named "BUILDER", "VERIFIER", "DECOMPOSER" that are not part of the global harness role inventory. The naming convention and the failure-pattern list (ghost props, conditional invisibility, stale org data, missing RLS, Trigger.dev registration, API route in middleware) are clearly Pocket Technician-specific.

**Why this is a gap.** A project-specific rule in `~/.claude/rules/` runs against every project the harness sees, including projects where these patterns don't apply. Pollutes the rule set and confuses new readers (per Q7 doc-clarity concern).

**Proposed action.** Phase 1d-E task — relocate `pipeline-agents.md` to Pocket Technician's project `.claude/rules/` (or merge into the project's CLAUDE.md). Verify no other rules reference it.

### NL-GAP-C — `claim-reviewer` agent post-Gen6 reassessment

**Observation.** `claim-reviewer` was added as the residual mitigation for verbal vaporware (claims in conversation not citing file:line). Per `vaporware-prevention.md`, it's self-invoked and has been called out as the unclosed Gen 4 gap. NL Gen 6 narrative-integrity hooks (`transcript-lie-detector`, `imperative-evidence-linker`, `goal-coverage-on-stop`) substantially mechanize the same class.

**Why this is a gap.** A self-invoked agent that may have been mechanically superseded is a maintenance overhead with no clear owner. Either (a) `claim-reviewer` still catches a class the Gen 6 hooks miss and should be made non-optional or merged into a hook, or (b) it's been superseded and should be deprecated.

**Proposed action.** Phase 1d-E task — for each class `claim-reviewer` was meant to catch, identify whether a Gen 6 hook now catches it. If yes for all classes, deprecate the agent. If some classes remain uncovered, mechanize as a Stop-hook variant rather than leaving as self-invoked.

### NL-GAP-D — Telemetry collection planned but not shipped

**Observation.** `docs/harness-strategy.md` (~line 296+) lists telemetry collection as a future capability (security maturity model, 2026-08 target). The doctrine's findings ledger (Phase 1c C9 mechanism proposal) and the future process-improvement-observer (Phase 1d-E in unified methodology) both require telemetry as a primary data source.

**Why this is a gap.** Several Phase 1d mechanism proposals (C9 findings-ledger schema, C20 telemetry-feeds-ledger, future process-improvement-observer) depend on telemetry existing. If telemetry slips past 2026-08, those mechanism proposals slip. The dependency chain is currently invisible — the methodology recommendation cites C9/C20 without flagging that telemetry is the upstream prerequisite.

**Proposed action.** Phase 1d-E task — explicitly flag telemetry as a prerequisite for C9 + C20 + process-improvement-observer in the methodology recommendation's dependencies section, and confirm the 2026-08 target is on track. If at risk, decide whether to (a) implement a minimal telemetry collector earlier specifically to unblock these mechanisms, or (b) defer the dependent mechanisms.

### NL-GAP-F — Rules possibly superseded by hooks (audit needed)

**Observation.** During Q3 deprecation discussion (2026-05-03), I noted that `vaporware-prevention.md` is now almost entirely a stub pointing at hooks (the rule explicitly self-describes as a stub). Other rules may have similarly migrated mechanism content into hooks while the prose remains as if it were authoritative discipline. Specific candidates worth checking: portions of `testing.md` (TDD discipline mostly enforced by `pre-commit-tdd-gate.sh`), portions of `diagnosis.md` (post-Gen6 narrative-integrity hooks may cover the "encode the fix" loop mechanically), portions of `git.md` (force-push and `--no-verify` are blocked by inline PreToolUse Bash blockers).

**Why this is a gap.** A rule that reads as authoritative discipline but is actually a stub for hooks creates two failure modes: (a) readers (human or LLM) treat the prose as load-bearing when the hooks are doing the work, and update prose without realizing the hook is the actual lever; (b) over time, rule prose drifts out of sync with hook behavior because the prose is no longer the source of truth.

**Proposed action.** Phase 1d-E task — for each rule in `~/.claude/rules/`, identify which sections are operationalized by hooks. Rules where >70% of content is now hook-enforced should follow `vaporware-prevention.md`'s pattern: become a stub that points at the hook enforcement map. Reduces drift surface and makes the source of truth (the hook) clearer.

### NL-GAP-G — Definition-on-first-use enforcement hook (Phase 1d-F proposal)

**Observation.** Q7 of the unified methodology recommendation (2026-05-03 session) surfaced that doctrine docs use ~50+ acronyms heavily without consistent definition. The user explicitly asked for a glossary; that glossary now lives at `~/claude-projects/Build Doctrine/outputs/glossary.md`. To prevent the same drift from recurring, definition-on-first-use should be enforced mechanically.

**Why this is a gap.** A glossary is necessary but not sufficient. Without enforcement, new doctrine content can introduce undefined acronyms, and the glossary slowly falls out of sync. The doctrine claims "documents are living; updates propagate on trigger" (Principle #9) — definition-on-first-use should be one such trigger.

**Proposed action.** Phase 1d-F (new phase, per Q7 answer) — implement a pre-commit hook that scans every `*.md` under `neural-lace/build-doctrine/` for first-use acronyms (regex-detected, ALL-CAPS or mixed-case patterns) and either: (a) requires a definition-in-context (the acronym is followed by a parenthetical expansion within the doc), OR (b) requires a cross-reference to `glossary.md`. Blocks commits that introduce undefined terms. The glossary itself becomes editable to add new entries; the hook just ensures new uses are anchored to a definition somewhere.

### NL-GAP-E — C16 behavioral-contracts validator residual risk

**Observation.** During Q4 anti-vaporware discussion (2026-05-03 session), I noted that C16 (behavioral-contracts validator) can be gamed by superficial conformance — a builder could mark a spec "frozen" with `idempotency: true` and `failure_modes: standard` as vacuous prose, and the validator's schema check would still pass.

**Why this is a gap.** If C16's enforcement is purely schema validation, it is theater. The mechanism's actual reliability gain comes from requiring CONCRETE invariants, not just the presence of fields.

**Proposed action.** Phase 1d-C (when C16 is implemented) — design the validator to require concrete invariants per category. For idempotency: require an explicit invariant statement that maps inputs to expected post-condition. For failure modes: require named modes from a project-defined enum, not free-text. For retry semantics: require numeric backoff parameters. Validation rejects vacuous fillers.

## Cross-references

- `~/claude-projects/Build Doctrine/outputs/analysis/03-comparative-analysis.md` — full comparative analysis with C-mechanism proposals
- `~/claude-projects/Build Doctrine/outputs/unified-methodology-recommendation.md` — Phase 1d-A through 1d-D plus the implicit Phase 1d-E (harness cleanup) this review motivates
- `docs/harness-strategy.md` — telemetry roadmap (NL-GAP-D)
- `~/.claude/rules/vaporware-prevention.md` — `claim-reviewer` residual-gap framing (NL-GAP-C)

## Resolution log

(Populated as gaps close. Each entry: gap ID, resolved-by commit/plan, date.)

- pending all 5 — to be addressed in Phase 1d-E or earlier per the methodology recommendation's prioritization.
