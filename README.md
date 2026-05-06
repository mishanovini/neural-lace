# Neural Lace

> A harness platform that wraps AI coding tools with mechanically-enforced software-engineering and AI-collaboration best practices — so individual developers and teams inherit years of distilled discipline by default, not by self-enforcement.

**Last verified:** 2026-05-06.

Neural Lace makes the AI a reliable collaborator in production work. It does this by giving the AI a **structured team to operate within**, not a single-agent prompt: an orchestrator dispatches builders, builders ship code, verifiers gate completion, advocates check user-observable outcomes, and reviewers catch what the others miss. The team's discipline is enforced by hooks, not relied on as agent self-discipline.

This is the front door. For depth → [`docs/architecture-overview.md`](docs/architecture-overview.md). For install → the Quick Start below. For the catalog of mechanisms → [`docs/harness-architecture.md`](docs/harness-architecture.md). For best-practice rationale → [`docs/best-practices.md`](docs/best-practices.md).

## How the harness is structured

Three things happen at once: a team of specialized agents, a layered architecture, and a structured product-delivery flow.

### The agents are a tech team

Each agent in the harness plays a real-world tech-team role. The orchestrator is the engineering manager; builders are ICs; verifiers are QA; reviewers are senior engineers and security/UX specialists; the advocate is the PM checking that the user actually got what they asked for.

| Role on a tech team | Agent in the harness | What it does |
|---|---|---|
| Engineering manager / tech lead | The main session (orchestrator) | Reads plan, dispatches builders, collects results, stays lean |
| IC engineer | `plan-phase-builder` | Builds one task at a time in an isolated worktree |
| QA engineer | `task-verifier` | Verifies each task before its checkbox flips |
| Product manager / UX advocate | `end-user-advocate` | Authors acceptance scenarios; verifies user-observable outcome at runtime |
| Senior engineer (code review) | `code-reviewer` | Reads diffs for quality, security, and consistency |
| Principal engineer / architect | `systems-designer` | Reviews systems-design plans before implementation |
| Security engineer | `security-reviewer` | Catches OWASP-class issues common in AI-generated code |
| Test engineer | `test-writer` | Generates tests following project conventions |
| Auditor / internal control | `plan-evidence-reviewer` | Independent second opinion on completion claims |
| Process improvement / retro | `enforcement-gap-analyzer` | Proposes harness improvements after every runtime failure |

Plus 9 additional specialists (UX designers, audience reviewers, comprehension reviewers, harness reviewers, claim reviewers, exploration agents, PRD validity reviewers, domain experts). Full mapping in [`docs/architecture-overview.md`](docs/architecture-overview.md).

### Three layered architectures, each answering a different question

The harness has three independent layer systems. Each answers a different question; they compose orthogonally.

**Layer 0/1/2/3 — *Where does code live?***
```
Layer 0  PRINCIPLES  (universal, tool-agnostic)     Risk model, autonomy ladder
Layer 1  PATTERNS    (tool-family-agnostic)         Rules, hooks, agents shapes
Layer 2  ADAPTERS    (tool-specific)                Claude Code, Codex, Cursor, Gemini
Layer 3  PROJECT     (per-repo)                     Project rules, audience, context
```

**Generation 1-6 — *When was each enforcement class added, and why?***
- Gen 4 (Apr 2026) — anti-vaporware mechanisms (evidence-based completion, runtime verification, plan-edit validation, tool-call budget)
- Gen 5 (Apr 2026) — acceptance loop, plan lifecycle, class-aware feedback
- Gen 6 (Apr-May 2026) — narrative-integrity Stop hooks (block sessions whose transcripts reveal deferred work, self-contradiction, skipped imperatives, unfulfilled goals)
- Build Doctrine integration (May 2026) — discovery protocol, comprehension gate, PRD validity + spec freeze, findings ledger, definition-on-first-use, scope-enforcement redesign, deterministic close-plan procedure

**ADR-027 Layer 1-5 — *How is handoff state verified at session boundary?***
- Layer 1: SCRATCHPAD as authored summary
- Layer 2: derived state-summary from primary sources
- Layer 3: session-wrap.sh handoff verification (auto-runs at Stop)
- Layer 4: stale-pointer detection signals
- Layer 5: handoff-freshness as precondition for session end

Each layer system answers one question. Together they describe the harness's full structure. Full per-layer cross-walk in [`docs/architecture-overview.md`](docs/architecture-overview.md).

### How a feature ships through the team

```
1. Planner drafts plan → start-plan.sh creates scaffold
2. ux-designer + systems-designer + end-user-advocate review at plan-time
3. Orchestrator dispatches plan-phase-builder(s) in worktrees
4. Builders build + commit on worker branches
5. task-verifier flips checkboxes (only mechanism that can; never self-report)
6. code-reviewer + security-reviewer pre-commit
7. end-user-advocate runs runtime acceptance scenarios against the live app
8. On FAIL: enforcement-gap-analyzer proposes a harness improvement
9. On PASS: close-plan.sh deterministically closes (auto-archives plan + evidence)
10. Auto-merge to master per the verified-complete rule in `~/.claude/rules/git.md`
```

Each transition is gated by a hook. The agent cannot skip a step.

## What it does

- **Enforced best practices** (not aspirational): evidence-based task completion, anti-vaporware verification, decision-record atomicity, tool-call budget discipline — each backed by a pre-commit hook or session gate that blocks the anti-pattern mechanically.
- **Risk-based permissions**: actions classified by 6 risk dimensions (reversibility, blast radius, sensitivity, authority escalation, novelty, velocity). Unknown actions handled gracefully.
- **Progressive autonomy**: trust accumulates through safe operation. Hard blocks (credential exposure, public access) never relax.
- **Two-layer configuration**: shareable harness code never contains identity, credentials, or machine-specific paths. Personal config in `~/.claude/local/` (gitignored). Hygiene scanner blocks accidental leaks at pre-commit.
- **Self-evaluation**: weekly `/harness-review` skill audits the harness itself — dead doc links, stale references, drift between installed and source copies, hygiene violations.
- **Defense in depth**: credentials scanned at commit AND push. Security anti-patterns common in AI-generated code flagged before they ship.
- **Narrative integrity** *(Gen 6)*: agent cannot end a session whose transcript reveals deferred work, self-contradiction, skipped user imperatives, or unfulfilled first-message goals.
- **Proactive learning capture**: mid-process realizations land as durable artifacts (`docs/discoveries/`), not chat-only narrative.
- **Forward-compatible**: universal principles (Layer 0) and abstract patterns (Layer 1) survive tool changes. Only thin adapters (Layer 2) need to be rewritten per tool.

Full catalog of 25+ practices, rationale, and where each is enforced: [`docs/best-practices.md`](docs/best-practices.md).

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

## Documentation

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
| [`docs/build-doctrine-roadmap.md`](docs/build-doctrine-roadmap.md) | Following Build Doctrine work | Tranche-by-tranche status table |
| [`docs/agent-incentive-map.md`](docs/agent-incentive-map.md) | Maintainers | Per-agent failure-mode analysis |
| [`docs/business-patterns-workflow.md`](docs/business-patterns-workflow.md) | Teams | Sharing credential patterns across a team |
| [`principles/permission-model.md`](principles/permission-model.md) | Anyone | Risk dimensions, scoring, tiers |
| [`principles/progressive-autonomy.md`](principles/progressive-autonomy.md) | Anyone | Trust model, autonomy ladder |
| [`principles/harness-hygiene.md`](principles/harness-hygiene.md) | Contributors | No sensitive data in harness code; two-layer config |
| [`docs/ux-guidelines.md`](docs/ux-guidelines.md) + [`docs/ux-checklist.md`](docs/ux-checklist.md) | UI builders | Design principles + 22-domain audit checklist |

## License

[MIT](LICENSE) — free to use, fork, and modify. Contributions welcome.
