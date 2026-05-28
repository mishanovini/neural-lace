---
title: Neural Lace two-repo fork deep-dive + sync strategy
date: 2026-05-27
type: process
status: pending
auto_applied: false
originating_context: Misha directive — "I am not going to pick one as canonical... figure out all modifications across all NL repos and everything in flight. Consolidate and keep the two repos in sync. They need to stay in sync. I am not going to archive either of them."
decision_needed: Approve a consolidation path + a going-forward sync mechanism. Several sub-decisions require Misha (force-push exception vs tree-only sync; governance alignment; visibility asymmetry; ADR-036 renumber). See "Risks + open questions".
predicted_downstream:
  - Pocket-Technician/neural-lace master + branch protection
  - mishanovini/neural-lace master + branch protection
  - adapters/claude-code/sync.sh
  - a new cross-repo sync GitHub Action (proposed)
---

# Neural Lace Two-Repo Fork: Deep Dive + Sync Strategy

**Read-only investigation.** Nothing was pushed, merged, cherry-picked, or reset. The
only state mutated: `git fetch` on both remotes (updates local tracking refs), and two
reversible `gh auth switch` operations (restored to the as-found `mishanovini` active
account). The `personal` remote already existed in this clone — no remote was added.

## Executive summary

There are **two independent GitHub repositories**, both live, both intended to hold the
same harness:

- **`mishanovini/neural-lace`** — PUBLIC. The historical "published" face.
- **`Pocket-Technician/neural-lace`** — PRIVATE, described in its own GitHub metadata as
  the "PT-org private mirror". Branch-protected (required `validate` check, **required
  linear history**, no force-push, conversation-resolution required).

They share history only up to **`fff2de3` (2026-05-22 17:07)** and have **diverged
bidirectionally** since: PT master is **16 commits** ahead of the merge-base; personal
master is **13 commits** ahead. The "mirror by design" was never automation — it was a
**manual, remote-name-dependent `sync.sh` wrapper** (`adapters/claude-code/sync.sh`) that
drifted because the two working clones name the PT remote differently. **Honest finding
(Rule 0): there has never been an automated mirror. "Mirrored" was an aspirational manual
convention that broke the moment two clones used different remote names and two repos used
different governance.**

The good news: most of the apparent "stranded" local work is **not unique** — its content
already exists on PT master under different SHAs (verified byte-identical). The genuinely
hard part is small and well-bounded: **6 files changed on both sides**, of which **3 are
heavy true conflicts** (the conversation-tree-UI web files `app.js` / `app.css`, and the
`conversation-tree-emit.sh` hook), plus an **ADR-036 number collision** and a structural
tension between PT's required-linear-history and the absolute force-push prohibition.

---

## PART 1 — COMPLETE INVENTORY

### 1a. The two remote repositories

| | `Pocket-Technician/neural-lace` (`origin`) | `mishanovini/neural-lace` (`personal`) |
|---|---|---|
| Visibility | **PRIVATE** | **PUBLIC** |
| Description | "...(PT-org private mirror)" | "Neural Lace — self-learning harness..." |
| Default branch | master | master |
| master HEAD | `f7ee4d2` (2026-05-27 12:04, PR #25) | `5715f3c` (2026-05-27 10:57) |
| Branch protection | **YES** — required check `validate`, strict; **required_linear_history**; no force-push; no deletions; required_conversation_resolution; enforce_admins=false | **NONE** (404 — no protection) |
| Open PRs | **0** | **9** (#28,29,30,31,34,35,36,37,38) |
| Access (this machine) | only the `MishaPT` gh account | the `mishanovini` gh account (public) |

**Merge-base (divergence point):** `fff2de3` — "chore(plan): close
session-state-refresh-2026-05-22" (2026-05-22 17:07:36). Matches the expected value.

**Divergence counts:** `origin/master` has 16 commits not in `personal/master`;
`personal/master` has 13 commits not in `origin/master`.

#### The 16 PT-only commits (oldest → newest)

All landed 2026-05-26 22:30 → 2026-05-27 12:04, several within seconds of each other
(a bulk landing). PT PR numbers in parens.

| SHA | PT PR | Subject | Key files |
|---|---|---|---|
| `793b37f` | #2 | reconcile ADR numbering + worktree-per-session (5-pattern cleanup) | `docs/decisions/036..042`, `DECISIONS.md`, plan-lifecycle plan, several discoveries |
| `748d418` | #12 | [docs-only] Pattern 4 Session-Resilience plan | `docs/plans/session-resilience-redesign.md` |
| `83bc2f6` | #3 | track backfill/add-pending-items scripts | conv-tree `scripts/*.js` |
| `c92a176` | #5 | session-wrap: create SCRATCHPAD on missing (435x loop) | `scripts/session-wrap.sh` |
| `c6956bf` | #10 | conv-tree: auto-extract pending items | `conversation-tree-extract-pending.sh`, `settings.json.template`, arch doc |
| `82a3460` | #14 | worktree-spawn primitive + isolation rules | `spawn-worktree.sh`, worktree-per-session conv, arch doc |
| `e1f3960` | #15 | [docs-only] Pattern 3 File-Lifecycle plan | `docs/plans/file-lifecycle-redesign.md` |
| `d11b0e6` | #16 | [docs-only] Pattern 5 Dispatch-Coordination plan | `docs/plans/dispatch-coordination-redesign.md` |
| `8d4a531` | #17 | ci: permissions block on pr-template-check | `.github/workflows/pr-template-check.yml` |
| `fa5d0e9` | #19 | hooks: validate build w/o live DB | `pre-commit-gate.sh` |
| `4e64e6e` | #20 | conv-tree: project-root topology + migration + emit path-fallback | `conversation-tree-emit.sh`, migration js |
| `e1d7d4f` | #21 | close fix-precommit-gate-db-build | plan archive move |
| `6924d2b` | #23 | **principles doc + warn-mode compliance gate** | `principles-compliance-gate.sh`, `rules/principles.md`, `settings.json.template`, arch doc |
| `50bb4a9` | #7 | harness-hygiene roadmap + principles/doctrine plans | roadmap + 2 plans |
| `e541c16` | #24 | **conv-tree: Tree pane renders projects → pending items** | `app.css`, `app.js`, reframe plan |
| `f7ee4d2` | #25 | tdd-gate: per-project routesTestedVia:e2e exemption | `pre-commit-tdd-gate.sh`, vaporware rule, guide |

#### The 13 personal-only commits (oldest → newest)

| SHA | personal PR | Subject | Key files |
|---|---|---|---|
| `b4fdf3b` | (in #24) | conv-tree-auto-current — P1 stale-tree fix | `conversation-tree-emit.sh`, `settings.json.template`, `register-heartbeat.ps1`, conv-tree `server.js`/`app.css`/`app.js`/`index.html` |
| `1c2c25a` | (merge) | merge origin/master into vibrant-fermi | (merge surface — FM-001/ADR-035/evidence files) |
| `02f3ad9` | **#24** | Merge PR #24 (conv-tree-auto-current) | conv-tree emit + UI |
| `1910fd9` | — | close conv-tree-auto-current | plan archive |
| `dbc1354` | **#25** | Merge PR #25 (conv-tree-auto-current close) | plan archive |
| `3659ca3` | #26 | file HARNESS-GAP-39 | `docs/backlog.md`, gap doc |
| `c304d3b` | #27 | conv-tree-ui: toast stacking | `app.js`, responsive selftest |
| `932e3be` | #33 | **conv-tree: auto-emit enforcement (Layer B reconciler + Layer D rule)** | `conv-tree-emit-reconciler.sh`, `conv-tree-orchestrator-emit.md`, `settings.json.template`, arch doc |
| `b93fdaf` | #32 | **conv-tree-ui: v2 layout (narrow tree + tabbed panel + modals)** | `reducer.js`, `schema.js`, `app.css`, `app.js`, `index.html` |
| `38d76e0` | #39 | **conv-tree-ui: v3 accordion panels** | `app.css`, `app.js`, `index.html` |
| `afcd9a8` | — | **merge-completed-work standing rule + auto-merge design** | `rules/merge-completed-work.md`, `designs/auto-merge-on-green-hook.md`, arch doc |
| `b1799a8` | — | close merge-completed-work-rule | plan archive |
| `5715f3c` | — | include Status flip in archival commit | plan archive |

#### Overlapping PR numbers (different content — inherent, unfixable)

PT and personal each have an **independent PR counter** (two separate GitHub repos). The
numbers WILL collide and cannot be reconciled:

| # | PT content | personal content |
|---|---|---|
| 23 | principles doc + gate | close diagnostic-first-protocol |
| 24 | Tree pane → pending items | conv-tree keep auto-current (heartbeat) |
| 25 | tdd-gate e2e exemption | close conv-tree-auto-current |
| 17 | pr-template permissions fix | pr-template placeholder-scope + checkout@v5 |

Both repos' PR histories stay as historical records. There is no way to "merge PR numbers".

### 1b. Local working state (this machine)

**Three clones exist; only this one holds divergent/stranded work.**

1. **`~/dev/Pocket Technician/neural-lace`** (this clone) — `origin`=PT, `personal`=personal.
   - HEAD: `feat/harness-principles-doc-and-gate` @ `295aaf9` (== origin feat branch; the pre-merge form of PT #23).
   - Local `master` @ `5eecd69` — **ahead 3 / behind 16** of `origin/master`.
   - **The "ADR-036 trio"** (`03a7d2d`, `234950a`, `5eecd69`) is the local-master "ahead 3."
     **Verified NOT unique**: `036-plan-lifecycle-mechanical-closure.md` and
     `plan-lifecycle-redesign.md` are **byte-identical** on PT master (empty diffs). The
     content landed on PT via #2; only the SHAs are stranded. Safe to abandon locally.
   - Other local branches: `salvage/session-wrap-scratchpad-fix-e7212e7` (@`e7212e7`),
     `design/session-resilience-redesign` (@`3d9f8f3`, origin gone),
     `fix/session-wrap-create-on-missing` (@`5eecd69`) — **all redundant SHAs**: their
     content (e.g. `session-wrap.sh`) is byte-identical to PT master. `conv-tree-bootstrap-mechanism`
     and 5 `claude/*` branches @ `92eecea` are **landed** (ancestors of origin/master).
   - One worktree: `.claude/worktrees/nervous-lehmann-35212e` @ `92eecea` (landed).
   - **Uncommitted (tracked, modified):** `docs/backlog.md`, `conversation-tree-ui/web/app.css`,
     `conversation-tree-ui/web/app.js` — live in the conv-tree-UI conflict zone.
   - **Untracked — duplicates of PT** (near-identical, ignore): `docs/plans/conv-tree-pending-items-reframe.md`,
     `docs/plans/dispatch-coordination-redesign.md`, `docs/plans/session-resilience-redesign.md`.
   - **Untracked — GENUINELY UNIQUE (on neither remote):**
     `docs/discoveries/2026-05-26-worktree-spawn-session-harness-friction.md`,
     `docs/discoveries/2026-05-27-conv-tree-checkout-divergence-and-wiring-coverage-gap.md`,
     `adapters/claude-code/commands/grant-local-edit.md`.
   - Operational untracked (gitignore-class, not work): `conversation-tree-ui/state/.claude/`,
     a `tree-state.json.bak.*` backup.
   - No stashes. Dangling commits exist (`git fsck`) but are normal rebase/amend GC detritus —
     no branch-referenced or reflog-reachable unique work was found beyond the above.
   - `neural-lace/neural-lace` is **NOT a nested repo** — it is the conv-tree-ui subdirectory.

2. **`~/dev/Personal/neural-lace`** — `origin`=personal only. master @ `16502d6`
   (2026-05-13). Clean, no stashes, master-only. **Stale, no unique work.**

3. **`~/dev/.archive/neural-lace`** — `origin`=personal only. master @ `1aadf35`
   (2026-04-22). Clean. **Archive snapshot, no unique work.**

### 1c. In-flight Dispatch sessions

`list_sessions` shows **no NL session currently running** (`isRunning: false` for all). The
two named sessions are idle and not NL (`Foresight rules engine` → `~/dev/Personal/foresight`;
`AI booking deeper diagnosis` → `~/dev/Pocket Technician/Circuit`). However ~15 NL sessions
were active *today* (cwd = this clone), several with open PRs (#17/#18/#19/#22/#25). This
heavy concurrent multi-session NL work is precisely what produced the divergence and the
duplicate-SHA landings. **The consolidation window is currently open** — nothing is
executing. Recommendation for sequencing: do the consolidation while no NL session is
running, and avoid spawning new NL build sessions during the window.

### 1d. Mirror-mechanism truth

**There was never an automated mirror.** Evidence:
- `.git/config` has two plain remotes — no `remote.*.pushurl` multi-URL, no `mirror=true`.
- The only GitHub Action is `pr-template-check.yml` — it validates PR bodies, it does not
  cross-push. No cron, no other workflow, no hook auto-pushes to a sister remote.
- The mechanism is **`adapters/claude-code/sync.sh`** — a manual wrapper that pushes the
  current branch to remotes named `personal` and `work`/`pt`.

**Why it drifted (root cause):** `sync.sh` matches remotes by *name*. In **this** clone the
PT remote is named **`origin`** (not `work`/`pt`). So running `sync.sh` here pushes to
`personal` and then looks for `work`/`pt` (neither exists) → it pushes to **personal only
and silently skips PT**. Meanwhile PT received work through PR merges from sessions whose
origin is PT. The personal clone (`~/dev/Personal`) has only `origin`=personal. So the same
script published to different targets depending on which clone ran it, and the two repos
also use different governance (PT = PR + linear history; personal = open). The "mirror" was
a fragile, remote-name-dependent manual convention with no enforcement — exactly the kind of
advisory-not-mechanism that drifts under concurrent multi-session pressure.

---

## PART 2 — CONSOLIDATION + SYNC DESIGN (proposal only; nothing executed)

### 2a. One-time consolidation plan

**Framing.** Per-commit cherry-pick is the wrong tool: many commits are duplicate content
under different SHAs, and personal's history contains merge commits PT's linear-history
rule rejects. The right approach is **content-level reconciliation** — produce one unified
file tree both masters should hold, resolve the small conflict set once, then publish that
unified state to both.

**Unique work that must cross over (the only real payload):**
- *Personal → PT* (not yet on PT): conv-tree-ui **v2 (#32)** + **v3 accordion (#39)**,
  **toast stacking (#27)**, **auto-emit enforcement (#33)**, **conv-tree-auto-current
  heartbeat (#24/#25 personal)**, **HARNESS-GAP-39 (#26)**, and the **`merge-completed-work`
  standing rule + auto-merge design doc**. Plus the 3 genuinely-unique untracked local files
  (2 discoveries + `grant-local-edit.md`).
- *PT → Personal* (not yet on personal): essentially **all 16 PT commits** — the ADR
  036–042 renumbering, session-wrap fix (#5), worktree-spawn primitive (#14), conv-tree
  extract-pending (#10) + project-root topology (#20), the **principles doc + gate (#23)**,
  pre-commit DB-less build (#19), tdd-gate exemption (#25), the docs-only pattern plans
  (#12/#15/#16), pr-template permissions (#17).

**True conflicts (files changed on both sides since `fff2de3`):**

| File | origin↔personal magnitude | Nature | Proposed resolution |
|---|---|---|---|
| `conversation-tree-ui/web/app.js` | +469 / −173 | **Two divergent UI lines**: PT #24 (projects→pending tree) vs personal #32+#39 (v2 tabbed → v3 accordion) | **Product/UX decision (Misha).** Likely: take personal's v3 accordion as the side-panel base, re-apply PT #24's "projects→pending-items tree" rendering into it. Hand-merge, not line-merge. |
| `conversation-tree-ui/web/app.css` | +259 / −260 | same divergent UI lines | Follows app.js decision; hand-merge styles for the chosen layout. |
| `conversation-tree-ui/web/index.html` | (personal-only changed) | personal v2/v3 only; PT untouched since base | **No conflict** — personal version wins. |
| `adapters/claude-code/hooks/conversation-tree-emit.sh` | +198 / −21 | PT #20 (project-root topology + path-fallback) vs personal #24+#33 (session-start auto-current + reconciler) | **Semantic merge.** Both are emit-hook features; combine: PT's topology/path-fallback + personal's auto-current/reconciler. Verify against the conv-tree state-gate self-tests. |
| `adapters/claude-code/settings.json.template` | +5 / −5 | both wired different hooks | **Union merge** — keep all hook entries (extract-pending, principles-gate, emit-reconciler). |
| `docs/harness-architecture.md` | +6 / −19 | both appended rows | **Union merge** of the enforcement/inventory rows. |
| `docs/DECISIONS.md` | −8 | PT renumbered ADRs; personal index older | Take PT's index, then add the renumbered Decision-Queue row (below). |

**ADR-036 number collision (must resolve):**
- PT master: `036-plan-lifecycle-mechanical-closure.md` (036–042 already assigned on PT).
- personal open PR #36 (`feat/decision-queue`, 1 commit ahead): `036-decision-queue-substrate.md`.
- **Resolution:** renumber the Decision-Queue ADR to the next free PT number (**043**),
  update its `DECISIONS.md` row and any cross-references, then land it.

**Stranded local commits (this clone):** the ADR-036 trio + salvage/design/fix branches are
all **content-duplicates** of PT master. **No salvage needed** — abandon the local SHAs
(reset local master to the unified tip once consolidation lands). The 3 unique untracked
files are the only local payload; commit them onto the consolidation branch.

**Overlapping PR numbers:** leave both repos' PR histories untouched as historical records.
Re-landed content gets **fresh PR numbers** on the receiving repo; this doc + the
consolidation PR descriptions serve as the **old→new migration log**.

**In-flight sessions:** quiesce before executing — confirm no NL session is `isRunning`
(true now) and hold new NL session spawns during the window.

**Proposed sequence (execution is a later phase, not now):**
1. Quiesce: confirm no running NL session; snapshot both master SHAs.
2. Cut an integration branch from `origin/master` (PT — the governed, ADR-renumbered side).
3. Replay personal's unique work onto it (cherry-pick the non-merge personal commits;
   for the conv-tree-UI files, hand-merge per the table). Renumber Decision-Queue → 043.
   Add the 3 unique untracked local files.
4. Resolve the 6 conflict files; run the conv-tree self-tests + harness `--self-test`s.
5. Land the integration branch on PT via PR (satisfies `validate` + linear history). This
   is the **unified tip `U`**.
6. Bring personal master to `U`'s content — **see 2b for the force-push tension; this step
   needs a Misha decision.**
7. Reconcile/close the 9 open personal PRs (most are now landed-or-superseded; #36 becomes
   ADR-043; the CONFLICTING ones — #34/#35/#37 — re-evaluate against `U`).

### 2b. Going-forward sync mechanism

**The core tension (state honestly):** Misha wants both repos in sync, neither canonical,
no archiving — *and* the harness forbids force-push absolutely (`git-discipline.md` Rule 1).
But:
- PT master requires **linear history** + a **PR-passing `validate` check** → you cannot
  push an arbitrary commit (or a merge commit) directly to PT master.
- personal master has **no protection** and **contains merge commits** → its history shape
  is already incompatible with PT's linear-history rule.
- To get *identical SHAs* on both going forward, one side must at least once adopt the
  other's history — which, for at least personal, is **not a fast-forward** and therefore
  needs either a force-push (prohibited) or a tree-identical merge commit (SHAs then differ
  forever).

So there is a real fork in the road that only Misha can choose (see open questions Q1/Q2).

**Mechanism options:**

| Option | How | Failure modes | Durability | Conflict handling |
|---|---|---|---|---|
| **A. Fixed dual-publish wrapper** | Rewrite `sync.sh` to push to **both remotes by URL** (not fragile name-match): `git push origin master && git push personal master`. Developer/Dispatch runs it (or a post-merge hook). | Manual step skippable; if one push is non-FF it half-syncs; PT direct-master push blocked by `validate` requirement. | Medium (still a discipline) | Manual: a non-FF push fails loudly; reconcile by hand. |
| **B. Cross-repo GitHub Action** | On push to master on either repo, an Action pushes the new SHA to the sister repo. PAT with push to both, stored as secret in both. | Token expiry; **direct push to PT's protected master fails the required `validate` check**; simultaneous pushes → non-FF on one side. | High (no manual upkeep — meets Misha's bar) | Action fails + alerts (ntfy) on non-FF; manual reconcile. Needs governance alignment to push to protected master. |
| **C. Single-source dual-published** | Local master is the single integration point; identical commits pushed to both. *Not* "canonical repo" — both remotes are mirror-equal. | Same as A; relies on always integrating in one place. | Medium-High | Divergence only if someone pushes elsewhere; pre-push hook (E) closes that. |
| **D. Bidirectional scheduled sync** | Cron fetches both, pushes deltas both ways. | Conflict resolution must be automated (hard); two-way is the most failure-prone. | Low | Poor — auto-resolving real conflicts is unsafe. **Not recommended.** |
| **E. Pre-push hook enforcing both** | Local hook rejects a push that would land on only one remote. | Only protects local pushes; server-side PR merges bypass it. | Medium (pairs with A/C) | N/A — a guard, not a sync. |

**Recommendation: B (cross-repo Action) as the durable spine, fronted by C/A for local
integration, with governance aligned so the Action can land on both.** Concretely:

1. **Align governance** so both repos accept the same publish path. Two viable shapes:
   - *(b1)* Both repos require PRs + the `validate` check + linear history. Work merges via
     PR on whichever repo; the Action mirrors the merged (already-checked) SHA to the
     sister's master. To let the Action push to a protected master, grant the Action's PAT
     bypass on that one branch (GitHub "allow specified actors to bypass"). Keeps full
     governance, identical SHAs.
   - *(b2)* Relax PT to match personal (drop required-PR/linear-history), then dual-publish
     identical commits to both with the fixed wrapper (A/C). Simpler, less governance.
2. **Fix `sync.sh`** to push by URL to both remotes regardless of local remote names
   (removes the name-match drift root cause) — useful as the local fallback and for the
   one-time consolidation.
3. **Add a pre-push guard (E)** so a manual push that hits only one remote is rejected.
4. **Alerting:** wire the Action's non-FF failure to ntfy (ADR-042 already exists on PT) so
   a desync pages immediately instead of silently drifting.

This meets "no manual upkeep" (the Action is the steady state), "neither canonical" (both
remotes receive identical mirrored SHAs), and "no force-push in steady state" (after the
one-time reconciliation, every sync is a fast-forward).

### 2c. Going-forward conventions

- **Pushing:** developers and Dispatch sessions integrate on a local master and publish via
  the fixed wrapper (or merge a PR and let the Action mirror). Never push to one remote only.
- **Branch protection (must MATCH on both):** today PT is protected and personal is wide
  open. Make them identical — same required `validate` check, same force-push prohibition.
  Decide linear-history together (Q2). Mismatched governance is the structural cause of the
  drift; symmetry is non-negotiable for durable sync.
- **Remote naming:** standardize every NL clone to the same remote names (e.g.,
  `origin`=PT, `personal`=personal) OR make all tooling URL-based not name-based. The
  fixed `sync.sh` should not depend on names at all.
- **"Which remote does this clone track?"** Stop caring — both are tracked, and every push
  targets both. The clone's `origin` is just the integration default; the wrapper guarantees
  both get the same commit.
- **Visibility:** PT private + personal public means everything synced to personal is
  PUBLIC. The harness-hygiene scanner already enforces a clean kit, so this is acceptable —
  but it must be a conscious decision (Q3), because bidirectional sync makes the private
  repo effectively public-equivalent in content.

---

## Risks + open questions for Misha

- **Q1 — Force-push exception for the one-time reconciliation?** Getting *identical SHAs*
  on both repos requires, at least once, a non-fast-forward update of personal master
  (PT is the governed side we build on). Options: **(a)** a one-time, explicitly-authorized
  force-push of personal master to the unified tip `U` (fully recoverable — old history is
  preserved in personal's PRs/branches), giving identical SHAs forever after; or **(b)** a
  **tree-identical merge commit** on personal (no force-push) — content matches but SHAs
  differ permanently, so future divergence checks must compare *trees*, not SHAs. Which?
- **Q2 — Linear history on both, or merge-commits allowed on both?** PT requires linear;
  personal has merge commits. Pick one regime and apply it to both.
- **Q3 — Visibility: keep PT private + personal public?** Bidirectional sync of identical
  content makes the private PT repo's content equal to the public personal repo's. Confirm
  that's intended (it's consistent with the hygiene-scanned clean-kit model, but it means
  "private" buys nothing for content).
- **Q4 — Conv-tree-UI canonical line?** `app.js`/`app.css` are the heaviest conflict: PT's
  "projects→pending-items tree" (#24) vs personal's v3 accordion side-panel (#32→#39). This
  is a UX call, not mechanical. Recommended default: personal v3 accordion shell + PT #24
  tree rendering re-applied — confirm or redirect.
- **Q5 — Governance shape for the Action (b1 vs b2)?** Keep full PR+linear governance and
  give the sync Action a branch-bypass PAT (b1), or relax PT to match personal and
  dual-publish (b2)?
- **Q6 — The 9 open personal PRs.** After consolidation most are landed/superseded; #34/#35/#37
  are CONFLICTING. Re-base-and-reland against `U`, or close as superseded? (Per-PR triage in
  the execution phase.)
- **Risk — concurrency.** The divergence was *caused* by many concurrent NL sessions. Until
  the Action + matched governance are in place, any concurrent multi-session NL work will
  re-diverge. Recommend a freeze on new NL build sessions until the sync mechanism lands.
- **Risk — `gh` active account anomaly.** This PT-org clone had `mishanovini` (personal)
  active, which breaks `origin` (PT) access entirely. The directory-based auto-switch is not
  holding here. Worth fixing independently — it will bite every PT-org NL operation.

---

## Appendix — data provenance

All figures from `git` against freshly-fetched `origin` (PT, via the `MishaPT` gh account)
and `personal` (mishanovini) tracking refs, plus `gh` PR/branch-protection queries on
2026-05-27. Merge-base `fff2de3`; PT master `f7ee4d2`; personal master `5715f3c`. No writes
to either remote; `gh` active account restored to `mishanovini` as found.
