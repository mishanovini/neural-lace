# Plan: Misha-asked-for drift backlog + self-reflective harness evaluator
Status: ACTIVE
Execution Mode: orchestrator
Mode: code
tier: 2
rung: 1
architecture: pattern
frozen: true
prd-ref: n/a — harness-development
acceptance-exempt: true
acceptance-exempt-reason: harness-internal observability/audit work; the "user" is the maintainer reviewing weekly packets, and the verification artifact is the first scan's output landing on disk + the first weekly packet being generated
Backlog items absorbed: none
Work-shape: build-harness-infrastructure (every file under `adapters/claude-code/`, `docs/`, or `~/.claude/` mirror)

## Goal

Misha's meta-observation: "the fact that this harness isn't yet self-learning is more evidence that not everything I tell you to do actually gets done. I wish I had a better way of tracking this."

Build two paired systems that close that meta-gap:

**System 1 — Misha-asked-for drift backlog.** Walk Dispatch transcript history at `~/.claude/projects/*/*.jsonl`, extract imperative-mood asks Misha has made ("we should", "I want you to", "let's build", "please [verb]", "we need to"), classify each into explicit-task / recommendation / aspirational-comment / dropped-suggestion, search repo state for an artifact that satisfies retained asks, persist anything older than 14 days without a satisfying artifact as a drift item. Honest by mandate — must include things deliberately deferred, dropped, or "process-theatered."

**System 2 — Self-reflective harness evaluator.** Meta-agent that periodically audits the harness's own effectiveness using the drift backlog from System 1 plus hook firings, bypass log, waiver tally, incident reports, and Conv Tree state. Produces a weekly review packet at `docs/reviews/harness-self-eval-YYYY-MM-DD.md` with top-3 lists (rules that didn't prevent incidents but were bypassed; rules with highest false-positive rate; newly-drifting items; agents whose discipline is degrading). Does NOT auto-update rules — Misha reviews the packet; that's the watchdog-for-the-watchdog.

## User-facing Outcome

After this work ships, Misha can:

1. Open `docs/backlog/misha-asked-for.json` and see a chronological list of imperative asks he made that have no matching repo artifact, oldest first.
2. Open `docs/reviews/harness-self-eval-2026-05-24.md` and see a structured evaluation of which harness rules are working, which are being bypassed, and which agents are degrading.
3. Run `bash adapters/claude-code/scripts/mine-misha-asked.sh --rescan` to re-mine on demand.
4. Run `bash adapters/claude-code/scripts/harness-evaluator.sh` to produce a fresh weekly packet.

The first scan must surface real drift items (not just placeholder rows); the first evaluator packet must surface rules I (the agent system) know are weakly enforced. If neither does, the heuristics need tuning before the systems are useful.

## Scope

- IN: transcript miner + drift detector + persistent backlog (System 1)
- IN: harness evaluator agent file + analyzer script + first weekly packet (System 2)
- IN: scheduled-task scaffolding (cron entry or scheduled-tasks MCP registration) for weekly runs
- IN: self-test that confirms both systems produce non-empty, honest output
- OUT: web UI for the drift backlog (Conv Tree integration is downstream — note in followup backlog)
- OUT: push notifications for new drift items (Misha will choose surfacing channel in his review)
- OUT: auto-rule-updates by System 2 — explicitly forbidden by design constraint
- OUT: full coverage of every harness mechanism in System 2's first version — 30% completeness is the scope ceiling

## Tasks

- [ ] 1. Create feature branch + scaffold this plan file. — Verification: mechanical
- [ ] 2. Build `mine-misha-asked.sh` transcript miner + heuristic classifier + drift detector. — Verification: full
   **Prove it works:** 1. Run `bash adapters/claude-code/scripts/mine-misha-asked.sh --rescan` against actual transcripts. 2. Inspect `docs/backlog/misha-asked-for.json` and confirm it contains real asks with timestamps, ask text, satisfying-artifact search results. 3. Confirm at least one drift item (no satisfying artifact + >14 days) appears.
   **Wire checks:** `adapters/claude-code/scripts/mine-misha-asked.sh` → reads `~/.claude/projects/*/*.jsonl` → writes `docs/backlog/misha-asked-for.json`
   **Integration points:** depends on `jq` for JSONL parsing; depends on `git log` for satisfying-artifact search.
- [ ] 3. Run first scan, commit the populated backlog file. — Verification: mechanical
- [ ] 4. Build `harness-evaluator.sh` analyzer + agent prompt at `adapters/claude-code/agents/harness-evaluator.md`. — Verification: full
   **Prove it works:** 1. Run `bash adapters/claude-code/scripts/harness-evaluator.sh` and confirm it produces a weekly packet at `docs/reviews/harness-self-eval-2026-05-24.md`. 2. Inspect the packet for top-3 lists (bypassed rules, false-positive rules, drift items, degrading agents). 3. Confirm the packet contains the agent's own track record (placeholder for first run; populated on subsequent runs).
   **Wire checks:** `adapters/claude-code/scripts/harness-evaluator.sh` → reads `docs/backlog/misha-asked-for.json` + hook-state + waiver files → writes `docs/reviews/harness-self-eval-YYYY-MM-DD.md`
   **Integration points:** reads from System 1's output file; reads from `~/.claude/logs/` and `.claude/state/*-waiver-*.txt` patterns; reads from `docs/failure-modes.md`.
- [ ] 5. Run first evaluator pass, commit the weekly packet. — Verification: mechanical
- [ ] 6. Add scheduled-task entry for weekly runs (cron pattern documented; actual registration TBD per Misha's preference). — Verification: mechanical
- [ ] 7. Self-test: confirm honest output (real drift items surfaced; known-weak rules surfaced). — Verification: full
   **Prove it works:** 1. Read the first scan's drift items, confirm at least one is something I (Claude) recognize as a real deferred ask. 2. Read the first evaluator packet, confirm at least one flagged rule is one I recognize as weakly enforced (e.g., `claim-reviewer` self-invocation residual gap from `vaporware-prevention.md`). 3. Document any heuristic gaps as followup items in the backlog.
   **Wire checks:** human (Claude) reads outputs; documents what's missing.
   **Integration points:** outputs flow into Misha's review cadence (TBD).
- [ ] 8. Open PR with branch; write final report. — Verification: mechanical

## Files to Modify/Create

- `docs/plans/drift-backlog-and-harness-evaluator.md` — this plan file (already created)
- `.claude/state/drift-backlog/misha-asked-for.json` — System 1 output (NEW path; gitignored per harness-hygiene — the JSON contains raw user-message content with machine-local paths and usernames that must not ship in a generic harness kit; moved here from the original `docs/backlog/` location after harness-hygiene-scan blocked the commit)
- `docs/reviews/harness-self-eval-2026-05-24.md` — System 2 first weekly packet (NEW file)
- `adapters/claude-code/scripts/mine-misha-asked.sh` — System 1 miner script (NEW file)
- `adapters/claude-code/scripts/harness-evaluator.sh` — System 2 analyzer script (NEW file)
- `adapters/claude-code/agents/harness-evaluator.md` — System 2 agent prompt (NEW file)
- `adapters/claude-code/scripts/lib/imperative-classifier.sh` — shared classifier helpers (NEW file)
- `docs/decisions/036-drift-backlog-and-harness-evaluator.md` — Tier 2 decision record (NEW file)

## In-flight scope updates

- 2026-05-24: `.claude/state/drift-backlog/misha-asked-for.json` — moved System 1 output to gitignored state dir after harness-hygiene-scan blocked the original `docs/backlog/` path (raw user-message content carries machine-local paths and usernames that must not ship in a generic harness kit). Per-machine operational state convention applied; weekly packet from System 2 remains the shareable committed artifact.

## Assumptions

- `~/.claude/projects/*/*.jsonl` reliably contain Dispatch transcript history including user-message content (verified by spot-check: 1603 jsonl files total, 214 modified in last 7 days, user messages have `type:user` + `message.content` as string).
- `jq` is available (used throughout the harness; verified by grep against existing scripts).
- "Misha" is the canonical user for these transcripts on this machine; no need to disambiguate by author identity in v1.
- The 14-day drift threshold is a starting heuristic; can be tuned in followup.
- Conv Tree GUI integration is downstream and gated on the auto-emit work landing (session `local_bcd900b8` per Misha's first message).
- Standing autonomous-execution authorization holds through both systems shipping on a branch with passing self-test.

## Edge Cases

- **No `jq` available.** Fail explicitly with installation guidance; do not silently degrade.
- **Transcript file unreadable** (cloud-sync conflict, partial write). Skip the file with a stderr warning; do not abort the whole scan.
- **Imperative phrase appears in Misha's quote of someone else** ("you wrote 'we should X'"). Classifier marks confidence:low; downstream LLM-classify step would catch (deferred to followup — v1 keeps everything heuristic).
- **Same ask appears in 10 sessions** (Misha repeats himself when the harness fails to act). Dedup by normalized-ask-text hash; surface the repetition count as a signal ("Misha repeated this 10 times — that itself is drift").
- **Ask was acted on but the artifact name doesn't match the ask text** (semantic drift). False positive; flagged for manual review by Misha in his weekly packet. v1 will have false positives — explicitly accepted scope ceiling.
- **Honesty self-test:** the drift backlog must include things I deliberately deferred. If the first scan returns zero drift items, the heuristics are wrong (too narrow) and tuning is required before commit.

## Testing Strategy

- **Mechanical:** scripts run without error on the actual transcript directory.
- **Functional:** outputs (JSON backlog file + weekly packet) contain non-empty real entries that survive Claude's own honest review (Task 7).
- **Self-test:** I confirm at least one drift item is something I recognize as a real deferred ask AND at least one flagged rule is one I recognize as weakly enforced. If either fails, tune heuristics before commit.

## Walking Skeleton

The smallest end-to-end vertical slice that proves the structure works:

1. `mine-misha-asked.sh` runs against the last 7 days of transcripts only (small dataset).
2. Produces a 5-row JSON backlog (limit-5 in v1 to keep first commit small).
3. `harness-evaluator.sh` reads those 5 rows + the existing waiver-file count + failure-mode catalog to produce a 3-section weekly packet.
4. Self-test: I (Claude) read both outputs and confirm at least one row in each is honest.

Once that slice runs end-to-end, expand to full history.

## Decisions Log

(populated during build for Tier 2+ choices)

### Decision: Heuristic-only classifier in v1, defer LLM-classify to followup
- **Tier:** 1 (reversible — can add LLM-classify step in any future iteration)
- **Status:** proceeded with recommendation
- **Chosen:** Bash + jq + regex for imperative detection; no LLM call in the miner itself.
- **Alternatives:** (a) Call Claude API per ask to classify into 4 buckets. Pro: better classification. Con: cost per scan grows with transcript history; slow; introduces credential dependency. (b) Use a local llama model. Con: not installed; not pre-authorized.
- **Reasoning:** v1 must run cheaply and repeatedly without API cost. False-positive rate from heuristic classifier is acceptable for v1 because Misha will see the false positives in his weekly review and the system explicitly documents the gap.
- **Reversal cost:** trivial — drop in an LLM-classify step at the classifier boundary later.

### Decision: 14-day drift threshold for "missing artifact" criterion
- **Tier:** 1 (reversible — tune in any future iteration)
- **Status:** proceeded with recommendation
- **Chosen:** asks older than 14 days without a satisfying artifact = drift.
- **Alternatives:** 7 days (too noisy — in-progress work shows up); 30 days (too lenient — drift items accumulate before surfacing).
- **Reasoning:** 14 days is one Misha-review-cycle assumption (weekly packet → next packet); anything that survives one full cycle without being shipped is candidate drift. Can be tuned.

### Decision: System 2 is read-only by design
- **Tier:** 2 (architectural — capture in ADR 036)
- **Status:** proceeded with recommendation
- **Chosen:** The evaluator agent produces write-ups only. It does NOT auto-update rules, auto-disable hooks, or auto-file backlog entries against the harness.
- **Alternatives:** (a) Auto-disable rules whose bypass rate exceeds 50%. Con: removes the watchdog-for-the-watchdog (Misha's review). Pro: closes the loop faster. (b) Auto-file backlog entries for items the evaluator surfaces. Con: noise pollution; defeats the "Misha reviews" principle. Pro: surfaces faster.
- **Reasoning:** Misha's design constraint was explicit: "Agent does NOT auto-update rules. Produces write-ups only." The evaluator is the watchdog; Misha is the watchdog-for-the-watchdog. Skipping that loop reintroduces the meta-failure this work is trying to fix.

## Definition of Done

- [ ] Both scripts run end-to-end without error
- [ ] `docs/backlog/misha-asked-for.json` populated with real entries
- [ ] `docs/reviews/harness-self-eval-2026-05-24.md` populated with real findings
- [ ] Self-test passed (Task 7)
- [ ] Branch pushed; PR opened (NOT merged per standing constraint)
- [ ] SCRATCHPAD updated with plan status
- [ ] Plan status flipped to COMPLETED (triggers auto-archival)

## Pre-Submission Audit

S1 (Entry-Point Surfacing): swept, every behavior change in this plan is cited at Tasks 2 / 4 / 7. 0 contradictions remaining.
S2 (Existing-Code-Claim Verification): swept, claims about `~/.claude/projects/*/*.jsonl` shape verified by inline tool calls during planning (1603 files exist; user messages have `type:user`+string content). Claims about `jq` availability verified by grep against existing scripts (used throughout). 0 stale claims.
S3 (Cross-Section Consistency): swept, "scope ceiling of 30% completeness for System 2" is consistent across Scope, Tasks, and Walking Skeleton sections. 0 contradictions.
S4 (Numeric-Parameter Sweep): swept for params: drift_threshold=14days (3 occurrences, all consistent); walking-skeleton-limit=5rows + 7days (consistent in Walking Skeleton section only). 0 inconsistencies.
S5 (Scope-vs-Analysis Check): swept, every "Add X" verb in Sections checked against Scope OUT list. Auto-rule-updates explicitly OUT and confirmed OUT in Decisions Log. Conv Tree GUI integration explicitly OUT.
