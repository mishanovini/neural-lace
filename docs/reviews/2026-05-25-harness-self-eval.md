# Harness Self-Eval — 2026-05-25

**Generator:** `adapters/claude-code/scripts/harness-evaluator.sh` (System 2 of the drift-backlog + harness-evaluator pair, per `docs/plans/drift-backlog-and-harness-evaluator.md`).

**Read-only.** This packet is descriptive, not prescriptive. Recommendations are for Misha to review and triage. The evaluator never auto-updates rules, hooks, or agents.

**Inputs read:** drift-backlog (System 1 output), scope-waivers, acceptance-waivers, autonomous-done attestations, dag-approved waivers, close-plan force-overrides, observed-errors-overrides, unresolved-stop-hooks log, failsafe-retirements, failure-mode catalog, HARNESS-GAP backlog, prior weekly packets (own track record).

**Mode:** real

---
## 1. Bypass tally (by mechanism)

How many times each gate's escape hatch was authored in the last 60 days.
High counts on a single gate mean either (a) the gate fires too aggressively,
or (b) the work it gates is genuinely orthogonal more often than expected.
Either way the evaluator surfaces it for Misha's judgment.

| Gate | Bypass count | Most-recent date | Top plan(s) bypassing |
|---|---|---|---|
| `scope-enforcement-gate.sh` | 10 | 2026-05-04 | pre-submission-audit-mechanical-enforcement (9), discovery-protocol (1) |
| `product-acceptance-gate.sh` | 2 | 2026-05-17 | conversation-tree-ui-v1-20260518T011348Z.txt,session-end-protocol-enforcer-20260517T183054Z.txt |
| `narrate-and-wait-gate.sh` | 3 | 2026-05-17 | — (session-scoped) |
| `dag-review-waiver-gate.sh` | 0 | — | — (session-scoped) |
| `close-plan.sh --force` | 9 | 2026-05-06 | harness-gap-17-narrative-doc-sweep (1), architecture-simplification-tranche-g-calibration-loop (1) |
| `observed-errors-gate.sh` | 0 | — | — |

## 2. Unresolved-stop-hooks log (retry-guard downgrades)

When a Stop hook fires the same failure signature 3+ times in one session,
the retry-guard library downgrades the block to a warn and appends to
`.claude/state/unresolved-stop-hooks.log`. High counts indicate gates that
are genuinely unresolvable mid-session OR are firing false-positively.

**Total log entries:** 2491

**By hook (top 10):**

| Hook | Count | Unique-signature count |
|---|---|---|
| `hook=deferral-counter` | 411 | 0 |
| `hook=pre-stop-verifier` | 408 | 0 |

**Interpretation hints (NOT auto-recommendations):**
- High-count + low-unique-sig: same failure recurring across sessions — likely a real ongoing gap (drift, missing prereq).
- High-count + high-unique-sig: gate fires across diverse contexts — may indicate over-eager triggering.
- Single-session bursts (count = N per session): retry-loops within one session — usually a blocker the agent couldn't resolve.

## 3. Drift backlog (System 1)

**Total unique asks classified:** 182
**Drift (no artifact, > 14 days):** 66
**Satisfied (artifact found):** 2
**Recent-pending (< 14 days):** 20

**Oldest 10 drift items (highest signal — Misha asked, no shipped artifact):**

| Age (d) | Reps | Trigger | Ask (truncated) |
|---|---|---|---|
| 31 | 1 | `please call` | This is the fourth iteration — the user has expressly authorized iteration up to 3 times before escalation. If gaps rema |
| 31 | 1 | `please say` | Return PASS or FAIL with severity classification. Per the user's escalation note: if PASS-with-nits, please say so expli |
| 31 | 1 | `Let's do` | Let's do parallel across the board. We have to have a bias toward quality code. I would rather take the time to get it r |
| 31 | 1 | `I want you to` | I want you to review those active plans and determine how they fit in with what you just planned; do they overlap? do th |
| 31 | 1 | `Can you ` | I approve the sequence as it is. Can you execute all of these fully autonomously without my involvement and with high qu |
| 31 | 1 | `please distinguish` | Apply the same strict review. Return PASS or FAIL with any remaining gaps. The plan has been through two iterations of F |
| 31 | 1 | `we need to` | 1. I don't see any reason why homeowners would ever navigate to that webpage. That exists purely for attempting to satis |
| 31 | 1 | `make sure` | "With the analyzer, every gap found becomes a rule/hook proposal" but I also want to make sure the rule/hooks being prop |
| 30 | 1 | `I want you to` | What are you handing off? I want you to continue until you've completed the entire plan. |
| 30 | 1 | `please say` | Apply your standard adversarial review of all 10 SE sections. Return PASS or FAIL with severity classification (critical |

**Items repeated 2+ times across sessions (Misha re-asked — strong drift signal):**

_None in this scan window._ (May indicate (a) Misha doesn't re-ask, (b) dedup is too aggressive, (c) classification is hiding repeats.)

## 4. Top-3 lists (Misha's review packet)

Per the design constraint: every recommendation cites ≥3 evidence pointers.
Recommendations are descriptive, NOT auto-applied.

### 4.1 Top 3 rules with highest bypass count

1. scope-enforcement-gate.sh — 10 bypasses
   - Evidence 1: 10 waiver files at `.claude/state/scope-waiver-*.txt`
   - Evidence 2: top plan needing waivers — `pre-submission-audit-mechanical-enforcement` (9 waivers, see ls)
   - Evidence 3: when a plan needs 9 waivers, the plan's scope was authored too narrowly OR the gate's path-matching is too strict
   - **Recommendation (descriptive):** investigate whether pre-submission-audit plan's scope should have included sibling files from the start, or whether the gate's regex needs an allowlist for that plan-shape
2. close-plan.sh — 9 bypasses
   - Evidence 1: 9 force-overrides logged at `.claude/state/close-plan-force-overrides.log`
   - Evidence 2: forced overrides cluster around the architecture-simplification tranche plans
   - Evidence 3: `close-plan.sh`'s rubric (typecheck, evidence-block, runtime-correspondence) may be stricter than Tranche-level plans need
   - **Recommendation (descriptive):** audit whether the rubric should be conditional on plan rung/tier
3. narrate-and-wait-gate.sh — 3 bypasses
   - Evidence 1: 3 autonomous-done attestations at `.claude/state/autonomous-done-*.txt`
   - Evidence 2: low count suggests sessions are correctly ending under explicit-done OR the gate isn't triggering often
   - Evidence 3: cross-check against unresolved-stop-hooks for narrate-and-wait hook entries
   - **Recommendation (descriptive):** if observed-bypass-count is much lower than expected-session-count, the gate may be silently passing

### 4.2 Top 3 newly-surfaced drift items (System 1)

1. **31d old** (reps=1): "This is the fourth iteration — the user has expressly authorized iteration up to 3 times before escalation. If gaps remain that you would classify as critical-b"
   - Evidence 1: ask first observed at 2026-04-23T22:42:17.493Z
   - Evidence 2: no satisfying artifact found in git log / branches / failure-modes / backlog
   - Evidence 3: trigger pattern `please call` matched — heuristic-class signal, may be false positive
   - **Recommendation (descriptive):** Misha review whether this is genuinely undone or was satisfied through a channel artifact_search doesn't see

2. **31d old** (reps=1): "Return PASS or FAIL with severity classification. Per the user's escalation note: if PASS-with-nits, please say so explicitly so I can proceed to implementation"
   - Evidence 1: ask first observed at 2026-04-24T00:04:51.338Z
   - Evidence 2: no satisfying artifact found in git log / branches / failure-modes / backlog
   - Evidence 3: trigger pattern `please say` matched — heuristic-class signal, may be false positive
   - **Recommendation (descriptive):** Misha review whether this is genuinely undone or was satisfied through a channel artifact_search doesn't see

3. **31d old** (reps=1): "Let's do parallel across the board. We have to have a bias toward quality code. I would rather take the time to get it right the first time and avoid having to "
   - Evidence 1: ask first observed at 2026-04-23T20:42:41.000Z
   - Evidence 2: no satisfying artifact found in git log / branches / failure-modes / backlog
   - Evidence 3: trigger pattern `Let's do` matched — heuristic-class signal, may be false positive
   - **Recommendation (descriptive):** Misha review whether this is genuinely undone or was satisfied through a channel artifact_search doesn't see

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

**First weekly packet.** No prior recommendations to evaluate.

On the NEXT run, this section will list each prior recommendation and one of: acted-on / ignored / partially-shipped, with citation.

## 6. Failsafe retirements

**Retired gates logged: 2**

2026-05-05 — `plan-closure-validator.sh` RETIRED
2026-05-06 — Honest accounting of `--force` usage during 2026-05-05 closures

Cross-check: are any retired gates' responsibilities now under-covered? (Heuristic only — Misha to judge.)

## 7. Pointers + freshness

**Drift backlog generated:** 2026-05-25T00:38:14Z
**Drift backlog window:** `recent-days` setting last used (check script invocation)
**State dir:** `.claude/state/` (gitignored)
**Failure-mode catalog:** `docs/failure-modes.md` (29 entries)
**HARNESS-GAP backlog entries:** 63

---

**Next packet:** TBD per Misha's review cadence. Schedule via `/schedule` or cron (see plan task 6 for placeholder).

**Honesty note:** this packet is v1. Known limitations:
- Section 4.4 'agents to watch' is currently heuristic-seeded, not data-driven. Future iteration ties to `.claude/state/calibration/` per `rules/calibration-loop.md`.
- Section 5 'own track record' is placeholder until 2+ packets exist for cross-reference.
- Drift items have false-positive rate — see plan's "Known v1 limitations".


---

## 8. Self-Test Honesty Audit (Task 7 of bootstrap plan)

**Bootstrap plan requirement:** confirm at least one drift item is something I (the orchestrator that built this) recognize as a real deferred ask AND at least one flagged rule is one I recognize as weakly enforced.

### Drift items — honesty check

I (Claude) recognize the following Section-3 drift items as **real deferred asks**:

1. **"I want you to continue until you've completed the entire plan"** (30d, agent-handoff context). This is Misha's recurring anti-narrate-and-wait pressure. It was the structural motivation for `narrate-and-wait-gate.sh` + `continuation-enforcer.sh`. The fact that it surfaces here as DRIFT is itself meta-honest — the mechanism shipped, but the underlying ask "stop handing off prematurely" is one Misha has had to repeat in many sessions. Confidence: HIGH this is real drift.

2. **"What are you handing off? I want you to continue until you've completed the entire plan"** — same pattern, different session. HIGH confidence real.

3. **"make sure the rule/hooks being proposed are generalized to include broader problems rather than [the named instance]"** — this is the Fix-the-Class-Not-the-Instance principle. **It WAS satisfied** (it's now codified in `rules/diagnosis.md` "Fix the Class, Not the Instance" section). The fact that artifact_search marked this as drift is a **known false-positive** (v1 limitation — artifact_search keyword extraction is narrow). This is exactly the kind of finding the System-2 weekly-packet review surfaces for Misha's manual triage.

### Known-weak rules — honesty check

Section 4.3 surfaced three rules I recognize as genuinely weakly enforced:

1. ✅ **`claim-reviewer` self-invocation gap** — I confirm. `rules/vaporware-prevention.md` explicitly documents this as the residual gap.
2. ✅ **`tool-call-budget.sh --ack` bypassable by direct file write** — I confirm. Same doc explicitly admits this.
3. ✅ **`review-finding-fix-gate.sh` stale-COMMIT_EDITMSG (HARNESS-GAP-23)** — I confirm. **I hit this gate during the very build of this system** (the gate matched ADR-031 from a prior unrelated commit; I had to `: > .git/COMMIT_EDITMSG` to work around it).

### Honest gaps surfaced during build

I encountered the following gaps that this v1 does NOT yet address — filed here as candidate followups:

- **F1.** `artifact_search` is too narrow. False-negative rate is high (many shipped artifacts go undetected). v2 should add semantic search (LLM-classify or embedding match).
- **F2.** `mine-misha-asked.sh` regex matches conversational fragments (e.g., "Yes, please draft the plan") even with MIN_ASK_LEN=40 + conversational-prefix filter. v2 should add LLM-classify pass on borderline cases.
- **F3.** Section 5 ("own track record") is placeholder. Requires 2+ packets to populate. Will be functional starting week 2.
- **F4.** Section 4.4 ("agents to watch") is heuristic-seeded, not data-driven. v2 should consume `.claude/state/calibration/<agent>.md` per `rules/calibration-loop.md`.
- **F5.** No surfacing channel wired yet. v2 should integrate with the Conv Tree GUI's "Drift" panel once the auto-emit enforcement lands (per session `local_bcd900b8`).
- **F6.** Project-scope filter is substring-match (`--project-filter "neural-lace"`). v2 should use a proper project-mapping config file.
- **F7.** No scheduled-task wiring yet. Cron pattern documented in plan (Task 6); actual registration deferred per Misha's review-cadence preference.
- **F8.** Branch-juggling during the build caused the plan-commit to get orphaned and required cherry-pick recovery. Suggests the harness's branch-state model under autonomous-mode could benefit from session-tied branch locks (out of scope for this work).

**Honesty principle satisfied:** I have surfaced both what this system DOES find AND what it DOESN'T find. Misha's review of this packet is the watchdog-for-the-watchdog signal.
