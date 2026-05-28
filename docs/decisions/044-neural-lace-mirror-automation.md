# ADR 044 — Neural Lace cross-repo mirror automation

- **Date:** 2026-05-27
- **Status:** Reverted (2026-05-28) — workflow file removed via PR after MIRROR_PAT cross-account scope proved over-engineered for the actual use case (Misha never pushes via web UI; all pushes go through Claude Code with `~/.claude/` harness loaded, so the cross-repo PAT operational burden isn't worth the edge-case coverage). Superseded by harness-internal drift detection (sync.sh post-push verification + scheduled-task drift poller + SessionStart drift warning). The URL-based `sync.sh` rewrite this ADR introduced is **kept** — it remains the right primitive for "push to both repos on every push." Historical record preserved here for traceability.
- **Stakeholders:** Misha (owner of both repos)
- **Supersedes / relates to:** the deep-dive `docs/discoveries/2026-05-27-neural-lace-fork-deep-dive-and-sync-strategy.md` (Option B in §2b); design plan `docs/plans/neural-lace-mirror-automation.md` (full 10-section Systems Engineering Analysis).

## Context

There are two live Neural Lace repositories — one private org repo and one public personal
repo — intended to hold the same harness. They diverged bidirectionally because there was
**never an automated mirror**: the only "sync" was a manual, remote-name-dependent `sync.sh`
that pushed to whatever remotes happened to be named `personal`/`work`/`pt` in the running
clone, and silently skipped the rest. Misha's directive: keep both repos live, neither
canonical, at **identical master SHAs** forever, with **strict governance (PR + linear
history + required `validate` check) preserved on both** (Q1–Q5 decisions, 2026-05-27).

## Decision

Adopt a **cross-repo GitHub Actions mirror** as the durable steady-state mechanism, fronted
by a **URL-based `sync.sh`** for local/Dispatch integration.

1. **The Action** (`.github/workflows/mirror-to-sister.yml`, deployed identically to BOTH
   repos): on `push` to `master`, mirror the pushed SHA to the sister repo's master via a
   fast-forward ref update. A single parameterized workflow — repo identity lives in a
   per-repo Actions **variable** (`SISTER_REPO`), never in the committed YAML (harness-hygiene
   + good security).
2. **`sync.sh` rewrite**: push the branch to **each distinct remote URL** discovered at
   runtime from `git remote -v` (name-independent — removes the drift root cause). Fail
   loudly if any push fails; never force.
3. **Staged, not enabled.** Both artifacts are committed on a feature branch and NOT pushed.
   Enabling is a cutover step that follows the one-time SHA reconciliation (Q1).

## Token model

Two distinct **fine-grained PATs**, one per repo's secret store, both named `MIRROR_PAT`:

- The PRIVATE-org repo's `MIRROR_PAT`: created by the personal-account owner, repository
  access limited to the PUBLIC personal repo, permission `Contents: Read and write`. Used to
  push to the personal master (which has no protection, so no bypass entry needed).
- The PUBLIC personal repo's `MIRROR_PAT`: created by the org admin actor, repository access
  limited to the PRIVATE org repo, permission `Contents: Read and write`, AND that actor is
  in the org repo's master **branch-protection bypass-allowances** (allow specified actors to
  bypass required PRs). Used to push to the protected org master.

**Honest limitation:** a fine-grained PAT cannot natively restrict pushes to a single branch
ref. "Push only to `refs/heads/master`" is enforced at the **workflow layer** (it only ever
writes that ref) plus the branch-protection layer — not by the token. The required `validate`
check gates PR *merges*, not a bypass-actor's direct FF ref update, so the mirror push does
not re-run `validate` on the sister. This makes "keep both repos' `validate` workflows
identical" a governance **precondition** (itself self-maintaining, since `validate` is also
mirrored content).

## Conflict handling

Post-cutover both masters are linear and dev is squash-only, so every steady-state mirror
push is a fast-forward. The workflow's decision logic:

1. **sister SHA == pushed SHA** → no-op (this is also the loop-break: a PAT push to the
   sister triggers the sister's workflow, which sees equality and exits — terminating the
   loop after exactly one round trip; GitHub's `GITHUB_TOKEN` loop-exemption does NOT apply
   to PAT pushes, so this early-exit is load-bearing, not optional).
2. **pushed SHA is an ancestor of the sister tip** (`git merge-base --is-ancestor`) → benign
   no-op: a rapid-succession second commit already advanced the sister; the newer SHA's run
   re-converges. This prevents false-alarm red runs on ordinary back-to-back merges.
3. **otherwise** → fast-forward `git push` (never `--force`). A non-FF rejection (true
   concurrent divergence, OR a merge commit hitting a linear-history-protected master) makes
   the run **fail loudly**. There is **no auto-resolve** — auto-picking a winner by timestamp
   or primary-writer would silently discard the loser's commit (data loss). A human reconciles.

## Failure alerting

The push step failing turns the workflow red, which triggers GitHub's native
failed-workflow notification (the floor — never silently dropped). An `if: failure()` step
additionally posts to ntfy (ADR-042 infra) when `NTFY_TOPIC`/`NTFY_URL` are configured, so a
desync pages immediately. No secret value is printed (only the auto-masked raw secret is
referenced).

## Updated `sync.sh` interface

```
sync.sh [branch]            # default: current branch
sync.sh --self-test         # run the built-in self-test
```

- Resolves **every distinct push URL** from `git remote -v` and pushes `branch` to each,
  de-duplicated by URL (so `origin` and `pt` pointing at the same URL push once). Name of the
  remote is irrelevant — this removes the original drift cause.
- Never force-pushes. Reports per-URL success/failure; exits non-zero if ANY push failed (no
  silent half-sync).
- Identity-free: the URLs come from the user's local git config at runtime, so the committed
  script contains no real org/user names (harness-hygiene).

## Alternatives considered

- **A — fixed dual-publish wrapper only** (`sync.sh` to both URLs): rejected as the sole
  mechanism — still a manual discipline that's skippable; chosen instead as the *local
  fallback* alongside the Action.
- **B-relaxed (b2) — drop PT's PR/linear governance** and dual-publish: rejected per Q5
  (Misha chose strict governance on both + a bypass PAT).
- **D — bidirectional scheduled cron sync**: rejected — two-way auto-conflict-resolution is
  unsafe (would silently resolve real conflicts).
- **Auto-resolve on divergence (timestamp-wins / primary-writer)**: rejected as default —
  silently discards a commit. A primary-writer model remains available as a future UX choice
  if Misha prefers it over fail-loud.

## Consequences

- **Enables:** identical-SHA mirror with no manual upkeep (Misha's bar); neither repo
  canonical; strict governance preserved on both; loud alerting on any desync.
- **Costs:** two PATs to create + rotate; a branch-protection bypass entry on the org repo; a
  governance precondition that both `validate` workflows stay identical; a one-time SHA
  reconciliation (Q1) must precede enabling.
- **Blocks nothing** while staged; the cutover runbook (plan §10) is the enabling path.
