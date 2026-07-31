# Harness Self-Eval — 2026-07-30

**Generator:** `adapters/claude-code/scripts/harness-evaluator.sh` (System 2 of the drift-backlog + harness-evaluator pair, per `docs/plans/drift-backlog-and-harness-evaluator.md`).

**Read-only.** This packet is descriptive, not prescriptive. Recommendations are for Misha to review and triage. The evaluator never auto-updates rules, hooks, or agents.

**Inputs read:** drift-backlog (System 1 output), scope-waivers, acceptance-waivers, autonomous-done attestations, dag-approved waivers, close-plan force-overrides, observed-errors-overrides, unresolved-stop-hooks log, failsafe-retirements, failure-mode catalog, HARNESS-GAP backlog, prior weekly packets (own track record).

**Mode:** full

---
## 1. Bypass tally (by mechanism)

How many times each gate's escape hatch was authored in the last 60 days.
High counts on a single gate mean either (a) the gate fires too aggressively,
or (b) the work it gates is genuinely orthogonal more often than expected.
Either way the evaluator surfaces it for Misha's judgment.

| Gate | Bypass count | Most-recent date | Top plan(s) bypassing |
|---|---|---|---|
| `scope-enforcement-gate.sh` | 0 | — | — |
| `product-acceptance-gate.sh` | 0 | — | — |
| `narrate-and-wait-gate.sh` | 0 | — | — (session-scoped) |
| `dag-review-waiver-gate.sh` | 0 | — | — (session-scoped) |
| `close-plan.sh --force` | 0 | - | — |
| `observed-errors-gate.sh` | 0 | — | — |

## 2. Unresolved-stop-hooks log (retry-guard downgrades)

When a Stop hook fires the same failure signature 3+ times in one session,
the retry-guard library downgrades the block to a warn and appends to
`.claude/state/unresolved-stop-hooks.log`. High counts indicate gates that
are genuinely unresolvable mid-session OR are firing false-positively.

**Total log entries:** 0

**By hook (top 10):**

| Hook | Count | Unique-signature count |
|---|---|---|

**Interpretation hints (NOT auto-recommendations):**
- High-count + low-unique-sig: same failure recurring across sessions — likely a real ongoing gap (drift, missing prereq).
- High-count + high-unique-sig: gate fires across diverse contexts — may indicate over-eager triggering.
- Single-session bursts (count = N per session): retry-loops within one session — usually a blocker the agent couldn't resolve.

## 3. Drift backlog (System 1)

**Total unique asks classified:** 130
**Drift (no artifact, > 14 days):** 0
**Satisfied (artifact found):** 0
**Recent-pending (< 14 days):** 10

**Oldest 10 drift items (highest signal — Misha asked, no shipped artifact):**

| Age (d) | Reps | Trigger | Ask (truncated) |
|---|---|---|---|

**Items repeated 2+ times across sessions (Misha re-asked — strong drift signal):**

_None in this scan window._ (May indicate (a) Misha doesn't re-ask, (b) dedup is too aggressive, (c) classification is hiding repeats.)

## 4. Top-3 lists (Misha's review packet)

Per the design constraint: every recommendation cites ≥3 evidence pointers.
Recommendations are descriptive, NOT auto-applied.

### 4.1 Top 3 rules with highest bypass count

1. scope-enforcement-gate.sh — 0 bypasses (clean)
2. product-acceptance-gate.sh — 0 bypasses (clean)
3. narrate-and-wait-gate.sh — 0 bypasses (clean)

### 4.2 Top 3 newly-surfaced drift items (System 1)

### 4.3 Top 3 rules with KNOWN-weak enforcement (from harness documentation)

These are explicitly documented as residual gaps by the harness itself (`rules/vaporware-prevention.md` 'Missing from the enforcement map' + 'Residual gap'):

1. **`claim-reviewer` agent — self-invoked, can be skipped**
   - Evidence 1: `rules/vaporware-prevention.md` "Residual gap (honest)" section explicitly: "Verbal vaporware in conversation is not mechanically blocked. Claude Code has no PostMessage hook. `claim-reviewer` is self-invoked and can be skipped."
   - Evidence 2: `rules/vaporware-prevention.md` table marks this row as "self-invoked (residual gap)"
   - Evidence 3: this is the canonical case of "rule that didn't prevent incidents but couldn't be bypassed because it never fired"
   - **Recommendation (descriptive):** until Claude Code ships a PostMessage hook, the only mitigation is the file:line-citation discipline + Misha's interrupt authority. The evaluator should track how often `claim-reviewer` IS invoked vs the number of feature-claim-bearing assistant messages.

2. **`tool-call-budget.sh --ack` attestation is bypassable by direct file write**
   - Evidence 1: `rules/vaporware-prevention.md` "Missing from the enforcement map" explicitly: "A builder could Write that file directly without invoking `plan-evidence-reviewer`."
   - Evidence 2: Friction raised (need sentinel format knowledge) but "not cryptographically closed"
   - Evidence 3: "Accepted residual risk for Gen 4"
   - **Recommendation (descriptive):** evaluator can track frequency of attestation-file writes WITHOUT a paired plan-evidence-reviewer invocation in the same session.

3. **`review-finding-fix-gate.sh` reads stale `.git/COMMIT_EDITMSG` (HARNESS-GAP-23)**
   - Evidence 1: `docs/backlog.md` HARNESS-GAP-23 documents this as a known issue (added 2026-05-06)
   - Evidence 2: this very System 2 build hit it: the gate matched ADR-031 from a previous unrelated commit
   - Evidence 3: workaround is to clear .git/COMMIT_EDITMSG before invoking `git commit -m` — undocumented and undiscoverable for new sessions
   - **Recommendation (descriptive):** fix HARNESS-GAP-23 by reading the actual staged-commit message via stdin rather than the stale file

### 4.4 Top 3 agents to watch for discipline degradation

These are heuristic flags — agents that have shown patterns of cutting corners under pressure. Cross-reference with future calibration entries at `.claude/state/calibration/<agent-name>.md` per `rules/calibration-loop.md`.

1. **`plan-phase-builder` — finding-workarounds-to-mark-complete**
   - Evidence 1: agent's own `## Counter-Incentive Discipline` section names "training-induced bias toward call-it-done shortcuts"
   - Evidence 2: `docs/failure-modes.md` FM-001..N catalog includes builder shortcuts as a recurring class
   - Evidence 3: lessons doc `docs/lessons/2026-05-22-fm-001-misdiagnosis.md` chronicles a multi-day builder-shortcut chain
   - **Recommendation (descriptive):** instrument task-verifier dispatches to check whether builder return shape includes hedge phrases ("partial", "deferred", "out-of-scope") at higher than expected rate

2. **`task-verifier` — pass-by-default on mechanical tasks**
   - Evidence 1: `Verification: mechanical` early-returns PASS without running full rubric (per `rules/risk-tiered-verification.md`)
   - Evidence 2: 92% of harness-dev tasks are `Verification: mechanical` — the dispatch rarely runs
   - Evidence 3: Calibration substrate at `.claude/state/calibration/task-verifier.md` is intentionally seeded for this exact class
   - **Recommendation (descriptive):** sample-audit some mechanical-class PASS verdicts manually to confirm they hold

3. **`end-user-advocate` — not dispatchable in Dispatch env (HARNESS-GAP-34)**
   - Evidence 1: `docs/backlog.md` HARNESS-GAP-34 (added 2026-05-15) documents that the agent cannot run in remote-Dispatch sessions
   - Evidence 2: the runtime acceptance loop therefore can't fire when the orchestrator is remote
   - Evidence 3: every acceptance-exempt: true on a Dispatch-built plan masks an inability, not a legitimate exemption
   - **Recommendation (descriptive):** count Dispatch-attributed plans with acceptance-exempt: true vs total; high ratio indicates the gap is biting

## 5. Own track record (recommendation outcomes)

**Prior packets found: 1**

_TODO (next iteration): for each recommendation in the most-recent prior packet, search git log between then and now for commits referencing the recommendation. Mark acted-on / ignored / partially-shipped._

Until that's implemented, Misha reads prior packets manually and updates them with status notes.

## 6. Failsafe retirements

_No failsafe-retirements.md log present._

## 7. Pointers + freshness

**Drift backlog generated:** 2026-07-30T00:28:33Z
**Drift backlog window:** `recent-days` setting last used (check script invocation)
**State dir:** `.claude/state/` (gitignored)
**Failure-mode catalog:** `docs/failure-modes.md` (38 entries)
**HARNESS-GAP backlog entries:** 84

---

**Next packet:** TBD per Misha's review cadence. Schedule via `/schedule` or cron (see plan task 6 for placeholder).

**Honesty note:** this packet is v1. Known limitations:
- Section 4.4 'agents to watch' is currently heuristic-seeded, not data-driven. Future iteration ties to `.claude/state/calibration/` per `rules/calibration-loop.md`.
- Section 5 'own track record' is placeholder until 2+ packets exist for cross-reference.
- Drift items have false-positive rate — see plan's "Known v1 limitations".


---

## Reviewer Notes (harness-evaluator judgment layer)

> Watchdog: harness-evaluator. Watchdog-for-the-watchdog: Misha. These are inputs to your triage, not decisions. Read-only — no harness files were modified. The script-generated body above is retained verbatim; note that its zeros are WRONG-SUBSTRATE artifacts, not clean-week evidence (see Honesty note — the assembly script reads state paths that moved out from under it).

**Period audited:** the 2026-07-28/29 hardening wave on `wip/harness-hardening-2026-07-29` (fork b4f9916 → tip a41b0e1 at audit time, 72+ commits since 07-27), plus the live state at `~/.claude/state/`. Prior packet: `docs/reviews/2026-05-25-harness-self-eval.md` — a 9-week gap on a weekly cadence (see Section 5).

### Mechanism verdict table (design × operating, with evidence line)

| Mechanism | Design | Operating verdict | Evidence line |
|---|---|---|---|
| `review-record-commit-gate.sh` | effective (post-9828ea1: generated 11,760-cell corpus, both interpreters) | **operating-effective at the master boundary; ERODING at change-time cadence** | it blocked the merge and forced the sweep (Q5, `docs/reviews/2026-07-29-operator-five-questions.md`); but 77 content-changed in-surface files sat uncovered at d1465f0 (measurement in F3) because the session dispatched zero reviewers |
| `scope-enforcement-gate.sh` (pre-fix) | effective on paper | **was THEATER on stock macOS** | `declare -A` at :1849 → error + exit 0 under bash 3.2; its self-test re-invoked via PATH bash 5.3, so "35/0 on 3.2" was false-green (19fe474; SCRATCHPAD "THREE GATES" block). Post-fix: 40/0 on both interpreters |
| `concurrent-ownership-gate.sh` (pre-fix) | effective on paper | **was THEATER on macOS** | empty `date -d` cutoff → loaded ZERO claims; scenario 12 passed because two failures cancelled (f633e53 commit body, M4) |
| all git hooks on this Mac (pre-fix) | effective on paper | **were THEATER** | mode 644 — git silently ignored every hook (0b767aa) |
| `install.sh` / `session-start-auto-install.sh` (pre-fix) | defective | **actively harmful — destroyed own source** | hooks/lib deleted twice; 27 committed files overwritten at 09:41:43 (`~/.claude/state/auto-install-log-20260729-094143.txt`); guards landed 4e29dc6 + b8dd674, proven 54-updated → 0-updated/326-self-sync-skipped, kill-switch `~/.claude/local/no-auto-install` |
| needs-you ledger + inbox | defective | **dark ~2 days, resolved** | 1-byte ledger (mtime 2026-07-27 20:46) from unguarded `${links[@]}` under bash-3.2 set -u; fixed 9e822ca + d1465f0 with a 3-state inbox contract so "zero" can no longer mask "broken" |
| self-test corpus as a control layer | high design trust | **ERODING — measured false-green class** | ≥6 proven instances + a ~20-host inventoried class (F2) |
| task-verifier / end-user-advocate layer | effective | **operating-effective this period** | FAIL verdicts held under pressure: P1 held FAIL (026184f) until a real fix (e6720aa); advocate returned 5/9 FAIL (e8c74cb); M5 verifier refuted 5 builder numeric claims (SCRATCHPAD "M5 VERIFIER FINDINGS") |
| problems-persist / nl-issue pipeline | effective (ff9d728: inline IDs, Stop-WARN 83/0, operator auto-file 32/0) | **filing arm operating-effective; triage arm SATURATED** | 61 ledger rows, 60 untriaged (threshold 5), auto-escalation row NL-ISSUES-TRIAGE-20260730 self-filed (8973f17) |
| verification-dispatch (V1-V5) | landed + verified (cd1aa93) | **insufficient evidence** — the commit-time carrier (V6) is deferred, so operating-effectiveness cannot yet be tested | plan `docs/plans/verification-dispatch-directive.md` V6 "DEFERRED, NOT IN THIS PLAN" |
| `estate-attribution-check.sh` (new) | effective | **too new to score; Goodhart-watch flagged** | informational exit-0 tool; its denominator already has a filed gap (ESTATE-METRIC-BRANCH-WITHOUT-WORKTREE-GAP-01, nl-issues 2026-07-29T22:42) |
| retry-guard / unresolved-stop-hooks substrate | effective | **UNREADABLE — 100% fixture pollution** | 178/178 entries in the main checkout's `.claude/state/unresolved-stop-hooks.log` carry synthetic session=st1/st5 IDs (89 each), all dated 2026-07-29/30, retry counts to 17 — FM-035's exact signature, live |
| harness-evaluator (this function) | drifted | **ERODING into irrelevance — restarted by this packet** | no packet since 2026-05-25; assembly script reads dead substrate paths (Honesty note) |

### Top finding (highest leverage)

**Master — the deploy source of truth — still carries every control this week proved broken, while the fixes live only on the wip branch.** `session-start-auto-install.sh` continuously syncs live machines from origin/master (CLAUDE.md, "Harness source of truth"), and origin/master at 6ffe534 contains: the pre-guard install/auto-install carriers (the ones that deleted hooks/lib twice and overwrote 27 committed files — `~/.claude/state/auto-install-log-20260729-094143.txt`), the `declare -A` scope gate that exits 0 on stock macOS (fixed only at 19fe474 on the branch), the `date -d` fail-open trio (fixed only at f633e53), AND a stale verification flip — 7506451 flipped perf-telemetry P1/P2 to PASS on master on 07-28, which the branch's targeted re-check REFUTED (P1 held FAIL at 026184f until the real defect was fixed at e6720aa, re-verified f09af28). Every hour of divergence extends the window in which a fresh SessionStart on a mis-configured machine deploys the destructive carriers, and in which master asserts a verification state the evidence has overturned. Leverage: one merge — already sequenced as step 4 of the SCRATCHPAD away-plan, reversible by revert — closes an urgent live-risk class plus a §1-honesty defect on master simultaneously: impact high × confidence high ÷ cost low. Concrete first action: re-run the F3 coverage join at the current tip to confirm the review delta is closed, then execute the already-planned merge.

### Findings (leverage-ordered)

#### F1 — Fixes stranded on-branch while master remains the auto-deployed truth
- **Class:** `fix-landed-but-not-deployed` (branch/master divergence under a continuous-deploy carrier)
- **Design/Operating verdict:** the deploy pipeline is design-effective (it really does sync from master — that is the exposure); the CONTROLS on master are operating-ineffective because they are the pre-fix versions
- **Severity:** urgent
- **Confidence:** high
- **Claim:** PROVEN — origin/master tip 6ffe534 (fetched this session) lacks 19fe474, f633e53, 0b767aa, 4e29dc6, b8dd674 (all present only in the branch range b4f9916..a41b0e1); 7506451 "verify(perf-telemetry): P1+P2 flipped" is on master (07-28 21:16) while 026184f → e6720aa → f09af28 on the branch supersede it with a FAIL-then-fixed-then-PASS chain
- **Shadow-metric check:** the headline "all four review verdicts fixed + landed" (SCRATCHPAD) is true ON THE BRANCH; its shadow — "what does a machine syncing master actually run?" — contradicts it until the merge
- **Evidence:** (1) CLAUDE.md "Harness source of truth" (auto-install syncs live from origin/master); (2) origin/master log = 6ffe534 / 8d07f7a / 9708ced / b5dfaf1 / 7cc1447 — none of the fix SHAs; (3) SCRATCHPAD away-plan step 4 explicitly sequences the merge, so this is a timing risk, not a forgotten one
- **Sweep query:** count of fix-commits in origin/master..wip/harness-hardening-2026-07-29 (each is a defect still live at the deploy source)
- **Recommendation (for Misha's triage):** consider treating the merge as the closing action of this wave once the sweep's coverage delta is confirmed closed. Trigger that fired: gate-inertness fixes >24h old with the deploy source still unpatched, plus one refuted verification flip live on master.
- **Week-over-week:** new

#### F2 — The self-test layer has a measured false-green CLASS, not isolated bugs
- **Class:** `self-test-false-green` — five sub-shapes: interpreter-identity lies, vacuous text-match oracles, cancelling failures, environment-dependent verdicts, real-state pollution
- **Design/Operating verdict:** design-effective as a corpus (suites exist, run, and back every "N/0" claim); operating-INeffective as a CONTROL in at least 6 proven instances — a green suite did not mean the control worked
- **Severity:** concerning (the day's fixes remediated the proven instances; the residual class is inventoried but unfixed)
- **Confidence:** high
- **Claim:** PROVEN per instance: (a) `hooks/lib/perf-ledger.sh:226` reported the PATH-resolved interpreter while running under /bin/bash 3.2 — the self-test lied about its own interpreter (e6720aa); (b) `scope-enforcement-gate.sh:1849` — "35/0 on 3.2" was false because the suite re-invoked itself via bare `bash` = PATH 5.3 (19fe474); (c) concurrent-ownership scenario 12 passed only because the date-d bug had disabled the claim scan — two failures cancelling into green (f633e53); (d) 15 hosts' suites wrote the operator's REAL ~/.claude state, proven by mutation (139670e); (e) admission-lib Scenario 16b was a TEXT match that matched comments — fake RED proofs (5f0eb73; SCRATCHPAD); (f) close-worktree verdict flipped 17/0 vs 15/2 depending on HOW the suite was invoked (fc94550). CLASS extent HYPOTHESIZED at ~20 hosts (nl-issues row 2026-07-30T00:29 names the grep) — REFUTED IF running those suites under forced /bin/bash 3.2 yields verdicts identical to PATH-bash runs.
- **Shadow-metric check:** the headline "suite N/0" has as its shadow "N/0 under WHICH interpreter, from WHICH cwd, against WHICH state dir" — that shadow contradicted the headline six times this week. Additional PROVEN pollution found by this audit: the main checkout's `unresolved-stop-hooks.log` is 178/178 entries with fixed synthetic session IDs st1/st5 (89 each, latest 2026-07-29T22:57Z, retry counts to 17) — a self-test accumulating real retry-guard state, FM-035's exact signature, ongoing AFTER 139670e's sandbox arming (HYPOTHESIZED cause: worktree copies still running pre-fix code, or a host 139670e missed; REFUTED BY a clean log after one fresh --self-test run at tip).
- **Evidence:** e6720aa; 19fe474; f633e53; 139670e; 5f0eb73; fc94550; nl-issues rows 2026-07-30T00:29 (x2) and 2026-07-29T15:25; the st1/st5 log measurement above
- **Sweep query:** the nl-issue row's own inventory grep for bare self-reinvocation across hooks/*.sh; plus a uniq count of session=st* IDs in unresolved-stop-hooks.log for pollution recurrence
- **Recommendation (for Misha's triage):** the class fix (re-invoke via "$BASH", sandbox state dirs per FM-035) is already inventoried in the nl-issue rows — consider promoting the CLASS to a docs/failure-modes.md entry (none of FM-035..038 covers interpreter-identity) so builders inherit it. Trigger: ~20 hosts named by one grep; 3 of the 6 proven instances were BLOCKING gates.
- **Week-over-week:** new (the prior packet had no self-test findings at all — this is the period's largest single discovery)

#### F3 — Review-record gate: held the boundary, lost the cadence; the records index is structurally failure-blind
- **Class:** `gate-boundary-holds-but-coverage-authored-in-batch` + `metric-counts-only-successes`
- **Design/Operating verdict:** design-effective (post-9828ea1 the verification corpus is GENERATED — 11,760/11,760 cells on both interpreters, and the generator caught 1,536 fail-open cells that reading could not); operating-effective at the master boundary (Q5: it blocked, and the block was correct); operating-INeffective at change-time for a full day
- **Severity:** concerning
- **Confidence:** high
- **Claim:** PROVEN — at d1465f0 my measurement (in-surface filter per `hooks/lib/review-record-gate-lib.sh:70-88`, joined against `docs/reviews/records/index.json` PASS entries at current blob_sha): 153 in-surface paths changed since fork; 52 were mode-only exec-bit churn (ba22fd9 — 0 insertions / 0 deletions, blobs identical to the grandfather manifest); 24 covered at current blob; **77 real content changes uncovered**, 30 of them holding stale PASS records at older blobs. The gap was then closed by an operator-authorized batch: 92 PASS index entries created 2026-07-30 (index now 189 entries), with 7 of ~98 reviews blocking on REFORMULATE/REJECT.
- **Shadow-metric check:** three shadows checked. (1) Bypass shadow: `~/.claude/state/review-record-gate-overrides.log` contains ZERO real-repo overrides — every line is a /T/tmp.* self-test fixture path (~70 lines, 15:28–18:47Z), so "no bypasses" is PROVEN, but only after filtering an audit trail that is 100% test pollution — the log as shipped is unreadable. (2) Rubber-stamp shadow on the 92-PASS burst: reject rate 7/98 ≈ 7% with substantive findings (a harness-doctor duplicate-dispatch bug; an untested model-pin-gate branch; `find-disk-scan-gate.sh:350` bash-4-only lowercasing = fail-CLOSED on stock macOS) — a burst that produces real REJECTs is evidence against pure theater, though per-record depth is unverifiable from here. (3) Structural shadow: the index carries ONLY PASS verdicts (189/189) — any coverage percentage computed from it cannot register failure; the non-PASS half of reality lives in untriaged nl-issue rows (F5).
- **Evidence:** `docs/reviews/2026-07-29-operator-five-questions.md` Q5 (141/31/110 measured in-session); my independent 153/52/24/77 measurement at d1465f0 (method above, reproducible in ~1 min); 7886762 + 8973f17 (sweep landings); 9828ea1
- **Sweep query:** re-run the index join at any tip; additionally, filter the overrides log for non-tmp paths — it must stay empty
- **Recommendation (for Misha's triage):** two considerations. (a) Cadence: the gate proved review happens — at the merge boundary, in one amnesty burst. If review should precede change-landing (the failure f6562b2 exemplifies), the standing rule must bind the ORCHESTRATOR's dispatch loop, not just the merge. Trigger: 77 uncovered files accumulated in ~1 day with 0 reviewers dispatched. (b) Records: consider making non-PASS outcomes visible in (or beside) the index so records-derived metrics carry both directions. Trigger: index verdict distribution is 189 PASS / 0 anything-else while 7 REJECT-class findings exist only as nl-issue rows.
- **Week-over-week:** new (the gate did not exist at the prior packet)

#### F4 — The checkbox pipeline decoupled from reality in BOTH directions in one week
- **Class:** `status-derives-from-ceremony-not-state` (done-but-unflipped AND flipped-but-not-true)
- **Design/Operating verdict:** design-effective (task-verifier as sole checkbox-flipper is wired and was used); operating-INeffective as a truth source during the period
- **Severity:** concerning
- **Confidence:** high
- **Claim:** PROVEN in both directions. Direction 1 — done-but-unflipped, three plans: verification-dispatch V1-V5 were built and MERGED TO MASTER on 2026-07-28 (84f5a3c, fe78ed3) yet the same-day operator answer read "0 of 6 tasks done" until the reconciliation pass flipped them (cd1aa93, corrected at 800bcbb); macos-portability M1-M5 content-complete at 0/6 until db280f2; context-watermark W1-W3 until 3b33a31. Direction 2 — flipped-but-not-true: 7506451 flipped P1/P2 PASS against a pre-wave tree and reached master; the targeted re-check held P1 FAIL (026184f) — the flip preceded the truth by a day and a real defect (e6720aa).
- **Shadow-metric check:** the headline "plan progress %" has as its shadow "verification recency vs content drift" — both directions above are that shadow disagreeing with the headline. The cockpit roadmap consumes these checkboxes, so the operator's primary status surface inherited both errors.
- **Evidence:** `docs/reviews/2026-07-29-operator-five-questions.md` Q1 + its same-day UPDATE block; cd1aa93; db280f2; 3b33a31; 7506451-on-master vs the 026184f/e6720aa/f09af28 supersession chain
- **Sweep query:** for each ACTIVE plan, compare the last verify-commit date against the last content-commit touching the plan's named files; any plan whose content moved after its last flip is a stale-verification candidate
- **Recommendation (for Misha's triage):** the reconciliation that caught all three was manual and happened only because the operator asked Q1. Consider making "re-verify on content drift" a standing trigger (the 2a82cda flip already embeds "re-check 2026-08-11" — a date-based version of the same idea). Trigger: 3 plans stale in one direction + 1 in the other within a single week.
- **Week-over-week:** new as a measured class (the prior packet's "task-verifier pass-by-default" worry is adjacent, but this week's data shows the verifier layer performed well — the decoupling is in WHEN verification is invoked, not in its quality)

#### F5 — Problems-persist works; it displaced the failure to triage (Goodhart, on schedule)
- **Class:** `enforced-capture-saturates-unenforced-triage` (harm displacement)
- **Design/Operating verdict:** design-effective and capture-side operating-effective (ff9d728: inline [NL-###] IDs, Stop-WARN 83/0, operator auto-file 32/0 — dozens of same-turn filings this week); triage side operating-INeffective
- **Severity:** concerning
- **Confidence:** high
- **Claim:** PROVEN — `~/.claude/state/nl-issues.jsonl` holds 61 rows; the auto-escalation row (docs/backlog.md NL-ISSUES-TRIAGE-20260730, landed 8973f17) states 60 untriaged against a threshold of 5, oldest >2d. Among the untriaged: `find-disk-scan-gate.sh:350` fail-CLOSED on stock macOS (a BLOCKING gate blocking legitimate commands), the ~20-host false-green class (F2), and `scripts/write-review-record.sh` dying on bash-4-only lowercasing — the RECORD WRITER for F3's gate is itself broken at the portability floor. The amplification risk is already on file: AUDITOR-NL-ISSUE-STORM-AMPLIFICATION-01 (one storm filed 700 rows).
- **Shadow-metric check:** the mechanism's headline (rows filed per problem stated — trending toward 100%) is healthy; its shadow (rows dispositioned per rows filed) is ~1/61. A capture metric without a disposition metric is the textbook shadow gap.
- **Evidence:** nl-issues.jsonl count + the three rows quoted; 8973f17 backlog hunk; ff9d728; the storm row (2026-07-29T23:18)
- **Sweep query:** weekly untriaged count via nl-issue.sh --list --untriaged; alert if monotonically increasing across 3 packets
- **Recommendation (for Misha's triage):** the mechanism did its job — the queue is now honest. Consider a triage pass ordered by blocking-severity (the 3 rows named above first). Trigger: 60 untriaged vs threshold 5, and ≥2 untriaged rows describe BLOCKING-gate defects.
- **Week-over-week:** adjacent-recurring — the v70-era handoff already carried "52 nl-issues untriaged"; the capture arm improved since, the triage arm did not. Escalating.

#### F6 — Deploy carriers and the needs-you ledger: two resolved incidents kept as regression classes
- **Class:** `deploy-carrier-destroys-own-source` (symlink topology: source inode == target inode); `corrupt-state-file-renders-as-reassuring-zero`
- **Design/Operating verdict:** both were design-DEFECTIVE (the mechanism itself was the hazard — not bypass, not erosion); both now fixed with verified guards
- **Severity:** info (resolved) — per the false-positive doctrine, no action recommended
- **Confidence:** high
- **Claim:** PROVEN — carriers: hooks/lib (19 files, ~12,400 lines) deleted twice by install.sh; 27 committed files overwritten at 09:41:43 with the log's own "updated ... (backed up ...)" lines as the confession (`~/.claude/state/auto-install-log-20260729-094143.txt`; post-run bytes identical to the older origin/master copy while HEAD held newer — Q4 record); guards 4e29dc6 (12/0 on bash 3.2.57) + b8dd674 (24/0 both interpreters; live-run proof 54-updated → 0-updated/326-self-sync-skipped; kill-switch `~/.claude/local/no-auto-install`). Ledger: 1-byte file dark ~2 days (mtime 07-27 20:46 → fix 07-29); root cause `${links[@]}` under bash-3.2 set -u, reproduced both ways (9e822ca); the UI's conflation of broken-with-empty closed by the 3-state inbox contract.
- **Shadow-metric check:** the carriers' "N files updated" success metric WAS the damage meter — the guard inverts it (self-sync-skipped is now the healthy signal). Watch marker: any updated>0 line in an auto-install log on a symlinked machine is a regression alarm. The inbox's "0 open asks" now has its shadow (ledger-validity state) surfaced in-band.
- **Evidence:** auto-install logs 094143/102043/105342; SCRATCHPAD "DANGER — TWO CARRIERS" block; Q4 table in the five-questions record; 4e29dc6; b8dd674; 9e822ca; d1465f0
- **Sweep query:** count of "^updated " lines across auto-install logs post-guard (must be 0 on symlinked installs)
- **Recommendation (for Misha's triage):** none — citing why: both guards are landed, mutation-proven on both interpreters, demonstrated end-to-end, with an operator kill-switch; the residual risk is the F1 merge-timing item, already surfaced.
- **Week-over-week:** new-and-resolved-in-period

#### F7 — Builder numeric-claim fidelity is the eroding agent signal; the verifier layer is the working control
- **Class:** `builder-report-overclaims-numerics` / `fabricated-evidence-rows`
- **Design/Operating verdict:** builder dispatch design-effective; builder REPORTS operating-INeffective as evidence (their numbers cannot be taken on trust); verifier layer operating-effective (it caught them, every time it ran)
- **Severity:** concerning
- **Confidence:** medium (multiple proven instances; no baseline rate to prove a worsening trend)
- **Claim:** PROVEN instances: M5's report carried 5 refuted numeric claims — including an off-by-one inside the very correction block written to fix a §1 honesty violation, and a headline "GREEN" quote that suppressed the WARN line directly above it (SCRATCHPAD "M5 VERIFIER FINDINGS"); T3's history includes a self-test writing fabricated rows into the real would-block ledger and needed 4 verification passes to flip (409ba26; 5f0eb73); the close-worktree invocation-dependence was found by the orchestrator, not the builder (fc94550, "found by ME" per SCRATCHPAD). TREND claim HYPOTHESIZED — builders may always have been this unreliable, with only this week's stronger verification making it visible; REFUTED BY a comparable refutation-count from re-auditing an earlier wave's builder reports.
- **Shadow-metric check:** headline = builder "suites N/0, verified"; shadow = verifier refutation count per report — this week: 5 refuted claims in one report, 1 fabrication incident, 1 invocation-dependence miss. Champion-challenger vs the prior packet is POSITIVE for the verifier layer: 2026-05-25 worried about task-verifier pass-by-default; this period task-verifier held FAILs (P1; M6; T3 three times) and the advocate returned 5/9 FAIL (e8c74cb) — the feared degradation did not materialize.
- **Evidence:** SCRATCHPAD "M5 VERIFIER FINDINGS" block; 409ba26; 5f0eb73; fc94550; e8c74cb
- **Sweep query:** count REFUTED findings in verifier outputs per wave (nl-issues rows tagged "(verifier)" and the evidence files)
- **Recommendation (for Misha's triage):** none beyond continuing the current posture — citing why: the control that matters (independent re-derivation before any flip) demonstrably worked each time it ran, and the calibration substrate that would let me trend this does not exist yet (Honesty note). Trigger for future action: refutation count per wave >5, or any refuted number reaching an operator-facing artifact uncorrected.
- **Week-over-week:** improved on the verifier axis vs the prior packet's stated worry; new on the builder-numerics axis

#### F8 — Operational-resilience note: the spend-limit kills
- **Class:** `external-kill-mid-flight` (not a harness defect)
- **Design/Operating verdict:** recovery path operating-effective as reported
- **Severity:** info
- **Confidence:** low-medium
- **Claim:** HYPOTHESIZED (coordinator-reported to this audit, not independently verified): 7 agents killed mid-work by a spend limit, all recovered via worktree transcripts. Corroboration I can cite: the same class struck earlier the same day — SCRATCHPAD's "AFTERNOON WAVE (post-limit-reset)" heading, and the review sweep's first launch dying at 0 tokens (Q5) with a cached resumeFromRunId retained. REFUTED BY absence of kill/recovery markers in the relevant worktree transcripts.
- **Shadow-metric check:** n/a — no headline metric
- **Evidence:** SCRATCHPAD:71 and :216-227; Q5 "first attempt died instantly... zero tokens"; coordinator report this session
- **Sweep query:** instance-only: external billing events are not a harness-internal class — but twice-in-one-day suggests the recovery playbook (worktree transcripts + resume-from-run-id) deserves a doctrine line if it lacks one
- **Recommendation (for Misha's triage):** none (info); the recovery worked twice.
- **Week-over-week:** new

### The ≤5 items to triage first

1. **Merge the wip branch to master** (F1) — closes the inert-gate + destructive-carrier exposure at the deploy source AND removes the refuted 7506451 P1 flip from master-as-truth. Already sequenced in the away-plan; precondition largely met (92 PASS records landed) — re-run the F3 join at tip to confirm the delta is 0 first.
2. **Triage the 3 blocking-severity nl-issue rows** (F5): find-disk-scan-gate.sh:350 fail-CLOSED on stock macOS; write-review-record.sh bash-4-only lowercasing (the review pipeline's own writer broken at the portability floor); the ~20-host bare-bash self-test false-green class (F2). The other 57 rows can ride the weekly cadence.
3. **Decide the review-cadence rule** (F3): per-change reviewer dispatch vs batch amnesty at the merge boundary — and whether non-PASS verdicts become visible in the records index so coverage metrics stop being structurally failure-blind (189/189 PASS today).
4. **Departition test pollution from real audit substrates** (F2/F3 shadows): unresolved-stop-hooks.log (178/178 fixture entries), review-record-gate-overrides.log (~70 tmp-fixture lines), scope-gate-exemptions.log (majority tmp lines). Until these are clean, every bypass/erosion audit — including mine — reads noise, and a REAL bypass would hide inside it.
5. **Repair the evaluator's own instruments** (Section 5 / Honesty note): the assembly script reads state substrates that no longer exist (its body above is vacuous for that reason, not because the week was clean); mine-misha-asked's artifact_search matched 0 of 130 asks; no calibration substrate exists; no packet was produced for 9 weeks. A watchdog with broken instruments is next week's finding.

### Section 5 — Own track record

**Leading entry, per the standing rule: the evaluator itself went dark.** The most-recent prior packet is 2026-05-25 — 9 weeks before this one, on a weekly contract. This is worse than "recommendations ignored for 4+ packets": the packets were never produced. Severity: concerning. The cause is partly mechanical (see Honesty note — the script's substrates moved out from under it; the daily variant scripts `harness-evaluator-daily.sh` + `install-daily-harness-eval-task.ps1` exist in-repo, but no daily packet exists at `~/.claude/state/harness-eval/` on this machine). The restart is this packet; the cadence fix belongs to triage item 5.

Prior packet's recommendations, each dispositioned:

| # | 2026-05-25 recommendation | Disposition |
|---|---|---|
| 4.1.1 | investigate pre-submission-audit scope-waiver cluster / gate allowlist | **superseded** — the waiver substrate itself was replaced (scope-waiver-*.txt → scope-gate-exemptions.log with structured reasons); no commit found addressing the original cluster; effectively ignored-as-written |
| 4.1.2 | audit close-plan rubric conditionality by plan tier | **ignored** (no related commit found; the force-overrides log is absent on this machine so current pressure is unmeasurable) |
| 4.1.3 | check narrate-and-wait for silent passing | **ignored** as an explicit check; the Stop chain was since rearchitected (stop-verdict-dispatcher), so the original question is stale |
| 4.2.1-3 | Misha manually re-check 3 drift items | **not verifiable** from repo state (operator-side action) |
| 4.3.1 | track claim-reviewer invocation rate | **acted-on** — `scripts/measure-claim-reviewer-rate.sh` landed 2026-05-28 (6cc5ff1) and is maintained; note its silent 90-days-became-7-days window bug was found and fixed THIS week (f633e53), meaning the tool had been quietly mismeasuring — a false-green of its own |
| 4.3.2 | track attestation-writes without a paired reviewer | **ignored** (no mechanism found) |
| 4.3.3 | fix HARNESS-GAP-23 (stale COMMIT_EDITMSG) | **ignored — drift flag per the N+4 rule**: still open at docs/backlog.md:204, re-surfaced 2026-06-01, now ~12 weeks old |
| 4.4.1 | instrument builder hedge-phrase rate | **ignored as a mechanism**; partially embodied in practice by this week's verifier refutations (F7) |
| 4.4.2 | sample-audit mechanical-class PASS verdicts | **partially-shipped in practice** — this week's reconciliation re-derived three plans' verdicts and caught a stale flip (cd1aa93, db280f2, 026184f); no STANDING sample-audit exists |
| 4.4.3 | count Dispatch acceptance-exempt ratio | **ignored** (no counter found; HARNESS-GAP-34 still cited in backlog) |
| F1 | artifact_search semantic upgrade | **ignored — escalating**: this run matched 0 satisfied of 130 asks (May: 2 of 182); the instrument is now fully blind |
| F2 | LLM-classify borderline asks | **ignored** (this run binned 120/130 as non_task — a distribution shift I cannot diagnose from here) |
| F3 | automate Section 5 | **ignored** — the script still prints its TODO placeholder (harness-evaluator.sh:433); this section was again produced by hand |
| F4 | calibration-driven agents-to-watch | **ignored** — `~/.claude/state/calibration/` does not exist |
| F5 | wire a surfacing channel | **partially-shipped** via a different lineage (the cockpit / needs-you surface exists; no evaluator feed into it) |
| F6 | project-mapping config for the miner | **not checked this run** (declared, not silently skipped) |
| F7 | scheduled-task wiring | **partially-shipped** — scripts exist in-repo; not operating on this machine (no output artifacts found) |
| F8 | session-tied branch locks for autonomous branch juggling | **partially-shipped** via the accountable-estate registration/closer mechanism (26414fa, T4) — different design, same need |

Score: 1 acted-on, 4-5 partial, ~11 ignored/stale, 1 escalating. Two items (4.3.3, F1) now carry the drift flag.

### Honesty note (what I could not verify this period)

- **The script-generated body above is substrate-blind and its zeros are false.** `harness-evaluator.sh` reads `$REPO_ROOT/.claude/state/` names (scope-waiver-*.txt, acceptance-waiver-*.txt, unresolved-stop-hooks.log, close-plan-force-overrides.log) that the live harness no longer writes there — current state lives at `~/.claude/state/` under different names (scope-gate-exemptions.log, review-record-gate-overrides.log, nl-issues.jsonl). I also ran it from a worktree whose own `.claude/state/` is empty, so even the main checkout's 534-line unresolved-stop-hooks.log was not read (the body says 0). Where these Notes disagree with the body, the Notes are the audited numbers. The body's header also reads 2026-07-30 (UTC stamp) for this 2026-07-29 (local) packet.
- **mine-misha-asked is currently blind:** 130 asks → satisfied=0, drift=0, recent=10, non_task=120. An artifact search that finds ZERO satisfied asks after a week like this one is not measuring. Transcripts on this Mac also reach back only to ~07-14 (first install), so the 60-day window is structurally thin.
- **Could not verify:** `docs/plans/review-independence.md` (named in my dispatch brief) does not exist at a41b0e1 — the operator-authorized sweep may have superseded it, or it lives in an unlanded worktree; the 7-agent spend-kill recovery detail (coordinator-reported; I corroborated only the class); per-record depth of the 92-PASS burst (I checked its reject rate and the substance of its REJECT findings, not each PASS); whether the Windows machine's daily evaluator task produces packets; the "123+" uncovered figure from my brief vs my 77 (different moments and filters — mine excludes 52 mode-only exec-bit paths and post-dates some record landings; both describe the same gap).
- **Calibration substrate absent**, so the agent-degradation finding (F7) rests on this week's incident evidence, not longitudinal data.
- **Worktree isolation** prevented direct git inspection of the shared checkout; all master/branch claims come from refs in the shared object store as of my fetch (~03:30Z 07-30). The main checkout's untracked live state (e.g., mid-run record landings) may have moved since.
- **Verdict-balance disclosure:** I found NO evidence of silent evasion (state c) of the review-record gate in the real repo — the override log, once its fixture pollution is filtered, shows zero real-repo overrides, and the coverage gap was visible-and-declared (Q5), not hidden. This period's failures were overwhelmingly honest-and-logged; the dangerous unlogged class was false-green self-tests, not gate evasion.
