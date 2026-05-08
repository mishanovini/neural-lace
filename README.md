# Neural Lace

> An intelligent, self-improving harness that gives AI coding tools the discipline of an entire engineering team — enforced mechanically, not by hoping the AI follows instructions.

**Last verified:** 2026-05-06.

## The problem

AI coding tools are powerful but unreliable at production-grade work. They skip verification, hallucinate completion, drift from the plan, forget constraints mid-session, and ship code that compiles but doesn't actually work end-to-end. The more autonomy you give them, the worse these problems get. Telling an AI "always verify your work" in a prompt is like telling a junior engineer "always write tests" — it works until it doesn't.

The deeper problem is that AI agents are amnesiac. Each session starts from zero. The architectural decisions from last week, the discoveries from yesterday's debugging session, the plan state across a multi-day feature build — all of it lives in chat transcripts that vanish when the session ends. There's no institutional memory, no structured handoff, no way to accumulate organizational knowledge.

Neural Lace exists because we got tired of catching these failures manually.

## What Neural Lace is

Neural Lace is a discipline and memory layer that sits between you and your AI coding tool. It implements industry best practices automatically by giving the AI a structured team to operate within — an orchestrator, developers, verifiers, reviewers, and an end-user advocate — and enforces engineering standards through hooks that the AI cannot bypass. The AI doesn't need to remember to verify its work; the harness blocks the session from ending if it hasn't.

Concretely, it's a set of rules, hooks, agent definitions, scripts, and templates that install into your AI tool's config directory, plus global git hooks that scan every commit and push. Once installed, every session inherits the discipline — no per-session opt-in, no self-applied rules.

The key insight: **AI discipline should be mechanically enforced, not self-applied.** Pre-commit gates, session lifecycle hooks, evidence requirements, and scope constraints fire automatically at enforcement points. The harness doesn't ask the AI to be disciplined — it makes undisciplined behavior structurally impossible.

### What makes it different

**Self-improving.** The harness audits itself weekly, captures mid-session discoveries as permanent artifacts, and has a dedicated agent that proposes improvements every time something slips through. It gets better from its own failures.

**Persistent memory across sessions.** Vanilla AI coding tools are amnesiac — each session starts from zero. Neural Lace adds structured handoffs between sessions, permanent discovery capture, decision records (ADRs), a findings ledger, cross-session plan state with evidence, and calibration data that tracks how the AI itself behaves over time. The AI goes from amnesiac to having genuine institutional memory.

**Defense in depth for AI-generated code.** Credential scanning at commit AND push, security anti-patterns flagged before they ship, OWASP-class issues caught by a dedicated security reviewer agent. AI-generated code is particularly vulnerable to these patterns and Neural Lace is built specifically to catch them.

**Narrative integrity.** The AI cannot claim it's done when it isn't. Sessions literally cannot end if the transcript shows deferred work, self-contradiction, skipped user directives, or unfulfilled goals.

**Progressive autonomy.** Trust accumulates through safe operation. The AI earns more freedom by demonstrating reliability — fewer interruptions, more autonomous multi-task execution. Hard blocks (credential exposure, public access changes) never relax.

**Tool-portable.** Universal principles and abstract patterns survive tool changes. Only thin adapters need rewriting. Today it ships for Claude Code; the architecture supports Codex, Cursor, and Gemini adapters.

## Is this for you?

You'll get the most value from Neural Lace if:

- You're a solo developer or small team building production code with AI coding tools.
- You've shipped vaporware at least once (code that compiles but doesn't actually work end-to-end) and want enforcement, not aspirations.
- You can install bash hooks and don't mind a config directory growing to ~50 files.
- You want the AI to operate autonomously on multi-task plans without losing quality.

**This differs from project-only `CLAUDE.md`** by adding hook-enforced gates — the AI cannot skip verification by not noticing the rule. **It differs from cursor rules / aider** by being tool-portable (Claude Code adapter shipping; Codex / Cursor / Gemini adapters planned via the Layer 0/1/2 model below).

## What it does

- **Enforced best practices** (not aspirational): evidence-based task completion, anti-vaporware verification, decision-record atomicity, tool-call budget discipline — each backed by a pre-commit hook or session gate that blocks the anti-pattern mechanically.
- **Risk-based permissions**: actions classified by 6 risk dimensions (reversibility, blast radius, sensitivity, authority escalation, novelty, velocity). Unknown actions handled gracefully.
- **Progressive autonomy**: trust accumulates through safe operation. Hard blocks (credential exposure, public access) never relax.
- **Two-layer configuration**: shareable harness code never contains identity, credentials, or machine-specific paths. Personal config in `~/.claude/local/` (gitignored). Hygiene scanner blocks accidental leaks at pre-commit.
- **Self-evaluation**: weekly `/harness-review` skill audits the harness itself — dead doc links, stale references, drift between installed and source copies, hygiene violations.
- **Defense in depth**: credentials scanned at commit AND push. Security anti-patterns common in AI-generated code flagged before they ship.
- **Narrative integrity**: agent cannot end a session whose transcript reveals deferred work, self-contradiction, skipped user imperatives, or unfulfilled first-message goals.
- **Proactive learning capture**: mid-process realizations land as durable artifacts (`docs/discoveries/`), not chat-only narrative.
- **Forward-compatible**: universal principles (Layer 0) and abstract patterns (Layer 1) survive tool changes. Only thin adapters (Layer 2) need to be rewritten per tool.

Full catalog of 25+ practices, rationale, and where each is enforced: [`docs/best-practices.md`](docs/best-practices.md).

This is the front door. For depth → [`docs/architecture-overview.md`](docs/architecture-overview.md). For install → the Quick Start below. For the catalog of mechanisms → [`docs/harness-architecture.md`](docs/harness-architecture.md). For best-practice rationale → [`docs/best-practices.md`](docs/best-practices.md).

## How the harness is structured

Three things happen at once: a team of specialized agents, a layered architecture, and a structured product-delivery flow.

### The agents make up an entire tech team

Each agent in the harness plays a real-world tech-team role. The orchestrator is the engineering manager; developers write the code; verifiers are QA; reviewers are senior engineers and security/UX specialists; the advocate is the PM checking that the user actually got what they asked for.

| Role on a tech team | Agent in the harness | What it does |
|---|---|---|
| Engineering manager / tech lead | The main session (orchestrator) | Reads plan, dispatches developers, collects results, stays lean |
| Developer | `plan-phase-builder` | Builds one task at a time in an isolated worktree |
| QA engineer | `task-verifier` | Verifies each task before its checkbox flips |
| Product manager / UX advocate | `end-user-advocate` | Authors acceptance scenarios; verifies user-observable outcome at runtime |
| Senior engineer (code review) | `code-reviewer` | Reads diffs for quality, security, and consistency |
| Principal engineer / architect | `systems-designer` | Reviews systems-design plans before implementation |
| Security engineer | `security-reviewer` | Catches OWASP-class issues common in AI-generated code |
| Test engineer | `test-writer` | Generates tests following project conventions |
| Auditor / internal control | `plan-evidence-reviewer` | Independent second opinion on completion claims |
| Process improvement / retro | `enforcement-gap-analyzer` | Proposes harness improvements after every runtime failure |

Plus 9 additional specialists (UX designers, audience reviewers, comprehension reviewers, harness reviewers, claim reviewers, exploration agents, PRD validity reviewers, domain experts). Full mapping in [`docs/architecture-overview.md`](docs/architecture-overview.md).

### The architecture is layered for tool-portability

```
Layer 0  PRINCIPLES  (universal, tool-agnostic)     Risk model, autonomy ladder
Layer 1  PATTERNS    (tool-family-agnostic)         Rules, hooks, agents — abstract shapes
Layer 2  ADAPTERS    (tool-specific)                Claude Code, Codex, Cursor, Gemini
Layer 3  PROJECT     (per-repo)                     Project rules, audience, context
```

This is the layer system that affects "is this useful for me?" — it tells you what changes if you want the harness to work with a different AI tool. (Two other layer systems exist for different questions: Generation 1-6 for *when each enforcement class was added*, and ADR-027 Layer 1-5 — Architecture Decision Record #027 — for *how handoff state is verified at session boundary*. Both are documented in [`docs/architecture-overview.md`](docs/architecture-overview.md) Section III.)

### How a feature ships through the team

Here's what happens after you type "build feature X" in a Claude Code session — every transition is gated by a hook; the agent cannot skip a step:

| # | Step | Who does it |
|---|---|---|
| 1 | Plan drafted → `start-plan.sh` creates scaffold | You + AI orchestrator (the main session) |
| 2 | Plan-time review: UX, systems-design, acceptance scenarios | `ux-designer`, `systems-designer`, `end-user-advocate` agents |
| 3 | Orchestrator dispatches builders in isolated worktrees | The main session (calling out to `plan-phase-builder` agents) |
| 4 | Builders build + commit on worker branches | `plan-phase-builder` agents |
| 5 | Each task verified before its checkbox flips | `task-verifier` agent (only mechanism that can flip checkboxes) |
| 6 | Pre-commit security + code review | `code-reviewer`, `security-reviewer` agents + pre-commit hooks |
| 7 | Runtime acceptance scenarios run against the live app | `end-user-advocate` agent |
| 8 | On FAIL → harness-improvement proposal | `enforcement-gap-analyzer` agent |
| 9 | On PASS → `close-plan.sh` deterministic closure | `close-plan.sh` script (auto-archives plan + evidence) |
| 10 | Auto-merge to master per the verified-complete rule | The main session, per `~/.claude/rules/git.md` |

The `start-plan.sh` and `close-plan.sh` scripts are bash; you can run them by hand or the AI invokes them. The agents are spawned by the main Claude Code session via the Task tool. The hooks fire automatically at Claude Code lifecycle events. Full step-by-step expansion with PASS/FAIL paths in [`docs/architecture-overview.md`](docs/architecture-overview.md) Section II.

## Documentation

Each doc serves a different audience tier — pick the row that matches what you're doing.

| Document | Audience | Covers |
|----------|----------|--------|
| **README.md** (this file) | Anyone | Front door — what + why + structure-as-shape + install |
| [`SETUP.md`](SETUP.md) | First-time installers | Fresh-install walkthrough, two-layer config customization |
| [`docs/architecture-overview.md`](docs/architecture-overview.md) | Fresh adopters wanting depth | Full team-role mapping + layered architectures cross-walked + end-to-end flow |
| [`docs/doc-writing-patterns.md`](docs/doc-writing-patterns.md) | Anyone writing docs in this repo | The 10 principles for user-facing documentation |
| [`docs/best-practices.md`](docs/best-practices.md) | Adopters + maintainers | Full catalog of 25+ practices + rationale + enforcement |
| [`docs/harness-architecture.md`](docs/harness-architecture.md) | Maintainers | Hook chains, agent table, credential layers, mechanism inventory |
| [`docs/harness-strategy.md`](docs/harness-strategy.md) | Strategy readers | Vision, milestones, layer model, security maturity |
| [`docs/harness-guide.md`](docs/harness-guide.md) | Adopters | File-by-file reference, setup instructions |
| [`docs/build-doctrine-roadmap.md`](docs/build-doctrine-roadmap.md) | Following Build Doctrine work | Tranche-by-tranche status of the **Build Doctrine** integration (a separate methodology covering failsafe-first, work-shapes, and risk-tiered verification — integrated into Neural Lace in May 2026) |
| [`build-doctrine/doctrine/07-knowledge-integration.md`](build-doctrine/doctrine/07-knowledge-integration.md) | Doctrine maintainers | The **Knowledge Integration Ritual** — how the doctrine itself evolves on cadence + 7 KIT triggers (calibration patterns, findings, discoveries, ADR-staleness, `/harness-review`, propagation-engine audit log, drift). Composes with [`adapters/claude-code/scripts/analyze-propagation-audit-log.sh`](adapters/claude-code/scripts/analyze-propagation-audit-log.sh) (KIT-6 consumer) and `/harness-review` Check 13 (KIT-1..KIT-7 sweep). |
| [`docs/agent-incentive-map.md`](docs/agent-incentive-map.md) | Maintainers | Per-agent failure-mode analysis |
| [`docs/business-patterns-workflow.md`](docs/business-patterns-workflow.md) | Teams | Sharing credential patterns across a team |
| [`principles/permission-model.md`](principles/permission-model.md) | Anyone | Risk dimensions, scoring, tiers |
| [`principles/progressive-autonomy.md`](principles/progressive-autonomy.md) | Anyone | Trust model, autonomy ladder |
| [`principles/harness-hygiene.md`](principles/harness-hygiene.md) | Contributors | No sensitive data in harness code; two-layer config |
| [`docs/ux-guidelines.md`](docs/ux-guidelines.md) + [`docs/ux-checklist.md`](docs/ux-checklist.md) | UI builders | Design principles + 22-domain audit checklist |

## Quick Start (Claude Code)

```bash
cd ~/claude-projects
git clone https://github.com/<your-org-or-user>/neural-lace.git
cd neural-lace/adapters/claude-code
chmod +x install.sh
./install.sh
```

Deploys rules, agents, hooks, and templates to `~/.claude/` and sets up global git hooks for security scanning. See [`SETUP.md`](SETUP.md) for the detailed walkthrough (customizing `~/.claude/local/`, choosing an automation mode, first-run verification).

## Directory structure

```
neural-lace/
  principles/                    Layer 0 — Universal principles
  patterns/                      Layer 1 — Abstract patterns
  adapters/
    claude-code/
      agents/                    19 specialized agents (the team)
      hooks/                     ~40 enforcement hooks
      rules/                     Behavioral rules loaded contextually
      scripts/                   close-plan.sh, start-plan.sh, state-summary.sh,
                                 session-wrap.sh, write-evidence.sh, others
      skills/                    Slash-commands (/harness-review, /find-bugs, ...)
      templates/                 Plan template, completion-report template, others
      patterns/                  Hygiene-scan denylist, security-scan patterns
      build-doctrine-templates/  Universal-floor doctrine templates
      examples/                  Per-machine config examples
      settings.json.template     Hook wiring (committed; live copy is gitignored)
    codex/                       Codex adapter (planned)
    cursor/                      Cursor adapter (planned)
  docs/                          Strategy, architecture, guides, decisions
    decisions/                   Decision records (NNN-slug.md)
    plans/                       Active plans + archive/
    discoveries/                 Mid-process learnings
    reviews/                     UX/audit findings (date-prefixed)
    sessions/                    Session summaries
  evals/                         Harness self-tests
```

## How it works (operational wiring)

After installation:

```
neural-lace/adapters/claude-code/
    │
    ├── install.sh ──────► ~/.claude/
    │                       ├── agents/     (spawned on demand)
    │                       ├── rules/      (loaded contextually by file pattern)
    │                       ├── hooks/      (called by settings.json lifecycle hooks)
    │                       ├── scripts/    (callable from sessions or shell)
    │                       ├── templates/  (referenced during planning)
    │                       └── settings.json (permissions, hooks, plugins)
    │
    └── git-hooks/ ─────► git config --global core.hooksPath
                           ├── pre-commit   (credential + security scan, EVERY commit)
                           └── pre-push     (credential scan, EVERY push)
                                              └── pattern sources:
                                                  ├── built-in (18+ pattern families)
                                                  ├── ~/.claude/sensitive-patterns.local
                                                  └── ~/.claude/business-patterns.d/*.txt
```

Key points:
- `install.sh` symlinks (or copies on Windows) adapter files into `~/.claude/`.
- `git core.hooksPath` makes the pre-commit and pre-push scanners global — they protect ALL repos, not just AI-assisted ones.
- `settings.json` is machine-specific (copied from template, never overwritten on update).
- Rules load contextually — `api-routes.md` only loads when editing API route files.

## Updating

```bash
cd ~/claude-projects/neural-lace
git pull
./adapters/claude-code/install.sh   # propagates changes on Windows
```

On macOS/Linux symlinks point to the repo, so `git pull` is enough. On Windows the installer copies files; re-run after pulling.

## Security scanning

### Pre-commit (every commit, every repo)

Scans staged content for:

**Blockers (exit 1):**
- Credentials: API keys, tokens, private keys, JWTs (18+ pattern families)
- Sensitive files: `.env`, `credentials.json`, `secrets.yaml`, SSH keys
- Supabase service role key in client-side code

**Warnings (informational):**
- Hardcoded localhost URLs, XSS vectors (`dangerouslySetInnerHTML`), disabled type-checking, TLS validation bypass, permissive CORS, SQL injection via template literals, exposed error internals, `debugger` statements, large files, lockfile desync.

### Pre-push (every push, every repo)

Scans the push diff for credential patterns. Second line of defense — catches anything past pre-commit.

### Pattern sources (layered)

1. **Built-in** — 18+ credential families hardcoded in the scanner.
2. **Personal** — `~/.claude/sensitive-patterns.local` (never committed).
3. **Team** — `~/.claude/business-patterns.d/*.txt` (symlinked from private repos).

See [`docs/business-patterns-workflow.md`](docs/business-patterns-workflow.md) for team pattern sharing setup.

### Override

```bash
git commit --no-verify  # bypasses pre-commit
git push --no-verify    # bypasses pre-push
```

In Claude Code sessions, `--no-verify` is itself blocked by a PreToolUse hook — AI cannot bypass scanners without explicit user authorization.

## Multi-account management

Neural Lace supports development across multiple GitHub accounts (e.g., personal + work org).

**Configuration:** copy `adapters/claude-code/examples/accounts.config.example.json` to `~/.claude/local/accounts.config.json` and fill in your accounts. The file is git-ignored and machine-local. Each account entry declares:

- `gh_user` — GitHub username to switch to
- `dir_triggers` — directories under which this account is active
- `public_blocked` — set `true` on work/sensitive accounts to prevent public-repo creation

**Per-session account switching:** the `SessionStart` hook reads the config and auto-switches GitHub + Supabase credentials based on the working directory.

**Syncing to multiple remotes:** see `sync.example.sh` for a reference script that pushes the current branch to all configured git remotes with matching account switching.

## What's NOT in this repo

Deliberately excluded:

- **Credentials and tokens** — stored in `~/.claude/sensitive-patterns.local`, `~/.supabase/tokens/`, or environment variables.
- **Project-specific rules** — each project has its own `.claude/rules/` directory.
- **Machine-specific settings** — `settings.json` is generated from template, per-machine.
- **Project/org IDs** — configured in `settings.json` placeholders, not committed.
- **Telemetry data** — stored locally at `~/.neural-lace/telemetry/`, never committed.

## Key concepts

### Risk dimensions

Every action is scored on six dimensions (0-4 each):

| Dimension | Question |
|-----------|----------|
| Reversibility | Can this be undone? |
| Blast Radius | How much is affected? |
| Sensitivity | Does this touch protected data? |
| Authority Escalation | Does this change permissions? |
| Novelty | Has this action been seen before? |
| Velocity | Is this part of a rapid sequence? |

### Permission tiers

| Tier | Score | Response |
|------|-------|----------|
| T0: Silent allow | 0-1 | Execute immediately |
| T1: Log & allow | 1-2.5 | Execute, log prominently |
| T2: Confirm | 2.5-4 | Pause, show risk, wait for approval |
| T3: Block | 4+ | Refuse, explain why |

### Trust accumulation

Trust (0.0-1.0) grows with safe operation and decays with incidents. Higher trust = fewer interruptions = more autonomous work. Hard blocks (credential exposure, public access) never relax.

## Current status

| Component | Status |
|-----------|--------|
| Layer 0 Principles | v1.0 |
| Layer 1 Patterns | v1.0 |
| Claude Code Adapter | v1.0 |
| Pre-commit security scanner | v1.0 (credentials + anti-patterns) |
| Pre-push security scanner | v1.0 (credentials) |
| Generation 4 anti-vaporware mechanisms | v1.0 (2026-04-15) |
| Generation 5 acceptance loop + plan lifecycle + class-aware feedback | v1.0 (2026-04-24) |
| Generation 6 narrative-integrity Stop hooks | v1.0 (2026-04-26) |
| Build Doctrine integration arc (Phase 1d-A through 1d-G) | v1.0 (May 2026) |
| Tranche 1.5 architecture-simplification (deterministic close-plan, mechanical evidence, work-shapes, risk-tiered verification, calibration loop) | v1.0 (2026-05-05) |
| Build Doctrine Tranches 2-6 (template schemas, content, knowledge-integration, orchestrator scaffolding) | v1.0 (2026-05-06) |
| Agent Teams compatibility | feature-flagged (experimental) — see [`adapters/claude-code/rules/agent-teams.md`](adapters/claude-code/rules/agent-teams.md) |
| Risk Engine Runtime | Planned (currently using pattern-match hooks) |
| Telemetry Collectors | Planned |
| Learning Loop | Planned |
| Codex / Cursor adapters | Planned (v1.5+) |

## License

[MIT](LICENSE) — free to use, fork, and modify. Contributions welcome.
