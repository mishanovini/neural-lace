# 037 — Canonical File-Lifecycle Policy for Session-Generated Artifacts

- **Date:** 2026-05-25
- **Status:** Proposed (design-only; implementation gated on Misha's authorization)
- **Stakeholders:** Misha (owner/authorizer), harness maintainers, every Claude Code session that writes SCRATCHPAD / `docs/reviews/` / `docs/discoveries/` / `docs/findings.md`, and every worktree-isolated builder/analysis session
- **Supersedes / amends:** does not supersede; extends ADR 028 (`session-wrap.sh` worktree fall-back) and composes with `git-discipline.md` Rule 2 (post-merge sync of the main checkout). Pattern 3 of 5 in the plan-lifecycle-redesign initiative (sibling: ADR 036 plan-closure).
- **Originating diagnosis:** `docs/discoveries/2026-05-25-file-lifecycle-root-cause-chain.md`
- **Design plan:** `docs/plans/file-lifecycle-redesign.md`
- **Companion ADR:** `docs/decisions/038-pending-items-marker-convention.md` (RC4 — auto-extraction)

## Context

Session-generated files in this harness have no codified lifecycle. There is no
policy for (a) where a given file class lives, (b) when a write is durable vs
ephemeral, or (c) how a file written inside a short-lived git worktree reaches the
operator's main checkout. The absence produces three distinct failures, diagnosed
in full in the originating discovery:

- **RC1** — `session-wrap.sh cmd_refresh` only edits an *existing* SCRATCHPAD; a
  missing file reads as a `1666666 min` stale sentinel and the Stop hook loops
  unbreakably (435× in one session today).
- **RC2** — durable deliverables (`docs/reviews/`, `docs/discoveries/`) written in
  a worktree are stranded when the worktree branch is discarded without a PR.
- **RC3** — the scripts that populate the Conv Tree are untracked, mixing a genuine
  reusable tool with a dated throwaway instance.

This ADR codifies the policy and selects the mechanism for each class. RC4 (the
auto-extraction hook) has its own ADR (038) because it introduces a marker
convention that is a separable contract.

## Decision

### D1 — File-class taxonomy (the policy)

Every session-generated file is classified into exactly one of three lifecycle
classes. The class is determined mechanically by path:

| Class | Examples | Lives in | Propagation to main | Tracked? |
|---|---|---|---|---|
| **Ephemeral** | `SCRATCHPAD.md`, `.claude/state/**` | the **parent** checkout (ADR 028) | none needed — already parent-scoped | gitignored |
| **Durable deliverable** | `docs/reviews/`, `docs/discoveries/`, `docs/findings.md`, `docs/decisions/`, `docs/plans/` | the checkout the session runs in | **branch-merge (primary) OR publish-on-stop (safety net, D3)** | version-controlled |
| **Tool vs instance** | tracked: reusable scripts in their module dir. NOT tracked: dated, machine-specific throwaways | module dir (tools) / nowhere (instances) | n/a | tools yes; instances never |

The taxonomy is the load-bearing artifact: every mechanism below is a consequence
of which class a file is in. "When does a worktree-write count as durable?" → iff
its path is in the **Durable deliverable** class. "Where does SCRATCHPAD live?" →
the parent checkout, always (so worktree sessions edit the parent's copy directly
and there is no stranding problem for ephemeral state).

### D2 — Ephemeral: SCRATCHPAD is auto-created from template when missing (fixes RC1)

`session-wrap.sh cmd_refresh` becomes **create-on-missing-from-template**: when the
parent-resolved `SCRATCHPAD.md` does not exist, write a minimal template stub
(atomic temp-then-rename, only when absent — never clobber) *before* the timestamp
arithmetic. `cmd_verify` Signal 1 then reads a fresh, real file. The stub follows
the 30-line format documented in `adapters/claude-code/CLAUDE.md` (Current State /
Latest Milestone / Active Plan / Backlog Pointer / What's Next / Blocking).

This is **curative, not palliative**: the alternative (skip Signal 1 when SCRATCHPAD
is missing, treating it as non-applicable like the non-git case) would *hide* the
gap. Doctrine (CLAUDE.md "Context Persistence") says every project maintains a
SCRATCHPAD — so the correct response to "it's missing" is to produce the artifact
doctrine wants, leaving a real file the next session reads, not to silence the
check. The create-always behavior is aligned with doctrine; in the rare case a
session runs in a git repo that genuinely should not have a SCRATCHPAD, the stub is
a harmless 30-line file the operator can delete.

### D3 — Durable: publish-on-stop for worktree-written deliverables (fixes RC2)

A new Stop hook `docs-publish-on-stop.sh`. At session end, for files in the
**Durable deliverable** class that this session created/modified inside a worktree:

1. Resolve the main checkout via `git rev-parse --git-common-dir` → dirname (the
   same parent-of-common-dir pattern `conversation-tree-emit.sh _main_repo_root`
   and `git-discipline.md` Rule 2 use).
2. **Copy-if-absent** each durable file into the main checkout's working tree at
   its same repo-relative path. Never overwrite an existing main-checkout file
   (dated/unique filenames make collisions rare; copy-if-absent makes them safe).
3. **Always** record the file + its content hash to a per-machine staging ledger
   at `~/.claude/state/published-docs/<sha>.json` (a durable backstop + audit
   trail, independent of whether the copy-into-main succeeded).
4. A SessionStart surfacer (`published-docs-surfacer.sh`, mirroring
   `spawned-task-result-surfacer.sh`) lists any ledger entry that could NOT be
   auto-placed (main unresolvable, or a same-path file already existed with
   different content), so the operator can harvest it deliberately. Acked entries
   stop re-surfacing.

Scope is deliberately narrow: only the durable-deliverable doc classes, never
source code (source belongs on the worktree branch and merges via PR), never
ephemeral state. **Approach A (transparent write-time path-redirect) is rejected as
mechanically infeasible** — PreToolUse hooks cannot mutate `tool_input.file_path`
(see Alternatives). RC2 is therefore solved at session-end (publish), not
write-time (redirect).

This composes with `git-discipline.md` Rule 2: branch-merge + main-pull is the
PRIMARY propagation path; publish-on-stop is the SAFETY NET for the never-merged
worktree branch. They do not conflict (copy-if-absent yields to a real committed
copy that arrives via merge).

### D4 — Tool vs instance: track the tool, retire the instance (fixes RC3)

- `neural-lace/conversation-tree-ui/scripts/backfill-from-sessions.js` → **track**.
  It is a reusable tool. Before tracking, sanitize the personal-path example in its
  header comment (`<abs-path-to-main-checkout>`) to a generic
  placeholder per `harness-hygiene.md` (the pre-commit `harness-hygiene-scan.sh`
  would otherwise flag it).
- `add-pending-items.js` → **do NOT track**. It is a dated instance (hardcoded
  2026-05-20 items, `today-20260520` node ids). Its intent is mechanized by RC4
  (ADR 038). Once the extraction hook ships, the instance is deleted. Until then it
  may stay untracked locally; it never enters version control as-is.

## Alternatives Considered

- **A — transparent write-time path-redirect for worktree durable writes.**
  Rejected: infeasible. Claude Code PreToolUse hooks emit allow/deny/context, not a
  mutated `tool_input`; they cannot redirect a write's `file_path`. The symlink
  variant (symlink `docs/reviews/` in worktrees to main) breaks git worktree
  isolation and the per-branch PR flow. This is why D3 is a session-end publish.
- **A2 — palliative skip-Signal-1 for RC1.** Treat missing-SCRATCHPAD as
  non-applicable and skip the freshness signal. Rejected: hides the gap instead of
  producing the artifact doctrine mandates; leaves the next session with no
  SCRATCHPAD. Curative beats palliative.
- **B4 — staging-dir-only for RC2 (no auto-copy into main).** Publish only to the
  neutral staging ledger; require the operator to harvest via the surfacer.
  Rejected as the *primary* path because "surfaced but never harvested" degrades to
  palliative; but ADOPTED as the *backstop* tier of D3 (the ledger + surfacer catch
  what copy-if-absent can't auto-place). The hybrid gives automatic-when-possible +
  never-lost.
- **Auto-defer / loosen gates.** Out of scope; rejected by the same reasoning the
  parallel ADR 036 records (symptom-masking; wrong layer).

## Consequences

**Enables:**
- The 435× Stop loop is structurally impossible (refresh always has a file to
  freshen). RC1 closed by a one-function change — the cheapest, first-shipped win.
- Worktree analysis/demo sessions can write durable deliverables and trust they
  reach the operator even if the branch is discarded. RC2 closed.
- The Conv Tree's population tool gets provenance and survives `git clean`; the
  throwaway instance is retired rather than fossilized into git history. RC3 closed.

**Costs:**
- D3 writes into the operator's main checkout working tree from a worktree session
  — new untracked files appear in `docs/reviews/` etc. This is the *intended*
  outcome (the deliverable is now where the operator looks) and is bounded by
  copy-if-absent (destroys nothing) + narrow path-class scope. It is the
  highest-blast-radius piece and ships LAST (roadmap R5), gated on Misha's ack.
- D2 means `session-wrap.sh` now *creates* files, a behavioral change from its
  prior edit-only contract. Bounded to a 30-line template, only-when-absent.

**Blocks nothing.** All three mechanisms are additive; existing closed plans,
existing SCRATCHPADs, and existing merge flows are unaffected.

## Refutation Criterion

The core causal claim — "missing-file SCRATCHPAD is what produces the
`1666666 min` sentinel and the loop" — is PROVEN: `mtime_seconds_ago` returns
`99999999` for a non-existent file (session-wrap.sh:128-130), `99999999/60 =
1666666`, and `cmd_refresh`'s `if [ -f "$scratchpad" ]` guard (line 259) is a no-op
when absent. The claim that D3 is *necessary* (vs branch-merge sufficing) is
HYPOTHESIZED; REFUTED if an audit shows every worktree that writes a durable doc
also reliably merges its branch (it does not — the nervous-lehmann review is the
counterexample, stranded and unmerged for 5 days).
