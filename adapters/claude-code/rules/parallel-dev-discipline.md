# Parallel-Dev Discipline — Trunk-Based CI/CD Defaults for Multi-Machine, Multi-Session Work

**Classification:** Hybrid. The seven practices below are the harness's standard CI/CD discipline for parallel development across multiple machines and concurrent sessions. Most are **Pattern** (self-applied by every session + the operator), with the operator's interrupt authority and the SessionStart freshness surfacer as backstops. **One practice is mechanically enforced** (Mechanism): the never-a-shared-counter rule (Practice 7) is backed by `migration-naming-gate.sh`, a PreToolUse Bash gate that blocks any newly-added migration with a bare sequential-integer prefix. The branch-protection and merge-queue practices (Practices 5–6) are **operator-executed-once** via the documented `gh` commands — the rule documents the exact commands; it deliberately does NOT run them, because branch-protection changes are coordination-sensitive (they affect every collaborator's push path) and belong to a human decision.

**Why this rule exists**

Across this week, four parallel-development failures shipped — all on a single codebase worked from multiple machines and multiple concurrent Claude Code sessions:

1. **Migration-number collision (silent schema loss).** Two machines each created `168_*.sql` against a shared sequential migration counter. On merge, `supabase db push` applies migrations in lexical order, sees the first `168_*` as "already applied", and **silently skips the second** — a schema change vanished with no error. Highest-leverage; mechanically prevented by Practice 7.
2. **Diverged remotes.** `origin` and the secondary remote (`pt`) drifted apart; pushes landed against a stale picture of "the truth", and reconciling them required manual cherry-picking. A single authoritative remote (Practice 2) prevents the divergence at the source.
3. **Uncommitted accumulation.** Work piled up uncommitted across sessions; a `git stash`/`git clean` from a sibling session, or a machine switch, risked losing it. Pull-before-work + push-before-switch (Practice 3) keeps the working tree shippable.
4. **Two machines on the same task.** Issue #513 was diagnosed independently on two machines — duplicated work, divergent conclusions. One-item = one-branch = one-machine on a shared work board (Practice 8) makes the double-claim visible before the work starts.

A harness whose whole premise is parallel sessions (worktrees, the orchestrator pattern, Dispatch) MUST encode the discipline that makes parallel safe. Without it, the parallelism the harness enables is exactly the parallelism that produces these four failure classes. This rule is that discipline, baked in as the default every session follows.

The intellectual frame is **trunk-based development**: short-lived branches off a single trunk (`master`), integrated frequently through a serialization point (a merge queue), with one authoritative source of truth. Trunk-based development is the canonical answer to "many people / machines / agents changing one codebase at once"; this rule applies it to the multi-machine, multi-session, agent-driven case.

---

## The seven practices (the harness standard)

Each practice names the failure it prevents and states the rule as the default every session follows.

### Practice 1 — Trunk-based, short-lived branches off `master`

**Prevents:** long-lived divergent branches that accumulate merge debt and conflict at integration time (a generalization of failures #2 and #3 — divergence and accumulation both grow with branch lifetime).

**The rule:** branch off `master` for a single coherent change; integrate it back within hours, not days. A branch's lifetime is bounded by the work it names — `feat/<slug>` for a feature, `fix/<slug>` for a bug — not by a calendar. The longer a branch lives, the further it drifts from trunk and the more it conflicts when it lands. Keep changes small enough to integrate same-day; if a change is too big to land same-day, split it. Branch naming follows the prefix convention in `branch-hygiene.md`.

### Practice 2 — ONE authoritative remote; mirrors are one-way only

**Prevents:** failure #2 (diverged remotes). When two remotes are both written to, neither is the truth, and reconciling them is manual cherry-pick archaeology.

**The rule:** designate exactly ONE remote as authoritative (canonically `origin`). All pushes go there. Any secondary remote (a mirror, a fork, an org copy) is updated **one-way, from the authoritative remote** — never written to directly from a working tree, never the target of a feature-branch push. If the harness needs to propagate to a mirror, that propagation reads the authoritative remote and writes the mirror; a developer/agent never pushes the same branch to two remotes. Two-way writing is what produces divergence; one-way mirroring cannot diverge.

### Practice 3 — Pull-before-work, push-before-switch, never two machines on the same branch

**Prevents:** failures #3 (uncommitted accumulation) and #4 (two machines, same work).

**The rule, three parts:**
- **Pull before work.** At the start of every working session, `git fetch && git pull --ff-only` the branch you're about to work on. Starting from a stale base is how you re-derive work that already landed and how you create avoidable conflicts. The SessionStart freshness surfacer (`session-start-git-freshness.sh`) already reports "local master is BEHIND ${remote}/master — pull before working" at session start; this practice says **act on it**.
- **Push before switch.** Before switching machines, before ending a session, before `git checkout` to another branch: commit and push the current branch. Uncommitted or unpushed work is invisible to the other machine and vulnerable to a sibling session's `git clean`/`git stash`. The working tree should be shippable at every machine-switch boundary.
- **Never two machines on the same branch simultaneously.** A branch is owned by one machine at a time. Two machines committing to the same branch produce divergence that needs a force-push to reconcile — and force-push is prohibited (`git-discipline.md` Rule 1). If you must move a branch between machines, push from machine A, then pull on machine B; the branch is never live on both at once.

### Practice 4 — PR-even-solo

**Prevents:** unreviewed-merge drift and the loss of the audit trail / integration-check surface that a PR provides — the connective tissue under failures #1–#4 (a PR is where a merge queue runs, where checks gate, where a second pair of eyes — human or agent — sees the change before it lands on trunk).

**The rule:** even when working solo, land changes through a Pull Request rather than a direct push to `master`. The PR is the integration point: it's where CI runs, where the merge queue serializes, where branch protection applies, and where the change is reviewable. Solo work tempts a direct `master` push for speed, but the direct push skips every safety surface the other six practices depend on. (Pre-customer projects on this harness may permit direct `master` commits per `git.md`'s customer-tier policy for trivial ancillary edits — but substantial work, and anything touching migrations or shared schema, goes through a PR. The PR is cheap; the silent-skip it prevents is not.)

### Practice 5 — Branch protection on `master` (operator-executed once)

**Prevents:** the entire class of "something landed on trunk without passing the gates" — the structural backstop under all four failures.

**The rule:** `master` is protected so that changes can only land through a PR that passed required checks. This is configured **once per repo by the operator**, not by an agent, because branch-protection changes affect every collaborator's push path and are a deliberate human decision. **The harness documents the exact commands; it does NOT run them** (see "Documented-not-executed `gh` commands" below).

### Practice 6 — Merge queue (the serialization point)

**Prevents:** failure #1's root shape (two changes that each pass on their own but conflict when both land) — and, more broadly, the race where two green PRs merge near-simultaneously against a `master` that each tested against separately.

**The rule:** enable a **merge queue** on `master`. A merge queue is the serialization point of trunk-based development: it takes the set of approved-and-green PRs and merges them ONE AT A TIME, re-running checks against the actual post-merge state of trunk before each lands. Two PRs that were each green against an older `master` but conflict with each other are caught by the queue, not by a broken `master`. The migration-number collision (failure #1) is exactly this shape — two changes green in isolation, broken in combination; a merge queue that re-tests against post-merge trunk would surface the duplicate-`168_` before it landed (and Practice 7 prevents the duplicate from existing in the first place — defense in depth). Configured once per repo by the operator (commands below).

### Practice 7 — NEVER a shared incrementing counter; use timestamps (MECHANISM)

**Prevents:** failure #1 (migration-number collision → silent schema loss). This is the single highest-leverage practice and the one the harness enforces mechanically.

**The rule:** any artifact whose name must be unique-and-ordered across parallel machines MUST use a **timestamp prefix** (`YYYYMMDDHHMMSS`), never a **shared incrementing integer counter**. A sequential counter is a coordination point that parallel machines cannot coordinate: each machine independently reaches for "the next number", both pick the same number, and the collision is silent. A UTC timestamp needs no coordination — two machines one second apart produce distinct, correctly-ordered names; even same-second collisions are vanishingly rare and visibly different in the descriptive slug.

This applies most acutely to **database migrations** (`supabase/migrations/`, `**/migrations/`, `prisma/migrations/`), where the collision causes `supabase db push` (and equivalent migration runners) to **silently skip** the second file of a duplicate-numbered pair. To create a migration:

```bash
prefix=$(date -u +%Y%m%d%H%M%S)
# e.g. supabase/migrations/${prefix}_add_state_card.sql
```

**Mechanically enforced:** `migration-naming-gate.sh` (PreToolUse Bash on `git commit`) BLOCKS any **newly-added** migration file whose name begins with a bare sequential-integer prefix (`168_`, `0042-`, `7_`). Existing integer-named migrations already in history are **grandfathered** — the gate only checks added files (`git diff --cached --diff-filter=A`), so the back-catalog is frozen and only new migrations must use timestamps. The gate recognizes Supabase, generic `**/migrations/`, and Prisma (where the prefix lives in the directory name) layouts; accepts `YYYYMMDDHHMMSS_`, `YYYYMMDDHHMMSS-`, and `YYYYMMDD-HHMMSS_` timestamp forms; and is a no-op for non-migration files and non-commit Bash. See the enforcement table below.

### Practice 8 — One item = one branch = one machine, tracked on a shared work board

**Prevents:** failure #4 (two machines diagnosing #513 independently — duplicated work).

**The rule:** every unit of work (an issue, a task, a plan) is claimed on a **shared work board** before work begins, and a claimed item maps to exactly **one branch on one machine**. The board is the single place where "who is working on what, where" is visible across machines — so a second machine sees #513 is already claimed before it starts a duplicate diagnosis. This composes with the harness's own surfaces: the conversation-tree/workstreams UI, `docs/backlog.md`, and active plan files (`docs/plans/`) are all work-board surfaces; the discipline is to **claim before you build** and to make the claim visible to the other machine. A branch with no corresponding claimed board item, or a board item claimed on two machines, is the signal of an impending duplicate.

---

## Documented-not-executed `gh` commands (Practices 5 + 6)

These are the exact commands to configure branch protection and a merge queue. **The harness does NOT run them** — they are coordination-sensitive (they change every collaborator's push path) and are an explicit operator decision. Run them once per repo, with the operator's authorization, replacing `<owner>/<repo>`:

```bash
# --- Practice 5: branch protection on master ---
# Require PRs (no direct pushes), require status checks to be green and
# up-to-date with the base before merge, dismiss stale approvals.
gh api -X PUT repos/<owner>/<repo>/branches/master/protection \
  --input - <<'JSON'
{
  "required_status_checks": { "strict": true, "contexts": [] },
  "enforce_admins": true,
  "required_pull_request_reviews": {
    "dismiss_stale_reviews": true,
    "required_approving_review_count": 0
  },
  "restrictions": null,
  "required_linear_history": true,
  "allow_force_pushes": false,
  "allow_deletions": false
}
JSON
# Notes:
#  - "strict": true is the merge-queue-adjacent guarantee that a PR must be
#    re-tested against the current base before it can merge (catches the
#    "green in isolation, broken in combination" race — failure #1's shape).
#  - "required_approving_review_count": 0 keeps PR-even-solo workable for a
#    solo operator while still routing every change through a PR + checks.
#    Raise to 1 once there is a second reviewer (human or a reviewer-agent
#    wired to approve).
#  - "allow_force_pushes": false reinforces git-discipline.md Rule 1.

# --- Practice 6: merge queue on master ---
# GitHub merge queue is configured via repo rulesets (the modern surface).
# The exact ruleset payload is repo-specific; the canonical command shape:
gh api -X POST repos/<owner>/<repo>/rulesets \
  --input - <<'JSON'
{
  "name": "master-merge-queue",
  "target": "branch",
  "enforcement": "active",
  "conditions": { "ref_name": { "include": ["refs/heads/master"], "exclude": [] } },
  "rules": [
    { "type": "merge_queue",
      "parameters": {
        "merge_method": "SQUASH",
        "max_entries_to_merge": 5,
        "max_entries_to_build": 5,
        "min_entries_to_merge": 1,
        "min_entries_to_merge_wait_minutes": 5,
        "check_response_timeout_minutes": 60,
        "grouping_strategy": "ALLGREEN"
      }
    }
  ]
}
JSON
# After this lands, PRs merge via the queue ("Merge when ready"), which
# re-runs checks against the post-merge state ONE PR AT A TIME — the
# serialization point that makes parallel PRs safe to land.
```

**Why documented, not executed:** branch protection and merge queues change the push path for everyone who works on the repo, can lock out an in-flight push mid-session, and interact with the repo's existing collaborator/automation setup. That is a deliberate human decision, not an autonomous agent action (consistent with `planning.md` Tier-3: changes to a shared contract / public API surface pause for the operator). The agent surfaces these commands and the operator runs them.

---

## Cross-references

- **`git-discipline.md`** — Rule 1 (force-push prohibition), Rule 2 (post-merge sync of the main checkout), Rule 4 (verify the staged set before commit). This rule's Practices 2–3 compose with those: one authoritative remote + pull-before-work + push-before-switch is the same anti-divergence discipline at the workflow level that git-discipline enforces at the per-operation level.
- **`branch-hygiene.md`** — the WIP-branch naming convention (`feat/*`, `fix/*`, `wip/<machine>-<topic>-<date>`), stash-lifetime discipline, and stale-branch policy. This rule's Practice 1 (short-lived branches) uses that naming convention; the `<machine>` token in `wip/` names is what makes Practice 3's "never two machines on the same branch" visible in `git branch`.
- **`session-start-git-freshness.sh`** — the SessionStart surfacer that reports "local master is BEHIND ${remote}/master — pull before working." Practice 3's pull-before-work is the operator/agent acting on that surfaced signal.
- **`orchestrator-pattern.md`** — parallel builders in worktrees, build-in-parallel + verify-sequentially. This rule is the cross-machine analogue of the orchestrator's in-machine parallelism discipline; the merge queue (Practice 6) is the cross-PR serialization point the way sequential verify is the cross-worktree one.
- **`migration-naming-gate.sh`** — the Mechanism backing Practice 7.

---

## Enforcement

| Practice | Layer | What enforces it | File |
|---|---|---|---|
| 1 — Trunk-based, short-lived branches | Pattern | Self-applied; naming via branch-hygiene; staleness surfaced at SessionStart | `branch-hygiene.md`, `stale-active-plan-surfacer.sh` |
| 2 — One authoritative remote, one-way mirrors | Pattern | Self-applied; divergence surfaced at SessionStart | `session-start-git-freshness.sh`, `git-discipline.md` |
| 3 — Pull-before-work, push-before-switch, one-machine-per-branch | Pattern | Self-applied; behind-master surfaced at SessionStart | `session-start-git-freshness.sh` |
| 4 — PR-even-solo | Pattern | Self-applied; reinforced by `merge-completed-work.md` | `merge-completed-work.md`, `git.md` |
| 5 — Branch protection on master | Operator-executed once | Documented `gh` commands above; operator runs them | (this rule) |
| 6 — Merge queue | Operator-executed once | Documented `gh` commands above; operator runs them | (this rule) |
| **7 — Never a shared counter; use timestamps** | **Mechanism** | **`migration-naming-gate.sh` BLOCKS newly-added bare-integer-prefixed migrations at `git commit`** | **`migration-naming-gate.sh`** |
| 8 — One item = one branch = one machine | Pattern | Self-applied; claim visible on the work board (workstreams UI / backlog / plans) | `orchestrator-pattern.md`, `docs/backlog.md` |
| All | User authority | The operator is the backstop for every Pattern-class practice | (Pattern) |

The seven practices are the harness's CI/CD standard for parallel development. Practice 7 is mechanically enforced because its failure is silent and high-cost (schema loss with no error); Practices 5–6 are operator-executed-once because they change a shared contract; the rest are Pattern-class, surfaced at SessionStart and backstopped by the operator's interrupt authority.

## Scope

Applies in every project whose Claude Code installation has this rule file present at `~/.claude/rules/parallel-dev-discipline.md`. Loaded contextually by the harness; no opt-in required. The practices bind every session in every mode — interactive local, parallel local (worktrees), cloud-remote / Dispatch, scheduled, and agent-team — because parallel development across machines and sessions is the harness's premise in all of them. Practice 7's mechanism fires wherever `migration-naming-gate.sh` is wired in the PreToolUse Bash chain; Practices 5–6's `gh` commands apply per-repo and are run once by the operator. Projects without migrations never trigger Practice 7's gate (it no-ops on non-migration commits).
