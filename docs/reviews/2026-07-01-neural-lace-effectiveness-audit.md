# Neural Lace Effectiveness Audit — full-harness review

Date: 2026-07-01
Method: 7 parallel audit agents + 1 adversarial verification agent (Workflow run `wf_030678e0-8fd`, 3.33M tokens, 185 tool calls) over the LIVE mirror (`~/.claude/`) and this repo checkout (worktree `modest-satoshi-150d97`, 29 commits behind origin/master — staleness accounted for per-claim; the verify pass re-derived every headline mechanical claim against origin/master).
Status of findings: none fixed in this session — remediation program proposed to operator, pending direction.
Evidence labels follow claims.md: everything below is PROVEN (measured on disk) unless tagged HYPOTHESIZED.

---

## 1. Wiring integrity (verified)

**Enforcement claimed but not firing on this machine:**

| Artifact | Claimed by | Actual state |
|---|---|---|
| `continuation-enforcer.sh` (DONE/PAUSING/BLOCKED gate) | CLAUDE.md, session-end-protocol.md ("enforced by continuation-enforcer.sh Stop hook"; worked example claims "wired into Stop chain … merged to master") | Wired in NEITHER live settings.json NOR origin/master settings.json.template. Dormant 45 days since creation (2026-05-17). Pure theater; the flagship session-end contract is unenforced everywhere. |
| `customer-facing-review-gate.sh` | customer-facing-review.md (Mechanism, "HARD REQUIREMENT") | Hook file present live; wired in origin template; NOT in live settings.json → never fires on this machine. |
| `worktree-teardown-gate.sh` + `session-start-worktree-advisor.sh` | worktree-isolation.md (Mechanisms) | Same partial-install state: files live, template wired, live settings NOT. |
| `stalled-work-surfacer.sh` | background-work-tracking.md (Mechanism) | Same. |
| `workstreams-turn-emit.sh` ("the every-turn writer") | workstreams-state.md | Wired NOWHERE — not in live settings, not in origin template. Never fires anywhere. |
| `propagation-trigger-router.sh` | vaporware-prevention.md row | Unwired (documented deferral, but the map row reads as live). |
| Gen-6 trio: `goal-coverage-on-stop.sh`, `goal-extraction-on-prompt.sh`, `imperative-evidence-linker.sh` | vaporware-prevention.md | Wired live, but self-tests FAIL (exit 2): fixtures live only in repo `adapters/claude-code/tests/` (install.sh never deploys them) and fallback path hardcodes `~/claude-projects/neural-lace` while the repo lives at `~/dev/Pocket Technician/neural-lace`. Runtime behavior unverifiable on this machine. |
| `decision-context-gate.sh` | decision-context.md | Wired live; self-test FAILS reproducibly 7/26 scenarios; `~/.claude/hooks/lib/workstreams-state-resolver.sh` missing from live lib (present on origin) — 4 live hooks soft-source it and degrade. |

**Corrections the verify pass made (things that DO work, contrary to first-pass claims):** `doc-gate.sh` is directly wired (settings.json:364); `backlog-plan-atomicity.sh`/`docs-freshness-gate.sh`/`harness-hygiene-scan.sh` run indirectly via `pre-commit-gate.sh`; the three `pre-push-*` hooks run machine-wide via the global `core.hooksPath` dispatcher (from the MAIN checkout); a live inline PreToolUse blocker for `git push --force`/`--no-verify` EXISTS at settings.json:199 (git-discipline.md + INDEX.md falsely claim "no current hook").

**Divergence:** 82/87 "divergent" hook pairs are CRLF-only checkout artifacts. The 5 real content divergences (check-harness-sync, plan-reviewer, completion-criteria-gate, customer-facing-review-gate, pr-health-snapshot-gate) are all live==origin/master, i.e. checkout staleness — zero true untracked drift. Live mirror is a PARTIAL install: hook files current, settings.json + hooks/lib older than origin. Note: completion-criteria/customer-facing/pr-health gates were flipped block→warn on origin (2026-06-20/23 "land stop-gates warn-default").

**Self-tests:** 5 reproducible TIMEOUTs >45s (doc-gate, plan-auto-closure, plan-deletion-protection, plan-lifecycle, plan-reviewer — the plan-suite's git-fixture tests; slow-not-hung on Windows). 8 first-pass TIMEOUTs did not reproduce (load-induced). 18 hooks have no self-test.

**Housekeeping:** 6 `conversation-tree-*`/`conv-tree-*` shims past their self-declared 2026-06-30 deletion date; 3 stray retry-guard state files under `hooks/.claude/state/`.

## 2. Failure evidence (the harness's own logs)

- **Retry-guard downgrades** (`unresolved-stop-hooks.log`, project checkout): 107 entries 2026-05-25→06-19 — goal-coverage-on-stop **50**, deferral-counter **25**, pre-stop-verifier **20**, transcript-lie-detector 7, decision-context 3, product-acceptance 2. One session (`77c3ce81`) = 66/107, holding live retry counters on **7 Stop gates simultaneously** at HEAD 9664f4a. (The 2026-05-25 self-eval had already counted **2,491** downgrade entries by 05-24.)
- **Acceptance gate:** 12 waiver files across 6 plans vs **1** plan with real runtime PASS artifacts; waivers written in batches (4 plans at one timestamp, twice). ADR 036 records "mass waivers … Loud is not rare"; a prior measurement found 1,369 acceptance waivers on one project.
- **decision-context-gate lifetime log:** 14 waivers honored, 12 Tier-2 soft markers, **0 blocks, 0 production fence emissions** (all 12 fence emits were self-test sinks). The entire fence apparatus (36KB rule + 4 hooks + Zod module) has never produced a production fence.
- **tool-call-budget:** counter at **10,959** calls; `~/.claude/state/reviews/` **empty** — zero reviewer attestations ever produced. The 30-call audit loop has never once happened.
- **Signal consumption:** external-monitor-alerts **32 produced / 0 acked** over 33 days (including one alert flagging a real PII paste); orchestrator wake queue **330 wakes / 330 dropped / 0 delivered**; calibration loop **never used**; spawned-task-results **never used**. The one consumed channel: workstreams GUI reads (86 markers).
- **Silent infrastructure failure:** `workstreams-task-binding` — **213/353 invocations (60%) failed for a full month** (module-not-found on stale `claude-projects/neural-lace` path), still failing at audit time; fails open. `decision-context/fallback.jsonl` shows the emit facade down ON AUDIT DAY (`all-sinks-failed`, same stale path).
- **Log pollution:** 48/63 scope-gate exemption entries and 12/12 decision-context fence events are self-test artifacts — the audit logs are corrupted by test runs.
- **Never-fired escape hatches** (gates installed, hatches unused): completion-gate-skips, tdd-gate-exemptions, ux-review-gate-overrides, close-plan-force-overrides, observed-errors-overrides.

## 3. Self-knowledge conversion (does documenting failures fix them?)

- 51 HARNESS-GAP IDs (~35 open), ≥6 ID collisions/renumbers; 32 FM classes — **6 of the last 9 FMs document the enforcement layer itself misfiring**.
- **Two-speed loop (measured):** small, operator-flagged, single-hook fixes convert same-day (GAP-37/38/41/49). Class-level/meta fixes accumulate: verbal-vaporware (70d), `--ack` HMAC fix prescribed as half-day (38d unshipped), P0 synthetic-session-runner (70d unbuilt), GAP-01..08 plan-staleness structurals (68d), GAP-20/21/22 meta-fixes (56d), continuation-enforcer wiring flagged "trivial, 1hr" (38d unwired).
- **Plan-staleness/waiver-tax class re-documented ≥6 times** under new IDs while its P1 mechanical fixes stayed unbuilt (waiver-density alarm — the incentive audit's #1 fix — does not exist).
- **Self-measurement ran once:** one harness-self-eval packet ever (2026-05-25; found 66/182 operator asks drifted >14d, 2 satisfied) despite a daily-cadence directive; findings not acted on.
- Backlog stale about itself (GAP-19 open though session-wrap IS wired; STALE-PLANS-01 open though the sweep ran).

## 4. Context bloat (the per-session tax)

- **Injected into EVERY session:** ~/.claude/CLAUDE.md (22,212 B) + ALL 61 rules (883,882 B, auto-loaded from `~/.claude/rules/`) + @-inlined templates ≈ **906–945 KB ≈ 226–270K tokens** — more than an entire 200K context window of standing doctrine before any work begins.
- Classification mix: Hybrid 60.9% of bytes, Pattern 23.0%, Convention 13.0%, **Mechanism-stub 3.1%**. Pattern prose (and the Pattern halves of Hybrids) is unenforced attention cost.
- **24.3% of rule bytes is scaffolding** (Enforcement tables 81.7KB, cross-refs 48.2KB, why-exists 31KB, Classification paras 27.4KB, Scope 22.3KB). The rule→hook map is recorded **3×** (~131KB).
- Concrete duplication: FUNCTIONALITY-OVER-COMPONENTS written twice in full (12.6KB); acceptance loop described 4× (~20KB); verification-pipeline.md is almost entirely re-narration; git cluster restates itself across 6 files; conv-tree-orchestrator-emit.md is the pre-rename doc with 12 stale script names.
- **Achievable reduction: 330–420KB (37–47%) without touching a single hook**; ~80–105K tokens/session. The stub form already exists in-harness (observed-errors-first.md: "if a constraint isn't backed by the hook, it's theater").
- Runtime chains: Stop = 20 hooks, SessionStart = 21, PreToolUse = 35 matcher groups.

## 5. Consistency defects

Dead refs: `neural-lace/conversation-tree-ui/…` (renamed; cited as "sole-normative" path by decision-context.md while workstreams-state.md cites the new path — two canonical locations for the same module); `feature-completion-audit.sh` (doesn't exist; cited by INDEX.md + the live hook's own header); `~/.claude/config/active-repos.txt` absent (pr-health gate on hardcoded fallback); `~/.claude/patterns/harness-denylist.txt` absent live → **hygiene scanner silently no-ops** (= GAP-52; actual PII reached GitHub through this hole).

Stale claims: "landing in Phase 1d-*" ~2 months after landing across 6 rules; harness-hygiene.md claims /harness-review "not yet implemented" (it exists); automation-modes.md claims "26 hooks / 17 rules" (actual: 95+/61); git-discipline claims force-push unmechanized (a live blocker exists).

Contradictions (top): git.md direct-master-OK + auto-merge-autonomously vs parallel-dev-discipline PR-even-solo + `enforce_admins` vs deploy-to-production review-before-deploy fallback (automation-mode gate wired, user-global config ABSENT → default contradicts git.md's default); keep-going vs wait-for-answer boundary rests on the unwired continuation-enforcer; session-end DONE-marker canonical phrasing ("merged to master <sha>") is exactly what completion-criteria-gate's trigger regex fires on; CLAUDE.md is 205 lines vs its own ≤200 rule.

## 6. Objectives & growth history

Objectives (from README/best-practices/principles, condensed): prevent vaporware; prevent false completion claims; replace self-applied discipline with mechanical enforcement; institutional memory; secret hygiene; honest plan closure; adversarial product verification; self-improvement from failures; safe autonomy; portability.

Growth (git ls-tree, adapters/claude-code): hooks 22 (04-20) → 49 (05-06) → 76 (06-01) → 90 (06-15) → 97 live. Rules 20 → 57 (61 live, 884KB). **ADR 026 (05-05) declared a hard freeze on new failsafes; +41 hooks and +22 rules landed in the 40 days after it.** The Tranche F retirement audit retired exactly 1 gate of 50+. ADR 036 restarted structural lifecycle work 3 weeks post-"simplification" because acceptance waivers had become the default escape.

By the harness's own claims discipline: "adding gates reduced failure rates" is HYPOTHESIZED and unmeasured (telemetry deferred, HARNESS-GAP-11); the available proxies (recurring incidents, monotone artifact growth, 1-gate retirement, waiver/downgrade volumes) point against it.

---

## 7. Root-cause synthesis

- **RC1 — Attention economics inverted.** ~230K tokens of always-on doctrine per session. Compliance follows salience; salience is diluted to near zero. The corpus's own recurring admission — "a memory rule drifts under exactly the context pressure where it matters most" — applies to the whole corpus, which is ~97% prose the gates never read.
- **RC2 — Theater destroys the credibility gradient.** Where claimed enforcement doesn't fire (§1) or fires falsely (path bugs, wrong-repo cwd bugs), sessions learn "gates are noise; waivers and downgrades are the path." Measured result: waiver:PASS 6:1 by plan; 107 (+2,491 earlier) downgrades; batch-waivering.
- **RC3 — Enforcement targets narration, not work.** The most-ridden gates are the final-message scanners (goal-coverage 50 downgrades, deferral-counter 25). Message-shape demands are Goodhart-able and get ridden. The gates that demonstrably work anchor on artifacts at action boundaries (TDD gate, scope gate, credential scan, plan-edit validator, migration naming).
- **RC4 — Open-circuit signal loop.** Signals produced at industrial scale, consumed at ~0% (alerts 0/32, wakes 0/330, attestations 0/10,959 calls, calibration never used, one self-eval ever). Logs additionally polluted by self-tests.
- **RC5 — The reactive loop generates gates faster than it maintains them.** Every incident births a new gate + new rule; wiring, calibrating, and retiring existing ones has no owner. 6 of the last 9 FM classes are the enforcement layer itself failing. Complexity is now the leading failure generator.
- **RC6 — Deployment brittleness.** Partial installs (settings/lib lag hook files), never-installed test fixtures, hardcoded legacy paths (`~/claude-projects`), repo divergence (29 behind + GAP-51 staged-batch deadlock), cwd-sensitive hooks in worktrees. No mechanical check verifies the harness's OWN deployment.

## 8. Proposed remediation program (pending operator decision)

- **Phase 0 — Truth reconciliation (~1-2 days).** Reconcile git (merge origin; clear GAP-51). Build `harness-doctor.sh`: verifies every Mechanism-classified rule has a wired, self-test-passing hook; template==live wiring; lib deps present; no hardcoded-path failures — red = surfaced at SessionStart + CI. Fix the 3 path families (legacy `~/claude-projects` refs, uninstalled tests/, missing lib file). Wire-or-delete each §1 item. Delete expired shims; correct or delete every false doc claim.
- **Phase 1 — Context diet (~85-90% reduction).** New always-loaded budget: CLAUDE.md ≤100 lines + one constitution file (Rules 0–7, FUNCTIONALITY-OVER-COMPONENTS, persistence discipline) ≈ ≤6K tokens. Move everything else OUT of the auto-loaded `~/.claude/rules/` dir; deliver doctrine just-in-time — surface-scoped rules injected by hooks at the moment of relevance, and gate block-messages carry the rule text (100% salience at exactly the right moment). One machine-readable enforcement manifest replaces the 3× map; surviving rules adopt the stub form.
- **Phase 2 — Gate consolidation.** Stop chain 20 → ~3 (artifact-integrity gate; one merged session-honesty check with measured false-positive rate; one non-blocking writer). SessionStart 21 → ~5 (one digest replaces 12 surfacers). Retire or demote the ride-through message-scanners; keep/strengthen artifact gates. Hard cap on blocking gates (adding one requires retiring one + ADR).
- **Phase 3 — Close the signal loop.** One daily digest (capped ~15 lines, auto-expiry, routed to the workstreams GUI — the one channel that IS consumed). All waivers/downgrades/skips feed one ledger; threshold breach auto-opens "fix or retire this gate." Self-tests write to a sandbox, not production logs.
- **Phase 4 — Measure compliance, not existence.** Ship the synthetic-session-runner (the 70-day-old P0): weekly golden scenarios replayed against the live harness. Three KPIs: waiver+downgrade rate per gate; doctor drift; FM recurrence. New gates gated on evidence thereafter.
- **Phase 5 — Governance.** Rule/token budgets enforced by the doctor; the meta-gaps (GAP-20/21/22) become the standing priority queue.

Full agent reports: Workflow run `wf_030678e0-8fd` (session transcript dir). This review is the durable record.
