# Agent-Incentive-Structure Audit — 2026-05-24

**Auditor:** systematic one-time pass complementing the daily `harness-evaluator` (System 2 of the drift-backlog pair).
**Scope:** every rule / hook / validator / agent in the Neural Lace harness substrate.
**Question:** for every existing rule, is the path-of-least-resistance the right path?
**Method:** READ-ONLY. Three parallel research agents inventoried the enforcement substrate, ran forensic counts on actual bypass usage in the last 60 days, and read in-flight evaluator + Decision-Queue context.
**Status:** descriptive. The audit produces a prioritized fix list. Fixes are NOT implemented here.

---

## TL;DR

- **84 enforcement artifacts inventoried** across hooks (54), rules (45), agents (19), scripts (17), git hooks (4), skills (10), CI workflows (1).
- **9 rules score ≥ 3 on the incentive-gap scale** (wrong path materially easier than right path). Most are *acknowledged* residual gaps already tracked by `vaporware-prevention.md` + HARNESS-GAP backlog.
- **The harness is self-correcting.** Every concentrated bypass incident in the 60-day window (scope-waiver cluster 2026-05-03; `--force` cluster 2026-05-06; retry-storm 2026-05-18; inline-PR-body emails 2026-05-22 → 24) produced same-week mechanism work. The audit's job is to surface what *hasn't* been corrected yet, not to re-derive what has.
- **The dominant bypass class is now `acceptance-waiver chronic-stale-plan tax`** — HARNESS-GAP-29/30/31 documents 1,369 acceptance-waivers on a downstream project (one plan alone: 200; another: 96; another: 69). The gate is firing *correctly*; the plans are the problem.
- **`--no-verify` is not in use.** 17 commit-message references, 63 content references — all are *meta* (gate work itself, rules, decisions). Zero actual `--no-verify` bypasses on master in the 60-day window.
- **Top 3 prioritized fixes:** (1) ship the GAP-29/30/31 stale-ACTIVE-plan staleness surfacer + waiver-density alarm; (2) close `tool-call-budget --ack` direct-Write bypass with HMAC sentinel; (3) instrument `claim-reviewer` self-invocation rate so we can see the residual gap rather than assume it.

---

## 1. Method

Three read-only research agents ran concurrently:

1. **Inventory.** Walked `adapters/claude-code/{hooks,rules,agents,git-hooks,scripts,skills}`, `.github/workflows/`, `.github/scripts/`. Read `settings.json.template` to enumerate which hooks are actually wired (vs. shipped but dormant). For each hook, grep'd source for `OVERRIDE`, `EXEMPT`, `--no-verify`, `WAIVER`, `force`, `skip`, env-var checks, marker-file checks. Result: 84-row table grouped by type.

2. **Forensic bypass-pattern sweep.** Ran `git log --grep` and `git log -S` for `--no-verify`, counted waiver-file types in `.claude/state/`, counted exempt-marker plan-headers across 117 plan files (active + archive), read every overrides log, audited `unresolved-stop-hooks.log` (2,491 lines), enumerated `Verification: <level>` distribution (193 mechanical / 114 full / 24 contract), checked recent PR-template (c) selections.

3. **In-flight session context.** Located the `local_bb36c9bf` and `local_eb88629f` artifacts (harness-evaluator on `feat/drift-backlog-and-harness-evaluator`; Decision Queue on `feat/decision-queue`). Confirmed the evaluator's daily packet schema (Section 5 = "own track record" — where my fix list integrates as the recommendation pointer-set evaluated over time). Confirmed the Decision Queue's `add` interface (CLI subcommand with `--question`, `--mode`, `--evidence`, etc.).

Three research transcripts are summarized inline in this audit; raw findings are agent-context-only (research agents do not persist to disk by convention).

---

## 2. Inventory summary

| Type | Count | Notes |
|---|---|---|
| PreToolUse hooks (wired) | 26 | Includes 4 inline-regex blockers in `settings.json.template` |
| PostToolUse hooks (wired) | 2 | `post-tool-task-verifier-reminder.sh`, `plan-lifecycle.sh` |
| Stop hooks (wired) | 11 | Position 1-10 blocking + position 11 non-blocking `session-wrap.sh` |
| SessionStart hooks (wired) | 10 | Surfacers, account-switcher, divergence detector |
| UserPromptSubmit hooks (wired) | 3 | Goal extraction, conv-tree read, title-bar mode tag |
| TaskCreated / TaskCompleted hooks | 2 | Agent-Teams mode only |
| Hooks shipped but NOT wired | ~13 | `pre-commit-tdd-gate.sh`, `plan-reviewer.sh`, `runtime-verification-*`, `pre-push-scan.sh`, `pre-push-test-gate.sh`, `continuation-enforcer.sh`, `decisions-index-gate.sh`, `docs-freshness-gate.sh`, `review-finding-fix-gate.sh`, `backlog-plan-atomicity.sh`, `migration-claude-md-gate.sh`, `propagation-trigger-router.sh`, `external-monitor-alert-surfacer.sh`. Most are invoked indirectly (from `pre-commit-gate.sh` chain or git hooks); a few are deferred (`propagation-trigger-router.sh`). |
| Rules | 45 | Pattern-class doctrine; ~30 are Hybrid (paired with a mechanism above) |
| Agents | 19 | 7 adversarial-review agents, 1 builder, 1 verifier, plus specialists |
| Scripts | 17 | `close-plan.sh`, `write-evidence.sh`, `harness-evaluator.sh`, etc. |
| Skills | 10 | Slash-command surfaces; `/grant-local-edit`, `/calibrate`, `/close-plan`, etc. |
| CI workflows | 1 | `pr-template-check.yml` (server-side mirror landed 2026-05-24) |
| Git hooks (global via `core.hooksPath`) | 4 | pre-commit, pre-push, pre-push-pr-template, post-commit |

The full inventory (per-row Name / Path / Trigger / Enforces / Bypass-surface) is materially the union of:

- `adapters/claude-code/rules/vaporware-prevention.md` enforcement-map (the harness's own self-documented inventory)
- `docs/harness-architecture.md` (the architectural overview)
- `settings.json.template` wiring map

This audit cross-checks those against actual files on disk. No rows in `vaporware-prevention.md` were found pointing at files that don't exist (the "honest" residual-gap section is honest).

---

## 3. Incentive-gap scoring

Per-rule scoring uses this rubric:

- **0 — right path is also easier.** Compliance is the default; bypass requires deliberate friction (separate file write, env var, marker, etc.).
- **1 — symmetric.** Compliance and bypass take comparable effort; agent discipline determines outcome.
- **2 — bypass slightly easier.** Wrong path saves 1-2 steps; right path requires document lookup.
- **3 — bypass meaningfully easier.** Wrong path is a one-liner; right path requires substantive artifact production.
- **4 — bypass dramatically easier.** Wrong path is a single flag/marker; right path takes 10+ minutes.
- **5 — bypass is trivial.** Wrong path is the default; right path requires explicit awareness of the rule.

### 3a. Rules scoring 0-1 (working as intended) — mass list

Rules where compliance is *also* the path of least resistance, or where bypass requires substantive friction. These are NOT a recommendation; they are the inventory of what's working.

| Rule / mechanism | Score | Why right-path wins |
|---|---|---|
| Inline `git push --force` / `-f` / `--force-with-lease` blocker | 0 | Absolute prohibition at PreToolUse Bash; no escape hatch except `--no-verify` which is itself blocked |
| Inline `--no-verify` blocker on `git commit` / `git push` | 0 | Symmetric — `--no-verify` is itself a blocked flag at the PreToolUse layer |
| `harness-hygiene-scan.sh` Layer 1 (denylist) | 0 | Right path = use placeholders; takes seconds. Wrong path = bypass requires `--no-verify`. Path-prefix exemptions are surgical, not generic |
| `plan-deletion-protection.sh` | 0 | Right path = justify in commit message; quick. Wrong path = build a justifying commit anyway |
| `env-local-protection.sh` | 0 | Blocks heredoc, redirect, sed -i. No documented bypass |
| `findings-ledger-schema-gate.sh` | 1 | Right path = fill the 6 fields. Wrong path = `--no-verify` (blocked). Schema mechanically enforced |
| `definition-on-first-use-gate.sh` | 1 | Right path = parenthetical or glossary entry. Wrong path = `--no-verify`. Glossary lookup adds a step |
| `no-test-skip-gate.sh` | 1 | Right path = `#NNN` annotation. Wrong path = `--no-verify`. Trivial right-path tax |
| `local-edit-gate.sh` + `/grant-local-edit` | 1 | Right path = `/grant-local-edit` is a one-call slash command. Wrong path = ?? (no bypass — the slash command IS the bypass surface, and it's the right path) |
| `pre-push-scan.sh` (credentials) | 1 | Right path = don't commit credentials. Wrong path = `--no-verify` (forbidden). Server-side scanning catches the residual |
| `wire-check-gate.sh` static trace | 1 | Right path = backtick-quote file:line in `## Wire checks:`; small authoring tax. Wrong path = `n/a — <reason ≥ 30 chars>` carve-out (substantive bar) |
| `decisions-index-gate.sh` | 1 | Right path = add the row to `docs/DECISIONS.md` in the same commit (mechanical). Wrong path = `--no-verify` |
| `backlog-plan-atomicity.sh` | 1 | Right path = delete absorbed slugs in the same commit. Wrong path = `--no-verify` |
| `migration-claude-md-gate.sh` | 1 | Right path = update the CLAUDE.md migration tracker. Wrong path = `--no-verify` |
| `review-finding-fix-gate.sh` | 1 | Right path = stage the review file alongside the fix commit. Wrong path = `--no-verify`. HARNESS-GAP-23 documents an unrelated stale-COMMIT_EDITMSG defect |
| `prd-validity-gate.sh` (mechanical layer) | 1 | Right path = populate 7 PRD sections OR use the harness-dev carve-out. The carve-out's exact-string requirement is itself substantive friction |
| `spec-freeze-gate.sh` | 1 | Right path = flip `frozen: true` after review. Wrong path = thaw-then-edit-then-freeze (audit-trail-visible) |
| `goal-extraction-on-prompt.sh` + `goal-coverage-on-stop.sh` | 1 | Tamper-detected (SHA-checksum). Wrong path = env disable (visible env) |
| `plan-edit-validator.sh` evidence-first protocol | 1 | Right path = invoke `task-verifier`. Wrong path = write fake evidence (mechanically gated by 120s freshness + matching Task ID + schema) |
| `plan-reviewer.sh` 13 checks | 1 | Right path = populate the required sections. Wrong path = `--no-verify` |
| `vaporware-volume-gate.sh` | 1 | Right path = include execution evidence in PR. Wrong path = `[docs-only]` / `[no-execution]` title prefix (auditable) |
| `pr-template-inline-gate.sh` (new 2026-05-24) | 1 | Right path = answer the mechanism question. Wrong path = `--no-verify` on push (blocked) |
| `narrate-and-wait-gate.sh` | 1 | Right path = keep working. Wrong path = `.claude/state/autonomous-done-*.txt` marker (low-friction, 3 fires in 60d — looks well-calibrated) |
| `continuation-enforcer.sh` | 1 | Right path = append DONE/PAUSING/BLOCKED marker. Wrong path = env disable. Marker requirement is minimal |
| `dag-review-waiver-gate.sh` | 1 | Right path = author ≥40-char waiver once per session. 0 bypasses observed in 60d — appears to be calibrated to actual Tier-3 plan frequency |
| `observed-errors-gate.sh` | 1 | Right path = paste the error body. Wrong path = `OBSERVED_ERRORS_OVERRIDE="<reason>"` (env var, logged). 0 overrides in 60d |
| `bug-persistence-gate.sh` | 1 | Right path = persist to backlog/reviews/discoveries/findings. Wrong path = attestation file. 0 attestations in 60d |
| `transcript-lie-detector.sh` / `deferral-counter.sh` / `imperative-evidence-linker.sh` | 1 | Right path = surface deferrals + reconcile claims in final message. Wrong path = env disable. Substrate well-aligned with the doctrine |
| `teammate-spawn-validator.sh` | 0 | Worktree-mandatory-for-write is the right shape — the gate I myself hit in this audit, correctly steering me to read-only research agents |
| `conversation-tree-state-gate.sh` + `-stop-gate.sh` | 1 | Right path = let the writer emit. Wrong path = substantive 1-hour waiver. Active during conv-tree-ui builds; appears calibrated |
| `automation-mode-gate.sh` | 1 | Right path = pre-customer projects opt into `full-auto`; customer projects pause. Per-project config makes the right path automatic |
| `systems-design-gate.sh` | 1 | Right path = author 10-section Mode:design plan. Wrong path = `Mode: design-skip` with substantive `## Why design-skip` (auditable) |
| Inline public-repo blocker | 0 | Absolute on `gh repo create --public` and `gh repo edit --visibility public`; one-way-door discipline |
| `secret-hygiene.md` three-layer defense | 0 | Global gitignore + pre-push scanner + GitHub Advanced Security; layered |

These 33 mechanisms account for the majority of the harness's enforcement surface and are working as intended.

### 3b. Rules scoring 2 (low-risk imbalance) — brief notes

| Rule / mechanism | Score | The imbalance |
|---|---|---|
| `tool-call-budget.sh` 30-call audit | 2 | Right path = invoke `plan-evidence-reviewer`. Wrong path = Write the attestation file directly (acknowledged residual; see 3c) |
| `outcome-evidence-gate.sh` | 2 | Right path = before/after observable evidence. Wrong path = inline manual reproduction recipe (text-only). Self-discipline gap |
| `findings-ledger.md` "class-aware" discipline | 2 | Schema gate enforces shape; the *class-aware* substance (correct severity, correct scope) is unverified |
| Plan-reviewer Check 9 (quantitative arithmetic) | 2 | Mode:design only. Right path = inline arithmetic. Wrong path = avoid quantitative claims entirely (silent regression to vague language) |
| `comprehension-gate` at R2+ | 2 | Right path = articulate 4 sub-fields ≥30 chars each. Wrong path = author plans at `rung: 1` to avoid R2+ (under-rung classification is a known dodge) |
| `task-completed-evidence-gate.sh` | 2 | Right path = real evidence file. Wrong path = event-field `bypass_evidence_check: true` (logged but trivially settable) |
| `task-created-validator.sh` | 2 | Same shape: `bypass_validation: true` is a one-liner |
| `risk-tiered-verification.md` (Verification: mechanical) | 2 | Right path = honest classification. Wrong path = label a runtime task `mechanical` to skip the agent dispatch. 193/331 tasks are `mechanical` — high but probably legit for harness-dev |
| `acceptance-exempt: true` plan header | 2 | Right path = substantive reason. Wrong path = generic 20+ char reason ("harness-internal work; self-tests are the acceptance artifact"). 67/117 plans use it |
| `prd-ref: n/a — harness-development` | 2 | Right path = exact em-dash string carve-out (proves the author considered it). Wrong path = label downstream-product work as harness-dev. 42/117 plans use it |
| `plan-lifecycle.sh` PostToolUse (Bash sed bypass) | 2 | Right path = Edit/Write tool. Wrong path = `sed -i` on `Status:` (caught by session-start sweep but with delay) |

These 11 rules have minor imbalances. None require immediate action; most are tracked via the daily evaluator's bypass tally. Listed for completeness.

### 3c. Rules scoring 3-5 (high incentive gap) — detailed analysis

The audit's load-bearing findings. These are where the wrong path materially out-competes the right path *today*.

---

#### IG-1. Stale-ACTIVE-plan tax via chronic acceptance-waivers — score 4

**The rule (`acceptance-scenarios.md` + `product-acceptance-gate.sh`):** every ACTIVE plan not marked `acceptance-exempt: true` requires a PASS acceptance artifact under `.claude/state/acceptance/<slug>/` matching `plan_commit_sha`, OR a fresh ≥1-line substantive waiver under `.claude/state/acceptance-waiver-<slug>-*.txt` (1-hour mtime).

**The right path:** the orchestrator's deliverable is the *closed* plan. The plan is closed (`Status: COMPLETED` and archived) when all task-verifier verdicts hold AND the completion report has landed AND `Status:` is flipped. Once flipped, the gate stops firing because the plan is no longer ACTIVE.

**The wrong path:** every session writes a fresh 1-hour waiver naming the ACTIVE plan. Cost per waiver: ~30 seconds (write a one-line substantive justification). The plan's `Status:` never flips because the orchestrator considers "all the builders returned DONE" as the completion signal (the failure mode `CLAUDE.md` explicitly names: "Bookkeeping is later" is a deferral pattern; closure IS the work).

**The evidence (HARNESS-GAP-29/30/31, filed 2026-05-14):**

- ONE downstream project accumulated **1,369 acceptance-waiver files across 38 worktrees**.
- One plan alone had **200 waivers**.
- Another **96 waivers**. Another **69**.
- All on stale-ACTIVE plans whose work had shipped but `Status:` was never flipped.
- HARNESS-GAP-36 (2026-05-17) is a concrete instance of the same pattern.

In Neural Lace's own repo, the count is currently low (2 acceptance-waivers) because:
- 57% of plans (67/117) declare `acceptance-exempt: true` (harness-dev — no product runtime)
- The downstream-project numbers are where the chronic-staleness tax lives

**Why the wrong path wins:** writing a one-line waiver every session is faster than the discipline of closing plans properly. Plans accumulate as ACTIVE because:

1. The orchestrator's reward signal is "builder returned DONE", not "plan closed".
2. Closure requires multiple steps (completion report, SCRATCHPAD update, `Status:` flip — and per the lifecycle rule, `Status:` must be the LAST edit because the archival is mechanical and immediate).
3. Each waiver is independently substantive enough to pass the gate's ≥1-character + 1-hour mtime check.
4. The gate is correctly firing — but it's firing against stale-ACTIVE plans, not against new work.

**The fix (per HARNESS-GAP-29/30/31, designed but NOT shipped):**

- **Staleness surfacer** — SessionStart hook that surfaces every ACTIVE plan whose most-recent commit is > N days old.
- **Ready-to-close detector** — heuristic that detects "all tasks checked + commits landed + no recent edits" and proposes `Status: COMPLETED` flip.
- **Waiver-density alarm** — block (not warn) when the same plan has accumulated > 5 waivers in 7 days.

**Score: 4** because the right path requires structural discipline the agent doesn't reliably execute under autonomy pressure, and the wrong path is a 30-second one-liner that satisfies the gate.

---

#### IG-2. `tool-call-budget.sh --ack` attestation is writeable by direct Write — score 3

**The rule (acknowledged residual in `vaporware-prevention.md`):** every 30 Edit/Write/Bash calls in the main session, `tool-call-budget.sh` blocks and requires a fresh `~/.claude/state/reviews/*.md` file containing `REVIEW COMPLETE` + `VERDICT:` sentinels.

**The right path:** invoke `plan-evidence-reviewer` agent via Task tool; the agent writes the review file with substantive content.

**The wrong path:** Write the sentinel directly without invoking the agent. The hook greps for the string pattern; it does not verify the file was authored by an agent or that the review is substantive.

**The evidence:** `vaporware-prevention.md` "Missing from the enforcement map" verbatim:
> "A builder could Write that file directly without invoking `plan-evidence-reviewer`. Friction is raised (the bypass requires knowing the sentinel format and writing a plausible review body) but not cryptographically closed. Closing this requires either per-session HMAC signing the agent knows but the builder cannot easily extract, or Claude Code architectural support for observing Task-tool invocations. Accepted residual risk for Gen 4."

**The fix:** per-session HMAC-signed sentinels. The harness-evaluator's daily packet Section 4.3 #2 calls this out as a KNOWN-weak rule. Closing requires a small mechanism (~half-day).

**Score: 3** because the right path is one Task invocation but the wrong path is one Write tool call — and an LLM under context pressure that hits the 30-call wall will reach for the path that resolves the block fastest.

---

#### IG-3. `claim-reviewer` is self-invoked — score 4

**The rule (acknowledged residual in `vaporware-prevention.md`):** every feature claim in user-facing prose should be cross-checked by `claim-reviewer` before send. Default verdict FAIL.

**The right path:** invoke `claim-reviewer` agent via Task tool; address its findings; revise prose; re-send.

**The wrong path:** don't invoke it. Claude Code has no PostMessage hook; the agent is self-invoked-only.

**The evidence:** `vaporware-prevention.md` "Residual gap (honest)" verbatim:
> "Verbal vaporware in conversation is not mechanically blocked. Claude Code has no PostMessage hook. `claim-reviewer` is self-invoked and can be skipped. This is the single unclosed gap from Generation 4."

**The fix (partial):** the harness-evaluator's daily packet Section 4.3 #1 recommends tracking *how often* `claim-reviewer` is invoked vs. the number of feature-claim-bearing assistant messages. This converts the gap from "unknown bypass rate" to "measurable bypass rate" — but doesn't close it. Full closure requires a Claude Code architectural change.

**Score: 4** because the wrong path is *the default*. The right path requires the agent to remember to invoke; under autonomy pressure, this is exactly the kind of discipline that drifts.

---

#### IG-4. Stop-hook retry-guard threshold under-shoots in long sessions — score 3

**The rule (`lib/stop-hook-retry-guard.sh`):** after 3 identical-failure retries with no git HEAD change, downgrade the block to warn + log to `unresolved-stop-hooks.log` + exit 0.

**The right path:** session makes progress (new commit changes HEAD; counter resets) OR session genuinely cannot satisfy the gate and the 3-strike downgrade kicks in.

**The wrong path observed (FM-025):** the conv-tree-ui retry-storm 2026-05-18 fired the same hook 332+ times in one session with `count` rising to 332 in the log. The 3-strike downgrade either didn't fire OR fired and the session kept retrying anyway (the log records the count but doesn't visibly mark "DOWNGRADED" entries).

**The forensic uncertainty:** the research agent couldn't confirm whether the downgrade fired but the session kept retrying anyway, or whether the threshold isn't actually capping. Reading the library source: `retry_guard_block_or_exit` at count ≥ threshold writes the log and `exit 0` — meaning the session SHOULD have terminated. The 332+ retry count suggests EITHER (a) something is incrementing the counter without invoking the downgrade path, OR (b) sessions are being re-spawned and resetting via `CLAUDE_SESSION_ID` change.

**Why the wrong path wins:** when a session enters a retry-storm, the cost of the loop is paid by the user (waiting for sessions that emit "Standing by" for an hour), not by the agent. The threshold of 3 is correct in principle, but the observed behavior suggests it's not always effective.

**The fix:** instrument the retry-guard to record both the `count=N` *and* a `DOWNGRADED=true` flag when the downgrade fires. Verify against the 2026-05-18 incident retroactively. If the downgrade did fire, the session-resumption logic needs review; if it didn't, the counter increment path needs review.

**Score: 3** because the threshold is correct but observability into whether it actually fired is poor.

---

#### IG-5. `acceptance-exempt: true` carve-out is unverified for downstream-product slip — score 3

**The rule (`acceptance-scenarios.md`):** plans with no product user (harness-dev, pure infra, migration-only) may declare `acceptance-exempt: true` with substantive ≥20-char reason. `harness-reviewer` may audit chronic misuse during routine review.

**The right path:** legitimate harness-dev plans declare the exemption with substantive reason.

**The wrong path:** a plan that obviously addresses a downstream product feature labels itself harness-dev to skip the runtime acceptance gate.

**The evidence:**
- 67 of 117 plans (57%) declare `acceptance-exempt: true`.
- Spot-check of 5 plans suggests no misuse, but 67 plans is a lot of surface area.
- No mechanical check exists for "plan claims harness-dev but `## Files to Modify/Create` lists `src/components/*.tsx`".
- HARNESS-GAP-34 (2026-05-15) documents that the `end-user-advocate` agent cannot run in remote-Dispatch sessions. The harness-evaluator's Section 4.4 #3 specifically calls out: "every acceptance-exempt: true on a Dispatch-built plan masks an inability, not a legitimate exemption."

**The fix:** mechanical check in `plan-reviewer.sh` — if `acceptance-exempt: true` AND any path in `## Files to Modify/Create` matches a downstream-product file shape (`src/`, `app/`, `pages/`, `supabase/`, `prisma/`), FAIL the plan-review with "carve-out claimed but scope contains product files."

**Score: 3** because the wrong path is a one-line plan-header change; the right path requires honest classification under no mechanical pressure to be honest.

---

#### IG-6. `Verification: mechanical` skips functionality-verifier — score 3

**The rule (`risk-tiered-verification.md`):** tasks declared `Verification: mechanical` skip `task-verifier`'s full rubric — no comprehension-gate, no runtime-verification replay, no `functionality-verifier`.

**The right path:** honest classification. Tasks that are genuinely structural (file edit, doc sync, schema authoring) declare `mechanical`; tasks that affect user-observable behavior declare `full`.

**The wrong path:** label a runtime task `mechanical` to skip the agent dispatch. The label is a single token; there's no mechanical check that the task is *actually* mechanical.

**The evidence:**
- 193 of 331 task-level declarations (58%) are `Verification: mechanical`.
- The harness-evaluator's Section 4.4 #2 specifically flags: "92% of harness-dev tasks are `Verification: mechanical` — the dispatch rarely runs."
- For harness-dev work this is probably legit. For downstream-product work, no audit exists.

**The fix:** mechanical check in `plan-reviewer.sh` Check 12 — if `Verification: mechanical` AND task description contains a Tier A runtime keyword (page, route, button, form, webhook, cron, endpoint, API, migration, RLS policy, auth flow), FAIL the plan-review with "runtime keyword detected; consider `Verification: full`."

**Score: 3** because the label is a token; the right path requires honest classification under no mechanical pressure.

---

#### IG-7. Outcome-evidence-gate accepts text-only reproduction recipes — score 3

**The rule (`outcome-evidence-gate.sh`):** before marking a task complete, plan must have before/after observable evidence OR an inline manual-reproduction recipe.

**The right path:** capture the observable evidence (screenshot, network log, query result, file state).

**The wrong path:** write a text "manual reproduction recipe" with no artifact. The recipe satisfies the gate without producing any verifiable evidence.

**The evidence:** spot-check of recent plans suggests this escape hatch is occasionally used. No mechanical verification that the recipe corresponds to what was built.

**The fix:** require either (a) artifact-file citation (screenshot path, network log path, query result file) OR (b) recipe that includes a `verify:` command line that the harness can replay. Pure-prose recipes lose the escape-hatch privilege.

**Score: 3** because text is cheap; verifiable artifacts cost effort.

---

#### IG-8. Stale-ACTIVE-plan substrate accumulates without a sunsetting signal — score 4

**The rule (implicit):** plans transition to terminal status when work completes. `plan-lifecycle.sh` auto-archives on the `Status:` flip.

**The right path:** orchestrator's "what done means" reframing (`CLAUDE.md` 2026-05-05): plan is shipped when `Status: COMPLETED` and archived. Closure IS the work, not bookkeeping for later.

**The wrong path:** leave plans `Status: ACTIVE` indefinitely. The harness has no mechanical signal that a plan should be closed; the discipline lives in the orchestrator's reward signal alone.

**The evidence:**
- HARNESS-GAP-29/30/31 documents the chronic-stale-ACTIVE substrate downstream (200+ waivers on one plan).
- No SessionStart hook surfaces "you have N plans `Status: ACTIVE` with most-recent-commit > 14 days old."
- `plan-status-archival-sweep.sh` archives plans that ARE marked terminal but were missed by `plan-lifecycle.sh`; it does NOT detect plans that SHOULD be marked terminal.

**The fix:** SessionStart hook that surfaces ACTIVE plans by staleness (oldest-commit-on-plan-file age + days-since-any-task-checkbox-flipped). If a plan hasn't moved in 14+ days, surface as a candidate for closure-or-deferral.

**Score: 4** because the absence of a sunsetting signal is the *root cause* of IG-1 (chronic acceptance-waivers). Fixing this substantially reduces IG-1's pressure.

---

#### IG-9. Wired-but-bypassable env-var disables on Gen 6 narrative-integrity hooks — score 3

**The rule:** Gen 6 narrative-integrity hooks (`deferral-counter.sh`, `transcript-lie-detector.sh`, `imperative-evidence-linker.sh`, `goal-coverage-on-stop.sh`, `continuation-enforcer.sh`) each support a `*_DISABLE=1` env-var bypass.

**The right path:** address the underlying narrative gap (surface deferrals, reconcile claims, link imperatives to evidence).

**The wrong path:** `export DEFERRAL_COUNTER_DISABLE=1` (or equivalent) in the session env. Logged nowhere; invisible to audit.

**The evidence:** memory entry `feedback_loud_is_not_rare.md` verbatim: *"Loud is not rare for an LLM — env-var 'overrides' are theater; audit-logged escape hatches are no harder to use than --force."*

The retry-guard's 3-strike downgrade is the right *audit-logged* bypass for these hooks. The env-var disables are redundant AND invisible.

**The fix:** remove the env-var disables OR convert them to logged overrides (write to `unresolved-stop-hooks.log` with `DISABLED_BY_ENV=true`). HARNESS-GAP-22 (2026-05-06) already tracks: "sweep harness for other escape-hatch flags / env-vars; remove or convert to non-LLM-satisfiable friction."

**Score: 3** because env-var bypass is invisible to audit; the retry-guard's 3-strike pattern is the right shape for these hooks already.

---

### 3d. Score distribution

| Score | Count | Class |
|---|---|---|
| 0 | 7 | Right path is also easier |
| 1 | 26 | Symmetric — discipline + visible bypass |
| 2 | 11 | Low-risk imbalance |
| 3 | 6 | High incentive gap (IG-2, IG-4, IG-5, IG-6, IG-7, IG-9) |
| 4 | 3 | Severe incentive gap (IG-1, IG-3, IG-8) |
| 5 | 0 | None — the harness has no rules where bypass is the default |

**Total rules scored: 53** (not 84 — agents, scripts, and pure-pattern docs don't take a score; only enforcement mechanisms do).

---

## 4. Pattern smells (cross-cutting)

These are systemic patterns, not per-rule issues. Surfaced for the daily evaluator's attention.

### Smell-1. The chronic-stale-ACTIVE-plan substrate is the dominant bypass class

Every "wrong path is easier" finding above (IG-1, IG-5, IG-8 explicitly; IG-3 and IG-9 implicitly through autonomy-pressure compounding) shares one root: plans accumulate as ACTIVE because closure is not mechanically forced after build-completion. The gate that fires correctly (`product-acceptance-gate.sh`) becomes the friction the agent works around.

**This is the load-bearing finding.** Shipping the GAP-29/30/31 staleness-surfacer reduces pressure on IG-1, IG-5, IG-8 simultaneously.

### Smell-2. Text-only validation is the recurring escape hatch

`outcome-evidence-gate.sh` (text reproduction recipe), `acceptance-exempt: true` reason field (≥20 char prose), `claim-reviewer` self-invocation (no PostMessage hook), `tool-call-budget --ack` (string-pattern sentinel), `Verification: mechanical` label, `acceptance-exempt-reason:` text — all are validation surfaces where text satisfies the gate without verifying the underlying claim.

The structural class: any gate whose check is "is there text?" rather than "is the text supported by an artifact?" is a text-only validator. Text is cheap for LLMs.

**Direction (not a fix proposal yet):** convert text-only validators to artifact-cited validators where the substrate makes it feasible. `outcome-evidence-gate.sh` and `acceptance-exempt: true` are the highest-leverage candidates.

### Smell-3. Env-var disables exist alongside audit-logged escape hatches — the audit-logged path is harder

The memory entry `feedback_loud_is_not_rare.md` already names this — but the audit confirms it's a *cross-cutting* pattern, not a single rule's issue. Gen 6 narrative-integrity hooks ALL have env-var disables. The audit-logged paths (waiver files, attestation markers, `OBSERVED_ERRORS_OVERRIDE=`) are *both* logged AND no harder to use than the env disables.

The right design: remove env-var disables entirely, OR log their use to a centralized override audit log. HARNESS-GAP-22 already tracks the sweep.

### Smell-4. Self-correction velocity is high — the harness catches its own bypasses and mechanizes against them

Counter-evidence to "the rules are broken": every concentrated bypass incident in the 60-day window produced same-week mechanism work.

- Scope-waiver cluster (2026-05-03) → gate redesign (2026-05-04, same week).
- `--force` cluster (2026-05-06) → override path removed entirely (2026-05-06, same day).
- Retry-storm (2026-05-18) → Signal-3 scoping fix + FM-025 catalog entry (2026-05-19).
- Inline-PR-body emails (2026-05-22) → `pr-template-inline-gate.sh` sibling hook (2026-05-24).
- Trailing-slash gitlink false-positive (2026-05-22) → 4 self-test scenarios added (2026-05-24).

**The audit's job is to surface what hasn't been corrected yet** — which is overwhelmingly in two buckets: chronic-stale-plan substrate (Smell-1) and acknowledged residual gaps in `vaporware-prevention.md` (Smell-2 IG-2, IG-3).

### Smell-5. The hooks-shipped-but-not-wired list is healthy

~13 hooks ship but aren't wired in `settings.json.template` (e.g., `pre-commit-tdd-gate.sh`, `propagation-trigger-router.sh`, `continuation-enforcer.sh`). Spot-check confirms most are invoked indirectly (pre-commit chain, git hooks) or deferred (propagation engine awaiting pilot evidence). Two appear to be genuinely orphaned and deserve a check: `external-monitor-alert-surfacer.sh`, `continuation-enforcer.sh`. These are listed as wired in `vaporware-prevention.md` but not in `settings.json.template`. Worth resolving.

---

## 5. Prioritized fix list

Ranked by (impact / effort). Each fix is concrete, tractable, and has a clear effort estimate. Coupling notes show which fixes depend on or enable others.

| # | Fix | Effort | Expected impact | Couples with |
|---|---|---|---|---|
| **1** | **Ship GAP-29/30/31 stale-ACTIVE-plan staleness surfacer + waiver-density alarm.** SessionStart hook + Stop-hook extension. Surfacer warns when plan has >14d since last commit/checkbox-flip; alarm BLOCKS Stop when same plan accumulates >5 waivers in 7 days. | medium (1 day) | High. Closes root cause of IG-1, IG-5, IG-8 simultaneously. ~95% reduction in chronic-stale plan substrate downstream. | IG-1, IG-5, IG-8 — fixing this defers all three |
| **2** | **Close `tool-call-budget --ack` direct-Write bypass with HMAC sentinel.** Per-session HMAC the agent knows but cannot easily extract; sentinel format is `REVIEW COMPLETE <HMAC>` where HMAC = `hmac(session_id, plan_path, "ack")`. | medium (half-day) | Medium. Closes IG-2 (acknowledged residual). Removes the only writeable text-only attestation. | Smell-2 |
| **3** | **Instrument `claim-reviewer` self-invocation rate.** Add to daily harness-evaluator: count Task-tool invocations of `claim-reviewer` per session vs. count of assistant messages containing feature-claim verb patterns ("works", "is done", "supports", "handles"). Surface ratio as Section 1 metric. | small (2 hr) | Medium. Converts IG-3 from "unknown bypass rate" to "measurable bypass rate." Doesn't close the gap but makes it visible. | Daily evaluator Section 1 |
| **4** | **Strengthen `acceptance-exempt: true` + `prd-ref: n/a — harness-development` carve-outs with mechanical check.** `plan-reviewer.sh` extension: if either carve-out is declared AND `## Files to Modify/Create` contains downstream-product file shapes (`src/`, `app/`, `pages/`, `supabase/`, `prisma/`), FAIL with "carve-out claimed but scope contains product files." | small (2 hr) | Medium. Closes IG-5. Prevents downstream-product slip into the harness-dev exemption channel. | Smell-2 |
| **5** | **Add Tier-A runtime-keyword check on `Verification: mechanical` declarations.** `plan-reviewer.sh` Check 12 extension: if `Verification: mechanical` AND task description contains (page, route, button, form, webhook, cron, endpoint, API, migration, RLS policy, auth flow), FAIL with "runtime keyword detected; consider `Verification: full`." | small (2 hr) | Medium. Closes IG-6. Prevents runtime tasks from being labeled mechanical to skip the functionality-verifier dispatch. | IG-6 |
| **6** | **Audit-log all env-var hook disables.** Sweep `*_DISABLE=1` env vars in Stop hooks; convert each to write `.claude/state/env-override-YYYY-MM-DD-<hook>-<session>.log` so the override is logged the same way `OBSERVED_ERRORS_OVERRIDE` is. | small (2 hr) | Medium-low. Closes IG-9. Resolves HARNESS-GAP-22 sweep. | Smell-3 |
| **7** | **Verify Stop-hook retry-guard 3-strike downgrade actually fires.** Add `DOWNGRADED=true` flag to `unresolved-stop-hooks.log` entries; retroactively verify the 2026-05-18 conv-tree-ui retry-storm against the new format. If the downgrade did NOT fire, investigate counter-increment path. | small (2-4 hr investigation + small fix) | Medium-low. Closes IG-4. Observability into the retry-guard's behavior. | IG-4 |
| **8** | **Convert `outcome-evidence-gate.sh` text-only recipe escape hatch to artifact-cited recipe.** Recipe must include either (a) artifact-file citation OR (b) `verify:` command line the harness can replay. Pure-prose recipes lose privilege. | small (3 hr) | Medium-low. Closes IG-7. Smell-2 example most amenable to mechanization. | Smell-2 |
| **9** | **Wire `continuation-enforcer.sh` and audit `external-monitor-alert-surfacer.sh` status.** Both are documented in `vaporware-prevention.md` but not wired in `settings.json.template`. Either wire them or remove from the inventory. | trivial (1 hr) | Low. Honest accounting; small surface area. | Smell-5 |
| **10** | **Add backlog-entry mechanical check for `harness-reviewer` chronic carve-out audit.** Per `acceptance-scenarios.md`: "Chronic exemption use without substantive reason is itself a signal — surface it in the weekly `/harness-review`." Today this is Pattern-only. Add a Check 14 to `/harness-review` skill that lists plans declaring carve-out alongside their `## Files to Modify/Create` for human review. | trivial (1 hr) | Low. Closes the audit-loop on Smell-2. | Smell-2, IG-5 |

**Coupling note:** fixes #1, #4, #5 all directly address Smell-1 (chronic-stale-plan substrate). Shipping #1 alone reduces pressure on #4 and #5; shipping all three closes the substrate.

**Tractability check:** every fix above is < 1 day of effort. No "fundamentally redesign X" items — the audit's discipline (per the charter: "Don't recommend fixes unless they're tractable") is honored.

---

## 6. Coordination with in-flight sessions

### 6a. Harness-evaluator (`local_bb36c9bf` / `feat/drift-backlog-and-harness-evaluator`)

The daily evaluator (`adapters/claude-code/scripts/harness-evaluator.sh`, agent at `adapters/claude-code/agents/harness-evaluator.md`) is already shipped and writes packets to `.claude/state/harness-eval/YYYY-MM-DD-harness-self-eval.md`.

**Integration via Section 5 (own track record):** the evaluator's Section 5 is a placeholder until 2+ packets exist. The audit's prioritized fix list becomes the recommendation pointer-set the evaluator tracks over time:

- For each fix #1-10 above, the evaluator should grep recent commits for `HARNESS-GAP-N` IDs and `IG-N` IDs referenced in PR titles / commit messages, then bucket each as acted-on / partially-shipped / ignored.
- Section 1 (bypass tally) already tracks the live counts that change as fixes ship — e.g., if Fix #1 ships, the acceptance-waiver count should drop materially over the following weeks.
- Section 4.3 (KNOWN-weak rules) currently cites 3 items from `vaporware-prevention.md`; this audit confirms those 3 + adds IG-1, IG-5, IG-8 to the KNOWN-weak roster. Worth a one-time `harness-evaluator.sh` extension that reads from THIS audit file as one of its inputs.

**Recommended message to local_bb36c9bf** (to be sent after the audit lands):

> The systematic incentive-structure audit has shipped at `docs/reviews/agent-incentive-structure-audit-2026-05-24.md`. Three integration points:
> 1. Section 4.3 of your daily packet should add IG-1 (stale-ACTIVE-plan tax), IG-5 (acceptance-exempt downstream slip), and IG-8 (no sunsetting signal) alongside the existing 3 KNOWN-weak rules.
> 2. Section 5 (own track record) should bucket the 10 prioritized fixes by status. Suggested grep: `git log --since='<prior-packet-date>' --grep='IG-[0-9]\\|HARNESS-GAP-29\\|HARNESS-GAP-30\\|HARNESS-GAP-31'`.
> 3. Section 1 bypass tally numbers will drop materially when Fix #1 ships — the evaluator should call out the delta when it's observed.

### 6b. Decision Queue (`local_eb88629f` / `feat/decision-queue`)

The Decision Queue substrate (`adapters/claude-code/scripts/decision-queue.sh`, ADR-036) is shipped on the `feat/decision-queue` branch but not on master. The top-3 fixes (per the charter's "Top 3 highest-leverage fixes get auto-added") should be added to the queue:

```bash
~/.claude/scripts/decision-queue.sh add \
  --question "Ship the stale-ACTIVE-plan staleness surfacer + waiver-density alarm (HARNESS-GAP-29/30/31)?" \
  --project "harness" \
  --mode QUICK \
  --recommendation "Yes — closes root cause of IG-1, IG-5, IG-8. ~1 day effort. ~95% reduction in chronic-stale plan substrate downstream." \
  --counter "Adds another SessionStart hook to the chain; potential noise for non-stale plans" \
  --defer-cost "Acceptance-waiver substrate continues accumulating. 1,369 waivers downstream is the data point." \
  --source-link "docs/reviews/agent-incentive-structure-audit-2026-05-24.md" \
  --source-link "docs/backlog.md" \
  --source-session "$CLAUDE_SESSION_ID" \
  --downstream "IG-1:1" --downstream "IG-5:1" --downstream "IG-8:1"
```

Plus equivalent `add` invocations for Fix #2 (HMAC sentinel) and Fix #3 (`claim-reviewer` rate instrumentation). The actual `add` commands will be issued in a follow-up turn once the audit lands (the Decision Queue lives on a separate branch and `decision-queue.sh` may not be in the current branch's PATH).

**Recommended message to local_eb88629f** (to be sent after the audit lands):

> Three Decision Queue items proposed from the systematic incentive-structure audit:
> 1. Stale-ACTIVE-plan staleness surfacer + waiver-density alarm (couples HARNESS-GAP-29/30/31; closes IG-1, IG-5, IG-8 simultaneously)
> 2. HMAC sentinel for tool-call-budget --ack (closes IG-2, the only writeable text-only attestation in the substrate)
> 3. claim-reviewer self-invocation rate instrumentation (converts IG-3 from unknown bypass rate to measurable)
> Audit: `docs/reviews/agent-incentive-structure-audit-2026-05-24.md`. Effort estimates and coupling notes in Section 5.

The user's charter notes "Top 3 highest-leverage fixes get auto-added to the in-flight Decision Queue" — but since the queue's `add` script lives on a separate branch, this is a coordination handoff, not a unilateral write.

---

## 7. What surprised me

- **The harness is *actively self-correcting*.** Every concentrated bypass incident in the 60-day window produced same-week mechanism work. I expected to find a long tail of "we should have done X" — instead, the harness's own self-evaluator is already tracking this in Section 4.4 and a stack of mechanism PRs landed 2026-05-22 through 2026-05-24 explicitly to close bypass paths.
- **The `--no-verify` panic is misplaced.** 0 actual uses on master in 60 days. The 17 commit-message and 63 content-diff hits are all *meta* (gate work itself). The local + server-side defense shipped 2026-05-24 is a hardening *against future use*, not a response to chronic use.
- **0 bug-persistence-waivers, 0 DAG-review-waivers, 0 observed-errors-overrides.** Three of the harness's substantive escape hatches are *not in use*. Either the gates are correctly calibrated to not fire spuriously, OR the agent has internalized the discipline. Either way, this is the empirical answer to "is the right path winning?" for those three rules.
- **PR-template (c) usage is healthy.** 4 of 30 recent PRs selected (c), all on legitimate categories (validator-fix self-recursion, UI polish, pure docs, layout). No reflexive abuse.
- **The chronic-stale-ACTIVE-plan substrate is THE bypass class.** 1,369 acceptance-waivers downstream. This was already documented in HARNESS-GAP-29/30/31 — but the audit confirms it's the single highest-leverage cleanup target *because three independent incentive gaps all collapse onto it*.
- **The harness-evaluator's design is correct.** Its 7-section format anticipated almost everything this audit surfaces. The audit's complementary value is the one-time *systematic* sweep that the evaluator's daily cadence is too short to perform. After this lands, the evaluator is the right venue for ongoing tracking.

---

## 8. Limitations and honesty notes

- **I did not score every individual rule's substance.** The 26 rules in the score-1 bucket are not analyzed individually; they're listed with one-line "why right-path wins" justifications. If a future audit suspects one of them has drifted, it should be re-scored against actual bypass data.
- **`Verification: mechanical` distribution (193 instances) was not exhaustively audited for misuse.** Spot-check suggests legitimate harness-dev shape, but full audit would require reading each task line in context.
- **The 2026-05-18 conv-tree-ui retry-storm is a load-bearing data point** for IG-4 (retry-guard threshold). The audit could not verify from the log alone whether the 3-strike downgrade fired. Fix #7 is the resolution: instrument first, then judge.
- **Downstream-project bypass numbers (1,369 acceptance-waivers, 200 on one plan)** come from HARNESS-GAP-29/30/31's filing notes — the audit did not re-verify those counts in the downstream repo today, because the downstream repo is outside the Neural Lace audit scope. If those numbers have changed, Fix #1's impact estimate may need adjustment.
- **In-flight session IDs `local_bb36c9bf` and `local_eb88629f` are not directly named in committed artifacts.** Their scope was inferred from role descriptions matching the work on `feat/drift-backlog-and-harness-evaluator` and `feat/decision-queue` branches. If the user intended different sessions, the coordination notes (Section 6) target the right *substrates* even if the session IDs differ.
- **Per the charter, this audit is READ-ONLY against the harness.** No fixes are implemented here. The PR opening this audit on a docs-only branch is the entire deliverable.
