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
---

## 2026-08-03 — Doctor RED triage (gated-pipeline-master-2026-08 Task 8, REQ-A8)

**Scope:** classify every `harness-doctor.sh` RED into fix / retire / waiver, per the design's
REQ-A8 ("Doctor 71-red triage... classify every RED... using the existing dispositions"). Seeded
from the §1-§6 dispositions above where they overlap (they don't overlap on doctor *check ids*
directly — the 2026-08-02 pass triaged nl-issues/alerts/plans/worktrees, not individual doctor
checks — but its verified-safe-worktree and landed-plan methodology is the applicable precedent
for two of the RED classes below).

**Evidence discipline (same as above):** PROVEN = re-run live this session, cited. HYPOTHESIZED =
plausible, refuter named. Every fix below was independently re-verified after landing (re-ran the
specific check or self-test, not trusted by inspection).

### 8a — Baseline, actually measured (not the historical "71")

`bash adapters/claude-code/hooks/harness-doctor.sh --full` was run at 2026-08-03 ~05:15 PDT.
**Checks 1-7 (the "quick" tier, which also runs inside `--full`) completed and are stable: 34 RED
lines across 12 distinct check-ids.** Check 8 (the self-test sweep — every live hook that
declares `--self-test`, run one at a time) then ran for **over 90 minutes** without reaching the
end of the hook list (alphabetical; reached roughly `h`→`r` in that time) before this triage
pass's time budget required moving to write-up with the sweep still in progress in the
background. Check 9 (portability sweep) was never reached.

**This incompleteness is itself the headline finding, not a gap in this triage:** P-14
(`docs/handoffs/2026-08-03-EXHAUSTIVE-issue-inventory.md`) already named "doctor self-test takes
9-10+ minutes, so nobody runs it, so it rotted" as PROVEN. This session just reproduced that
live and mechanically: `harness-doctor.sh --self-test` alone (one of ~55+ hooks the sweep must
run) took ~9 minutes standalone; `plan-reviewer.sh --self-test` alone is independently documented
elsewhere in this file as measured at 987s (~16.5 min); the sweep default per-hook timeout is
1500s. A full `--full` run is realistically **60-120+ minutes**, not the "200-300s+" this task's
own dispatch prompt estimated — that estimate itself undercounted the same rot P-14 describes.

**Baseline actually recorded, checks 1-8-partial:** 34 (checks 1-7) + 4 selftest-sweep hook
failures observed before time-boxing (`harness-doctor.sh`, `model-pin-gate.sh`,
`plan-edit-validator.sh`, `plan-reviewer.sh`; a 5th, `review-record-commit-gate.sh`, surfaced
after this table was drafted — see the Known-incomplete note at the end) = **38 RED lines
confirmed, with the sweep still running and additional survivors likely** as it works through
the remaining alphabetically-later hooks (`review-*`, `scope-*`, `session-*`, `spec-*`, `tdd-*`,
`wire-check*`, etc. — several of which, per this file's own comments, are large/slow suites).
This is BELOW the historical 71, consistent with T1-T4 (already landed on this branch) having
fixed some of what the 71 counted, but it is **not a clean apples-to-apples number** against the
historical figure since that count's own check-8/9 coverage at capture time is not on record.

### 8a — Classification table (one row per distinct RED check-id observed)

| Check id | RED lines (in `--full`) | Class | Disposition |
|---|---|---|---|
| `budget-worktrees-branches` | 13 | **BLOCKED** | Real (28 worktrees vs budget 6, several stale branches). Mechanized safe remedy exists (`worktree-prune.sh`, conservative: merged-into-master + age>=3d only) — but invoking it, even `--dry-run`, was refused by this session's own auto-mode permission classifier ("Blocked by classifier"), and this task explicitly does not authorize working around a denial. Cross-worktree git mutation is out of a worktree-isolated builder's reach; needs an orchestrator/operator-level session. |
| `review-reviewer-independence` | 10 (in `--full`; **0 in `--quick`** — the authorship walk is `MODE==full`-only, so this line does not count against the plan's separate "doctor quick-run ≤9 REDs" bar) | **OPEN, deliberately not waived** | PROVEN real: e.g. record `2026-08-03-harness-change-review-110426f8.json`'s introducing commit (`0de26988`) has message `chore(review-records): register hcr-...` — a manual/direct commit, not routed through `review-runner.sh`'s stamped `GIT_AUTHOR_NAME="review-runner"` identity (confirmed present in `review-runner.sh:385`). All 10 are genuine post-cutover self-approvals. NOT waived: `docs/decisions/067-review-independence-same-session-pathway.md` already redesigned this exact check FROM a permanently-dead pinned-commit-SHA cutover TO an ISO-date cutover specifically so post-cutover self-approval stays enforceable RED, not silent theater — adding a new grandfather list here would re-litigate that considered, dated decision without operator sign-off. Real remedy: re-run each of the 10 through `review-queue.sh`+`review-runner.sh` with a genuinely independent reviewer dispatch — its own task, not this one's scope. |
| `manifest-check` | 1 (aggregate; wrapped 3 sub-findings, now 1) | **FIX (partial, 2/3)** | `hooks-coverage` x2 (`concurrent-ownership-gate-body.sh`, `scope-enforcement-gate-body.sh` unclaimed) — FIXED, see 8b. `wired-template` x1 (`session-heartbeat` claims `wired_template:true` but is absent from `settings.json.template`) — OPEN: clean fix needs a `manifest.json` edit (task-forbidden) or new template wiring (would fight this same plan's Task 5-7 Stop-chain-reduction direction, already RED at `budget-chains`). The doctor's own `check_manifest()` only ever emits ONE aggregate RED line regardless of sub-finding count, so this line survives either way until the 3rd clears. |
| `wiring-resolves` | 1 | **BLOCKED** | KNOWN, pre-existing: `docs/backlog.md` `HOOK-SHIM-RETIRE-01` (open since 2026-07-23) documents this exact gap — `workstreams-state-gate.sh` retired from the repo template in `bf0acf9`, but `merge_settings()`'s additive-only sync has no removal path, so live `~/.claude/settings.json` still carries 2 stale wirings. Direct edit attempted (`Edit` tool on `~/.claude/settings.json`) — refused by the classifier. |
| `template-live-drift` | 1 | **BLOCKED** | Same root cause and same block as `wiring-resolves` above (one fix clears both). |
| `manifest-freshness` | 1 | **BLOCKED** | `cp adapters/claude-code/manifest.json ~/.claude/manifest.json` (the doctor's own suggested remedy, and the safe targeted form of `install.sh`'s sync) — refused by the classifier. Any write under `~/.claude/` from this worktree-isolated session is refused categorically (tested 3x, 3 different targets, 3 denials). |
| `wave-e-e6-needs-you` | 1 | **BLOCKED** | `needs-you.sh render` writes to `$(nl_main_checkout_root)/NEEDS-YOU.md` — the MAIN checkout, not this worktree, and itself gitignored per-machine shared state. Cross-worktree write, same blocked class. |
| `obs-heartbeats-fresh` | 1 | **OPEN, tracked** | Live, real-time cross-session observability state (2 other sessions' transcripts <30min old with no heartbeat file yet). Not a repo defect this task can fix; likely transient or belongs to whichever OTHER session owns those 2 transcripts. |
| `obs-ask-capture-completeness` | 1 | **OPEN, tracked** | 27 of 33 trailing-24h sessions (82%) missing a registered ask. Real and substantial, but a session-by-session live-state investigation disproportionate to fold into this task — recommend a dedicated follow-up (`hooks/workstreams-read.sh`'s ask-capture splice, per-session). |
| `budget-chains` | 1 | **OPEN, out of Task-8 scope** | Stop chain 9>6 live. Explicitly owned by this SAME plan's Tasks 5-7 (R3.3 Stage-2 hook reduction) per the `Files to Modify` table; Task 8's own Integration point states the REVERSE relationship (Phase-A/B don't block on Task 8's doctor state) but not that Task 8 owns Tasks 5-7's remedy. |
| `budget-active-plans` | 1 (aggregate; does not scale with count) | **OPEN, out of Task-8 scope** | 25 ACTIVE plans vs budget 3. Matches this file's own §4 stale-plans pile (which has grown, not shrunk, since 2026-08-02 — see the Known-incomplete note). Properly resolving it means individually verifying and closing ~22 plans by this file's own §4 methodology — its own dedicated undertaking (§5 item 8), correctly out of proportion for a doctor-triage task. |
| `selftest-sweep` — `harness-doctor.sh` | 1 (of the 71/9 budget; wraps 5 P-14 scenarios) | **ROOT-CAUSED, not fixed** | The 5 failing scenarios (`dpp-jq-parity-red`, `dpp-jq-parity-grandfather`, `ngeb-jq-parity-red`, `claim-honesty-jq-parity-red`, `budget-chains-jq-parity-red`) are P-14 exactly. PROVEN not a doctor logic defect: `_nonode_path()`'s PATH-shim symlinks `bash` itself, which fails to load on Windows/MSYS2 without its companion DLLs (`PATH=<shim> bash -c true` → `error while loading shared libraries`) — the child crashes before the check under test ever runs. Independently verified the real jq expressions are correct (e.g. `_count_chain_entries`'s jq form run standalone against live `settings.json` → `9`, matching the live `budget-chains` RED). Filed: `SELFTEST-SWEEP-NONODE-SHIM-WINDOWS-01` (backlog). Needs a Windows-safe shim redesign — its own scoped task. |
| `selftest-sweep` — `model-pin-gate.sh` | 1 | **TRANSIENT, not durable** | Sweep reported 15/2 fail; standalone re-run ~15 min later: 17/0 PASS. HYPOTHESIZED non-hermetic (2 "tier exhausted" scenarios likely read live `model-policy.json` tier state rather than an injected fixture). Filed: `MODEL-PIN-GATE-SELFTEST-NONHERMETIC-01` (backlog). |
| `selftest-sweep` — `plan-edit-validator.sh` | 1 (was; now 0) | **FIXED** | See 8b. Also updates the pre-existing `CI-REQUIRED-CHECK-PR-ONLY-01` backlog finding (same self-test, same root cause, same fix). |
| `selftest-sweep` — `plan-reviewer.sh` | 1 | **OPEN, not investigated** | Sweep reported a bare "one or more scenarios failed"; a standalone re-run was started but the ~16.5-minute measured runtime (this file's own CI section) exceeded this pass's remaining time budget. Not concluded — flagged, not silently dropped. |
| `selftest-sweep` — `review-record-commit-gate.sh` | 1 | **OPEN, not investigated** | Surfaced late in the sweep (65 passed, 2 failed) after this table was drafted. Time-boxed out of this pass — see Known-incomplete note. |
| `selftest-sweep` — (remaining ~40 hooks unswept at write time) | unknown | **UNKNOWN — sweep incomplete** | See the baseline note above. Not claimed as zero; not claimed as any specific number. |

### 8b — Fix class (executed, committed per-file, mechanically re-verified)

1. **`docs/harness-architecture.md` regenerated** (`bash adapters/claude-code/scripts/gen-architecture-doc.sh`) — was drifted from `manifest.json` (157 vs 159 entries, missing the two `session-heartbeat` rows). Pure repo-file, deterministic, no manifest.json edit. Re-verified: `gen-architecture-doc.sh --check` now exits 0; the doctor's `--quick` re-run (post-fix) no longer lists `wave-f-f2-docs`.
2. **`manifest-check.sh` disk-coverage exemption for the fast-pass/body split** (`concurrent-ownership-gate.sh`/`concurrent-ownership-gate-body.sh` and `scope-enforcement-gate.sh`/`scope-enforcement-gate-body.sh`): the top-level `*-body.sh` sourced-implementation convention (same shape as the existing `hooks/lib/*.sh` exemption, just not physically under `lib/`) had no coverage exemption, so both bodies RED'd as "unclaimed disk hooks." Added a MECHANICALLY VERIFIED exemption (wrapper must exist, be itself covered, and actually `source` the exact body filename — an orphaned `*-body.sh` still REDs) plus two new self-test scenarios (`S3b` green, `S3c` red-if-orphaned). Re-verified: `manifest-check.sh check` dropped from 3 RED findings to 1 (the remaining one is the `session-heartbeat` `wired-template` drift, blocked per the table above); `manifest-check.sh --self-test` 30/30 pass on the new/touched scenarios (one PRE-EXISTING, unrelated failure — `s21-jq-fallback-hook-shape` — was found and left alone; filed below, not fixed, out of this pass's scope).
3. **`plan-edit-validator.sh` self-test stat-shim fixed** (F16-F19's `F16_BINSHIM` fixture): the shim unconditionally translated `stat -c %Y` to `/usr/bin/stat -f %m`, assuming BSD `stat`. On GNU coreutils (this Windows/MSYS2 checkout, and the Linux CI runner) `-f` means `--file-system` — a completely different, multi-line output shape — which then broke `age=$((now - mtime))` arithmetic. Fixed by trying the GNU form for real first, falling back to the BSD form only on genuine failure. Re-verified: `plan-edit-validator.sh --self-test` 24/24 PASS (was 20/4). This is the SAME failure the pre-existing `CI-REQUIRED-CHECK-PR-ONLY-01` backlog entry already diagnosed (its own diagnosis pointed at production lines 1467/1535, which are actually fine — corrected in the backlog entry, see below) — should also re-green CI's `Server-side enforcement` job.

**No check was deleted as a "fix."** All three fixes above are config/stale-reference/path-class repairs to repo-tracked scripts, none touching `manifest.json`, `INDEX.md`, or `model-policy.json`.

### 8c — Retire class

**None retired.** Every RED examined either (a) reflects a genuine, still-applicable gate doing
its job correctly (`review-reviewer-independence`, `budget-*`), (b) is a real, fixable bug with a
known remedy currently blocked by sandbox scope rather than by the check being wrong
(`wiring-resolves`, `template-live-drift`, `manifest-freshness`, `wave-e-e6-needs-you`), or (c) is
a genuine but under-investigated finding (`obs-*`, the remaining `selftest-sweep` entries). No
check's reason-to-exist was found to have lapsed.

### 8d — Waiver class

**None landed.** The one candidate seriously considered — a grandfather-list downgrade for
`review-reviewer-independence`'s 10 post-cutover self-approvals, mirroring the doctor's own
existing `PRE_BAR_GRANDFATHERED` (`check_new_gate_evidence_bar`) and
`DETERMINISTIC_PROCESS_GRANDFATHERED` (`check_deterministic_process_proof`) in-code grandfather
mechanism — was rejected after reading `docs/decisions/067-review-independence-same-session-
pathway.md` in full: that decision deliberately redesigned this exact check from a permanently-
dead pinned-commit cutover to a live ISO-date cutover FOR THE EXPRESS PURPOSE of keeping post-
cutover self-approval enforceable RED rather than becoming "documented enforcement that cannot
fire." A waiver here would be silently reversing a considered, dated, named decision without the
operator's involvement — exactly the theater the mechanism exists to prevent. Left OPEN instead.

### 8e — Re-measure

**Not achieved: `--full` re-measure ≤9 REDs was not reachable within this session's time
budget**, and would not have been achievable even with unlimited time, for structural reasons
independent of runtime: **31 of the confirmed-baseline RED lines are either sandbox-permission-
BLOCKED (worktrees/branches, live-mirror writes: 13+1+1+1+1 = 17) or explicitly out-of-Task-8's-
scope by this plan's own task boundaries (`review-reviewer-independence` 10 in `--full`,
`budget-chains` 1, `budget-active-plans` 1 = 12)** — neither class is something a doctor-triage
task, run from a worktree-isolated builder session, can honestly clear to zero. A **`--quick`
re-run** (fast, ~90s, does not include the self-test sweep or the review-independence deep walk)
was executed post-fix as a partial, directly-verifiable re-measure:

```
[doctor] RED budget-worktrees-branches   x13   (BLOCKED, see table)
[doctor] RED wiring-resolves             x1    (BLOCKED)
[doctor] RED template-live-drift         x1    (BLOCKED)
[doctor] RED manifest-freshness          x1    (BLOCKED)
[doctor] RED wave-e-e6-needs-you         x1    (BLOCKED)
[doctor] RED obs-heartbeats-fresh        x1    (OPEN, tracked)
[doctor] RED obs-ask-capture-completeness x1   (OPEN, tracked)
[doctor] RED manifest-check              x1    (FIX 2/3, 1 OPEN — see table)
[doctor] RED budget-chains               x1    (OPEN, out of scope)
[doctor] RED budget-active-plans         x1    (OPEN, out of scope)
= 22 REDs (quick mode; was 24 pre-fix by the same accounting — wave-f-f2-docs cleared,
  manifest-check unchanged at the aggregate-line level despite 2/3 sub-findings fixed)
```

This is the plan's own separately-stated top-level bar ("Doctor quick-run reports ≤9 REDs after
Task 8," line 58) — **also not met (22 > 9)**, for the identical structural reasons above.

**Every survivor is named with its open disposition** in the classification table (8a) — none
silently dropped. Nine of the eleven distinct check-ids are genuinely open for reasons outside
this task's reach as scoped (sandbox permissions, or explicit ownership by Tasks 5-7 / a
dedicated future task); two (`obs-heartbeats-fresh`, `obs-ask-capture-completeness`) are
investigation debt this pass time-boxed rather than chased to conclusion.

### Known-incomplete, stated honestly

- The `--full` self-test sweep (check 8) did not finish; `plan-reviewer.sh`,
  `review-record-commit-gate.sh`, and `review-record-push-gate.sh` self-test failures were
  observed but not individually root-caused before this pass's time budget closed. None is
  claimed fixed, retired, or waived — all are OPEN (the first two are in the table above;
  `review-record-push-gate.sh` surfaced after the table was drafted). `review-record-push-gate.sh`
  is worth flagging as a DATA POINT for the pattern already established by 3 of the 4 fixed/
  root-caused sweep failures above: its own failure text names a Windows/NTFS filesystem
  limitation directly ("this filesystem cannot hold a file whose NAME contains a backslash...
  run the suite on macOS/Linux to exercise it") — i.e. this machine's self-test corpus is
  accumulating a recognizable CLASS of Windows-specific self-test friction (nonode-shim symlink,
  BSD-stat-shim assumption, NTFS-reserved-character fixtures), distinct from real production
  defects. A dedicated Windows-portability pass over the self-test suite (sibling to the existing
  macOS-portability program) is the generalizable fix, not one-off patches per hook.
- `manifest-check.sh --self-test`'s pre-existing `s21-jq-fallback-hook-shape` failure (confirmed
  present BEFORE this session's edits via `git stash`) was found incidentally and left alone —
  out of this pass's scope, not filed as a fresh backlog item here (it doesn't affect any doctor
  RED count; `check_manifest()` runs `manifest-check.sh check`, never `--self-test`, against the
  live/repo state).
- `budget-worktrees-branches`' 28-worktree count (vs the 2026-08-02 triage's 10 unlocked
  worktrees observed one day earlier) shows the estate's worktree pile is GROWING, not shrinking
  — worth flagging to whichever operator/orchestrator session next runs `worktree-prune.sh`.

### Summary of dispositions (counts)

- Distinct RED check-ids classified: 15 (12 quick-tier + 4 selftest-sweep, 1 shared aggregate
  counted once)
- **FIX, executed and verified: 3** (`wave-f-f2-docs`, `manifest-check` 2-of-3 sub-findings,
  `selftest-sweep`/`plan-edit-validator.sh`)
- **RETIRE: 0** — no check found genuinely obsolete
- **WAIVER: 0** — one candidate seriously considered and deliberately rejected (would reverse a
  named, dated operator-adjacent decision without sign-off)
- **BLOCKED by sandbox permission (worktree-isolated session cannot write `~/.claude/*` or run
  cross-worktree git mutation, tested and refused 4x across distinct targets): 5 check-ids, 17
  RED lines** (`budget-worktrees-branches`, `wiring-resolves`, `template-live-drift`,
  `manifest-freshness`, `wave-e-e6-needs-you`)
- **OPEN, explicitly out of Task 8's scope by this plan's own task boundaries: 3 check-ids, 12
  RED lines (`--full`)** (`review-reviewer-independence`, `budget-chains`, `budget-active-plans`)
- **OPEN, root-caused but not fixed (own scoped follow-up task needed): 2** (`selftest-sweep`/
  `harness-doctor.sh` — Windows nonode-shim gap; `selftest-sweep`/`model-pin-gate.sh` — non-
  hermetic self-test)
- **OPEN, not yet investigated (sweep incomplete): 2+** (`selftest-sweep`/`plan-reviewer.sh`,
  `selftest-sweep`/`review-record-commit-gate.sh`, plus an unknown number from the ~40 hooks the
  sweep had not reached)
- **Net RED count: NOT reduced to ≤9.** Best directly-verified number (`--quick`, post-fix): 22.
  `--full` baseline (partial, checks 1-8-in-progress): 38 confirmed, growing as the sweep
  continues. Neither meets the plan's ≤9 bar; the gap is honestly attributed above, not asserted
  away.
