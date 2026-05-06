# Neural Lace — Evolution Strategy

**Status:** ACTIVE
**Created:** 2026-04-12
**Last reviewed:** 2026-05-05
**Owner:** Misha
**Repo:** `~/claude-projects/neural-lace/` (absorbs claude-config)

## Recent milestones
- **2026-05-06:** Build Doctrine integration arc continued — Tranche 1.5 architecture-simplification arc closed (deterministic close-plan procedure replaces 13-dispatch closure; mechanical evidence substrate; risk-tiered verification; calibration loop; work-shape library); Tranches 2 (template schemas — 7 files), 3 (template content — 29 files), 6-orch (Python orchestrator scaffolding), 5a (knowledge-integration ritual at `build-doctrine/doctrine/07-knowledge-integration.md` — 7-trigger taxonomy), 6a (propagation engine framework + 8 starter rules + audit log at `build-doctrine/telemetry/propagation.jsonl`), and 5a-integration (audit-log analyzer + `/harness-review` Check 13 + pilot-friction template) all shipped. Pre-pilot infrastructure complete; Tranche 4 (canonical pilot) is the structural wall remaining (per `docs/plans/tranche-4-canonical-pilot-handoff.md`). Tranches 5b (cadence calibration), 6b (per-canon rules), 7 (residual C-mechanisms) gate on pilot evidence; Tranches 5c, 6c, HARNESS-GAP-11 gate on 2026-08 telemetry. Validates G7 (Doctrine-Driven Evolution) — the doctrine + measurement substrate ship before the pilot consumes them.
- **2026-05-05:** HARNESS-GAP-08 (spawn_task report-back convention) and HARNESS-GAP-13 (hygiene-scan expansion Layers 1-2) shipped. HARNESS-GAP-17 (this doc-sweep) updates the user-facing narrative layer to match the Gen 5/6 + Build Doctrine integration arc. Numbering conflict between two GAP-16 entries resolved (closure-validation kept as 16; docs-stale renumbered to 17).
- **2026-05-04 — May 2026 (Build Doctrine Phase 1d arc):** Build Doctrine integration shipped seven mechanism families addressing gaps in the Gen 4-6 substrate: **Discovery Protocol** (capture-and-decide for mid-process learnings; surfacing at session start), **Comprehension Gate** (R2+ builders articulate Spec / Edges-covered / Edges-NOT-covered / Assumptions; agent applies three-stage rubric), **PRD Validity + Spec Freeze** (plan creation requires valid `prd-ref:`; edits to declared files require `frozen: true`; 5-field plan-header schema), **Findings Ledger** (`docs/findings.md` with six-field entries; bug-persistence accepts as fourth durable target), **Definition-on-First-Use** (acronym-must-be-defined gate for doctrine docs), **Scope-Enforcement Gate redesign** (plans become living artifacts via `## In-flight scope updates` section; three structural options replace waiver model), **DAG Review Waiver Gate** (Tier 3+ plans require substantive waiver before first Task invocation). Settings-template-vs-live divergence reconciled (HARNESS-GAP-14 + Phase 1d-G followups). Decision records 013-024 land. Validates G6 (Progressive Autonomy) further: more judgment encoded into mechanical gates rather than self-applied prose.
- **2026-04-26:** Generation 6 narrative-integrity hooks landed — six new Stop/PreToolUse hooks read `$TRANSCRIPT_PATH` JSONL (which the agent cannot edit) to close the gap between agent claims and transcript evidence: A1 first-message goal extraction with checksummed integrity, A3 self-contradiction detection, A5 deferral surfacing, A7 strong-imperative coverage, A8 vaporware-volume gate on PR creation. Originating incident: agent shipped a PR with 800 lines of docs + 174 lines of CI YAML and ZERO execution evidence while the plan's DoD was unchecked. Validates G3 (Comprehensive Security) by moving enforcement from "agent should self-report honestly" to "agent's own transcript is the witness."
- **2026-04-24:** Generation 5 harness extension landed — adversarial observation of the running product, plan-lifecycle integrity, self-improvement meta-loop. Key Gen 5 additions: end-user-advocate acceptance loop (plan-time + runtime), `product-acceptance-gate.sh` Stop hook position 4, `plan-lifecycle.sh` PostToolUse archival, `plan-deletion-protection.sh`, `docs/failure-modes.md` six-field catalog, class-aware reviewer feedback (7 adversarial agents emit `Class:` + `Sweep query:` + `Required generalization:`), capture-codify PR template + branch-protection. Validates G1 (Self-Evaluation) by ensuring every runtime FAIL produces a generalized harness-improvement proposal via `enforcement-gap-analyzer`.
- **2026-04-15:** Generation 4 harness hardening landed — mechanical hooks replace self-enforced rules to prevent vaporware. Additions: pre-commit TDD gate with 4 layers, plan-edit-validator with evidence-first authorization, runtime-verification executor + correspondence reviewer, blocking tool-call-budget, plan-reviewer, verify-feature skill. Validates G3 (Comprehensive Security) and G6 (Progressive Autonomy) by moving enforcement from prose to hook-executed gates — the system refuses broken work at commit and session-end without requiring the builder to remember rules.

## Vision

Build **Neural Lace** — a self-learning, continuously evolving foundation for AI-assisted development. A harness platform that grows with its host, usable across AI coding tools (Claude Code, Codex, Gemini, Cursor) and by other developers.

## Key Design Documents

| Document | Location | Covers |
|----------|----------|--------|
| Risk-Based Permission Model | `principles/permission-model.md` | 6 risk dimensions, 4 tiers, scoring algorithm, dual-run migration |
| Progressive Autonomy | `principles/progressive-autonomy.md` | Trust accumulation, autonomy ladder (L1-L5), hard limits |
| Forward Compatibility | `principles/forward-compatibility.md` | Abstraction rules, adapter interface, what survives tool changes |
| Risk Profiles (seed data) | `patterns/risk-profiles/actions.jsonl` | 20 seeded profiles migrated from hooks + common actions |
| Telemetry Schemas | `telemetry/schema/*.json` | Event schemas for permissions, hooks, agents, sessions |
| Golden Tests | `evals/golden/*.sh` | Behavioral tests for critical permission boundaries |

The guiding principle: **each layer of abstraction should let you build more with less specific guidance.** The harness should progressively encode judgment so that sessions become more autonomous over time, not just more rule-bound.

## Strategic Goals

### G1: Self-Evaluation & Continuous Learning
The harness evaluates and improves itself continuously — not just at scheduled intervals. It observes its own behavior, detects patterns, proposes improvements, and tracks the effectiveness of changes over time.

### G2: Intelligent Loading
Components load only when relevant, minimizing context overhead while keeping all capabilities available on demand.

### G3: Comprehensive Security
Expand from credential-focused defense to full-spectrum security: dependency safety, data flow, supply chain, audit trail, prompt injection awareness.

### G4: Tech Agnostic
Separate universal principles from tool-specific enforcement, enabling the same harness to drive Claude Code, Codex, Cursor, Gemini, and future tools.

### G5: Distributable
Package the harness so others can install, configure, and benefit from it — whether open-sourced or commercialized.

### G6: Progressive Autonomy
Each iteration should encode more judgment into the system, reducing the amount of explicit instruction needed per session while maintaining safety guarantees.

### G7: Dedicated Harness Platform
Graduate from a config directory (`claude-config`) to a standalone product repo with its own runtime, telemetry, learning loop, and eventually a management UI.

---

## Architecture: The Layer Model

```
Layer 0: PRINCIPLES (universal, any AI tool, any project)
    Core values, decision posture, non-negotiables
    Format: plain markdown, no tool-specific syntax

Layer 1: PATTERNS (tool-family-agnostic)
    Rule system, hook system, agent system, template system,
    pipeline system, evaluation system
    Format: structured markdown with machine-readable metadata

Layer 2: ADAPTERS (tool-specific implementations)
    Claude Code: settings.json, CLAUDE.md, agents/*.md
    Codex: AGENTS.md, codex.json
    Cursor: .cursorrules
    Gemini: gemini config format
    Format: native config for each tool

Layer 3: PROJECT-SPECIFIC (per-repo overrides)
    .claude/rules/, audience.md, project CLAUDE.md
    Format: determined by Layer 2 adapter
```

### Layer Boundaries

- **Layer 0 never references a specific tool.** It says "destructive operations require confirmation" not "add a PreToolUse hook for git push --force."
- **Layer 1 defines patterns abstractly.** It says "a pre-commit hook should run tests and check for credentials" not "bash: pre-commit-gate.sh."
- **Layer 2 translates patterns into tool-native config.** This is the only layer that knows about `settings.json` or `.cursorrules`.
- **Layer 3 adds project context.** It knows about your specific database schema, API routes, or audience.

### Migration Path (Current -> Layered)

Phase 1: Annotate existing files with their layer designation (no structural changes).
Phase 2: Split rules that mix principles and enforcement into separate files.
Phase 3: Create adapter infrastructure for a second tool (Codex recommended — closest to Claude Code).
Phase 4: Build installer that generates Layer 2 config from Layer 0+1 source.

---

## Dedicated Harness Repo (G7)

### Why a Separate Repo

`claude-config` is a deployment artifact — it stores files that get copied to `~/.claude/`. As the harness evolves toward self-evaluation, continuous monitoring, and a management UI, it needs its own product infrastructure:

- **Telemetry store**: structured data about hook firings, agent invocations, blocked actions, session durations, component usage frequency
- **Learning loop**: patterns extracted from telemetry → proposed rule improvements → human approval → deployed changes
- **Issue tracker**: harness-level issues (not project bugs — harness gaps, false positives, missed catches)
- **Management UI**: dashboard for usage patterns, security posture, component health, improvement proposals
- **Continuous monitoring runtime**: not just periodic audits, but always-on observation that feeds the learning loop

### Repo Structure (Preliminary)

```
harness/                          ← product repo
  principles/                     ← Layer 0: universal, tool-agnostic
    core-values.md
    permission-model.md
    evaluation-discipline.md
    security-posture.md
    ...
  patterns/                       ← Layer 1: abstract patterns
    rules/
    hooks/
    agents/
    templates/
    pipelines/
  adapters/                       ← Layer 2: tool-specific
    claude-code/
      settings.json.template
      install.sh
      agents/*.md
      hooks/*.sh
    codex/
      ...
    cursor/
      ...
  telemetry/                      ← continuous monitoring
    schema/                       ← event schemas
    collectors/                   ← hooks that emit telemetry events
    store/                        ← local telemetry database (SQLite or JSONL)
    analyzers/                    ← scripts that extract patterns from telemetry
  learning/                       ← self-improvement engine
    proposals/                    ← auto-generated improvement proposals
    accepted/                     ← approved and applied improvements
    rejected/                     ← declined proposals (retained for learning)
  ui/                             ← management dashboard (future)
    ...
  evals/                          ← harness self-tests
    golden/                       ← behavioral golden tests (Layer B)
    structural/                   ← integrity checks (Layer A)
  docs/
    strategy.md                   ← this document
    architecture.md
    ...
```

### Relationship to claude-config

`claude-config` becomes a **downstream consumer** of the harness repo. Specifically:

- The harness repo owns Layer 0 (principles) and Layer 1 (patterns)
- `adapters/claude-code/` replaces what's currently in `claude-config`
- `claude-config` either becomes a subdirectory of the harness repo or is deprecated in favor of `harness/adapters/claude-code/`
- The install script reads from `harness/adapters/claude-code/` and deploys to `~/.claude/`

### Continuous Monitoring Architecture

The monitoring system runs as a background process within each AI coding session, not as an external service. This keeps it self-contained and privacy-preserving.

**What gets tracked (telemetry events):**

| Event | Data | Purpose |
|-------|------|---------|
| `hook.fired` | hook name, trigger, result (pass/block), latency | Usage frequency, false positive rate, performance |
| `agent.invoked` | agent name, invoker, duration, verdict | Utilization patterns, effectiveness |
| `rule.loaded` | rule name, session context | Which rules are actually relevant |
| `action.blocked` | hook/rule that blocked, what was attempted | Security posture, catch rate |
| `session.start` | project, duration, components loaded | Session profiles |
| `session.end` | work completed, plan status, issues encountered | Completion patterns |
| `improvement.proposed` | source (telemetry pattern), description | Learning loop input |
| `improvement.applied` | proposal ID, files changed | Learning loop output |

**How learning works:**

1. Telemetry accumulates locally (never leaves the machine unless explicitly shared)
2. Weekly strategic review reads telemetry and identifies patterns:
   - Hooks that never fire → candidates for removal or retargeting
   - Hooks that fire and always pass → may be unnecessary overhead
   - Agents that get invoked then produce the same finding repeatedly → candidate for a rule
   - Rules that load but never influence behavior → candidates for demotion
   - Blocked actions that the user then manually overrides → false positive, policy needs refinement
3. Patterns become **improvement proposals** (stored in `learning/proposals/`)
4. Human reviews proposals (via UI or CLI) and approves/rejects
5. Approved proposals are applied to the harness, with the change linked to the proposal

**Design-forward principle:** Every new feature should ask "what telemetry event does this emit?" If a component can't be observed, it can't be evaluated, and it can't be improved. Build the collector alongside the feature, not after.

### UI Vision (Future)

A local web UI (likely Next.js, consistent with existing skills) that provides:

- **Dashboard**: security posture score, component health, session stats, recent blocked actions
- **Usage heatmap**: which components fire most/least, by project and time
- **Improvement inbox**: pending proposals with approve/reject/defer actions
- **Issue tracker**: harness-specific issues (false positives, gaps, performance problems)
- **Rule editor**: view/edit rules with live preview of which files they'd match
- **Telemetry explorer**: query and visualize raw telemetry events

This is a v2.0+ deliverable. The telemetry store and learning loop come first — they're valuable without a UI (CLI and review files work initially).

---

## Component Lifecycle Policy

### Agents Are Tools, Not Overhead

Agents live in `~/.claude/agents/` and are spawned on demand. They consume zero context when idle. The policy:

- **Never remove an agent because it hasn't been used recently.** Remove only if its purpose is permanently obsoleted.
- **Review agents for relevance quarterly**, not for recency. The question is "would this be useful if the right situation arose?" not "was it used this month?"
- **Agents should be self-describing.** Each agent file should contain: purpose, when to invoke, what it checks, expected output format.

### Rules Are Contextual

Rules in `~/.claude/rules/` load by file pattern. The policy:

- **Always-loaded rules** (security, git, diagnosis, planning): kept in a designated set, reviewed quarterly for bloat.
- **Contextual rules** (api-routes, database-migrations, ui-components, etc.): load only when relevant files are being edited.
- **CLAUDE.md content**: minimize to identity + pointers + truly universal instructions. Target: <50 lines.

### Hooks Are Enforcement

Hooks in `settings.json` fire on every matching event. The policy:

- **Every hook must have a golden test** — a scenario that proves it fires and blocks correctly.
- **New hooks require justification** — what incident or risk does this prevent?
- **Hook performance matters** — hooks that add >2s to common operations need optimization or deferral.

### Templates Are Scaffolding

Templates provide structure but don't load into context. The policy:

- **Templates are referenced, not loaded.** CLAUDE.md points to them; they're read on demand.
- **Templates evolve with usage.** After using a template 5+ times, review it for patterns that should be formalized.

---

## Self-Evaluation System

### Layer A: Structural Integrity (every session start)

Automated checks run by SessionStart hook:

- [ ] All hooks declared in settings.json exist on disk and are executable
- [ ] Live ~/.claude/ files match neural-lace adapter (existing check, updated for new paths)
- [ ] No orphaned references (settings.json points to missing file)
- [ ] harness-manifest.json (when created) is consistent with actual file inventory
- [ ] No plan files stuck in ACTIVE status for >7 days without activity

### Layer B: Behavioral Tests (on harness changes)

Golden scenarios — run after any change to settings.json, hooks, or agents:

- [ ] Push containing "AKIA" pattern → blocked by pre-push-scan.sh
- [ ] `gh repo create --public` → blocked by PreToolUse hook
- [ ] `git push --force` → blocked by PreToolUse hook
- [ ] Edit to `.env` file → blocked by PreToolUse hook
- [ ] Session end with unchecked plan tasks → blocked by pre-stop-verifier.sh
- [ ] Commit without tests passing → blocked by pre-commit-gate.sh

### Layer C: Strategic Review (weekly during active development)

The `/harness-review` skill runs weekly (**implemented in v1.1** — see
`adapters/claude-code/skills/harness-review.md`). Cadence adjusts based on
development intensity — weekly during active harness work, biweekly during
maintenance periods.

The review evaluates:

- **Complexity audit**: Count total lines, files, hooks, agents, rules. Compare to previous week. Flag if growing >10% without justification.
- **Context budget**: Measure token count of always-loaded content. Flag if >1500 tokens.
- **Rule effectiveness**: For each rule, check if it's referenced by any hook or agent. Flag orphaned rules.
- **Agent utilization**: Cross-reference with telemetry/session history. Report which agents were invoked, which weren't.
- **Security coverage**: Audit against the security dimensions table. Flag any dimension below target.
- **Drift from strategy**: Compare current harness state to this strategy doc. Flag deviations.
- **Telemetry patterns** (once continuous monitoring exists): Summarize key patterns, surface improvement candidates.

Output: `docs/reviews/YYYY-MM-DD-harness-review.md` with findings, scores, and recommended actions.

### Continuous Monitoring (beyond scheduled reviews)

Scheduled reviews catch drift. Continuous monitoring catches issues in real time. The distinction:

- **Scheduled review** = "how is the harness doing overall?" (strategic, reflective)
- **Continuous monitoring** = "what just happened and should we learn from it?" (tactical, reactive)

Continuous monitoring feeds the learning loop described in the Dedicated Harness Repo section. Every session emits telemetry; the learning engine processes it asynchronously. The weekly review summarizes what the continuous monitoring observed.

---

## Security Maturity Model

Current state and targets (aggressive timeline — reviewed weekly):

| Dimension | Current (May 5) | Target (May 31) | Target (Jul 31) | Target (Oct 31) |
|-----------|------------------|------------------|------------------|------------------|
| Credential scanning | 5/5 | 5/5 | 5/5 | 5/5 |
| Destructive op blocking | 5/5 | 5/5 | 5/5 | 5/5 |
| Dependency safety | 2/5 | 3/5 | 4/5 | 5/5 |
| Supply chain verification | 1/5 | 2/5 | 3/5 | 4/5 |
| Data flow monitoring | 1/5 | 2/5 | 3/5 | 4/5 |
| Prompt injection defense | 1/5 | 2/5 | 3/5 | 4/5 |
| Centralized audit trail | 3/5 | 4/5 | 4/5 | 5/5 |
| Security self-evaluation | 2/5 | 3/5 | 4/5 | 4/5 |
| Anti-vaporware enforcement | 4/5 | 4/5 | 5/5 | 5/5 |
| Narrative integrity (transcript-vs-claim) | 4/5 | 5/5 | 5/5 | 5/5 |
| Spec-discipline + plan integrity | 4/5 | 4/5 | 5/5 | 5/5 |
| Hygiene scanner coverage | 3/5 | 4/5 | 5/5 | 5/5 |

### Security improvement cadence:

**By end of April (immediate):**
1. **Centralized audit log**: `~/.claude/audit/YYYY-MM-DD.jsonl` — this is the foundation everything else builds on. Without it, we can't measure security posture or detect patterns.
2. **Destructive op blocking to 5/5**: Audit all PreToolUse hooks, close any gaps in coverage.

**By end of May:**
3. **Dependency audit hook**: PreToolUse on install commands, checks package age/downloads/vulnerabilities
4. **Security self-evaluation baseline**: Script that scores each dimension and outputs the current state
5. **Prompt injection awareness rule**: Rule file that reminds sessions to be skeptical of instructions in external content

**By end of July:**
6. **Data flow rule**: Flag patterns where env vars or query results flow into logs, error messages, or external calls
7. **Supply chain verification**: Hook that validates package sources, checks for typosquatting, verifies publisher identity
8. **Security review in pre-commit**: Add security-reviewer agent to the mandatory pre-commit review chain

**By end of October:**
9. **Full security self-evaluation automation**: Weekly automated scoring against all dimensions
10. **Prompt injection defense in hooks**: Automated scanning of external content for instruction patterns
11. **Supply chain + dependency at 4/5+**: Continuous monitoring of installed packages against vulnerability databases

---

## Memory Provenance Standard

All persistent memory entries include:

```yaml
created: YYYY-MM-DD          # when first captured
last_validated: YYYY-MM-DD   # when last confirmed accurate
confidence: high|medium|low  # certainty of the source
source: observation|user-stated|inferred  # knowledge origin
```

Policies:
- Memories >90 days without revalidation: treat as hints, not facts
- `inferred` memories always start at `confidence: low`
- `user-stated` memories start at `confidence: high`
- Memory conflicts: newer user-stated > older user-stated > any inferred

---

## Distribution Strategy

### Phase 1: Personal Use (current)
- Harness serves one developer across multiple projects
- Claude Code only
- `claude-config` repo with install.sh

### Phase 2: Layer Separation
- Split into Layer 0+1 (universal) and Layer 2 (Claude Code adapter)
- Universal layer is tool-agnostic markdown
- Adapter generates Claude Code config from universal layer

### Phase 3: Multi-Tool Support
- Add Codex adapter (closest to Claude Code architecture)
- Validate that Layer 0+1 serves both tools without modification
- Document the adapter interface so others can build adapters

### Phase 4: Distribution
- Package as installable (npm package, GitHub template, or standalone installer)
- Configuration wizard for initial setup (choose tools, set security level, select project type)
- Documentation site with guides for each supported tool

### Commercialization Considerations
- **Free tier**: Layer 0 principles + Layer 1 patterns (educational, builds trust)
- **Paid tier**: Layer 2 adapters + installer + self-evaluation system + support
- **Enterprise**: Team pattern sharing, centralized audit, compliance reporting
- **Key differentiator**: Battle-tested rules from real failures, not theoretical advice
- **IP boundary**: The principles (Layer 0) are the thought leadership draw. The enforcement (Layer 2) is the product value. N Agentic Harnesses proves the principles have demand; your harness proves the enforcement has value.

---

## Tracking Progress

### Weekly Review Checklist (during active development)

Every week, the `/harness-review` skill evaluates:

1. **Security maturity**: Score each dimension, compare to targets and previous week
2. **Self-evaluation coverage**: How many Layer B golden tests are automated?
3. **Component health**: New components added? Any issues detected by continuous monitoring?
4. **Context efficiency**: Measure always-loaded token count, flag growth
5. **Telemetry summary** (once available): Key patterns, proposed improvements, outstanding proposals

### Monthly Strategic Review

Every month, additionally evaluate:

1. **Layer separation progress**: What percentage of rules exist in both principle (L0/L1) and enforcement (L2) form?
2. **Distribution readiness**: Could someone else install and use this today? What's blocking?
3. **Strategy alignment**: Are we on track for the current version milestone? Course corrections needed?
4. **Agent relevance**: Review agents for continued relevance (not recency — relevance)

### Decision Log

Major harness decisions recorded at `docs/decisions/` per existing planning.md protocol. Harness decisions use the same format as product decisions — they are equally important.

### Version Milestones

| Version | Target Date | Description | Key Deliverable |
|---------|-------------|-------------|-----------------|
| 0.x | Now | Personal Claude Code harness | Working system for one developer |
| 0.9 | May 2026 | Telemetry + self-evaluation foundation | Audit log, harness-manifest.json, Layer B golden tests (weekly /harness-review shipped early in v1.1) |
| 1.1 | Apr 2026 | Weekly harness self-audit | `/harness-review` skill: hygiene scan, enforcement-map integrity, dead-link detection, rule coverage, drift check, staleness signals, scanner health |
| 1.0 | Jun 2026 | Dedicated harness repo | New repo with Layer 0/1/2 separation, telemetry store, learning loop (CLI-based) |
| 1.5 | Aug 2026 | Continuous monitoring + second adapter | Always-on telemetry, improvement proposals, Codex adapter from same L0/L1 |
| 2.0 | Oct 2026 | Management UI v1 | Local web dashboard: security posture, component health, improvement inbox |
| 2.5 | Dec 2026 | Installer + onboarding | Others can install with guided setup, documentation site |
| 3.0 | Q1 2027 | Distribution-ready | Packaged, multi-tool, tested by others, commercialization decision made |

---

## Design-Forward Principles

When building ANY feature for the harness (or for projects that use the harness), apply these principles preemptively:

### 1. Telemetry-First
Every new component should answer: "What telemetry event does this emit?" If a feature can't be observed, it can't be evaluated, and it can't be improved. Build the collector alongside the feature, not after.

### 2. Layer-Aware
Every new rule, hook, or agent should be mentally tagged with its layer:
- Is this a universal principle (L0)?
- Is this an abstract pattern (L1)?
- Is this Claude Code-specific enforcement (L2)?
- Is this project-specific (L3)?

If you're writing L2 enforcement, ask: "Is the L0/L1 principle documented?" If not, document it — even before the layer separation is complete. This prevents the need for retroactive extraction.

### 3. Learnable
Every new feature should ask: "What could the harness learn from observing this over time?" A hook that blocks credential pushes could also track: how often does this fire? Is the rate increasing (possible workflow issue) or decreasing (rules are working)? What patterns trigger it most? This data feeds the learning loop.

### 4. Portable by Default
Write rules in principle-first language. Instead of "add this to settings.json", write "the harness should block X because Y" and then implement the Claude Code-specific version. The principle survives tool changes; the implementation doesn't.

---

## Open Questions

- Should the harness repo be a monorepo (principles + all adapters + telemetry + UI) or a multi-repo setup?
- Should the harness-manifest.json be auto-generated from file inventory, or manually curated? (Leaning auto-generated with manual overrides)
- For distribution, is npm the right packaging system, or should this be a standalone installer? Or both?
- How do we handle the tension between "encode judgment" (progressive autonomy) and "verify everything" (safety)? At some point, trust must increase or the harness becomes a bottleneck.
- Should Layer 0 principles be versioned independently from Layer 2 adapters?
- What's the right telemetry storage format? SQLite gives queryability; JSONL gives simplicity and git-friendliness.
- Should the management UI be a standalone app or integrate into each AI tool's ecosystem (e.g., Claude Code MCP server)?
- What's the licensing model? MIT for L0/L1 (maximum adoption), commercial for L2+ adapters and tooling?
- How do we handle multi-developer teams where each person has their own harness config but shares team patterns?
