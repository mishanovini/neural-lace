# Queued Decisions — Tranche 1.5 (Architecture Simplification)

**Date:** 2026-05-05
**Authority:** ADR 027 (autonomous decision-making process) — this is the inaugural decision queue
**Parent plan:** `docs/plans/architecture-simplification.md`
**Reviewer:** Maintainer (asynchronous review)

> **For the user:** below are the decisions the orchestrator will face during Tranches C, D, E, F, G of architecture-simplification. Each has options + tradeoffs + a recommendation. **Reversible decisions proceed with the recommendation if you don't override before the orchestrator hits them.** Irreversible decisions (none in this queue today; all listed are reversible) would pause and wait. Override any recommendation by editing this file with your decision; the orchestrator reads the queue at each tranche kickoff.

> **For the orchestrator:** read this file at the start of each tranche. Apply the user's overrides where present. Default to the recommendation where the user has not amended.

---

## Tranche C — Work-Shape Library

### C.1 — How many work-shape categories to seed initially?

**Question:** The work-shape library catalogs recurring task classes. How many do we seed in the v1 ship vs deferring to as-needed expansion?

**Options:**
- **A:** Seed 6 (build-hook, build-rule, build-agent, author-ADR, write-self-test, doc-migration). Cost: ~3-4 days of authoring; covers ~80% of harness-dev work. Benefit: the most common shapes are mechanical-checked from day one.
- **B:** Seed 3 (build-hook, build-rule, author-ADR). Cost: ~1-2 days. Benefit: fast ship; expansion grows from observed gaps.
- **C:** Seed 12 (the 6 above + build-skill, build-template, write-discovery, write-review, refactor-existing-hook, sync-mirror). Cost: ~6-8 days. Benefit: maximum coverage.

**Recommendation:** A (seed 6). Reversible — adding more shapes later is purely additive.

**Reversibility:** REVERSIBLE.

**User override (if any):**

---

### C.2 — Where to store shape templates?

**Question:** Shape templates need a canonical location. Where?

**Options:**
- **A:** `adapters/claude-code/work-shapes/` mirroring to `~/.claude/work-shapes/`. Cost: standard pattern. Benefit: consistent with existing rules/, hooks/, agents/, skills/, templates/ directories.
- **B:** `adapters/claude-code/templates/work-shapes/` (subdirectory of templates). Cost: slight nesting. Benefit: emphasizes that work-shapes ARE templates conceptually.
- **C:** `build-doctrine-templates/work-shapes/` — co-located with the doctrine's template system. Cost: couples harness work-shapes to the doctrine's templates structure. Benefit: doctrinal alignment.

**Recommendation:** A (top-level `work-shapes/`). The harness is its own client; co-locating with the existing top-level structure is most discoverable. Templates dir is for plan/decision/completion-report generic shapes; work-shapes is a different concept.

**Reversibility:** REVERSIBLE — single rename if we change.

**User override (if any):**

---

### C.3 — Format: Markdown with YAML frontmatter or pure JSON?

**Question:** Each shape needs structure (file paths, test patterns, mechanical-check definitions) AND prose (worked example, when-to-use). What format?

**Options:**
- **A:** Markdown with YAML frontmatter for the structured part. Cost: standard pattern, used by every existing harness file. Benefit: human-readable, consistent.
- **B:** Pure JSON. Cost: harder to read; can't embed prose easily. Benefit: machine-parseable end-to-end.
- **C:** Markdown with a fenced code block of YAML for the structured part. Cost: slightly more parsing work. Benefit: same human-readability without frontmatter conventions.

**Recommendation:** A (Markdown + YAML frontmatter). Matches every existing harness pattern (rules/, agents/, skills/ all use this).

**Reversibility:** REVERSIBLE — convert format with a sed pass if we change.

**User override (if any):**

---

### C.4 — Mechanical compliance check format

**Question:** Each shape declares mechanical checks (e.g., "files match this glob," "self-test exits 0," "frontmatter has these keys"). How are checks specified?

**Options:**
- **A:** Bash regex / grep patterns inline in the shape's YAML frontmatter. Cost: limited expressiveness. Benefit: no new tooling; immediately runnable via bash.
- **B:** Custom check DSL (e.g., `check: file-exists; check: self-test-passes; check: frontmatter-keys: [foo, bar]`). Cost: design + implement a DSL. Benefit: more expressive.
- **C:** Pluggable — frontmatter declares check names; check implementations live as bash scripts in `work-shapes/checks/`. Cost: more files to maintain. Benefit: complex checks possible.

**Recommendation:** A (inline regex/grep) for v1. Simple is reliable. Escalate to C if v1 hits expressiveness limits.

**Reversibility:** REVERSIBLE — migrate format when escalating.

**User override (if any):**

---

## Tranche D — Risk-Tiered Verification

### D.1 — Three tiers (mechanical/full/contract) or more granular?

**Question:** Per-task verification level granularity.

**Options:**
- **A:** Three: `mechanical` (bash check), `full` (task-verifier agent), `contract` (schema/golden-file). Cost: simple. Benefit: covers ~95% of cases per the discovery's analysis.
- **B:** Five: above three plus `runtime` (executes a runtime command, like the existing runtime-verification entries) and `none` (explicit skip with rationale). Cost: more configuration surface. Benefit: matches the doctrine's gate categorization more precisely.
- **C:** Two: `default` (mechanical when possible, escalate as-needed) and `manual` (orchestrator escalates explicitly). Cost: hides the categorization. Benefit: simplest possible.

**Recommendation:** A (three tiers). Matches the doctrine's `04-gates.md` categorization of mechanical, test (contract = schema validation), and adversarial review (full = task-verifier agent). Reversible.

**Reversibility:** REVERSIBLE — additional tiers can be added in a future iteration.

**User override (if any):**

---

### D.2 — Default verification level when not specified?

**Question:** When a task doesn't declare a `Verification:` field (transitional period for existing plans), what do we treat it as?

**Options:**
- **A:** `full` (current task-verifier mandate). Cost: maintains overhead during transition. Benefit: backward-compatible; no surprise downgrades.
- **B:** `mechanical`. Cost: existing plans suddenly run lighter verification. Benefit: immediate overhead reduction.
- **C:** Block plan validation if `Verification:` is missing on R2+ tasks; allow on R0/R1. Cost: forces planners to declare. Benefit: discipline-forcing.

**Recommendation:** A (default `full`) for backward compat. New plans use the field explicitly; legacy plans operate as before. Migrate to C in a follow-up.

**Reversibility:** REVERSIBLE — change default with one-line update to plan-reviewer.sh.

**User override (if any):**

---

### D.3 — Where does `Verification:` declaration live in plan task syntax?

**Question:** How do tasks declare their verification level?

**Options:**
- **A:** Inline at end of task description: `- [ ] 1. Build the X — Verification: mechanical`. Cost: conventional. Benefit: visible, parseable.
- **B:** New separate section: `## Verification Levels` listing per-task levels. Cost: split source-of-truth. Benefit: easier to override globally.
- **C:** YAML frontmatter on the plan: `verification_levels: { 1: mechanical, 2: full, 3: mechanical }`. Cost: harder to read. Benefit: all-in-one-place override.

**Recommendation:** A (inline, end-of-task). Visibility wins; the per-task discipline is "look at the task, see the level." Sed-migrable later.

**Reversibility:** REVERSIBLE — migration via parsing.

**User override (if any):**

---

## Tranche E — Deterministic Close-Plan Procedure

### E.1 — Implementation language: bash, python, or slash-command-wrapping-bash?

**Question:** The deterministic close-plan procedure replaces the current `/close-plan` skill. What language?

**Options:**
- **A:** Bash script at `adapters/claude-code/scripts/close-plan.sh`, invokable via `/close-plan` slash command (skill wrapping the script). Cost: bash is verbose for complex flows. Benefit: consistent with existing harness scripts; no new runtime dependency.
- **B:** Python script. Cost: introduces python as a runtime requirement; new dependency surface. Benefit: more expressive for complex closure logic.
- **C:** Pure slash command (markdown-only skill). Cost: limited to what a skill prompt can describe. Benefit: aligns with existing skill conventions but doesn't run mechanical checks deterministically.

**Recommendation:** A (bash script wrapped by slash command). Closure logic IS mechanical; bash is the right granularity. Python's expressiveness isn't needed; the runtime cost (new dependency for future-fresh-installs) is.

**Reversibility:** REVERSIBLE — port to python in v2 if bash hits limits.

**User override (if any):**

---

### E.2 — Should close-plan auto-push, or commit only?

**Question:** After closure (Status flip + auto-archive), does the procedure also push to remotes?

**Options:**
- **A:** Commit only; orchestrator pushes per existing default-push rules. Cost: a separate step. Benefit: consistent with existing customer-tier branching policy and explicit per-action authorization patterns.
- **B:** Auto-push by default (consistent with the user's stated full-auto + always-deploy preference per memory `feedback_full_auto_deploy.md`). Cost: less granular control over push timing. Benefit: closure is fully turnkey.
- **C:** Auto-push if `Mode: code` (small reversible work) AND not on master without an open PR; pause for user otherwise. Cost: more complex logic. Benefit: nuanced default per work type.

**Recommendation:** B (auto-push default). The user's memory explicitly says "Always full-auto mode; always deploy immediately." Closure should match that pattern. Reversible: if the auto-push lands a wrong commit, revert + redeploy (the existing customer-tier branching policy).

**Reversibility:** REVERSIBLE.

**User override (if any):**

---

### E.3 — Closure-check failure behavior: block, or surface and offer to skip?

**Question:** When a closure check fails (e.g., test suite red, files missing), what does the procedure do?

**Options:**
- **A:** Block by default; clear remediation message naming the failed check; `--force` flag for emergency override (logged for audit). Cost: occasional friction when a check produces a false-positive. Benefit: protective by default.
- **B:** Surface with a confirmation prompt; orchestrator says "proceed?" and either user replies or some default fires. Cost: pauses the closure. Benefit: user-in-loop on edge cases.
- **C:** Surface as warning; proceed regardless. Cost: removes the protection. Benefit: never blocks.

**Recommendation:** A (block by default with `--force` escape). Closure protections exist for real reasons; bypass is logged. Aligns with existing gate-block patterns.

**Reversibility:** REVERSIBLE — change default behavior with one-line update.

**User override (if any):**

---

## Tranche F — Failsafe Audit (for retirement)

### F.1 — Per-gate scoring: KEEP / SCOPE-DOWN / RETIRE classification?

**Question:** The 50-row enforcement map needs gate-by-gate triage. What's the scoring rubric?

**Options:**
- **A:** Three buckets — KEEP (still load-bearing), SCOPE-DOWN (subsumed by new mechanism but partial), RETIRE (redundant with new substrate). Cost: judgment per gate. Benefit: matches the discovery's recommendation.
- **B:** Four buckets — above three plus DEFER (decision pending more usage data). Cost: defers some decisions. Benefit: avoids premature commitment.
- **C:** Numerical scoring (each gate scored 0-5 on "load-bearing" + 0-5 on "subsumed by new substrate"; aggregate dictates action). Cost: pseudo-precision over judgment calls. Benefit: explicit weights.

**Recommendation:** A (three buckets with rationale per gate). Avoids decision-deferral; commits to clear actions.

**Reversibility:** REVERSIBLE — re-classify any gate based on observed need post-retirement.

**User override (if any):**

---

### F.2 — Retire all classified gates in one commit, or one-at-a-time?

**Question:** Sequencing of the actual retirements after classification.

**Options:**
- **A:** One-at-a-time, each in its own commit, each with its own self-test confirming nothing breaks. Cost: more commits, more time. Benefit: each retirement is independently revert-able.
- **B:** All retire-bucket gates in one commit. Cost: harder to revert a single retirement. Benefit: faster.
- **C:** By gate-category (e.g., all closure-gates, then all evidence-gates, etc.). Cost: middle-ground. Benefit: groups related risk together.

**Recommendation:** A (one-at-a-time). The whole point of the redesign is reversibility; retirement granularity should match.

**Reversibility:** REVERSIBLE — each retirement is its own revert.

**User override (if any):**

---

### F.3 — Threshold for "still load-bearing"?

**Question:** What signal indicates a gate should be KEPT vs RETIRED?

**Options:**
- **A:** Gate has fired in the last 30 days OR catches a class no other gate catches. Cost: requires log review. Benefit: empirical.
- **B:** Gate is in the doctrine's gate matrix (`04-gates.md`) AND its enforcement implementation matches the doctrine's spec. Cost: requires per-gate audit. Benefit: alignment with architectural source.
- **C:** Both A and B (must satisfy both). Cost: stricter retirement bar. Benefit: dual signal.

**Recommendation:** C (both). Empirical (it's used) AND architectural (doctrine wants it). Aligns with ADR 026's "harness catches up to doctrine" framing.

**Reversibility:** REVERSIBLE.

**User override (if any):**

---

## Tranche G — Calibration Loop Bootstrap

### G.1 — Where do calibration entries live?

**Question:** Each builder/reviewer failure produces a calibration entry. Where?

**Options:**
- **A:** `.claude/state/calibration/<agent-name>.md` (per-agent files; gitignored locally). Cost: not version-controlled. Benefit: keeps personal/operational data out of harness repo.
- **B:** `docs/calibration/<agent-name>.md` (committed). Cost: harness repo grows over time. Benefit: shareable; survives across machines.
- **C:** Findings ledger entry per calibration event (extending `docs/findings.md` shipped 2026-05-04). Cost: mixes calibration with findings. Benefit: single durable substrate.

**Recommendation:** A (gitignored state) for v1. Calibration is largely operational; promotion to durable artifacts happens via the existing knowledge-integration ritual (Build Doctrine Phase 5, deferred). C is a candidate after the ritual lands.

**Reversibility:** REVERSIBLE — migrate to B/C in a future iteration.

**User override (if any):**

---

### G.2 — Manual calibration cadence vs telemetry-gated?

**Question:** Without telemetry (HARNESS-GAP-11 is gated on 2026-08), how does calibration land?

**Options:**
- **A:** Discipline-only: every observed failure produces a calibration entry (manual write); /harness-review skill periodically rolls them up. Cost: relies on discipline. Benefit: shippable now without telemetry.
- **B:** Defer all calibration work until telemetry lands. Cost: months of unmechanized failures. Benefit: cleaner mechanical pipeline.
- **C:** Build a lightweight manual-entry skill (`/calibrate <agent> <observation>`) that captures entries with a structured format; mechanize the roll-up post-telemetry. Cost: small skill build. Benefit: reduces friction of manual entry.

**Recommendation:** C (lightweight skill). A is too discipline-heavy; B defers value. C makes calibration easy now and mechanizes the rollup later.

**Reversibility:** REVERSIBLE — drop the skill if it doesn't get used.

**User override (if any):**

---

## Decisions taken so far in this session (for awareness — already landed)

These are the autonomous decisions the orchestrator made during the architecture-simplification work BEFORE this queue file existed. ADR 027 establishes the new pattern; these are documented retrospectively for completeness:

- **Lightweight closure for GAP-16 + Tranche 0b** (per user directive 2026-05-05): closed via commit-SHA-citation evidence rather than per-task task-verifier dispatch. Auto-archived. Reversible (re-open + re-close with full evidence if desired).
- **Tranche 1.5 sub-tranche dispatch order**: A+B parallel, then D, then E, then F; C and G off the critical path. Per integration review's analysis. Reversible.
- **Codename anonymization in migrated doctrine docs**: 3 of 8 doctrine docs sanitized to generic placeholders per harness-hygiene rule. Reversible via sed in reverse.
- **Path-shape exemption for `build-doctrine/*` and `build-doctrine-templates/*`** in `harness-hygiene-scan.sh`. Reversible.
- **`build-doctrine-templates` same-repo placement** (ADR 025). Reversible via `git subtree split`.

---

## How to respond to this queue

**Option 1 (preferred):** Edit the **User override (if any):** line under each decision with your answer. The orchestrator reads this file at each tranche kickoff and applies your overrides.

**Option 2:** Reply in chat with the decision identifiers + your overrides (e.g., "C.1: B; D.2: C"). The orchestrator updates this file based on your reply.

**Option 3:** Don't override; let the orchestrator proceed with recommendations. All listed decisions are reversible.

The orchestrator proceeds with recommendations on any decision the user doesn't override before the orchestrator hits it during execution. Each recommendation, if applied, will be documented as either a Decisions Log entry in the relevant plan OR a dedicated ADR per ADR 027 Layer 3.
