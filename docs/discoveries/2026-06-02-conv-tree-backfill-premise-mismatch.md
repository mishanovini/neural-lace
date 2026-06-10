---
title: Conv-tree backfill brief rests on refuted premise + schema mismatch
date: 2026-06-02
type: architectural-learning
status: implemented
auto_applied: false
originating_context: A Dispatch-orchestrator session relayed a 4-part brief to (Part 1) read the conv-tree interface, (Part 2) backfill ~40 "decision/work/completion/failure" nodes from today's Dispatch conversation, (Part 3) wire orchestrator-prime's SKILL to emit to the tree, (Part 4) add tree-emission to a dispatch-relay-protocol.md "being created by the orchestrator-prime session." Standing direction "do not pause, do not ask." Diagnostic-first investigation before writing anything to the canonical truth log.
decision_needed: How should "make today's work visible" be satisfied, given the backfill brief as specified is unbuildable on three independent grounds? (A) drop the manual backfill, rely on the auto-emit hooks already populating the tree; (B) greenlight dispatch-coordination-redesign.md (pending since 2026-05-25); (C) salvage the sound core via a new Mode:design plan. A+B is the recommendation.
predicted_downstream:
  - docs/discoveries/2026-06-02-orchestrator-prime-relay-premise-refuted.md
  - docs/plans/dispatch-coordination-redesign.md
  - neural-lace/conversation-tree-ui/state/tree-state.json (one truthful test event emitted; decision surfaced)
---

## What was discovered

A Dispatch-orchestrator brief asked this harness-native Code session to backfill the
conversation tree with ~40 hand-authored nodes and to wire two forward-going emit paths.
Diagnostic-first reading of the actual interface (`neural-lace/conversation-tree-ui/state/state.js`,
`schema.js`, the live `tree-state.json`, ADR-032 §8, ADR-034, and the conv-tree rules)
found the brief unbuildable **as specified** on three independent grounds, and its core
premise partly false.

### Finding 1 — the tree is NOT un-emitted; the premise is partly false (PROVEN)

The brief states "the orchestrator has NOT been emitting tree events during today's
conversation." The live `tree-state.json` (served at 127.0.0.1:7733) contains **252
snapshot nodes**, with the newest at `2026-06-02T05:38:31Z` — minutes before this session.
Branch nodes are auto-created throughout today by the Layer A spawn-emit + SessionStart
self-registration + heartbeat hooks (`conversation-tree-emit.sh`), labeled by project root
("neural-lace", "misha", and a downstream-product-repo label). The mechanism IS emitting. What is absent is
free-form decision/completion/failure *narration* — and that absence is **by design**
(Finding 3).

### Finding 2 — Part 2's event vocabulary, actor, and attestation model are schema-invalid (PROVEN)

- **Actor enum is closed.** `schema.js` `validateEvent` throws unless `actor ∈ {dispatch, gui}`
  (ACTORS at schema.js:143; check at :178). The brief's instruction to attest with a
  `"backfill session"` actor identity would be **rejected at validation**.
- **Event types are a closed set.** Valid types are `branch-opened`, `decision-raised`,
  `question-raised`, `action-added`, `concluded`, `annotated`, … The brief's
  "decision-node / work-node / completion-node / failure-acknowledgment event" vocabulary
  **does not exist**. (`decision-raised` is specifically a decision *awaiting the operator*
  per `rules/decision-context.md` — not a log of a decision already made.)
- **There is no per-event attestation block.** ADR-032 §8 r2.1's attestation
  (`attestSnapshot` / `verifySnapshotAttested`) is a **snapshot-integrity hash auto-computed
  during atomic publish** (the `snapshot-committed` marker, actor `system`), not a
  caller-authored provenance block. The brief's "provide the proper attestation block per
  event" misreads the primitive.

### Finding 3 — the tree is a Dispatch conversation-branch tracker, not a product-event log (PROVEN)

ADR-034 / `rules/conversation-tree-state.md` scope the tree to **Dispatch conversation
branches** (the conversations Misha has with AI via Dispatch). Sub-agent and product-workflow
events are explicitly **OUT** ("would only pollute the operator's view with workflow noise").
The brief's backfill list is overwhelmingly product-shipping events (feature shipments,
schema migrations, a page redesign) — most of them in a **downstream product repo**, not
neural-lace. Those already live in their proper homes: git history,
completion reports, `docs/backlog.md`, and the refutation discovery. Duplicating them into the
conversation tree as 40+ free-form nodes would pollute the exact surface ADR-034 protects, and
would assert unverified cross-repo claims into what the brief itself calls "the harness's
structured truth" — the opposite of `rules/conversation-tree-state.md`'s "write the
*semantically true* tree" and `rules/claims.md`.

### Finding 4 — Parts 3 and 4 depend on artifacts refuted/never-created today (PROVEN)

- Part 3 ("orchestrator-prime's SKILL must emit to the tree") depends on orchestrator-prime,
  which was **diagnostic-refuted today** (commit `67b0007`;
  `docs/discoveries/2026-06-02-orchestrator-prime-relay-premise-refuted.md`). No SKILL exists.
- Part 4 ("add tree-emission to the dispatch-relay-protocol.md being created by the
  orchestrator-prime session") depends on a file that session **did not create** — because the
  relay it would document is the refuted mechanism (RC1, `2026-05-25-dispatch-coordination-debug.md`).

This is the **same sandbox-blindness recursion** Finding 3 of the orchestrator-prime
refutation named: the Dispatch orchestrator can't see `~/.claude/` or the repo, so it
re-specifies refuted/nonexistent things. A harness-native session (this one) can see them —
which is itself evidence FOR the sound half of the orchestrator-prime motivation.

## Why it matters

Executing the brief literally would either (a) fail validation, or (b) be force-written past
validation to pollute the canonical truth log with unverified, out-of-scope, cross-repo
claims — a vaporware-into-the-truth-log failure that erodes the operator's trust in the one
surface (the "waiting on you" tree) that exists to be trustworthy. The "do not pause" directive
does not authorize shipping a non-fix, exactly as it did not for orchestrator-prime.

## What was actually done (sound, reversible slice)

1. Read the real interface (Part 1) — which is what surfaced Findings 2-4.
2. Ran the one well-formed acceptance test: emitted **one truthful, schema-valid, in-scope**
   `branch-opened` (`n-backfill-conv-tree-2026-06-02`, actor `dispatch`) via the `appendEvent`
   facade, plus a `decision-raised` that surfaces the real pending decision (below) into the
   "waiting on Misha" pane. Verified both render in the served snapshot (server fresh, age 24s).
3. Acknowledged the two unread spawned-task results.
4. Captured this discovery + surfaced to Misha. Did NOT write the 40+ fabricated nodes.

## Options

- **A — Drop the manual backfill; rely on the auto-emit hooks.** The tree already captures
  Dispatch conversation branches automatically; that is the tree's job per ADR-034. Cost: the
  free-form decision/completion narration the brief wanted is not in the tree — but it lives
  (correctly) in git history / completion reports / backlog / discoveries. Cheapest, honest.
- **B — Greenlight `dispatch-coordination-redesign.md`** (Mode:design, tier 3, ADRs 039/041/042,
  pending Misha since 2026-05-25). Solves the operator-visibility outcome honestly (list_sessions
  reconciler + ntfy human-wake + bounded poll + filed upstream issue). Independently valuable.
- **C — Salvage the sound core via a new Mode:design plan** (stateless harness-native orchestrator
  re-hydrated per Dispatch turn — no parent-wake dependency). Delivers "orchestrator should be
  harness-native" without the refuted relay. Cost: new plan + systems-designer PASS.
- **D — Defer.** Capture only; wait.

## Recommendation

**A + B.** A is the correct disposition of the backfill itself (the tree is already doing its
job; manual narration backfill is out-of-scope and partly schema-invalid). B is the cheapest
honest win for the operator-visibility pain the brief is really reaching for, and it is already
authored and waiting on Misha. C remains the right answer for the deeper "harness-native
orchestrator" ambition but is a separate, larger decision (it is options B/C of the
`2026-06-02-orchestrator-prime-relay-premise-refuted.md` discovery, still pending).

This is a Tier-3-class disposition (touches load-bearing harness orchestration topology + the
canonical truth log). Per `rules/discovery-protocol.md` and `rules/planning.md` Tier-3, it is
surfaced to Misha and **NOT auto-applied**.

## Decision

**A (rely on auto-emit) + orchestrator-prime owns forward emission.** Confirmed 2026-06-02: the
local conv-tree auto-emits Dispatch conversation branches (40 nodes in this checkout, 252 in the
served dev checkout; newest minutes old) via the SessionStart/spawn/heartbeat hooks — the tree
already reflects today's Dispatch work. The 40-node manual narration backfill stays REJECTED
(schema-invalid: closed actor `{dispatch,gui}` + closed event-type set + ADR-034 scopes product
events OUT; raw-writing would also break the ADR-032 §8 attestation). Going forward,
orchestrator-prime's per-cycle body emits schema-valid in-scope events (`branch-opened`,
`decision-raised` for *pending* decisions, `concluded`) through the `appendEvent` facade — that is
how "the conv-tree reflects today's work" is satisfied honestly. Misha's "let orchestrator-prime
figure out what fits the schema" is exactly this disposition.

## Implementation log

(Reconciled 2026-06-10, pending-discoveries triage — the paragraph that previously lived
here pre-dated the Decision section above and contradicted it; Misha DID decide on
2026-06-02: "A (rely on auto-emit) + orchestrator-prime owns forward emission.")

The decided disposition is implemented:

- **A — no manual backfill:** the 40-node narration backfill was never written (correct);
  the tree/Workstreams state continues to be populated by the auto-emit hooks, since
  consolidated onto the single canonical state file (`0291279`, Workstreams
  consolidation).
- **Forward emission owned by orchestrator-prime:** the live
  `adapters/claude-code/skills/orchestrator-prime.md` mandates exactly this — its cycle
  body emits schema-valid, in-scope events through the `appendEvent` facade
  ("Emit tree events for spawn / completion / decision / agent-invocation /
  audit-surface / merge — schema-valid only (closed actor enum {dispatch,gui}, closed
  event-type set per ADR-032/034; a *pending* decision = `decision-raised`)") and its
  Never-list forbids fabricated/out-of-scope/cross-repo nodes — the precise honesty
  contract Findings 2–3 established. ADR 050 records the architecture.
- Status flipped pending → implemented in the 2026-06-10 triage; investigation
  side-effects from 2026-06-02 remain as recorded under "What was actually done."
