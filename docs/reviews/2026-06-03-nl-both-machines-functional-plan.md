# Neural Lace — "Fully Functional on Both Machines" — Assessment + Plan

**Date:** 2026-06-03 | **Author:** Office_PC session
**Goal (Misha):** every aspect of NL synced, clean, updated to latest, shared across both computers, fully functional + in active working order on both machines.

## Machines
- **Office_PC** (this machine) — broadcast branch `harness/active-sessions/Office_PC` confirmed.
- **BOOK-JDM547N8BO** (the other machine, MacBook) — broadcast branch `harness/active-sessions/BOOK-JDM547N8BO` confirmed. **I cannot directly act on it from here** — it self-syncs via the `session-start-auto-install` hook the next time a session runs there.

## Assessment (this machine, 2026-06-03)
| Dimension | State | Gap |
|---|---|---|
| **master sync** | HEAD `6b79adb`, **2 behind** origin/master, 0 ahead | Pull to latest (the other machine pushed 2 commits) |
| **uncommitted** | 12 tracked files dirty on master | Reconcile (commit/stash) |
| **install currency** (`~/.claude` vs `adapters/claude-code`) | **hooks 34, rules 19, skills 6, templates 6, agents 1 differ/missing** | Live harness is STALE — re-sync from canonical (after pull) |
| **Workstreams UI** | server restarted on current code; no-cache header live; **194 nodes served** | ✅ FIXED (display). Duplicate-node reducer = remaining cleanliness |
| **cross-machine broadcast** | both machines register on PT `harness/active-sessions/*` | Working |

## Plan (ordered)
1. **Sync this machine to latest master** — `git pull --ff-only` (2 behind); reconcile the 12 uncommitted (stash→pull→pop, commit harness-relevant). [DRIVE NOW]
2. **Restore install currency** — after pull, re-run the harness sync so `~/.claude` matches canonical (the 34-hook / 19-rule drift). Carefully: master-wins for harness files, preserve per-machine `~/.claude/local/*`. Honor HARNESS-GAP-44 (don't full-install while behind master → that's why pull is step 1). [DRIVE]
3. **Workstreams UI** — no-cache display fix DONE; remaining = reducer upsert-by-stable-id to kill the 28/34 duplicate nodes (needs its own change to `state.js` + `workstreams-emit.sh` + state regen). [FOLLOW-UP — code change]
4. **Other machine (BOOK)** — cannot touch from here. It self-syncs via `session-start-auto-install` on its next session (which pulls latest master + re-syncs `~/.claude`). Action: ensure canonical master + the auto-install hook are correct (steps 1-2) so BOOK self-heals; then a session on BOOK completes it. [DOCUMENT + relies on a BOOK session]
5. **"Shared across both computers" — interpretation.** The harness (rules/hooks/agents/skills) becomes byte-identical on both via the canonical-master + auto-install (steps 1-2,4). The Workstreams UI state file is inherently **per-machine** (each shows that machine's own Dispatch sessions); cross-machine session *visibility* already flows through the broadcast branches. True cross-machine tree **aggregation** (one GUI showing both machines' trees) would be a new feature — flagged as a design question, not assumed.

## What I can finish from Office_PC vs what needs BOOK / a decision
- **Finishable here:** steps 1, 2, 3 (workstreams display done; reducer fix is code I can write); ensures BOOK self-heals.
- **Needs a BOOK session:** step 4's completion (BOOK pulling + re-syncing its own `~/.claude`).
- **Needs Misha's decision:** step 5 — is per-machine workstreams data sufficient, or do you want cross-machine tree aggregation (a new feature)?
