# Cockpit-v2 — adversarial ARCHITECTURE review (verdict: NEEDS-RESHAPING)

Reviewer: `architecture-reviewer` (first run of the new agent). 4 critical · 5 major · 2 minor.
Target: `docs/plans/cockpit-v2-push-materialized-store.md` (v2, itself a reshape after a 5-lens panel
failed v1 5/5 — `docs/reviews/2026-07-14-cockpit-v2-plan-review.md`).

## THE ONE THING
**The plan never measured the cost of the thing it exists to remove.** Measured on this machine:

| Operation | Cost |
|---|---|
| Node reads+parses the **2 plans the read path actually touches** | **0.57 ms** |
| Node reads+parses **all 21 active plans** | **3.47 ms** |
| Node reads+parses **all 237 plans** (incl. 216 archived, 4.3 MB) | 26.2 ms |
| Node `stat`s all 237 plans | 2.53 ms |
| Node SHA-256s all 21 active plans | **1.41 ms** (cheaper than parsing them) |
| **ONE bash spawn** (the projector's per-invocation floor) | **~87 ms** |

**A single invocation of the proposed projector costs 25× more than re-parsing every active plan.** The
"expensive read-time re-derivation" costs **3.5 ms**. v2 spends a subprocess, an on-disk store, two
triggers, a cross-language timestamp protocol, a four-state honesty model, a cause classifier, an
auto-issue loop, an escalation policy, a backfill and a pruner — to buy 3.5 ms — and pays with a **new
drift class that did not previously exist**.

## Critical findings

**C1 — "Drift becomes impossible to hide" is FALSE; the stamp covers one of two inputs.** `in_flight`
does not come from the plan markdown — `computePlanRows` (`server.js:833-866`) derives it from the
per-ask event JSONL. The projection has TWO sources of truth; the staleness stamp (plan-file
mtime/size) covers ONE. Divergence in the event-derived half is **structurally invisible**. Failure: a
`task_started` fires, the trigger silently fails (subshelled, `|| true`, non-fatal by design), the plan
file never changes → stat says `fresh` → **the operator sees zero in-flight while three builders run,
and the cockpit stamps that lie `fresh`.** Also PROVEN: task 1's interface is `plan-project.sh
<plan-file>` — it has no ask-id, so it **cannot read the event log**; it is mathematically incapable of
producing the field its own schema mandates. **Fix: `in_flight` leaves the projection and stays a
read-time join over the event log (cost ≈ 0). That also deletes trigger (b) and with it the same-plan
write race (M2).**

**C2 — The reader becomes a writer, and a bash fork lands on the HTTP request path.** Task 3 says a
stale read re-projects "on the spot"; task 5 forbids Node from parsing a plan; therefore Node must
**spawn the bash projector inside the request handler** — making the GUI a SECOND writer (which the
plan forbids for the auditor) and re-incarnating the defect class `derive-cache.js:77-87` documents:
bash must be absolute-path + login shell (the 2026-07-09 "cockpit lobotomy"), `spawnSync` blocks the
event loop, and concurrent spawns trip `NL_SPAWN_CEILING` returning **a lying rc=0 with empty stdout**.
Failure: operator opens the cockpit after a `git pull`, 8 plans stale → 8 forks → breaker trips →
projector "succeeds" empty → **store overwritten with nothing; plans go blank as you look at them.**
**Fix: the request path is strictly read-only — it stats, compares, renders `stale`. It never forks and
never writes. Healing happens only in the existing in-process auditor loop (the single writer).**

**C3 — The auto-healing loop fires on the harness's own normal workflow, and files an unfixable defect.**
The plan's own premise says no git op fires a hook. The orchestrator's DEFAULT flow is
builders-in-worktrees → **cherry-pick** into the main checkout. Combined with "only the main checkout
projects," **every task completion in every orchestrated plan arrives via the drift path.** Task 4 then
declares every divergence "the push mechanism is broken" and auto-escalates at 3×. **The plan
contradicts itself** (preamble: git drift is inherent and unpreventable; task 4: every instance is a
defect to file). Result: the nl-issue ledger floods with `cherry-pick` drift proportional to productive
work, auto-escalating into a build-ready backlog row demanding a fix for **something that cannot be
fixed**. And `nl-issue.sh` dedup only collapses byte-identical text within 24h and does not merge into an
already-triaged entry — **the improvement loop DoS's itself.** Deeper shape problem: v2 *creates* a drift
class, then builds a loop to detect the drift it created, and calls that self-improvement — **its inputs
are 100% self-inflicted** — while the auditor's genuinely meaningful divergences
(`log_ahead_task_not_flipped` et al.) are **not wired into nl-issue at all**. **Fix: partition causes
into ARCHITECTURALLY-EXPECTED (git-side: cherry-pick/pull/merge/checkout/`git mv`) → a METRIC, never an
issue; and UNEXPECTED (hook registered but didn't fire; matcher hole; out-of-band write) → file it. And
point the feedback loop at the auditor's REAL divergences — that is the operator's actual intent.**

**C4 — Reverse Chesterton: the incumbent exists because it is correct by construction.** A PULL cannot
drift. No store to corrupt, no bootstrap, no schema version, no writer to serialize, no cross-machine
concern, no archive-prune lifecycle, no cause classifier — and it sees a `git checkout` **for free, with
zero mechanism**. It is the only shape in this design space with **no drift class at all**. v2 discards
that for 3.5 ms without ever pricing it.

## Major findings
- **M1 — the stamp is broken three ways.** `source_size` is a **no-op** (a checkbox flip is
  byte-size-preserving: `- [ ] 1.` → `- [x] 1.`, 27 bytes both). mtime precision is unstated and the
  natural bash idiom `stat -c %Y` is **1-second** — a blind window in which a size-preserving unhooked
  flip is invisible (exactness requires `%.Y` + Node `{bigint:true}.mtimeNs`, which do match exactly).
  And the **stamp-ordering TOCTOU is fatal**: stamping the mtime observed *after* reading yields
  new-mtime + old-content → the stat says `fresh` **forever** → a permanent, unhealable lie. **Fix:
  stat → read → stat again, retry on mismatch, stamp the pre-read value. Better: SHA-256 (1.4 ms for
  all active plans, cheaper than parsing) — exactly correct, no timestamp protocol. Drop `source_size`.**
- **M2 — per-plan sharding does not prevent lost updates WITHIN a plan.** v2 deliberately adds a second
  trigger for the same plan; two projector runs race (A reads v1, B reads v2, B writes, A writes last)
  → **stale content carrying a fresh stamp → never healed.** The repo's only mutex is required by its
  own header to give up after ~150ms and PROCEED UNLOCKED — unusable for read-modify-write. **Fix:
  delete trigger (b) per C1.**
- **M3 — "only the main checkout projects" makes the PUSH decorative.** Orchestrated plan state arrives
  by cherry-pick (no hook) → the projection is maintained almost entirely by the heal path → **this is
  not a PUSH; it is a 120-second BAKE with a stat check bolted on** — the worst of the three categories.
  The cockpit is up to 120s behind reality for every orchestrated task, and each lag also auto-files an
  issue (C3).
- **M4 — the cause classifier is largely underivable.** mtime+size+reflog cannot attribute a
  working-tree write to a *tool*. **The honest, mechanically-derivable classifier is two forks:**
  `git hash-object <plan>` vs `git rev-parse HEAD:<plan>` — equal ⇒ a git operation wrote it (expected →
  metric); not equal ⇒ an out-of-band write (unexpected → file it). Everything finer is fiction.
- **M5 — lifecycle + the resolvers still disagree.** `close-plan.sh` `git mv`s a plan to `archive/` (no
  hook) → `source_path` points at a nonexistent file. And v2 unifies the **parser** but not the
  **resolver** — which is the half that actually diverges today: `server.js:789` searches only
  `docs/plans/`; `auditor.js:247` searches `docs/plans/` **and** `archive/`. **Task 1 must own both.**

## Minor
- **m1** — the denylist carve-out must be scoped by **KEY**, not provenance: `payload-schema.js` `walk()`
  scans string *values* and cannot observe where a string came from. Add `description` to
  `DETAIL_ALLOWED_KEYS` + a `DENYLIST_EXEMPT_KEYS` set (as `HREF_KEYS` already does), with a length cap —
  and state plainly that this knowingly widens the anti-noise constraint.
- **m2** — the UI polish items are unrelated to the data architecture; only one depends on it. Split.

## Steelman (the recommendation)
**Keep the read-time parse; add an mtime/SHA-keyed in-memory cache in the Node server.**
`Map<absPath, {stamp, tasks}>`; on request, stat (or hash) each linked plan; unchanged → serve cached
parse; changed → re-parse that one plan (0.17 ms). This delivers **everything v2 claims, plus things it
cannot**:
- **Fast** — steady state is a few stats (the same stats v2 does), minus the store, minus the fork.
- **Current** — a `git checkout` / `pull` / `cherry-pick` / `git mv` / `sed` / MultiEdit / external
  editor / second-machine write is picked up **on the next request**, with **no hook, no trigger, no
  matcher, and nothing to forget.** v2's entire task 2 + task 4 exist to approximate what cache
  invalidation gives for free.
- **Honest** — absence is `null`, which already renders "no plan file found". **The `0/0` lie is
  impossible by construction** because there is no store whose absence can be mistaken for emptiness.
- **Zero new drift classes.** Nothing to reconcile, heal, auto-file, escalate, prune, bootstrap, version.
- **It still fixes every REAL bug:** ONE shared parser (killing the 3 divergent grammars and the 176
  lettered-id tasks invisible to the server), ONE shared resolver, `in_flight` stays a read-time join
  (it already works), and the `MultiEdit` matcher hole gets fixed on its own merits.

**When does the store actually win?** Only if (i) a **non-Node consumer** must read plan state (the `nl`
CLI, the session digest, a second machine's cockpit, a future multi-user surface) — *that* is the
argument the plan should be making; (ii) scale grows ~100×; or (iii) the cockpit must show plans whose
files are **not on this disk**. **None hold today, and the plan asserts none of them.**

> **On the operator's framing:** the requirement as written ("a mechanism pushes state into a JSON store;
> the GUI reads the store") specifies an *implementation*. The **outcomes** behind it — fast, current,
> honest, spans many plans, feeds detected problems back as fixes — are all delivered, and delivered
> better, by the cache. Whether to hold the stated shape anyway (because a non-Node/cross-machine
> consumer is coming) is genuinely the operator's call — but it should be made **against these numbers**,
> not against the assumption that read-time parsing is expensive. It is 3.5 ms.

## What v2 gets right (must survive into ANY shape)
1. Killing "push ⇒ cannot drift" — correctly evidenced, correctly named as a false mechanism claim.
2. **"A missing store must never render as 0/0"** — keep as a hard law regardless of shape.
3. Recognising `in_flight` comes from events, not plan edits (the correct conclusion from that insight is
   to *leave it* as a read-time join).
4. **ONE parser** — the highest-value item in the plan by a distance. Real bugs; they just don't need a store.
5. No in-repo mirror — non-negotiable.
6. Bounded work / no jq on the write path — right instinct, one step short of its conclusion (the cheapest
   bounded work is *not forking at all*).
7. "Silent healing is forbidden" — right principle, pointed at the wrong divergences.
