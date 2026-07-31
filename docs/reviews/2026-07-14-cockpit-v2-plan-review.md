# Cockpit-v2 plan review — 5-lens adversarial panel (VERDICT: 5/5 FAIL on the v1 design)

Panel: architecture-skeptic · systems/data-flow · harness-mechanism · ux · end-user-advocate (acceptance).
All read-only. Every lens returned **FAIL** on the naive "push ⇒ cannot drift" design. Findings below are
the CONVERGENT ones (independently hit by multiple lenses — that convergence is the signal), each verified
against code.

## Convergent findings

1. **`in_flight` is structurally dead (4/5).** The projection has TWO inputs (plan markdown AND the
   per-ask event JSONL) but the v1 plan wired triggers for only ONE. `task_started` is emitted by
   `workstreams-emit.sh --on-builder-dispatch` (PreToolUse) — a builder dispatch edits **no plan file**,
   so the projector never fires. Dispatch three builders → the cockpit shows **zero in-flight**. The
   read-time join being replaced gets this RIGHT. Regression of the cockpit's most valuable signal.

2. **"Store and plan cannot drift" is a FALSE MECHANISM CLAIM (4/5).** `settings.json.template:371`
   registers `plan-lifecycle.sh` under matcher `Edit|Write` — **not `MultiEdit`** (the very next entry
   uses `Edit|Write|MultiEdit`). And **no git-side mutation fires a PostToolUse hook**: cherry-pick (this
   harness's DEFAULT orchestrator flow), pull, checkout, merge, rebase, `close-plan.sh`'s own `git mv`.
   Precedent: `docs/discoveries/2026-05-04-sed-status-flip-bypasses-plan-lifecycle.md` — this harness has
   already learned once that plan mutations escape the Edit/Write hook.

3. **Absence renders as a plausible zero (5/5 — unanimous).** Once `countPlanTasks` is deleted, a missing
   / truncated / schema-skewed store, a cold machine, or a never-projected plan all yield
   `progress{done:0,total:0}` → `0/0`, `0%`: indistinguishable from a real plan with no work done. Today's
   path returns null and renders an honest "no plan file found". **A confident lie is worse than slow.**

4. **Lost updates on a consolidated blob (4/5).** One machine-global JSON + upsert = read-modify-write.
   `tmp+rename` makes a WRITE atomic; it does nothing against a lost UPDATE. The repo's only mutex
   (`progress-log-lib.sh`) is by its own header REQUIRED to give up after ~150ms and "PROCEED UNLOCKED" —
   benign for an append-only JSONL, catastrophic for an RMW blob. 59 worktrees, parallel builders, a
   second computer. Routine path, not a stress case.

5. **Worktree keying → unmerged work renders as "done" (3/5).** The store is machine-global keyed on
   `plan_slug`, but the same slug exists in the main checkout AND every worktree at different revisions.
   A builder's un-merged checkbox flip overwrites the main projection → the cockpit claims "done" for
   unmerged work — a **§1 honesty violation inside the operator's own dashboard**.

6. **No hot-path budget; the safety net reincarnates the fork-per-file defect (4/5).** `|| true` bounds
   ERRORS, not RUNTIME — no timeout anywhere. Measured on this machine: bash spawn ~87ms, jq fork ~77ms →
   ~160ms+ per plan edit against the harness's documented ≤50ms splice budget and its explicit
   no-jq-on-the-write-path convention. **246 plan files on disk**: a spawn-per-plan backfill or a
   120s-cadence sweep shelling the projector 246× is the confirmed-MAJOR fork-per-file latency defect,
   reborn inside the safety net.

7. **`drift_badges` dropped; the drift report has no destination (3/5).** `DETAIL_ALLOWED_KEYS` pins
   `drift_badges`; `server.js` joins them per-task from the live auditor. The v1 schema omitted them and
   the GUI cut deletes the path that assembles them → a shipped feature silently regresses. And v1 never
   said HOW the auditor heals — which would have made it a SECOND writer with a SECOND parser.

8. **The projection grammar is undefined and THREE divergent parsers already exist (4/5).** `server.js`
   and `auditor.js` accept **numeric ids only**; `plan-lifecycle.sh` also accepts **lettered** ids — and
   **176 lettered-id task lines exist in the plan corpus today**, invisible to the server's grammar. The
   two resolvers already disagree (auditor searches `archive/`, server does not). "description = the
   task's text" defines no rule for continuation lines, the `[serial]` prefix, or the `— Verification: X`
   suffix — and a bash projector concatenating that into JSON produces an **unparseable store the first
   time a description contains a double quote**.

9. **Projection lifecycle undefined (3/5).** `close-plan.sh` git-mv's the plan into `docs/plans/archive/`;
   v1 never said whether the entry is removed, marked terminal, or left pointing at a dead path. With 246
   plans, "active plans" vs "everything ever" decides whether the cockpit stays scannable.

10. **"In-repo mirror if the GUI needs it" is a landmine (3/5).** A per-second-mutating derived blob
    committed into a repo with 59 worktrees = permanent dirty trees, merge conflicts on every branch — and
    it lands in the PUBLIC personal mirror.

11. **Task descriptions break the payload contract (PROVEN, UX lens).** `description` is absent from
    `DETAIL_ALLOWED_KEYS` → the recursive allowlist walk rejects it. And `GATE_HOOK_DENYLIST_PATTERNS`
    scans EVERY string for `/\.sh\b/i`, `/(pretooluse|posttooluse|…)/i`, `/(plan-lifecycle|close-plan|…)/i`
    — which plan text legitimately contains (this very plan's own task text does). Descriptions would be
    rejected outright.

## Disposition
The v1 design was **reshaped**, not patched — see `docs/plans/cockpit-v2-push-materialized-store.md` (v2).
The central correction: **we cannot PREVENT drift (git operations cannot fire a hook), so we must not
claim to. Instead: push for speed, DETECT staleness cheaply and always (mtime/size vs the projection's
recorded source stamp — a `stat`, not a parse), heal, and report the cause into the auto-healing loop.**
Drift becomes impossible to HIDE even though it is impossible to PREVENT.
