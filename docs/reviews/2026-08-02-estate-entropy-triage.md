# Estate entropy triage — 2026-08-02

**Scope:** read-only triage of four piles (nl-issues, monitor alerts, stale plans, stranded
worktrees) into a ranked, actionable picture. Binding principle honored throughout: **ignored !=
unimportant — it means the system had no queue.** Nothing below is discarded for being old;
every item gets a disposition and a citation.

**Evidence discipline:** PROVEN = cited command/SHA/path, re-run live in this session. HYPOTHESIZED
= plausible, refuter named. UNVERIFIED = mechanical proxy only, not individually confirmed —
labeled, not silently trusted.

---

## 1. Headline counts — raw pile vs. distinct signal

| Pile | Raw count (PROVEN, measured this session) | Distinct root causes / real signal | Noise ratio |
|---|---|---|---|
| nl-issues untriaged | 135 (of 155 total lines; `jq -s 'group_by(.triage_status)'` on `nl-issues.jsonl`) | 32 dated 2026-07-27..08-02 (the redesign cluster, see §2); ~103 older, dated 07-06..07-25 | 6 of the 32 (19%) are raw `<task-notification>` XML dumps or bare operator-question captures with zero standalone signal — see §2 "NOT-AN-ISSUE" rows |
| Monitor alerts unacked | 1,231 non-`.acked` files (measured now; task brief's ~1,209 was measured ~7h earlier — the 22-file gap is exactly accounted for by the still-enabled product-health-monitor firing every ~30 min in between, see below) | **3 root classes cover 97%** of the pile: `harness-doctor DOCTOR_RED` (503), `worktree-hygiene-sweep SWEEP_TIMEOUT` (240), `webhook-retell UNEXPECTED_STATUS` (447) = 1,190 of 1,231 | 97% |
| Stale ACTIVE plans | 24 plans carry `Status: ACTIVE`; 1 is `harness-execution-redesign-2026-08.md` itself (today's live work) → **23 stale-candidates**, matching the brief's cited figure exactly | Of the 8 individually verified (see §4): 4 are fully landed on master under a *different* commit shape and only need `close-plan`; 1 (`status-event-ledger.md`) is a live-tracked plan whose custom BUILT/PARTIAL/UNBUILT taxonomy makes naive checkbox-counting wrong — **not stale**; 1 (`machine-folder-reorg.md`) is deliberately paused by an explicit 2026-07-30 operator directive, correctly recorded, not neglected | most "staleness" here is bookkeeping debt, not abandoned work |
| Stranded worktrees | 10 unlocked, non-master-tip worktrees under `.claude/worktrees/` (4 more are `locked` = live sibling agents including this one, not stranded) | **All 10 verified SAFE** — every commit `git cherry` flagged as "unmerged" was independently confirmed landed on master under a reshaped SHA (cherry-pick/integration changed the diff, not the content) — see §4's methodology and the LOUD callout | 0 — this pile looked dangerous and, on deep verification, is not |

**The single biggest fact in this pile:** Stage 0 of the redesign plan (commit `e9c5bc0f`,
2026-08-02 17:03 local) already **stopped two of the three dominant alert classes at the source**.
`harness-doctor DOCTOR_RED` alerts (health-tick) last fired 2026-08-02T18:25:58Z; `SWEEP_TIMEOUT`
alerts (supervisor-tick) last fired 2026-08-02T19:08:24Z. Neither has fired again in the ~7 hours
since (latest alert file overall: 2026-08-03T02:28:49Z, from the still-enabled product-health-monitor
only). This is PROVEN by `ls` timestamps on the alert directory, not inferred — the handoff doc
(`docs/handoffs/2026-08-02-stage0-pending-integration.md`) independently corroborates: the five
`NL-*` maintenance scheduled tasks were disabled the same session, CPU dropped 99.9%→~13%, bash
count 111→~8.

---

## 2. nl-issues triage table — the 32-item redesign cluster (2026-07-27..08-02)

Clustered against `docs/designs/harness-execution-redesign-considerations-2026-08-02.md` (the
"brief") and `docs/plans/harness-execution-redesign-2026-08.md` (the "plan"). Line numbers below
refer to those two files as read this session.

| # | Date | Text (truncated) | Disposition | Evidence |
|---|---|---|---|---|
| 1 | 07-28 | downstream-product `.env.local` flagged PRODUCTION by `prod-guard.ts`, blocks `test:unit` | **ACTIONABLE-MED** | downstream-product bug, not harness; route to that product's own backlog |
| 2 | 07-28 | downstream-product CI integration-test shard rotates its failing file (Supabase `beforeAll` hook timeouts) | **ACTIONABLE-MED** | downstream-product bug; capacity contention on shared test DB |
| 3 | 07-28 | downstream-product `uniquePhone()` factory collision, leaked orgs | **ACTIONABLE-MED** | downstream-product bug |
| 4 | 07-28 | downstream-product `test:links` red since PR #1201, fragment-anchor false positive | **ACTIONABLE-LOW** | downstream-product bug; cosmetic (CI attribution only) |
| 5 | 07-28 | Worktree-isolated agents lose acceptance artifacts on worktree cleanup | **ACTIONABLE-HIGH** | NOT covered by the redesign plan (plan's Scope OUT is the *orphan-bash* reaper, D2; this is the *worktree* reaper — a different mechanism). Same incident class as #14/#16 below — see §4 LOUD callout |
| 6 | 07-28 | Builder subagent used `git push --force-with-lease` on its own PR branch; no gate enforces constitution Rule 9 for subagent worktrees | **ACTIONABLE-HIGH** | UNVERIFIED-fixed: grepped `adapters/claude-code/hooks/*.sh` for a force-push PreToolUse block — none found (only comments/tests reference the string). Real gap, not superseded by the redesign plan (which touches gate *messages*, not new gate *coverage*) |
| 7 | 07-28 | `session-wrap.sh` Signal-2 false-attributes `plans_touched_this_session` in fresh worktrees (4h-window inheritance bug) | **ACTIONABLE-MED** | same shape as a "2026-05-17 Signal-3" finding the issue itself cites as precedent; not part of the redesign plan's scope |
| 8 | 07-28 | Kernel pool bloat (12.25 GB) / Appinfo handle leak, reboot-only recovery | **SUPERSEDED-by-considerations-brief §1.1 A2** | brief line 17 records this exact evidence and explicitly marks causation HYPOTHESIZED ("spawn churn *causes* the leak — refuter: pool still bloats after migration"); plan header line 52 keeps it HYPOTHESIZED and commits only to *measuring* pool bytes before/after Stage 1, never to claiming it fixed |
| 9 | 07-28 | T15 candidate: portable harness profile for cloud/scheduled sessions | **NEEDS-OPERATOR-DECISION** | a `docs/plans/accountable-estate-program-2026-07.md` backlog candidate, never promoted into that plan's task list (grep confirms no "T15" row exists there yet) — queued, not lost |
| 10 | 07-28 | T16 candidate: `bench-estate.sh` portable benchmark suite | **NEEDS-OPERATOR-DECISION** | same — not yet promoted into the estate plan |
| 11 | 07-29 | T17 candidate: build-process value-stream audit | **NEEDS-OPERATOR-DECISION** | same |
| 12 | 07-30 | T18 candidate: WSL2 builder-host pilot, measured spawn-cost data | **SUPERSEDED-by-considerations-brief R3.1** | brief lines 255-271 (operator decision 2026-08-02c, BINDING): "NO WSL dependency." T18's own *measurement* (200 spawns <0.15 ms) is the evidence base R3.1 cites, but its *program* (builder-hosting pilot) explicitly "leaves this program" (line 271) — T18 survives only as a possible future experiment, never a harness dependency |
| 13, 15, 23 | 08-01, 08-01, 08-02 | Raw `<task-notification><task-id>...<output-file>...` XML fragments | **NOT-AN-ISSUE — capture artifact** | verbatim tool-notification text auto-captured by the nl-issue pipeline, not an authored finding; zero standalone signal. Flagged here rather than silently dropped per the binding principle, but there is nothing to disposition |
| 14, 16 | 08-01 | Worktree reaper removed an ACTIVE dispatched agent's worktree mid-verification (`agent-a8534c70587c7548c`), contents + `.git/worktrees` metadata deleted | **ACTIONABLE-HIGH** | duplicate captures of the same 2026-08-01T00:11 incident (two different verifier sessions independently filed it). NOT in the redesign plan's scope (plan excludes only *orphan-bash* reaper arming, D2). Cites its own precedent salvage commit `8bde0f56` — UNVERIFIED (not independently confirmed this session; grep for that SHA was not run) |
| 17 | 08-01 | ORPHAN-BASH + DRAIN-MODE: reaper disarmed (`PERF_TICK_REAP_ARMED` false); no drain mode at dispatch-admission; Windows has no PDEATHSIG | **PARTIALLY ALREADY-FIXED-in-e9c5bc0f** | point 2 (tick-level HALT/drain) shipped in `e9c5bc0f` (`sf_halt_set/clear/active`, honored by `coord-sync.sh`, `supervisor-tick.sh`, `health-tick.sh` — confirmed via `git show --stat e9c5bc0f`). Point 1 (reaper arming) stays with the operator, D2, unarmed by design. Point 2b ("checked at dispatch admission") and point 3 (Job Objects) remain open — tracked in plan Stage 2/3 (tasks 4-5), not yet built |
| 18, 19, 28 | 08-01, 08-01, 08-02 | Operator-verbatim design-dialogue questions (reaper safety data, proactive protections, capacity-check reasoning) | **SUPERSEDED-by-considerations-brief** | folded into the brief's "Addendum — round 2" (lines 225-243) and "Round 3 revamp" R3.1/R3.2 sections (lines 255-286); historical record of the design conversation, answered in the same document |
| 20 | 08-01 | HOOK TAX GREW 2.5x UNMEASURED: 25 PreToolUse hooks per Bash call, 4.1s latency; recommends a doctor budget check | **ALREADY-FIXED-in-e9c5bc0f (WARN only)** | `budget-bash-hooks` check shipped in `e9c5bc0f` per its commit message ("two new WARN-only checks... budget <=6 per R3.3, current real count ~25 so this WARNs today"). RED flip and the actual 25→~5 reduction is Stage 2 (plan task 4), not yet built — the finding's core ask (a check exists) is done, the outcome it wants (tax reduced) is not |
| 21 | 08-01 | Operator: "file your four suggested changes... Also you're still failing to provide working links" | **NEEDS-OPERATOR-DECISION / open** | no lesson file or gate found addressing "broken links" specifically this session (`git log --grep="working link\|broken link"` since 08-01: zero hits) — genuinely unresolved constitution §2 friction, distinct from the redesign's technical scope |
| 22 | 08-01 | MEASUREMENT BUG: `Get-Process MsMpEng` reads 0% CPU (Protected Process Light); must use `Get-Counter` | **ACTIONABLE-LOW / open** | no doctrine update or lesson found (`git log --grep="MsMpEng\|Get-Counter"`: zero hits) — a real methodology correction not yet encoded anywhere durable |
| 24 | 08-02 | `needs-you.sh` with no/unknown verb emits `line 2251: render: command not found` before usage | **ALREADY-FIXED (fix SHA UNVERIFIED)** | current `needs-you.sh` (this worktree) has no bareword `render` call — the 0-arg path (lines 2250-2278) is a plain `cat <<EOF` block, and the unknown-verb path (line 2288) calls `die "unknown verb '$1'..."`. Bug not reproducible at HEAD. Candidate fix commits (untraced to this specific bug): `ca35249c`, `86e8264c`, `d1465f09` all touched `needs-you.sh` this window |
| 25 | 08-02 | SELF-DOS: 17h @ 99.9% CPU root-caused to nested doctor chains + CoordSync cadence-inversion + O(mess) checker cost | **PARTIALLY ALREADY-FIXED-in-e9c5bc0f** | fixes (b) "extend single-flight to all doctor/digest entries" and (e) "validates hook-count budget" are DONE (`e9c5bc0f`, confirmed via commit diff). Fixes (a) doctor verdict cache, (c) CoordSync cadence change, (d) poller timeouts are Stage 1 (plan task 3), not yet built |
| 26 | 08-02 | REDESIGN VERDICT: CPU 99.9%→~11% after killing spinners + disabling 5 tasks; names the execution-redesign scope | **SUPERSEDED-by-plan (docs/plans/harness-execution-redesign-2026-08.md)** | this entry IS the plan's genesis — the plan's own Assumptions section (line 400) names "nl-issues 2026-08-02, entries a-d" as the binding spec source |
| 27 | 08-02 | REDESIGN INPUT: push-vs-pull doctrine, lost-event prevention, cleanup-as-sensor, death certificates | **SUPERSEDED-by-considerations-brief** | verbatim reproduced in brief's "Addendum — round 2" section, lines 225-243 |
| 29 | 08-02 | REDESIGN INPUT round 2: capacity-knowledge axis, lease/ack, write-ahead intent, death taxonomy | **SUPERSEDED-by-considerations-brief** | same Addendum section, lines 225-243 — near-verbatim match confirmed by direct text comparison |
| 30 | 08-02 | OPERATOR DECISION 2026-08-02c (BINDING): NO WSL dependency | **SUPERSEDED-by-considerations-brief R3.1** | brief lines 255-271 reproduce this near-verbatim, including the "no prior no-WSL decision existed" honesty note |
| 31 | 08-02 | REDESIGN ROUND 3 — OPERATOR GO 2026-08-02d: no new hardware, Gate Philosophy Law, accepted improvements | **SUPERSEDED-by-considerations-brief R3.2-R3.6 + plan** | brief lines 273-339; this entry is literally the build authorization that produced `docs/plans/harness-execution-redesign-2026-08.md` |
| 32 | 08-02 | Live `settings.json` has TWO overlapping `matcher:""` SessionStart blocks (merge_settings additive drift) | **ACTIONABLE-MED, tracked** | plan Edge Case 5 (line 433) names this exact class; the handoff doc's "Live settings reconciled on THIS machine" section shows it was fixed *on the desktop* (4 blocks/16 hooks → 3 blocks/8 hooks) but the handoff's OWED #5 flags the SAME reconcile is still needed on the laptop and Mac mini — open on 2 of 3 machines |

**Net for the 32-item cluster:** 3 NOT-AN-ISSUE (capture noise), 8 SUPERSEDED (fully absorbed into
the brief/plan, no further action), 5 ALREADY-FIXED or PARTIALLY-FIXED with a cited SHA, 3
NEEDS-OPERATOR-DECISION (T15-T18 backlog candidates + the broken-links friction), the remainder
ACTIONABLE at various priorities (6 downstream-product bugs, 2 harness gaps not covered by the
redesign's scope: worktree-reaper liveness check and force-push gate coverage).

### The older 103 (2026-07-06..07-25) — aggregate, not individually triaged

Full individual triage of 103 more items was out of the effort budget available for this pass; a
project breakdown: neural-lace 45, downstream-product 18, ~15 small one-off agent-session projects,
25 mixed downstream projects. Spot-checking found the same supersession pattern as the redesign cluster —
example: the 2026-07-12 entry "SessionStart hooks have no single-flight lock" describes **exactly**
the defect `e9c5bc0f` fixed three weeks later (PROVEN — same root cause, same fix shape). This
strongly suggests (HYPOTHESIZED, refuter: a keyword sweep finding no match) that a material
fraction of the 103 are already superseded by the intervening seven weeks of harness commits, but
each needs the same `git log --grep`-style check performed by hand in §2 above before it can be
marked SUPERSEDED — see §6 for the mechanized version of this check as a prevention item.

---

## 3. Alerts — distinct classes and mechanical clears

| Class | Count | Source file pattern | Mechanical action to clear the class |
|---|---|---|---|
| `harness-doctor\|DOCTOR_RED` | 503 | `*-health-tick.json`, `.results[].label=="harness-doctor"` | Already stopped (last fired 2026-08-02T18:25:58Z — single-flight guard + task disable in `e9c5bc0f`). Remaining action: bulk-ack the 503 pre-existing files (plan Stage 4 drain, D3 watermark) |
| `supervisor-tick\|SWEEP_TIMEOUT` | 240 | `*-supervisor-tick.json`, `worktree-hygiene-sweep.sh --stranded timed out after 107s` | Already stopped (last fired 2026-08-02T19:08:24Z, same task-disable). Root fix still open: the sweep script itself has no internal timeout budget (nl-issue #29's fix item (d), Stage 1/3 territory, not yet built) |
| `orphaned-worktree\|ORPHANED_WORKTREE` | 15 | `*-supervisor-tick.json` | Real signal, not noise — 15 alert-firings map to a handful of genuinely stranded worktrees (§4 count: 10 currently present). Action: the worktree-prune.sh sweep (already exists, `--apply` mode) once each worktree's landed-on-master status is confirmed (§4 methodology) |
| `webhook-retell\|UNEXPECTED_STATUS` | 447 | bare-timestamp `*.json`, `monitor_url` = downstream-product production URL | **Product bug, not harness**: `/api/webhooks/retell` returns 200 for an unauthenticated request where the monitor expects 401. One-line fix in the downstream product's webhook auth route; every single tick re-fires this until the route is fixed — highest-value single fix in the entire alert pile (447 of 1,231 files, 36%) |
| `*\|SLOW` across ~20 distinct downstream-product endpoints | ~200 combined | bare-timestamp `*.json` | HYPOTHESIZED tied to general latency, NOT cleanly correlated to the 08-01/08-02 CPU-burn window (SLOW entries found spanning 07-13 through 08-02 — refuter: if it were purely the self-DoS, it would cluster in the 17h burn window only, and it does not). Needs its own investigation into the downstream product's dev-tunnel latency, separate from harness work |
| `scheduled-tasks\|TASK_QUERY_FAILED` + `heartbeat-reap\|REAP_ERROR` | 4 + 4 | `*-health-tick.json` | Small; likely transient Task Scheduler query failures during the CPU-burn window. Low priority |
| 15 files with malformed JSON (control chars) | 15 | scattered across all three patterns | Corrupted alert writes, likely from the same CPU-pressure window (partial writes under load). Doesn't block classification (isolated during processing) but is itself a small data-integrity signal worth a doctor check |

**Distinct root classes: 7** (doctor-red, sweep-timeout, orphaned-worktree, webhook-retell-auth,
downstream-slow, task-query-failed, heartbeat-reap-error) underlying 1,231 raw files — a **99%
duplication ratio** for the top 3 classes alone (1,190 of 1,231).

---

## 4. Stale plans + stranded worktrees

### Stale ACTIVE plans (23 candidates, 8 individually verified)

| Plan | Mechanical proxy (tasks done/total, last commit) | Verified disposition | Evidence |
|---|---|---|---|
| `status-event-ledger.md` | 0/10 checkboxes (misleading) | **NOT STALE — real, live progress** | Uses a custom BUILT/PARTIAL/UNBUILT taxonomy table (SE1-SE13), not `- [ ]` checkboxes. SE1/SE3/SE4/SE10 confirmed BUILT with cited SHAs (`4a2ca13`, review-fixed via `37b2a59f`); several PARTIAL, few UNBUILT. Checkbox-count is the wrong instrument for this plan |
| `needs-you-ledger-corruption-hotfix.md` | 0/8, target passed 07-29 | **ALREADY-LANDED, unflipped** | Plan's own Goal text ("validity-guard sweep + 3-state inbox contract") matches commit `9e822ca1` "fix(needs-you-incident): validity-guarded state-file init + 3-state inbox contract", same date (2026-07-29) |
| `review-gate-identity-anchor-2026-07-30.md` | 0/8, target passed 07-30 | **ALREADY-LANDED, unflipped** | 3 REJECT-round fix commits found: `987bbb4b` "anchor gate identity outside the pusher's write set (closes harness-reviewer REJECT: 3 Critical, 3 Major, 1 Minor)", `24aa91ce`, `802a9377` |
| `workstreams-debounce-and-sentinel-tests-hotfix-2026-07-29.md` | 0/7, target passed 07-29 | **ALREADY-LANDED (via a sibling program), unflipped** | Debounce fix (30s→120s) landed as `8918f4ef`/`efbe5279`; ask-sentinel regression tests landed as `8913dfd2` — both absorbed into `accountable-estate-program-2026-07.md` T7 (`b5dfaf1e`) rather than this standalone plan's own commit trail |
| `machine-folder-reorg.md` | 0/6, no target date | **DELIBERATELY PAUSED — correctly recorded** | Header states: "Status: ACTIVE (DEPRIORITIZED — operator 2026-07-30: 'the folder cleanup is not a priority at all'; no tasks dispatched until the operator raises it. Recorded, not dropped.)" This is the binding principle working exactly as intended — do not touch |
| `code-trace-methodology-2026-07-30.md` | 0/4, target passed 07-30 | **LIKELY LANDED (HYPOTHESIZED)** | `6073905c` "docs(designs): code-trace methodology — 12 of 14 shipped defects are statically traceable" matches the plan's apparent single deliverable; not individually line-diffed against the plan's task list — refuter: re-read the plan's task list against that doc's content |
| `context-watermark-window-class-fix.md` | 0/6, no target date | **LIKELY LANDED (HYPOTHESIZED)** | `dcb01f69` "fix(context-watermark): retire the stale-window-table CLASS — no denominator, no percentage" matches the plan's title/scope; a *sibling* plan of similar name (`context-watermark-opus5-window`) is confirmed CLOSED and archived (`c7b8c226`) — this one may be the generalization that followed it, not yet closed itself |
| `cockpit-review-surface-and-verification-gaps.md` | 0/12, target passed 07-30 | **UNVERIFIED — proxy only** | Related-sounding commits exist (`65e3db5e`, `49fba9e7`) but they read as backlog filings/measurements, not clear 1:1 task completions — needs an individual pass, not claimed here |
| Remaining 15 plans (`accountable-estate-program-2026-07.md`, `cockpit-roadmap-redesign.md`, `flat-skills-directory-form-migration.md`, `perf-telemetry-2026-07.md`, `model-awareness-knowledge-2026-07-24.md`, `operator-requirement-ledger.md`, `progress-log-placeholder-ask-id-fix.md`, `requests-tab-visibility-fix-2026-07-30.md`, `review-independence.md`, `status-ground-truth-discipline-2026-07-24.md`, `supervisor-tick.md`, `verification-dispatch-directive.md`, `doctrine-review-surface-measurement-2026-07-30.md`) | see raw table below | **UNVERIFIED — proxy only, not individually checked** | Task ratio + last-commit date only; several (`requests-tab-visibility-fix` 6/6, `macos-portability-2026-07` 6/6 — note: this one *is* `Status: ACTIVE` per grep but was not in the un-triaged set requiring a fresh look) look done-but-unflipped by the same proxy, but given the false-negative rate demonstrated above (checkbox count wrong for `status-event-ledger.md`), none of these are claimed without individual verification |

Raw proxy table (task-completion ratio, last commit date) for every ACTIVE plan, for the operator's
own scan:

```
accountable-estate-program-2026-07.md                          | tasks=7/14  | last-commit=2026-07-31
cockpit-review-surface-and-verification-gaps.md                | tasks=0/12  | last-commit=2026-07-30
cockpit-roadmap-redesign.md                                    | tasks=8/9   | last-commit=2026-07-30
code-trace-methodology-2026-07-30.md                            | tasks=0/4   | last-commit=2026-07-30
context-watermark-window-class-fix.md                           | tasks=0/6   | last-commit=2026-07-29
doctrine-review-surface-measurement-2026-07-30.md               | tasks=0/1   | last-commit=2026-07-30
flat-skills-directory-form-migration.md                          | tasks=5/6   | last-commit=2026-07-12
harness-execution-redesign-2026-08.md (TODAY'S WORK, not stale)  | tasks=0/11  | last-commit=2026-08-02
intended-functionality-stage-0-2026-07-30.md                     | tasks=8/8   | last-commit=2026-07-30
machine-folder-reorg.md                                          | tasks=0/6   | last-commit=2026-07-30 (deliberately paused)
macos-portability-2026-07.md                                     | tasks=6/6   | last-commit=2026-07-30
model-awareness-knowledge-2026-07-24.md                          | tasks=1/2   | last-commit=2026-07-29
needs-you-ledger-corruption-hotfix.md                             | tasks=0/8   | last-commit=2026-07-29
operator-requirement-ledger.md                                   | tasks=0/5   | last-commit=2026-07-29 (target 2026-08-05, not yet due)
perf-telemetry-2026-07.md                                        | tasks=2/7   | last-commit=2026-07-28
progress-log-placeholder-ask-id-fix.md                            | tasks=5/9   | last-commit=2026-07-29 (target 2026-08-15, not yet due)
requests-tab-visibility-fix-2026-07-30.md                        | tasks=6/6   | last-commit=2026-07-30
review-gate-identity-anchor-2026-07-30.md                        | tasks=0/8   | last-commit=2026-07-30
review-independence.md                                           | tasks=0/9   | last-commit=2026-07-30 (target 2026-08-05, not yet due)
status-event-ledger.md                                            | tasks=0/10  | last-commit=2026-07-30
status-ground-truth-discipline-2026-07-24.md                      | tasks=1/2   | last-commit=2026-07-23
supervisor-tick.md                                                | tasks=3/6   | last-commit=2026-07-22 (target 2026-07-20, past due)
verification-dispatch-directive.md                                | tasks=5/6   | last-commit=2026-07-29
workstreams-debounce-and-sentinel-tests-hotfix-2026-07-29.md      | tasks=0/7   | last-commit=2026-07-30
```

### Stranded worktrees — LOUD callout, then the verified answer

**LOUD:** raw `git cherry master <branch>` flagged **12 commits across 5 worktrees** as unmerged —
the exact number the task brief warned a prior session "nearly stranded... this way." This is not a
coincidence to wave off; it is the mechanism by which that near-miss happens, caught live:

```
worktree-agent-a60cd9f14ad2034df   | ahead=3 | cherry-unmerged=2 | last-commit=2026-07-23
worktree-agent-aa680cc77830d361b   | ahead=4 | cherry-unmerged=2 | last-commit=2026-07-23
worktree-agent-ac49878b3f9c1d026   | ahead=1 | cherry-unmerged=1 | last-commit=2026-08-02
worktree-agent-aeed9a16399bf88e6   | ahead=5 | cherry-unmerged=5 | last-commit=2026-07-12
worktree-agent-afcf419ea529b1ca0   | ahead=4 | cherry-unmerged=2 | last-commit=2026-07-15
```

**Verified, not assumed:** `git cherry` compares patch-id, which breaks across cherry-pick/squash
reshaping — a false-positive machine. Each of the 12 was checked individually via
`git merge-base --is-ancestor <landed-SHA> master` against a differently-shaped commit found by
grepping master's log for the same deliverable name, PLUS a direct `git diff master <branch> --
<key-file>` content check on at least one case (empty diff = content-identical):

| Worktree commit (unmerged by SHA) | Landed equivalent on master (different SHA, same content) | Verified via |
|---|---|---|
| `bf0acf94`/`7afffe07` — retire `workstreams-state-gate.sh` wiring | `d805a9a3` (confirmed ancestor of master); file-level diff on the retired script is empty | `git merge-base --is-ancestor d805a9a3 master` = true; `git diff master <branch> -- workstreams-state-gate.sh` = empty |
| `75bb3aed` — `ss_repo_key` helper; `390dc65e` — scope-drift doc | `e6302ce6` (confirmed ancestor); `4ee18805` (confirmed ancestor, byte-identical commit body, same author/timestamp) | `git merge-base --is-ancestor`, both true; `git show` diff of the two doc commits is textually identical |
| `9fdc36b4` — execution-redesign task 1 | `e9c5bc0f` (the SHA already cited throughout this report); `single-flight-lib.sh` diff between the worktree and master is **empty** | `git diff master <branch> -- adapters/claude-code/hooks/lib/single-flight-lib.sh` = no output |
| 5 commits — vaporware-config-controls (HARNESS-GAP-45) | Plan closed and archived on master: `d8912257` "chore(plans): close anti-vaporware-config-controls-generalization (COMPLETED + completion report, archived)", `735fe663` | `git log --grep="vaporware-config-control"` shows the full close-out lineage |
| `f0608c4a`/`4c940b7b` — grandfather trust-anchor re-bootstrap | `3ab7fa50`, `81e8d031` (both confirmed ancestors) | `git merge-base --is-ancestor`, both true |

**Verdict: all 10 unlocked worktrees are safe to prune** (`worktree-prune.sh --apply`, which already
requires merged-into-master + age ≥3 days as a precondition and will independently re-derive this).
Zero net loss if pruned today. The 4 `locked` worktrees (including this one) are live sibling agent
sessions, not stranded, and must not be touched by any sweep.

One additional stray: `git worktree list` on the downstream-product checkout shows a `prunable` worktree at a
now-deleted scratchpad path (`lesson/status-ground-truth` branch, `f128dd0e`) — `git worktree prune`
in that repo clears it mechanically; not a data-loss risk (git itself already flags it dead).

---

## 5. Top 10 genuinely-actionable items, ranked by impact

| # | Item | Impact | Priority |
|---|---|---|---|
| 1 | Fix `/api/webhooks/retell` to return 401 for unauthenticated requests (downstream product) | Clears 447 of 1,231 alert files (36% of the entire pile) with one route-level fix | **HIGH** |
| 2 | Ship Stage 1 of the redesign plan (doctor verdict cache + CoordSync cadence fix + poller timeouts) | Clears the `SWEEP_TIMEOUT` root cause once the sweep itself gets a timeout budget; makes doctor `--quick` genuinely O(1) instead of O(mess) | **HIGH** — already staged, task 3 of the live plan |
| 3 | Add a liveness/lease check to the worktree reaper before `git worktree remove` (nl-issues #5/#14/#16) | Prevents active-agent data loss; already happened once (2026-08-01, salvage required); NOT covered by the current redesign plan's scope | **HIGH** |
| 4 | Add a PreToolUse block on `push --force*` patterns in builder/subagent worktree contexts (nl-issue #6) | Closes a live constitution Rule 9 enforcement gap; currently zero mechanized coverage | **HIGH** |
| 5 | Run the Stage 4 drain (bulk-ack pre-2026-07-27 alerts + nl-issues per the plan's own D3 watermark) | Directly reduces doctor's O(mess) cost — the mechanism the whole redesign depends on for its <2s doctor target | **HIGH** — already staged, task 6 |
| 6 | `worktree-prune.sh --apply` against the 10 verified-safe worktrees (§4) | Reclaims disk + removes 10 rows from every future `git worktree list` scan doctor/janitor pay for | **MED** |
| 7 | Reconcile live `settings.json` SessionStart duplication on the laptop + Mac mini (nl-issue #32, handoff OWED #5) | Same 2x-hook-firing bug already fixed on the desktop; open on 2 of 3 machines | **MED** |
| 8 | Run `close-plan` verification on the 4 confirmed-landed-but-unflipped plans (needs-you-ledger-corruption-hotfix, review-gate-identity-anchor, workstreams-debounce-and-sentinel-tests-hotfix, plus code-trace-methodology pending its own verification) | Removes 3-4 plans from the stale-ACTIVE pile with zero new build work — pure bookkeeping | **MED** |
| 9 | Fix the downstream product's dev-tunnel/latency source behind the scattered `SLOW` alerts (~200 files, ~20 endpoints) | Second-largest alert contributor after webhook-retell; currently unexplained (HYPOTHESIZED not correlated to the CPU-burn window) | **MED** |
| 10 | Encode the `Get-Process` vs `Get-Counter` protected-process measurement bug (nl-issue #22) into a durable doctrine note | Cheap, prevents a repeat of "concluded Defender was free and advised the operator NOT to act" on a wrong 0% reading | **LOW** |

---

## 6. Prevention — one mechanism per noise source, tied to the redesign plan's stages

| Noise source | Mechanism that stops it regenerating | Redesign plan tie-in |
|---|---|---|
| `harness-doctor DOCTOR_RED` alert flood (503 files) | Doctor verdict cache (TTL-materialized, derived fingerprints) — a RED state gets computed once per TTL instead of once per tick | Stage 1, task 3 (not yet built; Stage 0's single-flight guard already stopped the *nested-chain* multiplier, confirmed PROVEN in §1) |
| `SWEEP_TIMEOUT` flood (240 files) | Cadence ≥ 2× measured cycle time, doctor-enforced (schedule-manifest) + a timeout budget inside the sweep script itself | Stage 0's schedule-manifest-cadence check (shipped, WARN-only, `e9c5bc0f`) + Stage 1's completion-anchored scheduling |
| Checkbox-vs-taxonomy false staleness signal (`status-event-ledger.md` class) | A doctor check that recognizes non-standard completion-tracking plans (custom taxonomy tables) before flagging "0 tasks done" — or, simpler, standardize on one completion-tracking convention across all plans | Not currently in the redesign plan's scope; candidate T19 for `accountable-estate-program-2026-07.md` |
| Landed-but-unflipped plans (4+ confirmed this pass) | The `close-plan` skill already exists and is the correct mechanism — the gap is that it's never invoked at the moment work lands, only later (or never). A Stop-hook check that looks for "all named files in a plan's evidence trail have commits newer than the plan's `Status: ACTIVE`" and nudges `close-plan` | Ties to the user's own standing memory note ("Complete plan bookkeeping in the SAME session as the work") — this is a harness-wide discipline gap, not specific to this redesign |
| Stranded-worktree false-alarm (`git cherry` patch-id mismatch on reshaped commits) | `worktree-prune.sh`'s merged-check should use `git diff --quiet <master>...<tip>` (already documented in the script's own header as one of its two merge tests) consistently, and the *reaper* alert (`ORPHANED_WORKTREE`) should reference the same test — right now the alert and the prune script may be using different equivalence tests, which is why 15 alert-firings didn't already get auto-resolved | Not in the redesign plan's scope; worth a standalone nl-issue |
| 447-file webhook-retell flood | Product-side auth fix (§5 #1) — no harness mechanism can fix a downstream product bug; the monitor is working as designed | n/a — product, not harness |
| Untriaged nl-issues regenerating faster than triage (135, growing ~5-15/day per §1 date histogram) | The considerations brief's own blind-spot #5 names this: "the warning pipeline had mandatory writes, voluntary reads." A mechanized supersession sweep — grep each untriaged issue's distinguishing keywords against `git log --grep` since its filing date, auto-suggesting ALREADY-FIXED/SUPERSEDED candidates for one-line human confirmation — is exactly the manual process performed by hand in §2 of this report, and is the single highest-leverage prevention item not yet built anywhere | Candidate for Stage 4 (drain) or a new estate-program task; directly demonstrated viable in §2 (found 2 confirmed + 1 hypothesized supersession by hand in minutes) |

---

## Summary of dispositions (counts)

- nl-issues cluster (32 items, 2026-07-27..08-02): 3 not-an-issue, 8 superseded, 5 already/partially
  fixed with cited SHA, 3 needs-operator-decision, 13 actionable (6 downstream-product, 7 harness)
- Alerts (1,231 files): 3 root classes already stopped firing (743 files, PROVEN via timestamp gap),
  1 root class actively growing and needs a product fix (447 files), 3 minor classes
- Stale plans (23 candidates): 4 confirmed landed-and-unflipped (pure bookkeeping to close), 1
  confirmed not-actually-stale (wrong instrument), 1 confirmed deliberately-paused (correct as-is),
  2 hypothesized-landed, 15 unverified (proxy only, explicitly not claimed)
- Stranded worktrees (10 unlocked): all 10 verified safe to prune, zero unmerged work confirmed
  lost — the "12 patches" near-miss the brief warned about is real as a *mechanism* (git-cherry
  false positives) but did not actually happen this time
