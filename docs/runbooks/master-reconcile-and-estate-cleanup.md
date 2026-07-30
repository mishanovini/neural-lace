# Runbook: reconcile the two masters + clean the branch/worktree estate

**Reusable procedure.** By design the two GitHub masters must NEVER diverge — personal `origin`
(github.com) and work `pt` (github-pt). When the git-freshness feed reports "master is BEHIND
pt/master by N (and ahead by M) — diverged," run this. It recurs until the never-diverge design
fix lands (see the harness-governance-batch plan); keep this runbook until then.

**Scope vs `estate-merge.sh` (accountable-estate T5):** this runbook is for reconciling the two
independently-writable REMOTES (Part A) and sweeping the branch/worktree estate (Part B) — a
different problem from "merge one branch into the current integration target," which now has a
deterministic, lock-serialized path: `bash adapters/claude-code/scripts/estate-merge.sh merge
<branch> --into <target>` (closers call it; see step 6's scope note below for exactly which
manual verification it retires and which it does not).

## Preconditions

- Run from the **main checkout** on `master` with **NO worktree** — the merge + dual-remote push
  and `git worktree remove/prune` can only be driven from the main checkout.
- `pt` is reachable only on the **work github account**: `gh auth status`; if the active account
  isn't the work one, `gh auth switch -u <work-account>`. (An agent CAN fetch/push pt this way —
  the "SSH access" appearance is just the account auto-switch being on personal.)
- Read the SessionStart active-session-broadcast + claims FIRST. NEVER delete/mutate a branch or
  worktree a live session owns; the concurrent-ownership gate will (correctly) block it — skip,
  never force.

## Part A — reconcile the masters (converge to one commit)

1. `git fetch pt master && git fetch origin master`
2. Confirm the split: `git rev-list --left-right --count pt/master...master` (left = pt-only,
   right = local-only).
3. Identify the conflict surface BEFORE merging:
   `BASE=$(git merge-base master pt/master)`;
   `comm -12 <(git diff --name-only "$BASE" master|sort) <(git diff --name-only "$BASE" pt/master|sort)`.
   Historically this is only `manifest.json` + `docs/backlog.md`, both ADDITIVE.
4. `git merge pt/master`. Resolve conflicts by **UNION** (keep BOTH sides' content):
   - `adapters/claude-code/manifest.json` → keep every entry from both sides; result must be valid
     JSON (`node -e 'JSON.parse(require("fs").readFileSync("adapters/claude-code/manifest.json","utf8"))'`).
   - `docs/backlog.md` → keep both sides' rows.
   - ANY other conflicting file → stop and reason; that's unexpected and not a mechanical union.
5. Post-merge invariant fix: every `agents/*.md` that arrived from the other side must be pinned or
   `check_model_pins` REDs. In particular pin `agents/architecture-reviewer.md` `model: fable` and
   add it to `config/model-policy.json` (design category).
6. VERIFY — against the COMMITTED merge, not the working tree (added 2026-07-16 after a
   reviewer-caught dropped-side merge; a dirty worktree can mask a broken commit).
   **SCOPE NOTE (accountable-estate T5, 2026-07-30 — partial retirement, not a deletion):** this
   checklist defends against a MANUAL conflict-resolution mistake — a human (or agent) picking
   "ours"/"theirs" during a UNION resolve and silently dropping one side's real change. Step 4
   above still does exactly that kind of manual resolution for the origin/pt two-master reconcile,
   so step 6 remains FULLY REQUIRED for Part A. It is retired ONLY for the other class of merge
   this repo now has a deterministic path for: `adapters/claude-code/scripts/estate-merge.sh`
   (accountable-estate T5 — closers call it to merge a worktree/feature branch into the current
   integration target). That script never performs manual conflict resolution: it fast-forwards
   (mathematically lossless — nothing to drop) or lets git's own automatic three-way merge
   succeed with a clean tree, and ABORTS ENTIRELY the moment git reports any conflict (proven by
   `estate-merge.sh --self-test` Scenario 4: a real conflicting edit on both sides aborts cleanly,
   no partial/manual-resolved state ever lands). The dropped-side failure mode this checklist
   exists to catch is therefore structurally impossible for anything that landed via
   estate-merge.sh — do not re-run this checklist for those merges. It stays load-bearing for
   Part A until Decision-064's branch-protection removes manual reconciles from this repo
   entirely.
   a. **Dropped-side sweep, both directions, must be EMPTY** (proves neither side's
      modifications-to-existing-files were silently reverted to base):
      `MB=$(git merge-base <local-parent> <pt-parent>)`; for each file in
      `git diff --name-only "$MB" <side>`: if `side:file != MB:file` and
      `MERGE:file == MB:file` → DROPPED. Run once per side.
   b. **Manifest id-set union AND per-entry faithfulness**: `union(parent id-sets) ==
      merged id-set` (jq + comm); every `doctrine/*.md` on disk has a manifest entry; AND
      every shared id's entry is canonical-JSON-equal (`jq -S`) to at least one parent —
      an id-set check alone would pass a merge that flipped a shared entry's field
      (e.g. `blocking:true→false`) with the id-set intact.
   c. **Generated-doc check against the committed blob** (use a real temp file — NEVER
      `VAR=<(...)` for a path the tool stats or re-reads; a FIFO fails `-f` guards and
      single-uses):
      `M=$(mktemp); git show HEAD:adapters/claude-code/manifest.json > "$M";
      GEN_ARCH_DOC_MANIFEST="$M" bash adapters/claude-code/scripts/gen-architecture-doc.sh --check;
      rm -f "$M"` — GREEN against the worktree does NOT certify the commit.
   d. `bash adapters/claude-code/hooks/model-pin-gate.sh --self-test`;
      `bash adapters/claude-code/hooks/harness-doctor.sh --self-test`;
      `harness-doctor.sh --quick` shows no NEW reds vs the pre-merge baseline.
   NEVER run `git stash` while a merge is in progress — stash push succeeds, destroys
   MERGE_HEAD, and the pop restores the working tree WITHOUT the index, so a later commit
   silently captures pre-merge content for every file you didn't re-add by hand.
7. REVIEW BEFORE PUSH — the merged master deploys estate-wide via auto-install. Dispatch
   `harness-reviewer` (model: fable, or opus if Fable is spend-capped — FRESH dispatch, a resume
   reverts to the fable pin) on the two conflict resolutions + the pin. Fix Critical/Major first.
8. PUSH BOTH (fast-forward on each after this merge — NO force):
   `git push origin master` then `git push pt master`.
9. Confirm convergence: `git rev-list --left-right --count pt/master...master` MUST be `0	0`.

## Part B — clean the branch/worktree estate (unowned + merged/stale only)

1. `git worktree list`; `git branch --merged master`; re-read the broadcast/claims.
2. REMOVE a worktree only if (its branch is merged into master) OR (stale >7d no commit) AND it is
   NOT live-owned: `git worktree remove <path>` then `git worktree prune`.
3. DELETE a local branch only if merged AND unowned: `git branch -d <name>` (never `-D` unless
   proven fully merged). For PR-close branches, verify the PR landed (`gh pr view <n>`) first.
4. KEEP: `master`, every live-owned branch/worktree, and anything the gate protects. Report what
   was removed and what was kept WITH the reason for each keep.

## Recurrence

Divergence keeps happening because both remotes take independent direct commits while
`master-drift-autocorrect.sh` only FF-syncs a strictly-BEHIND master (true divergence is surfaced,
never auto-merged) and the fork-sync isn't running (backlog `PT-FORK-SYNC-NOT-RUNNING-01`). The
durable fix is a design change (single canonical master + auto-mirror, or a robust bidirectional
FF-sync, or a pre-push gate blocking direct commits to the non-canonical remote) — tracked in the
harness-governance-batch plan. Until it lands, this runbook is the manual reconcile.
