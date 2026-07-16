# Cockpit v2 — cross-machine plan store (push-projected, staleness-detecting)

Status: DRAFT (v3 — operator chose STORE; incorporates the architecture-reviewer's mandatory corrections)
Mode: build
rung: 3
lifecycle-schema: v2
ask-id: <id | none — no linked ask>
prd-ref: none

## The decision, and the ONLY thing that justifies it
The `architecture-reviewer` verdict (`docs/reviews/2026-07-14-cockpit-v2-architecture-review.md`) was
**NEEDS-RESHAPING**, on a measurement: the read-time parse the store exists to eliminate costs **3.5 ms**
for every active plan, while **one spawn** of the proposed projector costs **~87 ms**. It named exactly
one condition under which the store nonetheless wins:

> *"(i) a **non-Node / cross-machine consumer** must read plan state — then an on-disk store is genuinely
> justified, and THAT is the argument the plan should be making."*

**The operator has now asserted that condition: cross-machine is a CURRENT requirement, not a future one.**
So the store is justified — **but only as a cross-machine artifact.** This changes the design:

> ### ⚠ CRITICAL — the v2 store did not actually deliver cross-machine
> v2 put projections in `~/.claude/state/plan-projections/` — **machine-local**. That delivers *nothing*
> cross-machine, and therefore fails the only test that justifies it. Plan *files* already sync via git;
> what does NOT sync is the ask/event/session state. **The store must therefore SYNC.**
>
> **Use the channel this harness already has:** `broadcast-active-session.sh` publishes cross-computer
> state to dedicated git refs (`harness/active-sessions/<hostname>`) on the remote — *not* to the working
> tree. The plan store uses the same pattern: a **dedicated ref**, not a working-tree file. This is also
> the only shape that dodges the landmine the panel flagged (a per-second-mutating blob committed into a
> repo with 59 worktrees and a public mirror).

**If cross-machine is ever dropped as a requirement, this store must be deleted and replaced by the
mtime/SHA-keyed in-memory cache** — which the reviewer proved is superior on every other axis. Record
that as the retirement condition.

## Mandatory corrections from the architecture review (non-negotiable)
- **C1 — `in_flight` STAYS a read-time join.** It is derived from the event JSONL, *not* the plan
  markdown; the plan-file staleness stamp cannot see it. Projecting it would show "zero in-flight while
  three builders run" *stamped `fresh`* — asserting the lie is current. It also deletes trigger (b) and
  with it the same-plan write race.
- **C2 — the HTTP request path NEVER forks and NEVER writes.** It stats, compares, and renders `stale`.
  Healing happens ONLY in the existing in-process auditor loop (the single writer). A fork on the request
  path re-incarnates the documented "cockpit lobotomy" (lying rc=0, empty stdout).
- **C3 — git-side drift is a METRIC, never an auto-filed issue.** Cherry-pick IS the orchestrator's
  default flow, so *every orchestrated task completion arrives via the drift path*. Filing those would
  DoS the improvement ledger with reports of a thing that cannot be fixed. **Partition:**
  ARCHITECTURALLY-EXPECTED (git-side: cherry-pick/pull/merge/checkout/`git mv`) → counted, never filed.
  UNEXPECTED (hook registered but did not fire; matcher hole; out-of-band working-tree write) → filed.
- **C3b — point the auto-healing loop at the auditor's REAL divergences.** It already computes genuine
  harness bugs (`log_ahead_task_not_flipped` et al.) that are **wired to nothing**. That is the operator's
  actual intent; self-inflicted drift is not a finding about Neural Lace.
- **M1 — use a CONTENT HASH, not mtime+size.** `source_size` is a no-op (a checkbox flip is
  byte-size-preserving: `- [ ] 1.` → `- [x] 1.`, 27 bytes both). SHA-256 over all active plans costs
  **1.4 ms** — cheaper than parsing them. Stamp-ordering must be `stat → read → stat`, retry on mismatch,
  or a TOCTOU produces a **permanently unhealable** lie.
- **M4 — the honest cause classifier is two forks:** `git hash-object <plan>` vs `git rev-parse HEAD:<plan>`.
  Equal ⇒ a git operation wrote it (expected → metric). Not equal ⇒ an out-of-band write (unexpected →
  file it). The 10-value enum was fiction.
- **M5 — task 1 owns the RESOLVER too, not just the parser.** `server.js:789` searches only `docs/plans/`;
  `auditor.js:247` searches `docs/plans/` AND `archive/`. That is the half that actually diverges today.
- **m1 — the denylist carve-out is by KEY, not provenance.** `payload-schema.js walk()` scans string
  VALUES and cannot observe where a string came from. Add `description` to `DETAIL_ALLOWED_KEYS` + a
  `DENYLIST_EXEMPT_KEYS` set (as `HREF_KEYS` already does), with a length cap — and state plainly that
  this knowingly widens the anti-noise constraint.
- **m2 — the UI polish items do not ride this plan.** Split into their own.

## Tasks

- [ ] 1. [serial] **The ONE parser + the ONE resolver (shared module).** The highest-value item in the
  plan and a prerequisite for every shape. Today there are THREE divergent plan grammars (server + auditor
  accept numeric task ids only; `plan-lifecycle.sh` also accepts lettered — and **176 lettered-id task
  lines exist today, invisible to the server**) and TWO resolvers that disagree about `archive/`. Build one
  parser + one resolver, used by every consumer. Handles: numeric AND lettered ids, continuation lines, the
  `[serial]` prefix, the `— Verification: X` suffix, and correct JSON escaping (a `"` in a description must
  not corrupt anything). `--self-test` incl. a malformed plan → `damaged`, never a silent zero —
  Verification: mechanical
- [ ] 2. [serial] **Projection schema + projector (content-hashed).** One projection per plan, written
  atomically. Carries `schema_version`, `source_path`, **`source_sha256`** (NOT size), `last_projected_ts`,
  `status`, `tasks[{id, description, done, evidence_link}]`, `progress{...}`. **NO `in_flight`** (C1).
  Stamp ordering per M1 — Verification: mechanical
- [ ] 3. [serial] **CROSS-MACHINE SYNC — the thing that justifies this store.** Publish/consume projections
  via a dedicated git ref, following `broadcast-active-session.sh`'s existing cross-computer pattern. NEVER
  the working tree. Each machine publishes its own projections; the cockpit merges the set and shows which
  machine each came from. **Acceptance: a plan whose work is happening on the OTHER machine appears,
  current, in this machine's cockpit** — Verification: full
- [ ] 4. [serial] **Push triggers (bounded, time-boxed).** `plan-lifecycle.sh` on `Edit|Write|**MultiEdit**`
  (the missing matcher is a real hole — fix it), start-plan, close-plan. Subshelled + non-fatal AND with an
  explicit timeout (`|| true` bounds errors, not runtime). Honest classification in the plan text: **for
  orchestrated work this is NOT a push — cherry-pick fires no hook — it is a bake+detect.** Say so —
  Verification: full
- [ ] 5. [serial] **Staleness detection + honest states, READ-ONLY.** The request path hashes/stats and
  compares; renders `fresh` / `stale` / `unknown` / `damaged`. **It never forks and never writes** (C2).
  **A missing projection NEVER renders as `0/0`** — Verification: full
- [ ] 6. [serial] **The auto-healing feedback loop (corrected).** Heal in the auditor (the single writer).
  Classify cause via `hash-object` vs `HEAD:` (M4). **Git-side = METRIC. Unexpected = auto-file via
  `nl-issue.sh` → triage → build-ready row, escalating on recurrence.** AND wire the auditor's EXISTING
  real divergences into that loop (C3b) — that is the actual auto-healing the operator asked for. Silent
  healing remains FORBIDDEN — Verification: full
- [ ] 7. [serial] **GUI reads the store; `in_flight` stays a read-time join.** Delete `countPlanTasks`.
  Preserve `drift_badges`. Payload contract per m1. Backfill batched (NOT fork-per-plan) — Verification: full

## Acceptance
1. **A plan being worked on the OTHER machine shows up, current, in this cockpit.** (The justification.)
2. Dispatch 3 builders → the cockpit shows 3 in-flight (read-time join preserved).
3. `git checkout` a plan behind the hook's back → detected, healed, counted as an EXPECTED metric — **and
   NOT auto-filed as a defect.**
4. Simulate a hook that is registered but did not fire → UNEXPECTED → auto-filed, escalating at 3×.
5. Delete/corrupt a projection → `unknown`/`damaged`, never `0/0`.
6. `grep` proves the request path never spawns a process and never writes a projection.
7. A description containing `"`, a newline, and `plan-lifecycle.sh` renders safely and is not denylist-rejected.

## Retirement condition
If cross-machine ceases to be a requirement, **delete this store** and replace it with the mtime/SHA-keyed
in-memory cache — proven superior on every other axis (3.5 ms, zero drift classes, absence-is-null).
