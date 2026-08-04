# NEEDS-YOU Digest — 2026-08-03 (hand-triaged, in the proposed format)

One-time human-readable triage of every entry in the live machine-local NEEDS-YOU.md (Generated 2026-08-03T16:14:38Z). NEEDS-YOU.md itself stays machine-owned — do not hand-edit it; the generator fix is specced in [2026-08-03-needs-you-readability-review.md](./2026-08-03-needs-you-readability-review.md). Every claim below is labeled PROVEN (evidence cited) or HYPOTHESIZED (refuter stated). Verification run today: 11 product-repo PR states via `gh`, referenced worktrees/branches/scripts checked on disk. Naming + links note (harness-hygiene): this committed digest says "the product repo" and cites PR numbers only — the org-identifying PR URLs live in the machine-local NEEDS-YOU.md entries under the ids cited here.

**Bottom line: of 15 "awaiting your decision" entries, 3 need you now, 2 more are quick one-worders, 4+ are answer-when-you-can, and 6 are dead or superseded.**

## Decide now

| # | id | Ask (one line) | Reply with | Age | Blocking? |
|---|------|---|---|---|---|
| 1 | `caeb` | Ratify the NL-Maintenance resident daemon (DEC-4) | `ratify` / `pure-tick` / `hold` | 0d | YES — this machine runs zero recurring maintenance; doctor RED 2026-08-16 |
| 2 | `5fd5` | Apply the parts-queue prod migration so PR #1203 can merge | `apply parts migration` / `hold parts` / `apply both waves` | 6d | YES — verified PR is parked on it (gh: #1203 still OPEN) |
| 3 | `bfef` | Repoint 52 machine-local .env.local files off PRODUCTION | `repoint all 52` / `repoint the 2, delete the 50` / `leave them` | 1d | no — but every day unanswered, 52 local files keep prod credentials + a prod DATABASE_URL |
| 4 | `38e7` | Retire or keep the pinned ws-ui-server checkout | `retire pin` / `point at pin` / `keep both` | 0d | no |
| 5 | `4f72` | You-only: create the staging E2E admin (one command) | run the command below, then `e2e admin done` (+ optionally `test phone pool ok`) | 16d | no — but Phase-2 acceptance stays INCOMPLETE until done |

### 1. DEC-4 — ratify the resident maintenance daemon `NY-1785771976-caeb` · tier 2 · added 2026-08-03
**Decision needed:** register ONE Windows scheduled task that keeps a supervised bash daemon alive for all harness maintenance on this machine.
Context: the 6 legacy NL-* scheduled tasks are Disabled since 2026-08-02 — nothing recurring runs until you answer; the doctor WARNs now and flips RED 2026-08-16. Your Round-3 direction said "no bespoke resident daemon"; the architecture review ([docs/reviews/2026-08-03-harness-execution-redesign-REAL-architecture-review.md](./2026-08-03-harness-execution-redesign-REAL-architecture-review.md), F3) called this shape defensible engineering but explicitly yours to ratify. Both Critical findings were fixed (6f5d1b22, d46beee5) and independently re-reviewed PASS ([docs/reviews/2026-08-03-gated-pipeline-t3-t4-implementation-review.md](./2026-08-03-gated-pipeline-t3-t4-implementation-review.md)); the installer's register-then-rollback was proven end-to-end under a test task name.
| Option | What happens |
|---|---|
| `ratify` | `install-maintenance-task.ps1` runs; coord-sync, heartbeats, doctor-cache, session-resumer resume within 5 min under one supervised daemon; HALT flag drains it in one gesture; `-Rollback` uninstalls cleanly |
| `pure-tick` | same task, fires `--tick` every 5 min, no resident process; same coverage, sub-5-min cadences degrade to 5-min floors |
| `hold` | nothing registers; WARN → RED on 2026-08-16; cross-machine sync stays dead |
**My pick:** ratify. **Reply with:** `ratify` / `pure-tick` / `hold`

### 2. Parts-queue prod migration `NY-1785234921-5fd5` · added 2026-07-28
**Decision needed:** authorize one additive prod migration (parts-requests table + RLS + index) so verified PR #1203 (product repo) can merge schema-first.
Context: PR #1203 (Wave-1 parts queue from the prospect gap-analysis) is fully verified — two adversarial review rounds MERGE-READY, 6/6 staging runtime legs PASS — and gh confirms it is still OPEN, parked solely on this authorization (the auto-mode classifier correctly blocks unattended prod `db push`). Merging before applying would ship code referencing a missing table.
Heads-up (new, found today): the product repo's master has since merged a DIFFERENT migration with the same version stamp (`20260728140000_messages_sending_account_attribution.sql` — PROVEN, on disk in master), so the branch's `20260728140000_parts_requests.sql` likely needs a version bump before the apply (HYPOTHESIZED it conflicts; refuted if the migration tooling accepts same-version distinct names). Whoever executes should re-check the migration list first.
| Option | What happens |
|---|---|
| `apply parts migration` | I push the migration, merge #1203, run the paired deploy, verify same-SHA; parts queue live |
| `hold parts` | PR stays open and verified; nothing ships |
| `apply both waves` | also pre-authorizes the recurring-campaigns migration once IT reaches the same verified state |
**My pick:** apply parts migration. **Reply with:** `apply parts migration` / `hold parts` / `apply both waves`

### 3. Repoint 52 .env.local files off PRODUCTION `NY-1785639574-bfef` · added 2026-08-02
**Decision needed:** authorize a bulk rewrite of 52 machine-local `.env.local` files (2 dev worktrees + 50 agent worktrees in the product repo) from the prod database project to staging.
Context: decision DD-12 promises "local dev targets staging, never prod" but 52 files still point at prod, 53 carrying a prod DATABASE_URL that a migration-apply script can execute DDL through, with ~58 scripts that bypass every environment guard. The main checkout is already fixed and PR #1287 (repoint + standing `check:env-local`) is MERGED (gh-verified 2026-08-02) — only this machine-local bulk edit awaits you. Reversible: every file gets a `.env.local.prod-bak-20260801` backup first.
| Option | What happens |
|---|---|
| `repoint all 52` | every checkout matches the documented design; a worktree that truly needed prod re-pulls |
| `repoint the 2, delete the 50` | dev worktrees fixed; agent worktrees regenerate on next pull (transient failure possible) |
| `leave them` | 52 files stay pointed at production |
**My pick:** repoint all 52. **Reply with:** `repoint all 52` / `repoint the 2, delete the 50` / `leave them`

### 4. Pinned ws-ui-server checkout `NY-1785773673-38e7` · tier 2 · added 2026-08-03
**Decision needed:** the cockpit exists in two copies — the main neural-lace checkout (what `ensure-cockpit.sh` PROVABLY always launches) and a "pinned stable" sibling clone at `claude-projects/workstreams-ui-server` (still on disk — verified today) that session-start never actually runs and that misled the 2026-08-03 incident diagnosis ([docs/handoffs/2026-08-03-cockpit-nl-recursion-rootcause.md](../handoffs/2026-08-03-cockpit-nl-recursion-rootcause.md)). Both copies carry the orphan-kill fix; nothing is broken today.
| Option | What happens |
|---|---|
| `retire pin` | pinned clone deleted; one deployment root; matches actual behavior |
| `point at pin` | install config repointed at the pin; needs your `/grant-local-edit` + a pin-update cadence |
| `keep both` | two copies keep racing for port 7733; pin keeps drifting |
**My pick:** retire pin (also closes the recurring "orphaned worktree: workstreams-ui-server" alerts — 3 of the 25 noise bullets). **Reply with:** `retire pin` / `point at pin` / `keep both`

### 5. Provision the staging E2E admin `NY-1784344817-4f72` · added 2026-07-18
**Action needed (you-only):** agent sessions are (correctly) forbidden from creating accounts, so the last two Phase-2 acceptance legs wait on you running one command. The prepared, uncommitted script is still on disk — PROVEN today, in the product repo's worktree `.claude/worktrees/agent-a62a1fc2a4344e201`, at `scripts/provision-e2e-platform-admin.ts`. (HYPOTHESIZED still needed; refuted if the staging project already has a platform-admin login or Phase-2 acceptance already flipped.)
**Do:** open a terminal in that worktree → `npx tsx scripts/provision-e2e-platform-admin.ts` (~5s, staging only, prints creds for CI secrets per the repo's docs/testing/e2e-env-vars.md). **Reply with:** `e2e admin done` (and optionally `test phone pool ok` to adopt the curated staging test-phone pool).

## Answer when you can (defaults applied or genuinely no-rush — I keep going regardless)

- **P4 gates a-d** (`NY-1784189529-18cf` remainder; the "merge #985" part is DONE — merged 2026-07-17, gh-verified): each has a named default already in the merged plans. Reply only to override: `p4a-transactional`/`p4a-hold` (default hold/shadow-log) · `p4b-retire`/`p4b-rebuild` (default retire) · `p4c-drop`/`p4c-build` (default drop) · `p4d-circuit`/`p4d-ptcsr` (recommended: the first).
- **W7 evening overbooking** (`NY-1784340400-ec21`, 16d): default (customers/AI CAN book designated evening slots, with disclosure) stands unless you reply `evenings dispatcher-only`.
- **A2P onboarding defaults O1-O3** (`NY-1784295041-06cf`, 17d; its plan PR #1006 MERGED): platform-managed credentials / email+in-app notifications / older plan absorbed. Reply `a2p-o1/o2/o3: <choice>` only to override before the lane activates.
- **Membership-claim policy** (`NY-1783699358-908e`, 24d): genuinely still undecided — no claimed/unverified provenance exists in the product src (PROVEN by grep today; refuted if it lives under another name). Should a customer's CLAIM of membership set the membership flag as claimed/unverified, stay memory-only (today's behavior), or block member-rate talk until verified? My pick: claimed-flag with unverified provenance. Reply: `membership: claimed-flag` / `membership: memory-only` / `membership: block`. (Also consider `money-guard: enforce` for the pilot org.)
- **Segments Phase-2 product calls** (`NY-1783716259-0a77`, 24d): five questions (kind/name/storage/UI-home/nudge) — design merged, Phase 1 shipped without them, nothing built since (PROVEN: no segments surface in the product src). Answer any subset when convenient; recommendations already recorded in the entry.
- **Demo-contact reversal** (`NY-1783849123-b634`, 22d): 2 DEMO-org contacts soft-retired by a test-script error; reversal documented in the product findings ledger entry 088 (its PR #919, merged). Cost of leaving = 2 demo contacts show retired. My pick after 22 days of it mattering to nobody: reply `leave them` and close it.
- **Cleanup leftovers** (`NY-1783553749-dbe5`, 26d, partially overtaken): of the 3 dirty product-repo worktrees, one (`agent-af68f3f9611e166a5`) is already gone; `wf_4968fa97-01e-2` and `agent-afd15a7c6bf656e4d` remain on disk (PROVEN), branch `feat/conversation-conclusion-2026-07-03` still exists with real unmerged work, and origin still has 98 remote branches (PROVEN) vs the ~75-stale estimate. Reply `remove the 2 dirty worktrees` and/or `sweep remote branches` when you want the estate pass.
- **appointments property-id feature** (the one surviving sliver of `NY-1784014662-db23`): schedule it or not — the multi-PROPERTY duplicate class stays open until it exists. Reply `schedule property_id` / `property_id later`.
- **Prospect facts for your follow-up text** (open question, 6d): (1) do their maintenance agreements live in their FSM platform or would the product own them; (2) who is their FSM admin / will they grant tenant API access; (3) volumes (texts/calls, agreement count, review platforms). Plus, longest-lead: file the Google Business Profile API access application (needs your Google account; I can draft it).
- **4 orphaned neural-lace agent worktrees** (the deduped content of 25 noise bullets; all 4 PROVEN still on disk: `agent-a60cd9f14ad2034df`, `agent-aa680cc77830d361b`, `agent-aeed9a16399bf88e6`, `agent-afcf419ea529b1ca0` — each 2-5 unintegrated commits): reply `sweep orphan worktrees` for a salvage-then-remove pass, or leave for the estate sweep above. (The 5th recurring alert, workstreams-ui-server, is decided by item 4 in Decide-now.)
- **Two classifier-denied estate cleanups** (open question, 18d): (a) remove the verified-phantom `nl-ux-wt` husk worktree; (b) push or decline pushing `ws-ui-server-stable` — note (b) is best answered together with Decide-now item 4.

## Probably dead — confirm to close

Reply `confirm dead <id>` (I resolve it) or `still live <id>` (I re-promote with fresh context). Evidence per line:

- `dd0b` DO-NOT-APPLY #973 as-is — SUPERSEDED, PROVEN: #973 merged 2026-07-17 with the property-aware amendment (its successor entry 62ef says so; gh confirms merge).
- `62ef` Authorize the #973 migration apply — LIKELY DONE, HYPOTHESIZED: entry 5fd5 (07-28) states "prod migration list verified clean with exactly this one pending," which is only possible if the #973 migrations were already applied. Refuted if the prod migration list still shows `20260714050000`/`20260714050100` pending.
- `db23` 2026-07-14 six-item board — 5 of 6 DONE/SUPERSEDED, PROVEN: #975 merged, #977 merged, #985 merged (absorbing the #974 decisions; #974 closed unmerged as instructed), the duplicate-appointment pair auto-completed per 62ef. Sliver extracted above (property-id).
- `18cf` "Merge PR #985" — DONE, PROVEN: merged 2026-07-17T03:39Z. Only the P4 default-gates survive (moved to when-you-can).
- In-flight stop-gate rows (5 entries, 2026-07-06..08) — DEAD, PROVEN: all three cited product-repo worktrees (generated names `hopeful-bhaskara-01a048`, `upbeat-kepler-3cac38`, `amazing-wright-d9c51e`) no longer exist on disk; whatever was uncommitted there is unrecoverable through this ledger.
- Fidelity re-audit "still UNRUN" — DEAD, PROVEN: the product repo's `docs/reviews/2026-07-08-fidelity-reaudit-findings.md` exists on disk, so the sweep ran after the entry was written.

## Accounting (nothing dropped)

All 15 open decisions mapped: 5 Decide-now (`caeb` `5fd5` `bfef` `38e7` `4f72`) · 6 when-you-can (`18cf`-gates `ec21` `06cf` `908e` `0a77` `b634` + `dbe5`, `db23`-sliver) · 4 probably-dead (`dd0b` `62ef` `db23` `18cf`-main). All 27 open-question bullets: 25 collapse to the 4-worktree sweep + item 4; 2 unique (estate cleanups, prospect facts) triaged above. All 6 in-flight rows: 5 dead-proven (stop-gate), 1 dead-proven (fidelity). The operator-todo AUTO section agrees: its only unticked pointers are `caeb` and `38e7`.
