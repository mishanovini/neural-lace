# Harness-Hygiene Roadmap — Integrated View

Owner: Misha
Created: 2026-05-26
Status: ROADMAP (coordination index — NOT a build plan; the work lives in the
plans/shells this doc points at)

> This is an **index + sequencing** artifact, deliberately placed at the `docs/`
> top level (alongside `DECISIONS.md`, `backlog.md`, `failure-modes.md`,
> `agent-incentive-map.md`) rather than under `docs/plans/`, because it is a
> coordination map over many plans, not itself a `plan-reviewer`-gated build plan.
> The two doctrine plans it references ARE gated build plans (Mode:design) under
> `docs/plans/`; the nine implementation pieces are SHELLS here that each graduate
> to their own full `docs/plans/*.md` plan when authored in a dedicated session.

---

## Why this exists

The harness has grown to ~30 rule files + ~30 hooks + ~16 agents + CLAUDE.md +
Build Doctrine + the 5-pattern redesign initiative in flight. It has accumulated
real hygiene debt: doctrine that claims enforcement which isn't wired, citations
to files that don't exist, a memory-loading bug that blinds repo-cwd and worktree
sessions, no single index of where doctrine lives or what the principles are, and
no mechanism that DETECTS this kind of drift. This roadmap integrates the
**harness-hygiene + principles-doctrine** work into one sequenced view, coordinated
with the existing 5-pattern redesign initiative.

**Governing constraint (from the session brief): preemptive over symptom-treating
throughout.** No auto-defer-style symptom treatments. Owner-accountability +
mechanical detection. The cleanup pass (#8) does not paper over defects; the
obsolescence detector (#4) finds the class, and owners decide.

---

## Step 0 finding — existing cleanup work (investigated 2026-05-26)

**There is NO standalone, in-flight "harness cleanup" plan.** What exists:

- **The 5-pattern redesign initiative (in flight, design-only).** Five coordinated
  Mode:design plans, all `Status: ACTIVE` / design-complete / awaiting Misha's
  authorization before implementation:
  - **Pattern 1 — plan-lifecycle** (`docs/plans/plan-lifecycle-redesign.md`, ADR 036). Mechanical plan closure.
  - **Pattern 2 — acceptance-gate session-relevance + waiver cleanup.** NOT a standalone plan; it is **R7 (Part A) + R8 (Part B) inside Pattern 1's plan** — sequencing-only, referencing the existing waiver root-cause analysis (HARNESS-GAP-31).
  - **Pattern 3 — file-lifecycle** (`docs/plans/file-lifecycle-redesign.md`, ADRs 037+038). session-wrap loop / worktree-publish / track-tool / auto-extraction.
  - **Pattern 4 — session-resilience** (`docs/plans/session-resilience-redesign.md`, ADR 040). Survive/recover terminal death; includes a `topic-shift-surfacer.sh` + `handoff-heartbeat.sh` + reuses `session-wrap.sh`.
  - **Pattern 5 — dispatch-coordination** (`docs/plans/dispatch-coordination-redesign.md`, ADRs 039+041+042). Dispatch↔Code coordination.
- **Historical cleanup arcs (COMPLETED, archived).** Phase 1d-E ("harness cleanup") sub-plans (`phase-1d-e-1` drift-fixes, `e-2` audit-cleanup, `e-3`/`e-4` gap reconciliation), the architecture-simplification tranches A–G, and HARNESS-GAP-13/16/17. These shipped; they are not in flight.
- **Backlog harness-cleanup-flavored items (open):** HARNESS-GAP-13 (hygiene-scan expansion, named "next pickup"), HARNESS-GAP-10 sub-gaps, the "P1 — harness-work plans have no tracked home" item, and the multi-push/SSH P2.
- **Open PRs (snapshot 2026-05-26, volatile — a parallel-session swarm is opening PRs live):** PR #2 (ADR reconciliation), PR #3 (conv-tree scripts), PR #4 (file-lifecycle plan), PR #5 (file-lifecycle R1 SCRATCHPAD fix), PR #6 (session-resilience plan), PR #7 (THIS session's Hygiene track), PR #8 (dispatch-coordination plan), PR #10 (conv-tree auto-extraction). PR #9 (this session's duplicate session-resilience) was opened then CLOSED in favor of #6. See the Existing-plan closure-status table above.

**Conclusion: the harness-hygiene + principles work is NEW** (call it the
**"Hygiene track"**). It does NOT supersede any of the 5 patterns; it **coordinates
with** them (de-confliction in Coordination Notes below). It picks up the open
backlog hygiene items (HARNESS-GAP-13 and the tracked-home item are natural
absorptions when the relevant pieces are authored).

---

## Existing-plan closure status — resolved this session (2026-05-26, TOP PRIORITY)

Per Misha's re-prioritization (drive the dangling uncommitted work to closure
BEFORE new shells), the prior-session deliverables that were sitting in
untracked-limbo are now resolved as follows. **These are prerequisites at the TOP
of the dependency tree, not background context** — the Hygiene track builds on top
of them. The working checkout was being actively churned by parallel sessions
during this resolution (branch switched ≥3×; PRs #22/#23 merged live), so all
commits were made in **isolated worktrees off `origin/master`** to avoid collision.

| Prior-session deliverable | Status | Where |
|---|---|---|
| Conv-tree backfill scripts (`add-pending-items.js`, `backfill-from-sessions.js`) | **TRACKED — parallel session** (machine path sanitized + README) | commit `a4d79b2`, **PR #3** |
| Pattern 3 — file-lifecycle **R1** (SCRATCHPAD create-on-missing; kills the 435× Stop-hook loop) | **COMMITTED — parallel session** | commit `e7212e7`, **PR #5** |
| Pattern 3 — file-lifecycle full plan | **COMMITTED — parallel session** | **PR #4** (`[docs-only]`) |
| Pattern 4 — session-resilience plan | **COMMITTED — parallel session PR #6** (canonical). This session opened a DUPLICATE (PR #9) before discovering #6; **PR #9 CLOSED + branch deleted** in favor of #6. | **PR #6**; my dup #9 closed |
| Pattern 5 — dispatch-coordination plan | **COMMITTED — parallel session PR #8** (`[docs-only]`). ⚠ This session independently observed **7 `plan-reviewer` findings** on this plan (illegal `Verification: review` ×2; missing `## Walking Skeleton`; Check-1 sweep ×3; Check-13 integration sub-blocks). `[docs-only]` bypasses the volume gate, NOT `plan-reviewer` — **verify these findings were addressed when reviewing PR #8** (see §Decisions D6). | **PR #8** |
| Conv-tree auto-extraction hook (the "missing from doctrine" diagnosis) | **IN PROGRESS — parallel session** | **PR #10** (`feat/conv-tree-extract-pending`) |
| Conv-tree bootstrap-mechanism session (#10 in the brief) | **FAILED (socket disconnect mid-design); never produced output** — KNOWN GAP | empty worktree `conv-tree-bootstrap-mechanism`; re-attempt or note |
| This session's 3 Hygiene docs (UNIQUE — nobody else did these) | **COMMITTED + PR** | branch `design/harness-hygiene-roadmap`, **PR #7** |

**Net:** ALL three dangling Pattern plans are now committed by a swarm of parallel
sessions (file-lifecycle PR #4 + R1 PR #5; session-resilience PR #6;
dispatch-coordination PR #8), plus the scripts (PR #3) and auto-extraction (PR #10).
This session's UNIQUE contribution is the Hygiene track (PR #7). One collision
occurred: this session raced PR #6 and opened a duplicate (PR #9), since closed.
**Coordination friction surfaced:** ~6 parallel sessions committing overlapping
work on one shared checkout (branch switched ≥3× mid-session) is collision-prone;
worktree isolation prevented data loss but not the duplicate PR. The one residual
review caveat is the 7 plan-reviewer findings on PR #8's dispatch plan (D6).

---

## The two doctrine plans (authored this session — `plan-reviewer` PASS)

| Plan | Path | Mode | plan-reviewer | Designs |
|---|---|---|---|---|
| Principles doctrine | `docs/plans/principles-doctrine-authoring.md` | design | PASS (0 findings) | The canonical scope-hierarchical principles index + six-field schema; ADR 043 reserved |
| Doctrine-scoping rules | `docs/plans/doctrine-scoping-rules-authoring.md` | design | PASS (0 findings) | Where doctrine lives by type + the ancestor-chain memory-load contract that fixes the cwd-mangle bug; ADR 044 reserved |

Both are design-only (their `## Tasks` are implementation roadmaps for future
sessions). Both dogfood the Pattern-1 `## Closure Contract` section + populated
`## Acceptance Scenarios`.

---

## The nine implementation-piece shells

Each shell is a one-paragraph scope. Per-piece FULL plan authoring happens in a
dedicated session (graduating the shell to its own `docs/plans/*.md`). Owner +
target-date are placeholders for Misha to set. Dependencies reference other pieces
and the 2 doctrine plans / the 5 patterns.

### Piece #1 — Doctrine index + admission control
**Scope/intent:** A single registry of every doctrine artifact (rules, hooks,
agents, templates, principles, conventions) with its type, scope-home (per the
doctrine-scoping taxonomy), and load-binding — PLUS an *admission-control* gate:
a new rule/hook/agent cannot land without a registry row (mechanical, at commit
time), so the doctrine corpus stays enumerable and new doctrine declares where it
lives. Extends/complements `docs/harness-architecture.md` (which is a manual
inventory today). **Dependencies:** the doctrine-scoping plan (defines the home
taxonomy the registry organizes); loosely the principles plan (principles are one
registry type). **Owner:** _TBD_. **Target:** _TBD_.

### Piece #2 — Task-keyed surfacers (per surfacer type)
**Scope/intent:** Today's SessionStart surfacers (`discovery-surfacer.sh`,
`spawned-task-result-surfacer.sh`, and the pending-items extraction) each fire
independently and unconditionally. Make surfacing *task-keyed* — a surfacer fires
its content keyed to the kind of work the session is doing / the kind of item
pending — so a session sees the surfaced items relevant to it rather than an
undifferentiated dump, and so new surfacer types plug into one framework.
**Dependencies:** Piece #1 (the index enumerates surfacer types); **must
de-conflict with Pattern 4's `topic-shift-surfacer.sh`** (a NEW surfacer Pattern 4
owns — Piece #2's framework should accommodate it, not collide). **Owner:** _TBD_.
**Target:** _TBD_.

### Piece #3 — Memory-loading fix (ancestor-chain load)
**Scope/intent:** Implement the ancestor-chain memory-load CONTRACT designed in
`doctrine-scoping-rules-authoring.md` (R3): a session loads the de-duplicated union
of memory dirs along its cwd ancestor chain (worktree → repo → parent → …, capped
at a root boundary, nearest-cwd-wins on `name:` slug conflict), fixing the
PROVEN bug where repo-cwd sessions miss parent-cwd memories AND worktree sessions
miss both. Includes the `[memory-load]` observability log. **Dependencies:** the
doctrine-scoping plan's R3 contract + §D3 loader-surface research (is the
auto-memory injection a harness SessionStart hook we own, or Claude Code native?).
Otherwise **fully independent** of the other pieces. **Owner:** _TBD_.
**Target:** _TBD_. **← RECOMMENDED FIRST (see below).**

### Piece #4 — Retirement / obsolescence detector
**Scope/intent:** A mechanical detector for doctrine drift: (a) citations to files
that don't exist (e.g. the PROVEN `gate-respect.md → feedback_loud_is_not_rare.md`
phantom); (b) scripts present on disk but NOT wired in `settings.json` (e.g. the
PROVEN unwired `continuation-enforcer.sh`, `propagation-trigger-router.sh`); (c)
ADRs flagged superseded > 30 days still un-archived. Output is a report +
owner-routed findings — NOT auto-deletion (preemptive detection, owner decides;
no auto-defer symptom treatment). **Dependencies:** Piece #1 (the registry is the
"what should exist" baseline the detector diffs against). **Owner:** _TBD_.
**Target:** _TBD_.

### Piece #5 — Consolidation triggers
**Scope/intent:** Mechanical signals that a doctrine cluster has grown to the point
it should be reviewed/consolidated: N rules in a topic cluster → surface a
consolidation review; a rule file past a token-count threshold → flag for
stub-plus-extension split (the rules-vs-hooks audit pattern); duplicated guidance
across files → flag. Surfaces a review, does not auto-merge. **Dependencies:**
Piece #1 (the registry provides the cluster/size data). **Owner:** _TBD_.
**Target:** _TBD_.

### Piece #6 — Self-improvement feedback loop (re-derivation → surfacer update)
**Scope/intent:** When a session re-derives knowledge that a surfacer SHOULD have
surfaced (i.e. the session had to rediscover something already captured but not
shown to it), capture that gap and feed it back to improve the relevant surfacer's
keying/content. Operationalizes the Knowledge-Integration ritual (KIT triggers) for
the surfacer layer specifically. **Dependencies:** Piece #2 (the surfacer
framework it improves) + Piece #7 (observability provides the re-derivation
signal). **Owner:** _TBD_. **Target:** _TBD_.

### Piece #7 — Surfacer observability (logs + gap surfacing)
**Scope/intent:** Every surfacer (existing + Pattern 4's + Piece #2's) emits a
structured log of what it surfaced, what it suppressed, and why — so a maintainer
can see whether surfacing is working and whether a session missed something it
should have seen (the signal Piece #6 consumes). The memory-load log (Piece #3) is
one instance of this pattern. **Dependencies:** Piece #2 (the framework it
instruments); composes with Pattern 4's surfacer observability (§6 of the
session-resilience plan). **Owner:** _TBD_. **Target:** _TBD_.

### Piece #8 — One-time cleanup pass for existing defects
**Scope/intent:** Fix the concrete drift confirmed this session + whatever Piece #4
surfaces on first run: (a) the `gate-respect.md → feedback_loud_is_not_rare.md`
dangling citation (PROVEN — either write the memory or remove/repoint the
citation, Misha's call since it's HIS principle); (b) wire (or deliberately retire)
`continuation-enforcer.sh` + `propagation-trigger-router.sh`, which are PROVEN
built-but-unwired in BOTH live `settings.json` AND the template — note that
CLAUDE.md + `session-end-protocol.md` currently DESCRIBE `continuation-enforcer.sh`
as a live Stop hook, so this is doctrine advertising enforcement that does not
fire (a high-severity finding); (c) the cwd-mangle memory bug is fixed by Piece #3,
not re-fixed here. **Dependencies:** Piece #4 (the detector tells the cleanup what
to clean — preemptive, not guess); Piece #3 (owns the memory-bug fix); **and
file-lifecycle R1 (`e7212e7`, SCRATCHPAD create-on-missing) — the cheapest
already-salvaged first-ship from the 5-pattern set; #8 builds on top of it rather
than re-deriving SCRATCHPAD resilience.** **Owner:** _TBD_. **Target:** _TBD_.

### Piece #9 — Fresh-machine bootstrap test
**Scope/intent:** A validation gate that asserts, on a fresh `install.sh` run, that
the harness is internally consistent: every `settings.json`-referenced hook exists;
every doctrine citation resolves (no dangling references); the doctrine index
(#1) matches the on-disk corpus; the principles bootstrap (principles plan R7) and
the doctrine-scoping load-resolution test (doctrine-scoping plan R4) pass; the
memory-load contract (#3) resolves correctly. This is the integration gate for the
whole Hygiene track. **Dependencies:** MOST other pieces must exist (#1 index, #3
memory, #4 detector logic reused as assertions, the 2 doctrine plans' tests).
**Owner:** _TBD_. **Target:** _TBD_.

---

## Sequencing & dependency graph

```
Independent / leaf (can start now):
  #3 memory-loading fix      ──(needs only doctrine-scoping R3 contract + §D3 research)
  [doctrine-scoping plan]    ──(design done this session; its R-tasks gate #3)
  [principles plan]          ──(design done this session; independent of the 9 pieces)

Foundation (unblocks the framework pieces):
  #1 doctrine index + admission control
       ├─> #4 obsolescence detector   (diffs against the index baseline)
       │       └─> #8 one-time cleanup pass   (cleans what #4 finds)
       ├─> #5 consolidation triggers  (uses index cluster/size data)
       └─> #2 task-keyed surfacers    (index enumerates surfacer types)
                 ├─> #7 surfacer observability   (instruments the framework)
                 │       └─> #6 self-improvement loop   (consumes #7 signal, improves #2)
                 └─(de-conflict with Pattern 4 topic-shift-surfacer.sh)

Integration gate (last):
  #9 fresh-machine bootstrap test   (asserts the whole track is consistent)
```

**Truly independent (parallelizable now):** #3 (memory fix) is independent of the
foundation chain — it only needs the doctrine-scoping R3 contract (designed this
session) + the §D3 loader-surface research. The two doctrine plans are independent
of each other and of the 9 pieces.

**Critical path:** #1 → #4 → #8 (detect-then-clean) and #1 → #2 → #7 → #6
(surfacer framework → observability → feedback loop). #9 is the terminal gate
depending on most others.

**What blocks what (summary):**
- #4, #5, #2 all depend on **#1** (the index is the baseline).
- #8 depends on **#4** (clean what the detector finds) + **#3** (owns the memory fix).
- #7 depends on **#2**; #6 depends on **#2 + #7**.
- #3 depends on the **doctrine-scoping plan** (R3 contract + §D3), nothing else.
- #9 depends on **most** pieces existing.

---

## Coordination Notes (de-confliction with the 5-pattern initiative)

- **C-1 (branch ownership — ACTION for Misha/next session).** This session is
  sitting on branch `chore/adr-reconcile-5pattern`, which is **PR #2's branch
  (a different session's deliverable)**. The 3 docs authored this session
  (`harness-hygiene-roadmap.md` + the 2 doctrine plans) should NOT be committed
  onto that foreign branch — they belong on their own branch (recommend
  `design/harness-hygiene-roadmap`). See Action Items.
- **C-2 (surfacers — Pattern 4 ↔ Pieces #2/#7).** Pattern 4's
  `session-resilience-redesign.md` introduces a NEW `topic-shift-surfacer.sh`
  (R5) and has its own surfacer observability (§6). Piece #2 (task-keyed surfacer
  framework) and Piece #7 (surfacer observability) must be designed to
  **accommodate** Pattern 4's surfacer, not collide with it. Recommended: Pieces
  #2/#7 land AFTER Pattern 4 R5, OR Pattern 4 R5 declares the surfacer-framework
  interface Piece #2 then generalizes. Flag at Piece-#2 authoring time.
- **C-3 (`session-wrap.sh` shared surface).** Patterns 1, 3, and 4 all touch
  `session-wrap.sh`; Piece #3 (memory-load) is adjacent (SessionStart). The
  memory-load fix should NOT duplicate session-wrap machinery — it reads memory
  dirs, it does not write handoffs. Confirm at Piece-#3 authoring that the
  loader surface (§D3) is distinct from session-wrap's refresh path.
- **C-4 (cloud blind spot — shared accepted boundary).** The doctrine-scoping
  cwd-memory load is LOCAL-modes-only (Decision 011 — cloud/`--remote`/scheduled
  inherit project `.claude/` only). This is the SAME accepted boundary the
  conversation-tree work and Pattern 4 accept; document it consistently, do not
  silently "fix" it.
- **C-5 (backlog absorption).** When Piece #4/#8 are authored, they naturally
  absorb HARNESS-GAP-13 (hygiene-scan expansion) and the "harness-work plans have
  no tracked home" P1; when authored, delete those from the backlog open sections
  per the backlog-absorption rule.

---

## ADR number reservations

- **043** — RESERVED for the principles-doctrine scope-hierarchy + six-field
  schema decision (authored at principles plan R1).
- **044** — RESERVED for the doctrine-scoping typed-home policy + ancestor-chain
  memory-load contract (authored at doctrine-scoping plan R1).
- **Next free ADR: 045.** (Allocated through 044 by these reservations; 036–042
  belong to the 5-pattern initiative; 043/044 reserved here.) Pieces #1, #4, and
  #9 will likely each warrant an ADR — allocate 045+ at their authoring sessions.
- NO `docs/DECISIONS.md` rows are added this session (043/044 are reserved, not
  yet authored). Recording the reservation here prevents collision.

---

## Recommended first plan to fully author + implement

**Piece #3 — the memory-loading fix.** Rationale:
- **Independent.** It only needs the doctrine-scoping R3 contract (designed this
  session) + the §D3 loader-surface research; it does not wait on the #1 index.
- **Small + bounded.** A chain-walk resolver + a load-resolution test with two
  bug-shaped fixtures. One focused session.
- **Immediate, PROVEN value.** The bug is confirmed and currently active — this
  very session was pointed at an EMPTY `…neural-lace/memory` while the real
  memories sit in `…Pocket-Technician/memory`. Every repo-cwd and worktree session
  is silently memory-blind today. Fixing it improves every subsequent session.
- **Regression-locked.** The doctrine-scoping plan's R4 test makes the fix durable.

Suggested order after #3: the **doctrine-scoping plan's R1–R5** (to land the
contract + rule #3 implements against), then **#1 (index)** to unblock the
foundation chain (#4/#5/#2), then **#4 → #8** (detect-then-clean), then the
surfacer chain (#2 → #7 → #6), with **#9** last. The **principles plan** can run
in parallel anytime (independent of the 9 pieces).

---

## Questions / Decisions / Action items for Misha

See the session summary message for the full list; recorded here for the next
session's continuity:

- **DECISION D1 — 9 shells embedded vs 9 stub files.** This roadmap keeps the nine
  pieces as SHELLS inside this doc (each graduates to its own plan when authored),
  rather than creating nine near-empty `docs/plans/*.md` stubs now. Rationale: nine
  stub `Status: ACTIVE` plans would storm the acceptance/pre-stop gates and clutter
  `docs/plans/`. _Confirm, or ask for separate stub files._
- **DECISION D2 — ADRs at-implementation vs now.** ADRs 043/044 are RESERVED but
  authored at their plans' R1 (not this session) to avoid mega-session. _Confirm._
- **DECISION D3 — doctrine filenames.** `principles.md` + `doctrine-scoping.md`
  under `adapters/claude-code/rules/` (per the naming-consult rule). _Confirm names._
- **DECISION D4 — `feedback_loud_is_not_rare.md` phantom.** `gate-respect.md:109`
  cites a memory that doesn't exist. Per the converged doctrine summary, **"loud is
  not rare" is NOT a principle — a one-off feedback, do not elevate** — so the
  recommended fix is to **remove/repoint the citation** (inline the one sentence of
  intent, drop the dangling memory reference), NOT to author the memory. (Piece #8
  executes; _confirm the remove-don't-write direction_.)
- **DECISION D5 — `continuation-enforcer.sh` + `propagation-trigger-router.sh`.**
  Both built-but-unwired in live settings AND template, yet CLAUDE.md +
  `session-end-protocol.md` describe `continuation-enforcer.sh` as live. Wire them
  (make doctrine true), or deliberately retire them (make doctrine match reality)?
  (Piece #8 executes; this is a real correctness decision, not cosmetic. Note: the
  unwired state is why this session's missing DONE/PAUSING/BLOCKED markers would not
  actually have been gated.)
- **DECISION D6 — dispatch-coordination (Pattern 5) plan-reviewer findings.**
  The plan was committed by a parallel session as **PR #8** (`[docs-only]`), so it
  is no longer in limbo. BUT this session independently ran `plan-reviewer` on it
  and found **7 findings**: illegal `Verification: review` level ×2 (must be
  mechanical/full/contract); missing `## Walking Skeleton`; Check-1 sweep language
  ×3; Check-13 integration sub-blocks. `[docs-only]` is the vaporware-VOLUME-gate
  escape hatch — it does NOT bypass `plan-reviewer`, so either the parallel session
  fixed these, or committed with `--no-verify`. **Action:** at review of PR #8,
  re-run `plan-reviewer.sh docs/plans/dispatch-coordination-redesign.md` and confirm
  0 findings before merge; if findings remain, the owning Pattern-5 session (or a
  follow-up) should fix them. I did not touch PR #8's content (won't rewrite another
  session's design intent).
- **ACTION A1 — branch (DONE).** The 3 Hygiene docs are committed + pushed on
  `design/harness-hygiene-roadmap` → **PR #7** (off `origin/master`, isolated
  worktree, not the foreign branch). Session-resilience → **PR #9**.
- **QUESTION Q1 — Hygiene track authorization.** Authorize the track + the
  recommended sequencing (start with #3)?
