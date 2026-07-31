# Cockpit-v2 push-materialized store — architecture review of v3

Reviewer: `architecture-reviewer` (Fable). Target: `docs/plans/cockpit-v2-push-materialized-store.md`
(DRAFT v3), reviewed against origin/master `5ebb520`. Predecessor: `docs/reviews/2026-07-14-cockpit-v2-architecture-review.md`.
Consumer: `docs/reviews/2026-07-17-circuit-continuous-building-design-sketch.md`.

```
VERDICT: NEEDS-RESHAPING (→ split local-read from cross-machine-export: local GUI keeps the
parse+cache; the "store" becomes a per-machine, timer+hash-gated EXPORT of the server's already-
derived payload — including the in_flight join RESULT — published into the EXISTING private
coordination repo via coord-push.sh/coord-pull.sh, rendered peer-side with age-based honesty
states. Delete the hook-push projector, the local store consumption, and the projector drift
machinery. Keep: ONE grammar (as spec+fixtures), the MultiEdit matcher fix, the m1 carve-out,
C3b wiring, the retirement condition.)

THE ONE THING: v3 syncs the wrong half of the state. Its own preamble concedes "plan files
already sync via git; what does NOT sync is the ask/event/session state" — then C1 (correctly,
for the LOCAL surface) strips the event-derived in_flight from the projection, and nothing else
syncs events/sessions. The store therefore ships a cross-machine artifact that omits the peer's
in-flight work — the one signal the justifying consumer (Circuit's Team tab "working on now")
actually needs — while carrying plan-file state that mostly syncs via git anyway. v3 copied its
reviewer's correction without noticing the correction's context (a local reader who CAN do the
event join) does not exist on the remote machine.
```

## Load-bearing premises tested
- P1 cross-machine current requirement — TRUE (operator-asserted).
- P2 "this store delivers cross-machine visibility of the peer's work" — **HALF-FALSE**: task-2
  schema syncs plan-FILE state only; peer in-flight/session state excluded by C1 and synced by
  nothing. Circuit's P0 row promises "peer machine's plan/**session** state appears" — the store
  as specced cannot deliver it.
- P3 broadcast-active-session pattern can carry it — **FALSE**: SessionStart-only write (Stop runs
  `claim` only), 300s throttle, read only at SessionStart, 2h window; its own header says
  "informational, never the load-bearing primary path." No cockpit fetch loop exists or is specified.
- P4 hash staleness model — TRUE locally; **FALSE for the remote reader** (peer clone at a different
  commit ⇒ perpetually "stale" or falsely "fresh"; the remote needs an AGE contract, never stated).
- P5 hook-push needed for freshness — **FALSE**: transport costs ≥600s throttle + pull cadence
  (~10min worst per Circuit's own contract); a 30–60s timer export is invisible in that budget, and
  hook-push is the SOLE reason the drift/heal/classifier machinery (tasks 4–6) must exist.
- P6 local GUI must read the store — **FALSE**: the local machine has the files; task 4 itself
  admits "bake+detect" (~120s stale after every cherry-pick), replacing a surface exact at every
  request today.
- P7 ONE parser "used by every consumer" — **FALSE as written** across the Node/bash boundary
  without a hot-path spawn. (The underlying bug GREW: **208** lettered-id task lines now invisible
  to the server's numeric-only grammar, vs 176 at the prior review.)
- P8 plan-lifecycle MultiEdit matcher hole — TRUE, still open (settings.json.template:407-414).
- P9 retirement stays two-way — TRUE today, **decays** once Circuit P2 consumes the store (unstated).

## Findings (ranked)
- **F1 CRITICAL (PROVEN)** — the synced artifact excludes peer in-flight/session state; the remote
  reader has no event log to join. Peer cockpit shows "3/9 done, zero in-flight" while three
  builders run. FIX: the per-machine export carries the RESULT of the peer's own read-time join
  (done, in_flight, per-task ids) computed at export time, stamped `exported_at`; in_flight stays a
  read-time join LOCALLY and an export-time snapshot for PEERS.
- **F2 CRITICAL (PROVEN)** — no staleness contract for the justifying consumer (no export cadence,
  publish throttle, fetch cadence, or between-states); local-hash `fresh/stale` does not transfer.
  FIX: own the numbers; named peer render states ("as of <ts>", "last seen Xm ago", "peer
  unreachable since <ts>"; absence is a named state); prefer receive-time over peer wall clock;
  acceptance replaces "current" with a bound.
- **F3 CRITICAL (PROVEN)** — task 3 templates on the gh-Contents-API broadcast pattern whose silent
  per-account auth failure (WARN + exit 0) is the documented class the purpose-built
  `coord-push.sh`/`coord-pull.sh` channel (private repo, git+SSH, per-hostname single-writer files,
  never-force-push) was created to replace — and Circuit already binds to coord. FIX: ride coord.
  Honestly: coord is currently invoked by NOTHING in the adapter — wiring its cadence is a real task
  this plan must own.
- **F4 MAJOR (PROVEN)** — single-writer holes: hook instances in any of 62 worktrees can project
  older plan copies over current projections; no projection KEY stated; no same-slug-two-machines
  merge rule; schema lacks hostname/branch/head_sha/dirty ⇒ a peer's unmerged state can render as
  plain done (§1 violation). FIX: ONE publisher per machine; key = (machine, repo, slug); schema
  gains provenance fields; local truth drives the local card, peer copies render as labeled rows.
- **F5 MAJOR (PROVEN)** — the LOCAL surface still routed through the store regresses
  correct-by-construction to bake+detect and adds unknown/damaged states to a surface that cannot
  currently be stale at all. FIX: local reads stay parse(+cache); the store is EXPORT-ONLY.
- **F6 MAJOR (PROVEN)** — hook-push buys ≤60s the minutes-scale transport erases, and is the sole
  reason drift machinery exists; a timer export that re-derives from disk CANNOT drift — only age.
  FIX: delete push triggers; export on coord's cadence gated by the 1.4ms hash check. Keep the
  MultiEdit matcher fix as an independent item.
- **F7 MAJOR (PROVEN)** — "one parser for every consumer" impossible across Node/bash without a
  hot-path spawn; ambiguity risks a FOURTH grammar. FIX: Node module canonical; bash consumers
  shell the Node CLI off the hot path OR conform via a SHARED fixture corpus both implementations
  pass in --self-test. Resolver (Node-only) genuinely unifiable.
- **F8 MAJOR-by-irreversibility (HYPOTHESIZED)** — the plan never names WHERE the ref lives;
  projections carry product task descriptions; a public mirror exists. FIX: bind to the private
  coordination repo in the plan text.
- **F9 MINOR (PROVEN)** — retirement condition decays into a one-way door once Circuit P2 consumes
  the store; true dependency edge is store → Team-tab/derived-queue (P2/P3), NOT store → Circuit P1.
  FIX: add the decay clause; don't block Circuit P1 on the store.
- **F10 no-impact** — the new merge-scan cursor helps (cheaper steady-state auditor); no v3
  assumption breaks.

Carried-correction audit: C1(local)/C2/C3/C3b/M1/M4/M5/m1/m2 all verified genuinely incorporated.
v3's failures are NEW and live almost entirely in task 3 — the task the predecessor could not
review because it did not exist.

## Pre-mortem (condensed)
gh auth rotates → one machine's projections freeze silently → peer renders a weeks-old snapshot
indistinguishably from live. A stale worktree's hook projects old plan content over current; the
auditor "heals" it back and forth every 120s. Circuit P2 needs "working on now" — the store lacks
it — a second sync channel grows beside the first: two transports, two staleness vocabularies, one
screen. Retirement is discovered to cost a Circuit rewrite.

## Steelman (the operator's question answered)
"Keep the read-time parse + cache, and git-ref-sync an EXPORT of the cache" — **yes; that IS the
store, correctly shaped.** The exported per-machine JSON in the coord repo is exactly the on-disk
artifact a non-Node/cross-machine consumer reads (the justifying condition), while keeping every
property the predecessor proved: local absence-is-null, zero local drift classes, no fork on any
request path — and zero drift classes on the export too (re-derived at export time ⇒ can only age,
honestly labeled). v3's one genuine point — hooks keep firing when the server is down — is answered
structurally: the exporter is a small Node CLI (using the ONE parser) on coord's throttled cadence,
server-independent, one spawn per ≥600s.

## What v3 gets right (must survive into v4)
Every predecessor correction absorbed; the retirement condition (+decay clause); per-machine
publication + provenance instinct; "NEVER the working tree" for sync; Task 1's grammar unification
(208 invisible lettered-id lines — highest value regardless of shape); the MultiEdit matcher fix;
the honest bake+detect admission.

## What would change the verdict
To SOUND: local read path off the store + single-exporter/provenance schema + coord (git+SSH)
transport + a written cadence/age contract + peer in-flight/session state in the export. "At that
point the plan and my Phase-0 candidate are the same design."
