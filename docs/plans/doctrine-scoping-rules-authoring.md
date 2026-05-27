# Plan: Doctrine-Scoping Rules Authoring — Where Doctrine Lives, and Who Loads It
Status: ACTIVE
Execution Mode: orchestrator
Mode: design
Backlog items absorbed: none
acceptance-exempt: true
acceptance-exempt-reason: Harness-development plan; the "user" is the maintainer and each shipped component's reviewer-check / `--self-test` PASS is its acceptance artifact. No product UI surface exists. The `## Acceptance Scenarios` below are populated as reviewer-check / load-resolution scenarios (dogfooding the plan-lifecycle-redesign Closure Contract), not browser scenarios.
tier: 3
rung: 2
architecture: coding-harness
frozen: false
prd-ref: n/a — harness-development
owner: Misha
target-completion-date: 2026-08-15

<!-- `owner:` / `target-completion-date:` model the ADR-036 schema (Pattern 1),
     dogfooded here. `## Closure Contract` dogfoods the plan-lifecycle-redesign
     (Pattern 1) Closure Contract section. -->

## Goal

Design `doctrine-scoping.md` (canonical at
`adapters/claude-code/rules/doctrine-scoping.md`, live mirror
`~/.claude/rules/doctrine-scoping.md` — exact filename a §Decision-for-Misha): a
rule that CODIFIES, for the harness, **where each TYPE of doctrine lives, and
which session type loads it** — and that fixes the confirmed memory-load bug at
the policy layer.

Three (at least) doctrine homes exist today, never written down as a coherent
policy:

1. **Global doctrine** — `adapters/claude-code/rules/` (canonical) → `~/.claude/rules/`
   (live mirror). Universal; loaded contextually by every session in every
   project (the `default-to-global` rule in `harness-maintenance.md`).
2. **Project-local doctrine** — `<repo>/docs/conventions/` + project
   `.claude/rules/`. Project-specific conventions (failure-mode-catalog standard,
   worktree-per-session, etc.); loaded only inside that repo.
3. **cwd-scoped memory** — `~/.claude/projects/<cwd-mangle>/memory/` (the
   `user` / `feedback` / `project` / `reference` memory types + `MEMORY.md`
   index). Per-cwd accumulated knowledge; loaded by the auto-memory SessionStart
   injection — **and this is where the bug lives** (see below).

**The confirmed memory-load bug (PROVEN this session).** The cwd-mangle is keyed
to the session's EXACT cwd. This session's cwd
(`…/Pocket Technician/neural-lace`) maps to the mangle
`C--Users-misha-dev-Pocket-Technician-neural-lace`, whose `memory/` dir exists
but has **no MEMORY.md** — while the real memories live one level up in
`C--Users-misha-dev-Pocket-Technician/memory/` (which HAS MEMORY.md). So a
repo-cwd session cannot see its parent-cwd memories. **Worse:** every worktree
gets its OWN mangle (`…neural-lace--claude-worktrees-<name>`), so worktree
sessions miss BOTH the repo-cwd AND the parent-cwd memories. The fix is an
**ancestor-chain load policy**: load the union of memory dirs along the cwd's
ancestor chain (worktree → repo → parent → …up to a sensible root), de-duplicated,
nearest-cwd-wins on conflict — NOT just the exact-cwd-mangle dir.

This plan DESIGNS the policy (the rule + the ancestor-chain load contract). The
LOADER MECHANISM that implements it is **roadmap piece #3 (memory-loading fix)**
in `docs/plans/harness-hygiene-roadmap.md`; that piece DEPENDS on this plan's
policy being decided.

**This plan is design-only.** Its deliverable is THIS design + the rule structure
+ the ancestor-chain load contract + the reviewer/test acceptance + the roadmap
(R-tasks). The rule doc + any loader change are authored by the R-tasks / piece #3
in subsequent sessions.

## Scope

- IN: Design of `doctrine-scoping.md` — the typed doctrine-home table (global /
  project-local / cwd-memory, with room for more types), the per-type LOAD rule
  (which session mode loads which home — interactive / parallel-local /
  cloud-remote / scheduled / agent-team, per `automation-modes.md` + Decision
  011's project-`.claude/`-only cloud inheritance), and the ancestor-chain
  memory-load CONTRACT (the policy that fixes the cwd-mangle bug).
- IN: The conflict-resolution rule for the ancestor chain (nearest-cwd-wins;
  de-duplication by memory `name:` slug).
- IN: The acceptance reviewer-check / load-resolution test (a test that, given a
  synthetic ancestor chain with memories at two levels, confirms the resolved set
  is the de-duplicated union).
- IN: The 10-section Systems Engineering Analysis, the self-test design, and the
  ordered implementation roadmap (R-tasks).
- IN: ADR 044 (RESERVED this session; authored at R1) recording the typed-home
  policy + the ancestor-chain memory-load contract decision.
- IN: A §D research item — confirm the LOADER SURFACE the harness controls (is the
  auto-memory injection a SessionStart hook we own, or Claude Code native? this
  determines how piece #3 implements the contract).
- OUT: Implementing the loader mechanism (that is roadmap piece #3); editing the
  auto-memory injection; moving any existing memory files between dirs.
- OUT: The PRINCIPLES content + structure — that is the sibling plan
  `docs/plans/principles-doctrine-authoring.md` (this plan is WHERE doctrine
  lives; the sibling is WHAT the principles are).
- OUT: Re-designing `harness-maintenance.md`'s default-to-global rule — this plan
  REFERENCES it as the global-doctrine load policy; it does not rewrite it.
- OUT: The doctrine INDEX + admission control (roadmap piece #1) — that is a
  separate piece; this plan defines the home TAXONOMY the index will organize.

## Tasks

The tasks below ARE the implementation roadmap. THIS design session checks off
NONE. Ordered by dependency; each ships its slice with a reviewer-check /
`--self-test` (harness-internal → `Verification: mechanical`).

- [ ] R1. Author ADR 044 + the `doctrine-scoping.md` skeleton. Lock the typed-home table columns (home / path / scope / loaded-by-which-modes / canonical-source) and the ancestor-chain memory-load contract statement. Resolve §D1 (filename), §D2 (ancestor-chain root boundary), §D3 (loader-surface research) at authoring time. ADR 044 records the typed-home policy + the ancestor-chain contract. Verification: mechanical
- [ ] R2. Populate the typed-home table with the three known homes (global / project-local / cwd-memory) and their per-mode load rules, cross-referencing `harness-maintenance.md` (global), the project-`.claude/` + `docs/conventions/` convention (project-local, incl. Decision 011 cloud inheritance), and the auto-memory convention (cwd-memory). Verification: mechanical
- [ ] R3. Specify the ancestor-chain memory-load CONTRACT in full: the chain-walk (worktree → repo → ancestors → root boundary), the de-duplication rule (by memory `name:` slug), the conflict-resolution rule (nearest-cwd-wins), and the worktree special-case (a worktree mangle resolves to its parent repo's chain). This is the spec piece #3 implements. Verification: mechanical
- [ ] R4. Build the load-resolution reviewer-check / test: given a synthetic ancestor chain with memories at two levels (a parent with MEMORY.md, a child empty — the exact shape of the real bug), assert the resolved set is the de-duplicated union with nearest-wins; given a worktree mangle, assert it resolves to the parent repo's chain. This is the acceptance artifact generator + the regression lock for the bug. Verification: mechanical
- [ ] R5. Bootstrap + finalization. Register `doctrine-scoping.md` in `docs/harness-architecture.md`; add the rules-table reference; sync live mirror; confirm the rule cross-references the sibling principles plan + the hygiene-roadmap piece #3 (the implementer). Verification: mechanical

## Files to Modify/Create

(Future-session targets. THIS session writes only the documentation files
marked ✎.)

- `docs/plans/doctrine-scoping-rules-authoring.md` — ✎ this design plan (this session)
- `docs/decisions/044-doctrine-scoping-and-ancestor-chain-memory-load.md` — R1: ADR (number RESERVED this session; authored at R1)
- `docs/DECISIONS.md` — R1: index row for ADR 044
- `adapters/claude-code/rules/doctrine-scoping.md` — R1–R3: NEW canonical doctrine-scoping rule
- `adapters/claude-code/rules/<load-resolution-test>.sh` OR addition to an existing self-test harness — R4: load-resolution reviewer-check/test
- `docs/harness-architecture.md` — R1/R5: inventory entry per `harness-maintenance.md`
- `~/.claude/rules/doctrine-scoping.md` (+ mirrored test) — R1–R5: live-mirror sync per two-layer-config discipline

(NOTE: the LOADER MECHANISM that consumes the ancestor-chain contract is roadmap
piece #3, in its OWN future plan — not a file this plan's R-tasks edit.)

## Assumptions

- The cwd-mangle is keyed to the session's exact cwd, producing distinct mangles
  for repo-cwd, parent-cwd, and each worktree (PROVEN this session: the dir
  listing showed `…Pocket-Technician`, `…Pocket-Technician-neural-lace`, and
  `…neural-lace--claude-worktrees-<name>` as separate mangle dirs, with MEMORY.md
  present ONLY in the parent `…Pocket-Technician/memory`).
- The memory `name:` frontmatter slug is a stable de-duplication key (confirmed by
  the auto-memory memory-file format the harness defines).
- `harness-maintenance.md` is the authoritative global-doctrine load policy
  (default-to-global) — this rule references it, does not rewrite it (confirmed:
  the rule is present in this session's context).
- Decision 011 governs cloud/`--remote`/scheduled inheritance (project `.claude/`
  only, NOT `~/.claude/`) — the per-mode load table must reflect this (confirmed:
  `automation-modes.md` documents it).
- Whether the auto-memory injection is a harness-owned SessionStart hook or a
  Claude Code native behavior is NOT confirmed this session — §D3 researches the
  loader surface before piece #3 picks an implementation. The DESIGN (the
  contract) does not depend on the answer; the IMPLEMENTATION (piece #3) does.
- The ancestor-chain root boundary (how far up to walk) is NOT settled — §D2
  resolves it (recommended: stop at the first ancestor that is not under a known
  projects root, i.e. `~/.claude/projects/<…>` decomposition, capped at the
  user-home level).

## Edge Cases

- **The exact bug shape: parent has MEMORY.md, child empty** → ancestor-chain load
  resolves to the parent's memories (the union); R4's primary fixture.
- **Worktree mangle** → resolves to the PARENT REPO's chain (worktree →
  repo-cwd → parent → …), so worktree sessions see the same memories as a
  repo-cwd session. R4's second fixture.
- **Same memory `name:` slug at two levels** (a child overrides a parent memory) →
  nearest-cwd-wins; the child's version is loaded, the parent's is shadowed (not
  both). De-dup by slug.
- **A memory dir exists but has no MEMORY.md** (this session's exact case) → it
  contributes nothing; the chain walk continues upward to find a populated dir.
- **No memory dir anywhere in the chain** → load nothing; no error (a fresh
  project legitimately has no memories yet).
- **Chain walk runs away past the projects root** → §D2 root boundary caps it;
  never walk above the user-home / projects-root level.
- **cloud / `--remote` / scheduled session** → per Decision 011, only project
  `.claude/` is inherited; `~/.claude/projects/<mangle>/memory` is NOT on a cloud
  VM. The load table marks cwd-memory as LOCAL-modes-only; cloud modes load no
  cwd-memory by design (an honest boundary, not a bug). This is the same
  cloud-blind-spot class the conversation-tree work accepts.
- **A project-local convention conflicts with a global rule** → the existing
  `harness-maintenance.md` precedence applies (project-level overrides or extends
  global); this rule references that precedence, does not invent a new one.

## Acceptance Scenarios

(This plan is `acceptance-exempt: true` — harness-development. Closure target is
the load-resolution test / reviewer-check PASS recorded in `## Closure Contract`.
The scenarios below are maintainer-facing load-resolution checks, populated to
dogfood the Pattern-1 Closure Contract discipline — NOT browser scenarios.)

### ancestor-chain-resolves-parent-memories — the bug is fixed and regression-locked

**Slug:** `ancestor-chain-resolves-parent-memories`

**User flow:**
1. Maintainer runs the R4 load-resolution test with a synthetic chain: parent dir has MEMORY.md + 2 memories, child (repo-cwd) dir is empty.
2. The test invokes the ancestor-chain resolver against the child cwd.
3. It asserts the resolved memory set = the parent's 2 memories (the union).

**Success criteria (prose):** the resolver returns the parent's memories for a
child-cwd session — i.e. the exact bug observed this session no longer happens.
The test exits 0; a maintainer can trust a repo-cwd session sees its parent's
memories.

**Artifacts to capture:** test stdout (resolved-set listing, exit 0, "N passed,
0 failed"); the synthetic-chain fixture paths.

### worktree-resolves-repo-chain — worktree sessions see repo memories

**Slug:** `worktree-resolves-repo-chain`

**User flow:**
1. Maintainer runs the R4 test with a synthetic worktree mangle whose parent repo has memories.
2. The test invokes the resolver against the worktree cwd.
3. It asserts the resolved set includes the parent repo's (and its ancestors') memories.

**Success criteria (prose):** a worktree session resolves to its parent repo's
chain and sees the same memories as a repo-cwd session; no worktree blind spot.

**Artifacts to capture:** test stdout (resolved-set listing, exit 0); the
worktree-fixture paths.

## Closure Contract

- **Commands that run (at R-session close):** the R4 load-resolution test
  (`bash adapters/claude-code/rules/<load-resolution-test>.sh --self-test` or the
  chosen harness); the R5 bootstrap/index check.
- **Expected outputs:** the load-resolution test exits 0 with "N passed, 0
  failed", including the two bug-shaped fixtures (parent-memories-from-child;
  worktree-resolves-to-repo-chain) PASSing.
- **On-disk artifact location:** structured evidence at
  `docs/plans/doctrine-scoping-rules-authoring-evidence/<R-task-id>.evidence.json`
  (verdict PASS) per the Tranche B mechanical-evidence substrate.
- **Done when:** all of R1–R5 are task-verifier PASS AND the R4 load-resolution
  test exits 0 with both bug-shaped fixtures green AND `doctrine-scoping.md` is
  registered in `docs/harness-architecture.md`. (THIS plan, design-only, is "done
  for the design phase" when this plan + the roadmap land and systems-designer
  PASSes; it stays ACTIVE through implementation.)

## Testing Strategy

Per-component reviewer-check / `--self-test` is the verification idiom.

**R1 skeleton:** the typed-home table columns render; the ancestor-chain contract
statement is present; ADR 044 authored + indexed.

**R2 typed-home table:** all three homes present with path + scope +
loaded-by-which-modes + canonical-source; the cloud-modes-load-no-cwd-memory row
is explicit (Decision 011).

**R3 contract spec:** the chain-walk, de-dup rule, nearest-wins rule, and
worktree special-case are each stated precisely enough that piece #3 could
implement from the text alone.

**R4 load-resolution test (the regression lock):** parent-has-memories/child-empty
→ resolves to parent union (the bug fixture); worktree-mangle → resolves to repo
chain; same-slug-two-levels → nearest-wins (child shadows parent); empty-dir-in-
chain → contributes nothing, walk continues; no-memory-anywhere → empty set, no
error; chain-runaway → capped at root boundary.

**R5 bootstrap:** `doctrine-scoping.md` present + indexed in harness-architecture;
rules-table reference added; cross-references to the sibling principles plan +
hygiene piece #3 resolve.

## Walking Skeleton

The thinnest end-to-end slice that proves the architecture: author the
`doctrine-scoping.md` skeleton with the typed-home table (three rows) + the
ancestor-chain contract paragraph; build the R4 load-resolution test with the ONE
bug-shaped fixture (parent has MEMORY.md, child empty → resolver returns parent's
memories); run it → PASS. This single slice exercises the policy (the contract),
the test harness, and the exact bug this plan exists to fix — and is the R4
regression lock's core path. It is the most important proof because it
demonstrates the one thing the bug report alone cannot: that a child-cwd session
CAN be made to resolve its parent's memories.

## Decisions Log

### Decision: Ancestor-chain load (union, nearest-wins), NOT exact-cwd-only
- **Tier:** 2
- **Status:** proceeded with recommendation
- **Chosen:** The memory-load contract walks the cwd's ancestor chain and loads the de-duplicated union (nearest-cwd-wins on slug conflict), fixing both the repo-misses-parent bug and the worktree-misses-everything bug.
- **Alternatives:** (a) exact-cwd-only (the status quo — the bug); (b) parent-only fallback when child is empty (fixes the named bug but NOT the worktree case, and not multi-level chains). Rejected — (a) is the bug; (b) is a symptom treatment that misses the worktree dimension. Ancestor-chain is the curative, general fix.
- **Reasoning:** Preemptive-over-symptom-treating (the session constraint): the worktree dimension proves "parent-only" is a partial fix; the ancestor chain is the root-cause-correct policy.
- **To reverse:** Narrow to parent-only or exact-cwd; low cost (the contract is a spec), but reintroduces the worktree blind spot.

### Decision: Split doctrine-WHERE (this plan) from principles-WHAT (sibling plan)
- **Tier:** 1
- **Status:** proceeded with recommendation
- **Chosen:** This plan designs WHERE doctrine of each type lives + the load rules; the sibling `principles-doctrine-authoring.md` designs the principle set + structure.
- **Reasoning:** Two distinct concerns; bundling would mega-session. They cross-reference but ship independently.

### Decision: This plan DESIGNS the load contract; piece #3 IMPLEMENTS the loader
- **Tier:** 1
- **Status:** proceeded with recommendation
- **Chosen:** The ancestor-chain CONTRACT is specified here (R3); the loader MECHANISM is roadmap piece #3, gated on this plan's policy.
- **Reasoning:** Design/implementation split per the 5-pattern convention; keeps each session small (FM-030 discipline). §D3 researches the loader surface so piece #3 can implement.

## Definition of Done

- [ ] (design phase) This plan authored + passes plan-reviewer; the typed-home taxonomy + ancestor-chain contract are the explicit spine; ADR 044 number reserved.
- [ ] (design phase) systems-designer returns PASS on the 10-section analysis.
- [ ] (design phase) Misha reviews + authorizes the roadmap + resolves §D1 (filename) / §D2 (root boundary) / §D3 (loader-surface research result).
- [ ] (implementation) R1–R5 each task-verifier PASS with reviewer-check / `--self-test` green.
- [ ] (implementation) R4 load-resolution test exits 0 with both bug-shaped fixtures green.
- [ ] SCRATCHPAD updated.

## Systems Engineering Analysis

### 1. Outcome (measurable user outcome, not output)

Success, measured post-implementation (jointly with piece #3): (1) a repo-cwd
session resolves and loads its parent-cwd memories — the exact bug observed this
session (this session was pointed at an empty `…neural-lace/memory` while the
real memories sat in `…Pocket-Technician/memory`) goes to ZERO; (2) a worktree
session resolves to its parent repo's chain and sees the same memories as a
repo-cwd session — the worktree blind spot goes to ZERO; (3) the harness has ONE
written policy stating where each doctrine type lives and which session mode loads
it, so a maintainer (or fresh session) knows where to put a new convention and why
a cloud session doesn't see cwd-memory; (4) the load-resolution test regression-
locks the bug so a future loader change cannot silently reintroduce it. Honest
boundary: cloud/`--remote`/scheduled sessions still load no cwd-memory (Decision
011 — the VM doesn't have `~/.claude/projects/`); that is documented as a known
boundary, not silently fixed.

### 2. End-to-end trace with a concrete example

The real bug, traced. A session starts with cwd
`…/Pocket Technician/neural-lace`. Today: the auto-memory injection points at
`~/.claude/projects/C--Users-misha-dev-Pocket-Technician-neural-lace/memory/`,
which has no MEMORY.md → the session loads nothing, even though
`…Pocket-Technician/memory/MEMORY.md` exists one level up. Post-fix: the
ancestor-chain resolver decomposes the cwd into its ancestor chain
(`…neural-lace` → `…Pocket Technician` → … capped at the §D2 root), maps each to
its mangle, finds memory dirs at `…-neural-lace` (empty) and
`…-Pocket-Technician` (MEMORY.md + memories), unions them de-duplicated by `name:`
slug (nearest-cwd-wins on conflict), and the session loads the parent's memories.
For a worktree cwd
`…/neural-lace/.claude/worktrees/bold-albattani-0939ef`: the resolver recognizes
the worktree segment, resolves to the parent repo's chain, and loads the same set
a repo-cwd session would. The R4 test encodes both traces as fixtures so a future
loader edit that breaks either is caught.

### 3. Interface contracts between components

| Producer | Consumer | Contract |
|---|---|---|
| `doctrine-scoping.md` typed-home table | maintainer / fresh session | One table: home / path / scope / loaded-by-which-modes / canonical-source. Answers "where do I put this doctrine + who loads it". |
| ancestor-chain contract (R3) | piece #3 loader | A precise spec: walk cwd ancestors (incl. worktree→repo special-case) → map to mangles → union de-duplicated by `name:` slug → nearest-cwd-wins → cap at §D2 root. Piece #3 implements EXACTLY this. |
| memory `name:` slug | de-dup rule | The stable key; two memories with the same slug at different levels → nearest wins. |
| Decision 011 | per-mode load table | cloud/`--remote`/scheduled inherit project `.claude/` only → cwd-memory row marked LOCAL-modes-only. |
| R4 load-resolution test | closure | Given synthetic chains, asserts the resolved set; PASS is the acceptance artifact + the regression lock. |

### 4. Environment & execution context

The deliverables are one rule doc + one load-resolution test, under
`adapters/claude-code/rules/` (canonical) mirrored to `~/.claude/`. The test is a
bash `--self-test` building synthetic `~/.claude/projects/<mangle>/memory/`
fixtures in a temp dir, `jq` available (degraded fallback per convention). No
external services, no auth, no network. The LOADER (piece #3) runs at SessionStart
— §D3 confirms whether that is a harness hook we own or Claude Code native; the
contract spec here is loader-surface-agnostic. Two-layer config discipline applies.

### 5. Authentication & authorization map

No external auth boundaries. No new BLOCK authority (this is a load-policy rule +
a test, not a gate). The only authorization-adjacent surface is read access to
`~/.claude/projects/<mangle>/memory/` dirs, which the session already has. No
tokens, quotas, rate limits.

### 6. Observability plan (built before the feature)

- The load-resolution test (R4): `[doctrine-scoping-test] chain=<…> resolved
  <N> memories from <M> levels (<dedup K shadowed>)` → exit line per fixture.
- The eventual loader (piece #3, out of this plan's scope but the contract
  mandates it logs): `[memory-load] cwd=<…> chain=<…> loaded <N> memories from
  <M> dirs` so a session can self-report which memory dirs it actually loaded —
  the observability that would have made THIS session's bug visible immediately.
- Reconstruct-from-output: from the test output alone, a maintainer can confirm
  the resolved set for any synthetic chain matches the union+nearest-wins rule.

### 7. Failure-mode analysis per step

| Step | Failure mode | Observable symptom | Recovery / policy | Escalation |
|---|---|---|---|---|
| R1 skeleton | Typed-home table omits a real home | a doctrine type with no documented home | R2 enumerates all known homes; a new home type is an ADR-044 amendment | amend ADR 044 |
| R3 contract | Chain-walk under-specified → piece #3 guesses | piece #3 implements differently than intended | R3 spec is precise enough to implement from text; R4 fixtures pin the behavior | tighten R3 spec |
| R3 contract | Root boundary unbounded → walks to filesystem root | resolver reads dirs it shouldn't | §D2 caps at projects-root/user-home | block ship if runaway fixture red |
| R4 test | False PASS (resolver returns empty but test passes) | bug looks fixed but isn't | R4 includes the exact bug fixture (parent-memories-from-child) as a POSITIVE assertion, not just absence-of-error | block close if bug fixture not asserting the union |
| R4 test | Worktree case missed | worktree blind spot persists | R4 second fixture asserts worktree→repo-chain | block close if worktree fixture absent |
| per-mode table | cloud-memory expectation wrong | a cloud session expected to load cwd-memory | Decision 011 marks cwd-memory LOCAL-only; the boundary is documented, not a bug | n/a (honest boundary) |

### 8. Idempotency & restart semantics

- `doctrine-scoping.md` authoring + the table population are plain doc editing —
  idempotent, restart-safe.
- The R4 load-resolution test builds synthetic fixtures in a temp dir and tears
  them down; re-running rebuilds the same fixtures → same result. No persistent
  state mutation.
- The ancestor-chain RESOLVER (contract) is a pure function of (cwd, filesystem
  state) → resolved memory set; reading it twice yields the same set (idempotent).
  It never WRITES to memory dirs (read-only resolution).

### 9. Load / capacity model

No runtime load surface in this plan — a rule doc + a test run on demand. The
resolver (piece #3) the contract describes walks ≤ a handful of ancestor levels
and reads ≤ a few small memory dirs at SessionStart — sub-second, bounded by chain
depth (capped at §D2 root). No saturation concern. The capacity question is chain
DEPTH; the root boundary (§D2) bounds it — that cap is the deliberate capacity
bound.

### 10. Decision records & runbook

**Open decisions to resolve before / at the relevant R-session (= ADR 044
§D1–§D3):**

- **§D1 (R1): canonical filename.** `doctrine-scoping.md` vs alternative.
  *Recommendation:* `doctrine-scoping.md` under `adapters/claude-code/rules/`.
  **Needs Misha confirm** (naming convention).
- **§D2 (R1): ancestor-chain root boundary.** How far up to walk.
  *Recommendation:* stop at the first ancestor not decomposable under
  `~/.claude/projects/<…>`, capped at user-home; never above. **Needs Misha
  preference** (does he want cross-project-root memories ever shared? default: no).
- **§D3 (R1, research): loader surface.** Is the auto-memory injection a
  harness-owned SessionStart hook or Claude Code native? *Recommendation:*
  research before piece #3 picks an implementation; the contract is
  loader-surface-agnostic, so this does not block THIS design, only piece #3's
  build. **Needs research.**

**Runbook (post-implementation):**
- *Symptom: a session loaded no memories but the project has them.* Check the
  `[memory-load]` log for the resolved chain; if the populated dir is above the
  §D2 root boundary, the boundary is too tight — widen §D2. If the chain didn't
  include the parent, the resolver has a chain-walk bug — re-run R4.
- *Symptom: a worktree session sees no memories.* Confirm the worktree→repo
  special-case fired (the `[memory-load]` log shows the resolved repo chain); if
  not, the worktree-segment recognition is broken — R4's worktree fixture is the
  regression lock.
- *Symptom: a cloud session sees no cwd-memory.* Expected (Decision 011) — not a
  bug; cwd-memory is LOCAL-modes-only.

## Pre-Submission Audit

S1 (Entry-Point Surfacing): swept — every behavior change in §1–§10 is cited in a
`## Tasks` R-entry AND a `## Files to Modify/Create` line (R1↔skeleton+ADR,
R2↔typed-home table, R3↔ancestor-chain contract, R4↔load-resolution test,
R5↔bootstrap+index); the LOADER is explicitly OUT (piece #3) and is prescribed in
no Files-to-Modify line here; 0 stranded.
S2 (Existing-Code-Claim Verification): swept — the cwd-mangle structure (separate
mangles for repo / parent / worktree; MEMORY.md only in the parent
`…Pocket-Technician/memory`) was PROVEN by the directory listing this session;
claims about `harness-maintenance.md` (default-to-global) and Decision 011
(project-`.claude/`-only cloud inheritance) verified against this session's
context; all confirmed accurate.
S3 (Cross-Section Consistency): swept — "ancestor-chain union, nearest-wins"
consistent across Goal/Scope/§2/§3/Decisions Log/Edge Cases/R3/R4;
"design-the-contract-here, implement-in-piece-#3" consistent across
Goal/Scope-OUT/Decisions Log/§3/§D3; "cloud loads no cwd-memory (Decision 011)"
consistent across Edge Cases/§1/§6/per-mode-table/§7; 0 contradictions.
S4 (Numeric-Parameter Sweep): swept for params [3 doctrine homes, R1–R5 roadmap,
ADR 044, ancestor-chain levels (depth-bounded by §D2 root)]; all values consistent
across §2/§3/§9/Testing Strategy/Tasks; the root-boundary depth is flagged
build-calibrated (§D2).
S5 (Scope-vs-Analysis Check): swept — every "Author/Populate/Specify/Build/Wire"
verb in §1–§10 targets a file in `## Files to Modify/Create`; no prescription
targets a Scope-OUT concern (the LOADER is piece #3, prescribed nowhere here;
moving existing memory files is OUT, prescribed nowhere; the principles content is
the sibling plan, prescribed nowhere; no code shipped this session per Scope OUT).
