# Plan: NL Overhaul Program — The Great Consolidation (Phases 0–5)
Status: ACTIVE
Execution Mode: orchestrator
Mode: code
Backlog items absorbed: none
acceptance-exempt: true
acceptance-exempt-reason: harness-internal program; self-tests, harness-doctor --full, and the golden-scenario synthetic runner are the acceptance artifacts (no product user surface)
tier: 3
rung: 1
architecture: coding-harness
frozen: true
lifecycle-schema: v2
owner: Misha (operator); orchestrator sessions execute
target-completion-date: 2026-07-21
prd-ref: n/a — harness-development

## Goal

Execute the six-phase remediation program greenlit in DEC-2026-07-01-001 (operator: "full program"), fixing the root causes established by the 2026-07-01 effectiveness audit (`docs/reviews/2026-07-01-neural-lace-effectiveness-audit.md`): RC1 context saturation, RC2 enforcement theater, RC3 narration-targeted gates, RC4 open-circuit signal loop, RC5 unmaintained gate sprawl, RC6 deployment brittleness. Architecture is locked in ADR 058 (D1–D9). The outcome is a harness whose claimed enforcement provably fires, whose always-loaded doctrine fits in ~6K tokens, whose gates are few/strong/artifact-anchored, whose signals are consumed, and whose effectiveness is measured weekly.

## User-facing Outcome

The operator (the harness's user) can, after this program: (a) run `harness-doctor.sh --quick` in any session and get a green/red truth report of claimed-vs-actual enforcement in <2s; (b) start any session paying ≤ ~15–20K tokens of standing doctrine instead of ~230K; (c) read ONE capped digest instead of 12+ surfacer blocks and 0%-consumed side channels; (d) see weekly compliance KPIs (waiver/downgrade rates per gate, doctor drift, FM recurrence) instead of guessing whether the harness works; (e) trust that a rule classified "Mechanism" fires, because the doctor blocks drift.

## Scope

- IN: everything under `adapters/claude-code/**` (hooks, rules→constitution+doctrine split, scripts, templates, schemas, settings.json.template, manifest, new `doctrine/` and `attic/` dirs, examples, patterns, tests, work-shapes); `install.sh`; live-mirror reconciliation at `~/.claude/**` (via install, not hand-edits); `evals/**` and `.github/workflows/**`; `docs/plans/**`, `docs/decisions/**`, `docs/backlog.md`, `docs/reviews/**`, `docs/harness-architecture.md`, `docs/best-practices.md`, `docs/failure-modes.md`, `docs/findings.md`, `docs/discoveries/**`; `CLAUDE.md` (repo adapters copy); main-checkout git-state surgery (GAP-51) with backup; remote/account fetch-path fix.
- OUT: the workstreams-ui application code (`neural-lace/workstreams-ui/**`) beyond digest-mirror touchpoints; downstream product repos (Circuit etc.); Dispatch/cloud platform limitations (ADR 011/031 accepted gaps stay accepted); building orchestrator-prime (separate ACTIVE plan — dispositioned in F3, not built here); any new enforcement gate not named in ADR 058 (D7's evidence bar applies).

## Execution model (read first — how to run this plan)

- **Waves run in order: B → C → D → E → F.** Within a wave, tasks marked `Parallelizable: yes` may run concurrently, **max 4–5 builders at once**, each via `Agent`/`Workflow` dispatch with `isolation: "worktree"` and the task's declared `Model:` tier passed as the dispatch `model` param. Build in parallel, verify sequentially (orchestrator-pattern).
- **Every wave starts with its `*.0 wave-spec` task** (Model: opus-tier main session): convert this plan's interface-level specs into exact per-task mechanical specs (exact diffs/greps) as an appendix `docs/plans/nl-overhaul-program-2026-07-specs-<wave>.md`, folding in prior-wave learnings. This is what keeps every DISPATCHED task buildable by lesser models without freezing stale detail now.
- **Serialization points** (never parallel): `settings.json.template` edits, `CLAUDE.md` rewrite, `manifest.json` creation, live-mirror sync/install runs, cutover tasks (D5), main-checkout surgery (B7).
- **Rollback:** tag `pre-<wave>-cutover` before B6, C5, D5. Retired hooks move to `adapters/claude-code/attic/` (kept ≥1 release), never hard-deleted in the same wave.
- **Verification:** every task is `Verification: mechanical` — its Done-when is a command that exits 0. task-verifier flips checkboxes per the standing mandate; no comprehension-gate overhead (rung 1).
- Wave A (pre-plan, complete): origin merge into program branch (`8a6a266`), ADR 058, this plan. Recorded here as prose, not checkboxes.

## Tasks

### Wave B — Phase 0: Truth reconciliation

- [ ] B0. Wave-spec refinement for Wave B (exact per-task specs appendix; embed the audit's defect lists verbatim as work items) — Model: opus — Parallelizable: no — Verification: mechanical
  - Done-when: `docs/plans/nl-overhaul-program-2026-07-specs-b.md` exists; every B-task below has an entry with exact file paths + grep/self-test assertions.
- [ ] B1. Build `adapters/claude-code/hooks/harness-doctor.sh` per ADR 058 D4 (--quick / --full / --self-test; checks: wiring live+template vs manifest-lite checklist, hook existence/executability, lib-dep resolution, legacy-path scan, always-loaded byte budget, template-vs-live diff) — Model: sonnet — Parallelizable: yes — Verification: mechanical
  - Done-when: `bash adapters/claude-code/hooks/harness-doctor.sh --self-test` exits 0 (≥10 scenarios incl. red-detection fixtures); `--quick` against the live mirror lists the known audit defects still open at run time.
- [ ] B2. Kill legacy-path family: create `hooks/lib/nl-paths.sh` resolver (env `NL_REPO_ROOT` > `~/.claude/local/nl-repo-path` > git-derived); replace every `claude-projects/neural-lace` reference in hooks/scripts/lib (incl. `workstreams-task-bridge.js`, Gen-6 trio fallbacks) — Model: sonnet — Parallelizable: yes — Verification: mechanical
  - Done-when: `grep -rl "claude-projects/neural-lace" adapters/claude-code/hooks adapters/claude-code/scripts` returns empty; `workstreams-task-binding.sh` self-test passes; a live probe invocation writes ok:true to its log.
- [ ] B3. Fix install completeness: `install.sh` deploys `hooks/lib/` fully + the `tests/` fixtures self-tests need + `patterns/` (hygiene denylist — closes the GAP-52 silent-no-op hole) + `examples/`; add `--verify` mode that runs doctor --quick post-install — Model: sonnet — Parallelizable: yes — Verification: mechanical
  - Done-when: install to a temp HOME then `goal-coverage-on-stop.sh --self-test`, `goal-extraction-on-prompt.sh --self-test`, `imperative-evidence-linker.sh --self-test`, `decision-context-gate.sh --self-test` all exit 0 from the temp HOME; `harness-hygiene-scan.sh` finds its denylist there.
- [ ] B4. Junk + dead-ref sweep: delete the 6 expired `conversation-tree-*`/`conv-tree-*` shims and stray `hooks/.claude/state/` files; fix `feature-completion-audit.sh` dead refs (INDEX row + completion-criteria-gate.sh header); collapse the two "sole-normative module" paths to the workstreams-ui one; merge-or-delete `conv-tree-orchestrator-emit.md` into `workstreams-state.md` — Model: haiku — Parallelizable: yes — Verification: mechanical
  - Done-when: shim files absent; `grep -r "feature-completion-audit" adapters/ | grep -v attic` empty; `grep -rl "conversation-tree-ui/" adapters/claude-code/rules` empty.
- [ ] B5. Doc truth sweep (mechanical list from audit §5): correct false/stale claims — git-discipline+INDEX force-push rows (a live inline blocker EXISTS), harness-hygiene /harness-review claim, automation-modes inventory counts, six files' "landing in Phase 1d-*" lines, CLAUDE.md ≤200-line trim, session-end-protocol + CLAUDE.md continuation-enforcer claims re-stated as pending-Wave-D — Model: haiku — Parallelizable: yes — Verification: mechanical
  - Done-when: per-item grep assertions in specs-b pass (e.g., `grep -c "not yet implemented" adapters/claude-code/rules/git-discipline.md` = 0).
- [ ] B6. Wiring reconciliation + truth-classification (SERIAL, after B1–B5 merge): sync template↔live via install run; re-classify every rule whose Mechanism claim is not yet true (pending Wave D/E) with an honest status line; tag `pre-wave-b-cutover` first — Model: sonnet — Parallelizable: no — Verification: mechanical
  - Done-when: `harness-doctor.sh --quick` exits 0 against the live mirror (zero claimed-but-unwired, zero missing lib deps, zero legacy paths).
- [ ] B7. Main-checkout surgery (GAP-51): backup branch of the staged ~40-file batch, audit batch vs origin/master, drop stale reversions (FM-024..031 must survive), land the main checkout clean at origin/master — Model: sonnet (exact command script in specs-b; supervised — orchestrator reviews diff before the reset step) — Parallelizable: yes — Verification: mechanical
  - Done-when: main checkout `git status --short` empty; `git rev-list --count master..origin/master` = 0 at main checkout; backup branch exists; `grep -c "FM-03" docs/failure-modes.md` ≥ 3 there.
- [ ] B8. Remote/account fetch-path fix: resolve the `Repository not found` on `git fetch origin` under the work `gh` account (remote URLs vs account mapping); verify both-remote sync works per the standing two-remote rule — Model: sonnet — Parallelizable: yes — Verification: mechanical
  - Done-when: `git fetch origin && git fetch personal` both exit 0 from a fresh session in the repo.
- [ ] B9. Backlog reconciliation pass 1: mark the entries this program absorbs with `(absorbed by docs/plans/nl-overhaul-program-2026-07.md)` — GAP-20/21/22, synthetic-session-runner P0, waiver-density alarm, continuation-enforcer wiring, GAP-52 (via B3), GAP-53 (via D5 completion-criteria relocation), tool-call-budget --ack HMAC item (superseded by D5 retirement), GAP-42 CI self-test substrate (via E4) — and close already-fixed-but-open items (GAP-19, STALE-PLANS-01) — Model: haiku — Parallelizable: yes — Verification: mechanical
  - Done-when: each listed ID's backlog entry contains the absorbed/closed marker (grep per ID); backlog `Last updated` line refreshed.
- [ ] B10. Baseline snapshot for D7 refutation criteria: record current ledger-precursor metrics (downgrade counts, waiver counts, alert ack-rate, rules-dir bytes, Stop-chain length) to `docs/reviews/nl-overhaul-baseline-2026-07.md` — Model: haiku — Parallelizable: yes — Verification: mechanical
  - Done-when: file exists with all six numbers + reproduction commands.

### Wave C — Phase 1: Context diet

- [ ] C0. Wave-spec refinement for Wave C (incl. final rule→{constitution|doctrine|stub|delete} disposition table for all 61 rules, cluster assignments for C4, and the JIT trigger map) — Model: opus — Parallelizable: no — Verification: mechanical
  - Done-when: specs-c file exists; disposition table covers 61/61 rules (count assertion).
- [ ] C1. Manifest: `adapters/claude-code/manifest.json` + `schemas/manifest.schema.json` + `scripts/manifest-check.sh` (validates schema; disk↔manifest coverage both ways); doctor upgraded to read it — Model: sonnet — Parallelizable: no (others read it) — Verification: mechanical
  - Done-when: `manifest-check.sh` exits 0; `harness-doctor.sh --quick` consumes manifest (grep for manifest read + red-fixture self-test scenario).
- [ ] C2. JIT injector `hooks/doctrine-jit.sh` (PostToolUse Edit|Write path-pattern matching from manifest `jit_triggers`; per-session dedup markers; ≤1 injection per doctrine file per session; compact-form injection ≤1.5K tokens each) — Model: sonnet — Parallelizable: yes — Verification: mechanical
  - Done-when: `--self-test` ≥6 scenarios exits 0, including a LIVE probe scenario proving PostToolUse output reaches the transcript (fixture-based); wired in template.
- [ ] C3. Constitution: draft `rules/constitution.md` (≤350 lines: Rules 0–7 compressed, FUNCTIONALITY-OVER-COMPONENTS, persistence discipline, session-end markers, gate-respect, credentials pointer, doctrine-index pointer) + CLAUDE.md rewrite ≤100 lines — Model: opus draft → **OPERATOR REVIEW checkpoint** (the one designed human gate in this program) — Parallelizable: no — Verification: mechanical
  - Done-when: operator approval recorded in Decisions Log; `wc -c` constitution ≤ 24000 bytes; CLAUDE.md ≤ 100 lines.
- [ ] C4. Stub-rewrite sweep: surviving rules rewritten to ≤40-line stubs (enforcement pointer + trigger + one-screen substance), full prose relocated to `doctrine/`; run as parallel cluster tasks (≈8 rules per cluster, ≤5 clusters concurrent) per the C0 disposition table — Model: haiku (sonnet for the 5 largest files) — Parallelizable: yes — Verification: mechanical
  - Done-when per cluster: every file ≤ 3000 bytes; content-checklist greps from specs-c pass; doctrine/ twin exists for each.
- [ ] C5. The move + cutover (SERIAL): relocate non-constitution rules out of the auto-load dir into `doctrine/`; update install.sh mapping; regenerate INDEX from manifest (or retire INDEX per C0 decision); tag `pre-wave-c-cutover`; install + doctor — Model: sonnet — Parallelizable: no — Verification: mechanical
  - Done-when: post-install `cat ~/.claude/rules/*.md | wc -c` ≤ 30000; `harness-doctor.sh --quick` green incl. new byte-budget check; golden evals pass.
- [ ] C6. Agent/skill/template reference sweep: update every `~/.claude/rules/<name>.md` reference across agents/skills/templates/hooks to constitution-or-doctrine paths — Model: haiku — Parallelizable: yes — Verification: mechanical
  - Done-when: `grep -rl "claude/rules/" adapters/claude-code/{agents,skills,templates}` matches only constitution-set files.

### Wave D — Phase 2: Gate consolidation

- [ ] D0. Wave-spec refinement + design freeze of the final gate map (ADR 058 D5 refined by Wave B/C learnings + ledger data; operator veto window on the retirement list closes here) — Model: opus — Parallelizable: no — Verification: mechanical
  - Done-when: specs-d exists with the frozen Stop/SessionStart/PreToolUse target lists + per-retired-gate behavior-relocation notes.
- [ ] D1. `hooks/lib/signal-ledger.sh`: append-only JSONL event lib (block/warn/waiver/downgrade/skip; HARNESS_SELFTEST sandboxing built in) — Model: sonnet — Parallelizable: yes — Verification: mechanical
  - Done-when: `--self-test` exits 0; retry-guard lib routes its downgrade events through it.
- [ ] D2. `hooks/work-integrity-gate.sh`: merge pre-stop-verifier + product-acceptance + worktree-uncommitted checks, scoped to session-touched plans/files (transcript-derived), retry-guard integrated, ledger-logging — Model: sonnet — Parallelizable: yes — Verification: mechanical
  - Done-when: `--self-test` ≥12 scenarios exits 0 incl. "orthogonal ACTIVE plan does NOT block" (the waiver-tax killer) and "session-touched plan with unchecked tasks DOES block".
- [ ] D3. `hooks/session-honesty-gate.sh`: marker contract (DONE/PAUSING/BLOCKED, continuation-enforcer semantics live at last) + merged narrative heuristics demoted to ledger warnings; blocks ONLY on marker-absence/format or DONE-vs-verification-block contradiction — Model: sonnet — Parallelizable: yes — Verification: mechanical
  - Done-when: `--self-test` ≥10 scenarios exits 0 incl. "waiting-on-operator turn with PAUSING passes" (the audit's false-positive case) and "DONE while work-integrity blocked this session fails".
- [ ] D4. Relocate retired-gate behaviors: completion-criteria → `close-plan.sh` + PR-merge path; customer-facing-review → spawn-time PreToolUse warn + ledger; pr-health → digest feed; decision-context enforcement retired (emit writers kept); vaporware-volume → CI — Model: sonnet — Parallelizable: yes — Verification: mechanical
  - Done-when: per-relocation grep/self-test assertions from specs-d pass.
- [ ] D5. Cutover (SERIAL): rewrite template Stop chain to the ≤6 target and SessionStart to ≤8; retire old gates to `attic/`; tag `pre-wave-d-cutover`; install; doctor + golden evals + full self-test sweep — Model: sonnet, orchestrator-supervised — Parallelizable: no — Verification: mechanical
  - Done-when: `node -e` chain-count assertions (Stop ≤6, SessionStart ≤8) pass on BOTH template and live; doctor --full green; golden evals green.
- [ ] D6. PreToolUse rationalization: retire tool-call-budget attestation loop (soft counter → ledger/digest), fold dag-review-waiver into spawn validator, keep artifact gates — Model: sonnet — Parallelizable: yes — Verification: mechanical
  - Done-when: specs-d assertions pass; blocking-gate count ≤12 (doctor check).

### Wave E — Phases 3+4: Signal loop + telemetry

- [ ] E0. Wave-spec refinement for Wave E — Model: opus — Parallelizable: no — Verification: mechanical
  - Done-when: specs-e exists.
- [ ] E1. Digest: one SessionStart block (≤15 lines; merges the 12 surfacers' feeds: discoveries, stale plans, monitor alerts, spawned-task results, pending decisions, git freshness, worktree advice, doctor --quick, ledger summary; dedup + auto-expiry + auto-ack of repeats) + mirror into workstreams GUI — Model: sonnet — Parallelizable: yes — Verification: mechanical
  - Done-when: `--self-test` exits 0; SessionStart chain shows digest replacing the retired surfacers (count assertion).
- [ ] E2. HARNESS_SELFTEST sandbox sweep: every hook's self-test writes state/ledger to sandbox (shared helper from D1); purge existing self-test pollution from production logs — Model: haiku — Parallelizable: yes — Verification: mechanical
  - Done-when: running the full self-test sweep leaves `~/.claude/state` and ledger byte-identical (hash before/after assertion).
- [ ] E3. Waiver-density alarm: ledger analysis in digest; ≥3 waivers/wk per gate → auto-append "fix or retire <gate>" backlog entry — Model: sonnet — Parallelizable: yes — Verification: mechanical
  - Done-when: fixture ledger with 3 waivers produces the backlog entry (self-test).
- [ ] E4. Synthetic-session-runner: golden scenarios (commit-without-tests, false-DONE, secret-paste, scope-creep, unwired-gate, legacy-path-drift, marker-missing, waiver-abuse) runnable locally + CI weekly — Model: sonnet — Parallelizable: yes — Verification: mechanical
  - Done-when: `evals/synthetic/run-all.sh` exits 0 locally; CI workflow file present + green on the program branch.
- [ ] E5. KPI script: weekly numbers from ledger (waiver+downgrade rate per gate, doctor drift, FM recurrence) → `docs/reviews/harness-kpis-<date>.md`; scheduled task registration documented — Model: haiku — Parallelizable: yes — Verification: mechanical
  - Done-when: script produces the report from fixture + live ledger; numbers match fixture expectations.

### Wave F — Phase 5: Governance + closure

- [ ] F1. Budgets in doctor: Stop ≤6 / SessionStart ≤8 / blocking ≤12 / always-loaded ≤30KB enforced as doctor checks; new-gate evidence bar (named golden scenario + FP expectation + retirement condition) added to the constitution's harness-change section — Model: sonnet — Parallelizable: yes — Verification: mechanical
  - Done-when: doctor red-fixtures for each budget violation pass self-test.
- [ ] F2. Docs regeneration: harness-architecture.md rewritten from manifest; best-practices.md updated; failure-modes + findings entries for the program's fixed classes — Model: sonnet — Parallelizable: yes — Verification: mechanical
  - Done-when: architecture doc inventory counts match manifest counts (script assertion).
- [ ] F3. Plan-estate + discovery dispositions: batch proposal to operator for the 6 pre-program ACTIVE plans, 1 DRAFT, 3 pending discoveries (recommendations prepared; operator approves per the no-silent-deferral rule) — Model: opus (main session) — Parallelizable: no — Verification: mechanical
  - Done-when: every listed artifact carries a terminal or explicitly-renewed status recorded with operator approval in Decisions Log.
- [ ] F4. Program retro vs baseline (B10) + refutation-criteria check (ADR 058) + completion report — Model: opus — Parallelizable: no — Verification: mechanical
  - Done-when: `docs/reviews/nl-overhaul-completion-2026-07.md` exists with before/after numbers for all six baseline metrics.

## Files to Modify/Create

- `adapters/claude-code/hooks/**` — new: harness-doctor.sh, doctrine-jit.sh, work-integrity-gate.sh, session-honesty-gate.sh, lib/nl-paths.sh, lib/signal-ledger.sh; modified: most existing hooks (ledger integration, path fixes, sandboxing); retired → `adapters/claude-code/attic/**`
- `adapters/claude-code/rules/**` — split into constitution set + stubs; bulk relocation to `adapters/claude-code/doctrine/**`
- `adapters/claude-code/manifest.json`, `adapters/claude-code/schemas/manifest.schema.json`, `adapters/claude-code/scripts/**` (manifest-check, KPI, helpers)
- `adapters/claude-code/settings.json.template`, `adapters/claude-code/CLAUDE.md`, `install.sh`, `adapters/claude-code/templates/**`, `adapters/claude-code/agents/**`, `adapters/claude-code/skills/**`, `adapters/claude-code/patterns/**`, `adapters/claude-code/examples/**`, `adapters/claude-code/tests/**`, `adapters/claude-code/work-shapes/**`
- `evals/**` (golden + new synthetic), `.github/workflows/**`
- `docs/plans/**` (this plan, per-wave spec appendices, estate dispositions), `docs/decisions/**` (ADR 058 + index), `docs/backlog.md`, `docs/reviews/**`, `docs/harness-architecture.md`, `docs/best-practices.md`, `docs/failure-modes.md`, `docs/findings.md`, `docs/discoveries/**`, `docs/DECISIONS.md`
- Live mirror `~/.claude/**` via install.sh runs only; main-checkout git state (B7); git remotes config (B8)

## In-flight scope updates
(none yet)

## Assumptions

- Claude Code auto-loads `~/.claude/CLAUDE.md` + every file in `~/.claude/rules/` into all sessions on this machine (verified empirically 2026-07-01 — the diet mechanism depends on it; if a future Claude Code version changes autoload behavior, the doctor's byte-budget check surfaces it).
- PostToolUse hook output reaches the model's context (used by doctrine-jit; verified by C2's live-probe self-test scenario before Wave C cutover relies on it).
- The operator is available for two checkpoints: C3 constitution approval and F3 estate dispositions; D0's retirement-list veto window.
- `origin` remote access is fixable from this machine (B8); until then, branch pushes may need the personal remote or account switch.
- Existing golden evals (`evals/golden/*.sh`) remain the regression floor throughout; no wave may leave them red.

## Edge Cases

- **Mid-program sessions on a half-migrated harness:** every wave lands atomically (branch → install → doctor green) and tags a rollback point; between waves the harness is always in a doctor-green state.
- **Other machines/sessions pulling mid-wave:** both remotes synced per wave-merge; doctor --quick at SessionStart surfaces any partial install immediately (the audit's silent-partial-install class).
- **A retired gate turns out load-bearing:** attic/ retention + rollback tags; behavior-relocation notes in specs-d name where each retired behavior went; refutation criteria in ADR 058 force a pause rather than re-sprawl.
- **JIT injection fails silently (PostToolUse output not reaching context):** C2's live-probe scenario gates Wave C cutover; fallback documented in specs-c (UserPromptSubmit injection or constitution pointer lines).
- **Parallel builders colliding on shared files:** serialization points declared in the execution model; worktree isolation + cherry-pick protocol per orchestrator-pattern.
- **Self-test slowness on Windows (45s+ observed):** doctor --full uses per-hook timeout 120s and runs in CI/weekly, not at SessionStart; --quick never runs self-tests.

## Acceptance Scenarios

n/a — acceptance-exempt (harness-internal program). The acceptance artifacts are: harness-doctor --full green, golden evals green, synthetic-runner green, and the F4 retro against the B10 baseline.

## Out-of-scope scenarios

- Cloud/Dispatch sessions gaining `~/.claude` enforcement (ADR 011/031 accepted gap; unchanged by this program).
- Workstreams-ui feature work beyond the digest mirror touchpoint.

## Closure Contract

- **Commands that run:** `bash adapters/claude-code/hooks/harness-doctor.sh --full`; `for t in evals/golden/*.sh; do bash "$t"; done`; `bash evals/synthetic/run-all.sh`; `cat ~/.claude/rules/*.md | wc -c`; chain-count assertions via node on live settings.json and template.
- **Expected outputs:** doctor --full exit 0; all golden + synthetic evals exit 0; always-loaded rules total ≤ 30,000 bytes; Stop entries ≤ 6, SessionStart ≤ 8, blocking gates ≤ 12.
- **On-disk artifact location:** `docs/reviews/nl-overhaul-completion-2026-07.md` (F4 retro with before/after vs `docs/reviews/nl-overhaul-baseline-2026-07.md`).
- **Done when:** all Wave B–F checkboxes verified-flipped, the closure commands above pass on a fresh install to a temp HOME AND on the live mirror, and the F4 completion report exists with the six baseline metrics compared.

## Testing Strategy

Mechanical throughout (rung 1): every new/modified hook ships `--self-test` (sandboxed via HARNESS_SELFTEST); every task's Done-when is a command assertion; golden evals are the standing regression floor per wave; the synthetic runner (E4) becomes the program's end-to-end proof; fresh-install-to-temp-HOME is the deployment test (B3, closure). No agent-judgment verification except task-verifier's standard checkbox mandate.

## Walking Skeleton

B1 (harness-doctor) + B6 (first green run against the live mirror) is the walking skeleton: the thinnest end-to-end slice of the program's core loop — *claimed enforcement is mechanically compared to actual, red is surfaced, and the system is brought to green*. Every later wave extends what the doctor checks (manifest, budgets) and what feeds it (ledger), but the loop exists end-to-end at the end of Wave B.

## Decisions Log

### Decision: Backlog absorption deferred to task B9 rather than declared in header
- **Tier:** 1 — **Status:** proceeded with recommendation — **Chosen:** `Backlog items absorbed: none` at creation; B9 performs the absorption markings with per-ID greps. — **Reasoning:** the backlog is itself stale (audit §3) and lives on a diverged main checkout at plan-creation time; atomically editing it in the creation commit would race B7's surgery. The atomicity contract's intent (no double-tracking) is honored by B9's Done-when. — **To reverse:** edit header + backlog in one commit later.

### Decision: Gate-retirement map locked at D0, operator veto window until then
- **Tier:** 2 — **Status:** proceeded with recommendation (program greenlit "full program") — **Chosen:** ADR 058 D5's retirement list stands as the working design; the operator may strike items any time before D0 closes. Notably: workstreams emit-side writers are KEPT (they feed the GUI — the one consumed channel); only fence ENFORCEMENT retires. — **Checkpoint:** ADR 058. — **To reverse:** strike items in D0's specs-d; attic retention makes post-cutover reversal a settings re-add.

### Decision: rung 1 / all-mechanical verification for this program
- **Tier:** 1 — **Status:** proceeded — **Chosen:** every task `Verification: mechanical`; no comprehension-gate dispatches. — **Reasoning:** harness work has deterministic oracles (self-tests, greps, evals); agent-judgment verification would burn the token budget the operator explicitly capped without adding assurance. — **To reverse:** raise rung on specific tasks in a wave-spec.

### Decision: Wave-spec refinement pattern (detail JIT, not all upfront)
- **Tier:** 1 — **Status:** proceeded — **Chosen:** interface-level specs here; exact mechanical specs per wave in `*-specs-<wave>.md` authored by the strong model at wave start. — **Reasoning:** keeps every dispatched task lesser-model-buildable (operator requirement) without freezing detail that Waves B/C learnings will invalidate; avoids spec rot — the audit's stale-claims class applied to plans. — **To reverse:** author all specs upfront in one pass.

## Pre-Submission Audit

- S1 (Entry-Point Surfacing): swept; every behavior change named in ADR 058 D1–D9 maps to a task (D1→C3/C5, D2→C2, D3→C1, D4→B1, D5→D2–D6, D6→D1/E1/E3, D7→E4/E5, D8→task Model fields, D9→execution model); Files-to-Modify covers all task targets.
- S2 (Existing-Code-Claim Verification): swept; all current-state claims (chain counts 22/24, 6 ACTIVE plans, audit defect lists) re-measured post-merge on 2026-07-02 in this session.
- S3 (Cross-Section Consistency): swept; budget numbers (Stop ≤6, SessionStart ≤8, blocking ≤12, ≤30KB rules, ≤350-line constitution) consistent across Goal/Tasks/Closure Contract/ADR.
- S4 (Numeric-Parameter Sweep): swept for params [30000 bytes, 6, 8, 12, 350 lines, 100 lines, 4–5 builders, 120s timeout, 15-line digest]; single value each across plan+ADR.
- S5 (Scope-vs-Analysis Check): swept; all Add/Modify verbs target IN-scope paths; workstreams-ui app code and orchestrator-prime build remain OUT with explicit notes.

## Definition of Done

- [ ] All Wave B–F tasks checked (task-verifier)
- [ ] Closure Contract commands pass on temp-HOME install AND live mirror
- [ ] Golden + synthetic evals green in CI on master
- [ ] F4 completion report exists with baseline comparison
- [ ] SCRATCHPAD/backlog/plan-estate reconciled (B9, F3)
- [ ] Completion report appended to this plan file
