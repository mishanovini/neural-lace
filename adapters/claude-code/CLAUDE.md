# Global Claude Code Standards (routing index)

The operating rules live in **`~/.claude/rules/constitution.md`** — the ONLY rule file
loaded into every session (ADR 058 D1). Read it as binding. Everything else lives in
`~/.claude/doctrine/` (index: `~/.claude/doctrine/INDEX.md`) and arrives just-in-time:
injected by `doctrine-jit.sh` when you touch the matching surface, taught by gate block
messages, or referenced explicitly below. The enforcement inventory (what fires when,
with what blocking semantics) is `manifest.json` — verified by `harness-doctor.sh`.

## Standing directives (the short list)

- **Honesty is absolute.** Done = merged to master with a SHA. Claims are PROVEN
  (cite evidence) or HYPOTHESIZED (state the refuter). Constitution §1.
- **Be the interface.** Every artifact you mention gets a clickable link + a summary
  sufficient to act without opening it. Constitution §2.
- **Keep going is the default.** Front-load decisions (compact format, constitution §3);
  decide-and-go with a Decisions-Log trail; pause ONLY for genuine irreversibility.
  Constitution §8.
- **Functionality over components.** A task is done when a user can do the thing and
  you demonstrated it. Constitution §4.
- **Persist in the same response.** Bugs/gaps/decisions go to their durable file
  (backlog / findings / plan / review) the moment they surface. Constitution §5.
- **End every turn with one marker:** `DONE:` / `PAUSING:` / `BLOCKED:` / `CONTINUING:`
  on the last line. Constitution §6.
- **Never ask for credentials** — read `~/.claude/local/credentials-reference.md` first.
- **Never name products, never create public repos, never force-push.** Constitution §9.

## Accounts

Two GitHub accounts (work org / personal); a SessionStart hook auto-switches `gh auth`
by directory. A gh/git 404 or 403 usually means WRONG ACCOUNT — `gh auth switch -u
<owner>`, retry, switch back. Supabase tokens: `~/.supabase/tokens/<account>`.

## Session working memory

Read `SCRATCHPAD.md` (repo root, gitignored) FIRST each session; rewrite (not append)
at milestones. Hard cap 30 lines; it is a pointer, not a log — details live in
`docs/plans/`, `docs/backlog.md`, `docs/decisions/`.

## Multi-task work → orchestrator pattern

For any plan with ≥2 tasks the main session ORCHESTRATES: dispatch builders
(`isolation: "worktree"`, parallel when file-disjoint, ≤5), cherry-pick, verify
sequentially; the orchestrator confirms on-disk evidence and never trusts builder
claims. Details: `~/.claude/doctrine/orchestrator-pattern.md`. A plan is shipped only
when `Status: COMPLETED` and archived — closure IS the work.

## Planning

Plans live in `docs/plans/<slug>.md` (template: `~/.claude/templates/plan-template.md`);
`task-verifier` is the only checkbox-flipper; sweep tasks decompose per-target; Tier-2+
decisions get `docs/decisions/NNN-*.md` in the same commit. Mid-build decisions follow
the two-tier reversibility model (constitution §8). Details:
`~/.claude/doctrine/planning.md`.

## Session modes

Interactive local (default, full harness) · parallel local worktrees · cloud remote /
scheduled (project `.claude/` only — Decision 011) · Agent Teams (flag-gated, Decision
012). Details: `~/.claude/doctrine/automation-modes.md`.

## Harness source of truth

The harness repo is canonical; `install.sh` copies to `~/.claude/` (no symlinks;
Windows). Changes to harness files are made in the repo and land live via install —
never hand-edit `~/.claude/`. `session-start-auto-install.sh` continuously syncs live
from origin/master, so harness changes are only durable once MERGED TO MASTER.
`harness-doctor.sh --quick` is the claimed-vs-actual truth report — keep it GREEN.
Maintenance discipline: `~/.claude/doctrine/harness-dev.md`.

## Detailed doctrine (JIT-delivered; read on demand)

`~/.claude/doctrine/INDEX.md` is the generated inventory. Highest-traffic files:
planning · orchestrator-pattern · testing · git · security · diagnosis · claims ·
discovery-protocol · findings-ledger · session-end-protocol · workstreams-state ·
harness-dev · frontend-conventions · code-conventions. Full-prose originals, where
kept, sit beside each compact as `<name>-full.md`.
