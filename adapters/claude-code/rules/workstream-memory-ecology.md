# Workstream-Memory Ecology — Match Capture To Tier; Don't Pollute Workstreams With Each Other's Context

**Classification:** Pattern (self-applied capture discipline). No hook can mechanically tell whether a fact belongs to a single project, to a cross-project workstream, or to the user's standing context — the trigger is the agent's judgment as a fact is observed. The mechanical layers that exist (auto-memory write, SCRATCHPAD freshness, plan-lifecycle archival, findings-schema gate) all enforce *shape* on a chosen tier; this rule governs *which tier to choose*.

**Originating source:** Jason Liu, *Codex-maxxing* (2026-05-10) — the "vault" pattern. Liu keeps a pinned conversation thread per workstream (Chief of Staff, Agents SDK, OpenAI CLI, Codex for open source, Twitter monitor) and lets each accumulate per-workstream context. To prevent that context from staying trapped inside a single thread, he distills the cross-cutting signal — people, decisions, open loops, daily notes, project state — into an Obsidian vault that lives *separate from any one project*. Liu: *"The vault is where the agent lives, separate from any one project. Repositories hold code. The vault holds rolling context around my work: people, decisions, open loops, daily notes, project state, and the bits of understanding that would otherwise get lost between threads."*

## Why this rule exists

NL today has four memory tiers, each scoped differently:

| Tier | Scope | Lifetime | Examples |
|---|---|---|---|
| **T1 — Global behavioral** | All sessions, all projects, all users of this install | Permanent | `~/.claude/CLAUDE.md`, `~/.claude/rules/*.md`, `~/.claude/principles/*.md` |
| **T2 — Per-project persistent** | One repo's git tree | Permanent (committed) | per-project `CLAUDE.md`, `docs/plans/`, `docs/decisions/`, `docs/findings.md`, `docs/backlog.md`, `docs/reviews/`, `docs/discoveries/` |
| **T3 — Per-project auto-memory** | One repo's `~/.claude/projects/<slug>/memory/` | Permanent (gitignored, per-machine) | `user_*.md`, `feedback_*.md`, `project_*.md`, `reference_*.md` per the auto-memory protocol |
| **T4 — Per-session ephemeral** | One session's working state | Cleared at `/clear` or `/compact` | SCRATCHPAD.md, in-conversation context |

Three failure shapes recur because the tier-to-fact match is the agent's call and the call is often wrong:

1. **Mistier-up (project fact pollutes the global tier).** A repo-specific architecture note ends up in `~/.claude/CLAUDE.md` or the user-tier auto-memory, where every future session in every project sees it and treats it as context for unrelated work. Cost: agent reasons about project A's columns while editing project B's component.
2. **Mistier-down (cross-workstream fact gets buried in one project).** A decision or open loop that genuinely spans multiple repos lands as a `docs/decisions/NNN-*.md` entry inside ONE of the affected repos. Other repos in the same workstream never see it; the next session working in repo B re-derives the question from scratch.
3. **Pollution (workstream A leaks into workstream B context).** A "what's next" item belonging to the auth-refactor workstream surfaces in a session focused on the payment-processor workstream because the SCRATCHPAD or the auto-memory captured it without scoping. The session spends context on the wrong thing.

The rule below names the tier for each fact-shape so the right tier is chosen on capture rather than discovered on contamination.

## Tier-selection rule (by fact shape)

When a fact is observed, classify it by its **scope of relevance** — not by where it was discovered. Match to tier:

### → T1 — Global behavioral (`~/.claude/CLAUDE.md`, `~/.claude/rules/*.md`)

A fact belongs in T1 only if **every future Claude session in every project** benefits from it. The bar is high:

- A behavioral discipline the agent should self-apply in all sessions.
- A correction the user has explicitly said applies universally ("never X" / "always Y").
- A canonical reference (a credentials convention, a CLI auth location) that every session needs to consult.

NOT T1: project architecture, current-state-of-this-codebase notes, ongoing-work pointers, anything time-bounded.

Mechanism backstop: `harness-hygiene-scan.sh` (PreCommit) and `harness-reviewer` (adversarial review on changes) catch identifier-leakage and project-specific content drift into T1. They cannot catch *correctly-generic-but-doesn't-belong-at-T1* — that is this rule's job.

### → T2 — Per-project persistent (`docs/` inside one repo)

A fact belongs in T2 if it is **specific to one repo's product or team** and a future session inside *that repo* needs it:

- Architecture decisions about that codebase (`docs/decisions/NNN-*.md`).
- Plans for work in that codebase (`docs/plans/<slug>.md`).
- Findings about that codebase (`docs/findings.md`).
- Backlog items for that team's work (`docs/backlog.md`).
- Review outputs (`docs/reviews/YYYY-MM-DD-*.md`).
- Discoveries about that codebase (`docs/discoveries/YYYY-MM-DD-*.md`).

The structural defenses (`findings-ledger-schema-gate.sh`, `plan-lifecycle.sh`, `bug-persistence-gate.sh`, `discovery-surfacer.sh`) presume T2-shaped capture and gate its shape; choosing T2 is the agent's call.

### → T3 — Per-project auto-memory (`~/.claude/projects/<slug>/memory/`)

A fact belongs in T3 if it concerns **the user-as-collaborator within one project's work** and persists across sessions of that project but is too operational / personal to commit:

- Per-project user preferences ("on this project, the user prefers Vitest over Jest").
- Per-project feedback the user has given ("don't auto-merge here without asking").
- Per-project ongoing-work pointers that don't belong in SCRATCHPAD but aren't team-shared either.
- References to per-machine paths or per-user accounts relevant to this project.

The auto-memory write protocol in CLAUDE.md governs the file format. The tier-choice question (T3 vs T2 vs T4) is this rule's job.

### → T4 — Per-session ephemeral (SCRATCHPAD.md, in-conversation context)

A fact belongs in T4 if it serves **only the current session's working state**:

- The current branch, the current task in progress, the next concrete step.
- Inline working notes the next session does not need.
- Outputs of a one-shot lookup that won't recur.

SCRATCHPAD.md is intentionally hard-capped at 30 lines (per CLAUDE.md) — anything that doesn't fit either compresses to a pointer or escalates to T2/T3.

## The cross-workstream gap (documented honestly)

A **workstream** is a coherent body of work that may cross repo boundaries. Examples:

- "Harness development" — spans NL (canonical) + downstream consumers that mirror harness configs.
- "Auth refactor" — spans the auth repo + every consumer of the auth client.
- "Two-repo fork reconcile" — spans PT and personal forks of NL itself.
- "Customer-X support" — spans the product repo + the customer's deployed instance + the support tracker.

Liu's vault pattern addresses this: a context store *separate from any single project* that holds the workstream's people, decisions, open loops, and rolling state. **NL does not currently have a T1.5 tier between global and per-project.** The closest substrates are:

- A note in T1 (drifts into "applies to every session" when it shouldn't).
- A note in one of the affected projects' T2 (other affected projects don't see it).
- A note in T3 of one affected project (only resurfaces in that project's sessions).
- Nowhere — the user's head.

This gap is **acknowledged**, not solved by this rule. Pending design work (tracked as friction at session-end per `friction-reflexion.md`): does NL want a `~/.claude/workstreams/<workstream>/` substrate (analogous to Liu's vault but harness-flavored)? If yes, how does it compose with auto-memory and SCRATCHPAD? Until that design lands, the discipline below applies as a stopgap.

### Stopgap when a fact is genuinely cross-workstream

1. **Identify the smallest set of repos the fact actually concerns.** If "every repo" — it is T1, not cross-workstream. If "one repo" — it is T2, not cross-workstream. Only the middle band is genuinely cross-workstream.
2. **Pick the *canonical* repo for the workstream** — the one whose `docs/` most naturally hosts the master record (e.g., NL is canonical for harness work). Land the durable artifact there.
3. **Place a one-line pointer in each *consumer* repo's T2** (`docs/backlog.md` or a one-line `docs/decisions/` cross-reference) naming the canonical artifact. The pointer ensures sessions opening the consumer repo discover the artifact when relevant.
4. **Do NOT replicate the substance** in each consumer repo — only the pointer. Substance lives in the canonical repo; replicas drift.
5. **Tag the artifact's frontmatter** with the affected-repos list (e.g., `affects: [neural-lace, downstream-app-A, downstream-app-B]`) so a future workstream-aware tool can index it.

## Anti-pollution: don't let workstream A's noise reach workstream B's context

The complement to choosing the right tier *on capture* is choosing the right scope *on retrieval*. Three concrete disciplines:

1. **SCRATCHPAD.md is one project's working state, not a workstream board.** If multiple workstreams flow through one repo, SCRATCHPAD names ONE active workstream at a time (the `Active Plan` field already enforces this in the template). Other workstreams' state is referenced by pointer, not enumerated.
2. **Per-project auto-memory is scoped by `~/.claude/projects/<slug>/`** — that scoping is the mechanism. The discipline is: when writing a memory, ask "would a session in a *different* project benefit from seeing this?" If yes, the memory is mis-tiered (escalate to T1, or to cross-workstream stopgap above). If no, T3 is correct.
3. **When loading context at session start, the SessionStart hooks (discovery-surfacer, plan-status-archival-sweep, etc.) operate per-project by design.** Cross-project memory should NOT be surfaced unless the user explicitly invokes a workstream-aware skill (none exist yet — see the gap above). Pulling cross-project context "in case it's relevant" is exactly the pollution this rule prevents.

## How this composes with existing rules

- `~/.claude/CLAUDE.md` "Memory Discipline" — names T1 vs T2-T4 implicitly via "CLAUDE.md = index, SCRATCHPAD.md = ephemeral, do not store facts derivable from the codebase, memory is a hint not truth." This rule makes the tier set explicit and adds the workstream dimension.
- `~/.claude/rules/discovery-protocol.md` — discoveries are T2 by construction (one project's `docs/discoveries/`). Cross-workstream discoveries follow the stopgap above (canonical-repo placement + consumer-repo pointers).
- `~/.claude/rules/findings-ledger.md` — findings are T2 by construction (one project's `docs/findings.md`). Same stopgap for cross-workstream findings.
- `~/.claude/rules/friction-reflexion.md` — friction is surfaced as a *suggestion*, not auto-filed; whichever tier the suggestion ultimately lands in is the user's choice. The cross-workstream T1.5 gap above is itself a candidate friction the agent surfaces when it recurs.
- `~/.claude/rules/teaching-moments.md` — teaching examples are T2 by default (`docs/teaching-examples/`), with cross-project propagation noted as a manual user step (the rule explicitly defers automation). Same shape as this rule's stopgap.

## Worked examples

**Example 1 — correctly T1.** "The user wants every session to end with a `DONE: / PAUSING: / BLOCKED:` marker on the last line." Universal behavioral discipline; lives in `~/.claude/rules/session-end-protocol.md`. Future sessions in every project benefit. T1 is correct.

**Example 2 — correctly T2.** "The Campaigns table in this product uses a `status` enum with values {draft, scheduled, sent, failed} — the UI relies on these exact strings." Specific to one repo; lives in `docs/findings.md` or as a comment in the schema migration. Future sessions in unrelated repos do not benefit. T2 is correct.

**Example 3 — correctly T3.** "On this project, the user reviews every PR personally rather than auto-merging." Per-project user preference; lives in `~/.claude/projects/<slug>/memory/feedback_review_before_merge.md`. Other projects may have the opposite preference. T3 is correct.

**Example 4 — cross-workstream (gap).** "The harness-dev workstream uses `<canonical-org>/<harness-repo>` as canonical; `<personal-account>/<harness-repo>` is the mirror; force-push between them is prohibited; reconverge happens via cherry-pick PR." Affects the harness itself + the operator's discipline when working in either fork. **Wrong tier choice:** put it in `~/.claude/CLAUDE.md` (pollutes every session). **Correct stopgap:** land the canonical decision in `<canonical-org>/<harness-repo>/docs/decisions/` and place a one-line pointer in the personal fork's `docs/decisions/` index that names the canonical entry.

**Example 5 — mistier-up failure (what NOT to do).** A session working in the Campaigns project notices the API uses Supabase RLS policies and writes a T1 memory: "this project uses Supabase RLS for tenant isolation." Six months later, an unrelated session working in a non-Supabase project sees the memory and reasons as if RLS applies there too. Cost: silent bug from wrong-context assumption. Correct tier: T2 (the Campaigns repo's `docs/decisions/`).

## Cross-references

- `~/.claude/CLAUDE.md` "Memory Discipline" — the implicit tier model this rule makes explicit.
- `~/.claude/CLAUDE.md` "auto memory" section — T3 protocol (write format, when to save, what NOT to save).
- `~/.claude/CLAUDE.md` "Context Persistence (SCRATCHPAD.md)" — T4 protocol.
- `~/.claude/rules/harness-hygiene.md` — T1 perimeter (no project-specific identifiers, no leaked secrets).
- `~/.claude/rules/findings-ledger.md` — T2 substrate for class-aware observations.
- `~/.claude/rules/discovery-protocol.md` — T2 substrate for mid-process learnings.
- `~/.claude/rules/teaching-moments.md` — T2 substrate for user-pushback captures (with the same cross-project-propagation gap acknowledged honestly).
- `~/.claude/rules/friction-reflexion.md` — how to surface the cross-workstream T1.5 gap as a discussion suggestion when it recurs.
- Source: Jason Liu, *Codex-maxxing* (https://jxnl.co/writing/2026/05/10/codex-maxxing/) — the vault pattern that motivates this rule's articulation of the four-tier model and the named gap.

## Enforcement

| Layer | What it enforces | File |
|---|---|---|
| Rule (this doc) | Choose the right tier on capture; recognize the cross-workstream gap; stopgap discipline (canonical-repo + consumer-pointers); anti-pollution at retrieval time | `adapters/claude-code/rules/workstream-memory-ecology.md` |
| Sibling rule (T1 perimeter) | `harness-hygiene-scan.sh` blocks project-specific identifiers from drifting into T1 | `~/.claude/hooks/harness-hygiene-scan.sh` |
| Sibling rule (T2 shape) | `findings-ledger-schema-gate.sh`, `plan-reviewer.sh`, `bug-persistence-gate.sh` enforce shape on T2 substrates once chosen | `~/.claude/hooks/*` |
| User authority | The cross-workstream T1.5 gap relies on the user noticing pollution and pointing at it | (Pattern) |
| Future work | A workstream-aware substrate (T1.5) — design pending; not built; surfaced as friction when the stopgap proves insufficient | (gap) |

The rule is Pattern-class. The tier the agent picks on capture is the load-bearing choice; the mechanisms only enforce shape *within* a chosen tier. The cross-workstream gap is named honestly rather than papered over — per `~/.claude/rules/principles.md` Rule 7 (no false promises).

## Scope

Applies in every project whose Claude Code installation has this rule file present at `~/.claude/rules/workstream-memory-ecology.md`. Loaded contextually by the harness; no opt-in required. Binds every agent in every session mode — the tier-selection discipline is universal, and the cross-workstream gap is universal (the operator's full set of workstreams crosses every repo they touch, regardless of which one a session is currently rooted in).
