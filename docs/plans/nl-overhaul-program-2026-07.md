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

Execute the six-phase remediation program greenlit in DEC-2026-07-01-001 (operator: "full program"), fixing the root causes established by the 2026-07-01 effectiveness audit (`docs/reviews/2026-07-01-neural-lace-effectiveness-audit.md`): RC1 context saturation, RC2 enforcement theater, RC3 narration-targeted gates, RC4 open-circuit signal loop, RC5 unmaintained gate sprawl, RC6 deployment brittleness. Architecture is locked in ADR 058 (D1–D9). The outcome is a harness whose claimed enforcement provably fires, whose always-loaded doctrine fits in ~6K tokens, whose gates are few/strong/artifact-anchored, whose signals are consumed, and whose effectiveness is measured weekly. Adversarially reviewed 2026-07-02 (harness-reviewer, REFORMULATE): all 12 findings folded into this revision — see Decisions Log.

## User-facing Outcome

The operator (the harness's user) can, after this program: (a) run `harness-doctor.sh --quick` in any session and get a green/red truth report of claimed-vs-actual enforcement in <2s; (b) start any session paying ≤ ~15–20K tokens of standing doctrine instead of ~230K; (c) read ONE capped digest instead of 12+ surfacer blocks and 0%-consumed side channels; (d) see weekly compliance KPIs (waiver/downgrade rates per gate, doctor drift, FM recurrence) instead of guessing whether the harness works; (e) trust that a rule classified "Mechanism" fires, because the doctor blocks drift.

## Scope

- IN: everything under `adapters/claude-code/**` (hooks, rules→constitution+doctrine split, scripts, templates, schemas, settings.json.template, manifest, new `doctrine/` and `attic/` dirs, examples, patterns, tests, work-shapes); `install.sh`; live-mirror reconciliation at `~/.claude/**` (via install, not hand-edits); `evals/**` and `.github/workflows/**` (CI wiring via a `Mode: design-skip` companion plan per task E.4); `docs/plans/**`, `docs/decisions/**`, `docs/backlog.md`, `docs/reviews/**`, `docs/harness-architecture.md`, `docs/best-practices.md`, `docs/failure-modes.md`, `docs/findings.md`, `docs/discoveries/**`; `CLAUDE.md` (repo adapters copy); main-checkout git-state surgery (GAP-51) with backup; remote/account fetch-path fix.
- OUT: the workstreams-ui application code (`neural-lace/workstreams-ui/**`) beyond digest-mirror touchpoints; downstream product repos (Circuit etc.); Dispatch/cloud platform limitations (ADR 011/031 accepted gaps stay accepted); building orchestrator-prime (separate ACTIVE plan — dispositioned in F.3, not built here); any new enforcement gate not named in ADR 058 (D7's evidence bar applies).

## Execution model (read first — how to run this plan)

- **Task-ID format is `<Wave>.<n>` (e.g., `B.1`)** — this exact shape is required by `plan-edit-validator.sh`'s task-ID extraction regex (`[A-Z]+\.[0-9]+`); do not rename. (Review finding 1.)
- **Waves run in order: B → C → D → E → F.** Within a wave, tasks marked `Parallelizable: yes` may run concurrently, **max 4–5 builders at once**, each via `Agent`/`Workflow` dispatch with `isolation: "worktree"` and the task's declared `Model:` tier passed as the dispatch `model` param (per-call `model`/`effort` overrides verified against the live Agent + Workflow tool schemas 2026-07-02). Build in parallel, verify sequentially (orchestrator-pattern); parallel-mode builders do NOT invoke task-verifier and do NOT edit this plan — the orchestrator cherry-picks and verifies.
- **Every wave starts with its `<Wave>.0 wave-spec` task** (Model: opus-tier main session): convert this plan's interface-level specs into exact per-task mechanical specs (exact diffs/greps/red-fixtures) in `docs/plans/nl-overhaul-program-2026-07-specs-<wave>.md`, folding in prior-wave learnings. This keeps every DISPATCHED task buildable by lesser models without freezing stale detail now.
- **Serialization points** (never parallel): `settings.json.template` edits, `CLAUDE.md` rewrite, `manifest.json` creation, live-mirror sync/install runs, cutover tasks (D.5), main-checkout surgery (B.7).
- **Rollback + live-session safety:** tag `pre-<wave>-cutover` before B.6, C.5, D.5. Retired hooks move to `adapters/claude-code/attic/**` AND leave a 3-line exit-0 shim at their old live path for one release — sessions already running during an install snapshot their hook config at session start and must not error on Stop (review finding 6). Hard-delete shims only in the release after cutover.
- **Verification:** every task is `Verification: mechanical` — its Done-when is a command that exits 0. task-verifier flips checkboxes per the standing mandate; no comprehension-gate overhead (rung 1).
- Wave A (pre-plan, complete): origin merge into program branch (`8a6a266`), ADR 058, this plan, adversarial review folded (`REFORMULATE` → this revision). Recorded here as prose, not checkboxes.

## Tasks

### Wave B — Phase 0: Truth reconciliation

- [x] B.0 Wave-spec refinement for Wave B (exact per-task specs appendix; embed the audit's defect lists verbatim as work items, incl. the red-fixture list for B.1) — Model: opus — Parallelizable: no — Verification: mechanical
  - Done-when: `docs/plans/nl-overhaul-program-2026-07-specs-b.md` exists; every B-task below has an entry with exact file paths + grep/self-test assertions.
- [x] B.1 Build `adapters/claude-code/hooks/harness-doctor.sh` per ADR 058 D4 (--quick / --full / --self-test; checks: wiring live+template vs manifest-lite checklist, hook existence/executability, lib-dep resolution, legacy-path scan, always-loaded byte budget, template-vs-live diff) — Model: sonnet — Parallelizable: yes — Verification: mechanical
  - Done-when: `bash adapters/claude-code/hooks/harness-doctor.sh --self-test` exits 0, and the self-test suite includes one red-fixture scenario per doctor check class as enumerated in specs-b §B.1 (each fixture must produce RED; each paired clean fixture must produce GREEN).
- [x] B.2 Kill legacy-path family: create `hooks/lib/nl-paths.sh` resolver (env `NL_REPO_ROOT` > `~/.claude/local/nl-repo-path` > git-derived); replace every `claude-projects/neural-lace` reference in hooks/scripts/lib (incl. `workstreams-task-bridge.js`, Gen-6 trio fallbacks) — Model: sonnet — Parallelizable: yes — Verification: mechanical
  - Done-when: `grep -rl "claude-projects/neural-lace" adapters/claude-code/hooks adapters/claude-code/scripts` returns empty; `workstreams-task-binding.sh` self-test passes; a live probe invocation writes ok:true to its log.
- [x] B.3 Fix install completeness: `install.sh` deploys `hooks/lib/` fully + the `tests/` fixtures self-tests need + `patterns/` (hygiene denylist — closes the GAP-52 silent-no-op hole) + `examples/`; add `--verify` mode that runs doctor --quick post-install — Model: sonnet — Parallelizable: yes — Verification: mechanical
  - Done-when: install to a temp HOME then `goal-coverage-on-stop.sh --self-test`, `goal-extraction-on-prompt.sh --self-test`, `imperative-evidence-linker.sh --self-test`, `decision-context-gate.sh --self-test` all exit 0 from the temp HOME; `harness-hygiene-scan.sh` finds its denylist there.
- [x] B.4 Junk + dead-ref sweep (hook files only; rules-file edits belong to B.5): delete the 6 expired `conversation-tree-*`/`conv-tree-*` shims and stray `hooks/.claude/state/` files; fix the `feature-completion-audit.sh` dead ref in `completion-criteria-gate.sh`'s header — Model: haiku — Parallelizable: yes — Verification: mechanical
  - Done-when: shim files absent; `grep -r "feature-completion-audit" adapters/claude-code/hooks | grep -v attic` empty.
- [x] B.5 Doc truth sweep (rules/docs files only; mechanical list from audit §5 embedded in specs-b): correct false/stale claims — git-discipline + INDEX force-push rows (a live inline blocker EXISTS), INDEX `feature-completion-audit` dead ref, harness-hygiene /harness-review claim, automation-modes inventory counts, six files' "landing in Phase 1d-*" lines, the two "sole-normative module" paths collapsed to the workstreams-ui one, `conv-tree-orchestrator-emit.md` merged into `workstreams-state.md`, CLAUDE.md ≤200-line trim, session-end-protocol + CLAUDE.md continuation-enforcer claims re-stated as pending-Wave-D — Model: haiku — Parallelizable: yes — Verification: mechanical
  - Done-when: per-item grep assertions in specs-b §B.5 pass (e.g., `grep -c "not yet implemented" adapters/claude-code/rules/git-discipline.md` = 0; `grep -rl "conversation-tree-ui/" adapters/claude-code/rules` empty).
- [ ] B.6 Wiring reconciliation + truth-classification (SERIAL, after B.1–B.5 merge): sync template↔live via install run; re-classify every rule whose Mechanism claim is not yet true (pending Wave D/E) with an honest status line; tag `pre-wave-b-cutover` first — Model: sonnet — Parallelizable: no — Verification: mechanical
  - Done-when: `harness-doctor.sh --quick` exits 0 against the live mirror (zero claimed-but-unwired, zero missing lib deps, zero legacy paths).
- [ ] B.7 Main-checkout surgery (GAP-51): backup branch of the staged ~40-file batch, audit batch vs origin/master, drop stale reversions (FM-024..031 must survive), land the main checkout clean at origin/master — Model: sonnet (exact command script in specs-b; supervised — orchestrator reviews diff before the reset step) — Parallelizable: yes — Verification: mechanical
  - Done-when: main checkout `git status --short` empty; `git rev-list --count master..origin/master` = 0 at main checkout; backup branch exists; `grep -c "FM-03" docs/failure-modes.md` ≥ 3 there.
- [x] B.8 Remote/account fetch-path fix: resolve the `Repository not found` on `git fetch origin` under the work `gh` account (remote URLs vs account mapping); verify both-remote sync works per the standing two-remote rule — Model: sonnet — Parallelizable: yes — Verification: mechanical
  - Done-when: `git fetch origin && git fetch personal` both exit 0 from a fresh session in the repo.
- [x] B.9 Backlog reconciliation pass 1: mark the entries this program absorbs with `(absorbed by docs/plans/nl-overhaul-program-2026-07.md)` — GAP-20/21/22, synthetic-session-runner P0, waiver-density alarm, continuation-enforcer wiring, GAP-52 (via B.3), GAP-53 (via D.4 completion-criteria relocation), tool-call-budget --ack HMAC item (superseded by D.6 retirement), GAP-42 CI self-test substrate (via E.4) — and close already-fixed-but-open items (GAP-19, STALE-PLANS-01) — Model: haiku — Parallelizable: yes — Verification: mechanical
  - Done-when: each listed ID's backlog entry contains the absorbed/closed marker (grep per ID); backlog `Last updated` line refreshed.
- [x] B.10 Baseline snapshot for D7 refutation criteria: record current metrics (downgrade counts, waiver counts, alert ack-rate, rules-dir bytes, Stop-chain length, live blocking-gate count) to `docs/reviews/nl-overhaul-baseline-2026-07.md` — Model: haiku — Parallelizable: yes — Verification: mechanical
  - Done-when: file exists with all six numbers + reproduction commands.
- [x] B.11 Plan-estate freeze (unblocks spec-freeze-gate collisions found in review finding 2): `orchestrator-prime.md` and `workstreams-completed-filter-fix-2026-06-17.md` flipped `frozen: false → true` with administrative rationale (full disposition remains F.3, operator-approved) — Model: opus (main session; performed inline 2026-07-02, this task is the verification record) — Parallelizable: yes — Verification: mechanical
  - Done-when: `grep -c "^frozen: true" docs/plans/orchestrator-prime.md docs/plans/workstreams-completed-filter-fix-2026-06-17.md` = 1 each; rationale entry present in this plan's Decisions Log.

### Wave C — Phase 1: Context diet

- [ ] C.0 Wave-spec refinement for Wave C (incl. final rule→{constitution|stub+doctrine|delete} disposition table for all 61 rules, cluster assignments for C.4, and the JIT trigger map) — Model: opus — Parallelizable: no — Verification: mechanical
  - Done-when: specs-c file exists; disposition table covers 61/61 rules (count assertion).
- [ ] C.1 Manifest: `adapters/claude-code/manifest.json` + `schemas/manifest.schema.json` + `scripts/manifest-check.sh` (validates schema; disk↔manifest coverage both ways); doctor upgraded to read it — Model: sonnet — Parallelizable: no (others read it) — Verification: mechanical
  - Done-when: `manifest-check.sh` exits 0; `harness-doctor.sh --quick` consumes manifest (grep for manifest read + red-fixture self-test scenario).
- [ ] C.2 JIT injector `hooks/doctrine-jit.sh` (PostToolUse Edit|Write path-pattern matching from manifest `jit_triggers`; per-session dedup markers; ≤1 injection per doctrine file per session; compact-form injection ≤1.5K tokens each). Injection MUST use the PostToolUse JSON `hookSpecificOutput.additionalContext` emission form (precedent: `gh-account-blindness-hint.sh` — plain stdout does NOT reach model context; review finding 7) — Model: sonnet — Parallelizable: yes — Verification: mechanical
  - Done-when: `--self-test` ≥6 scenarios exits 0 (fixture-level); PLUS one real live-session probe (a scripted session touching a trigger path shows the injected doctrine text in its transcript) recorded in specs-c — this probe gates C.5 cutover.
- [ ] C.3 Constitution: draft `rules/constitution.md` (≤350 lines: Rules 0–7 compressed, FUNCTIONALITY-OVER-COMPONENTS, persistence discipline, session-end markers, gate-respect, credentials pointer, doctrine-index pointer) + CLAUDE.md rewrite ≤100 lines — Model: opus draft → **OPERATOR REVIEW checkpoint** (the one designed human gate in this program) — Parallelizable: no — Verification: mechanical
  - Done-when: operator approval recorded in Decisions Log; `wc -c` constitution ≤ 24000 bytes; CLAUDE.md ≤ 100 lines.
- [ ] C.4 Stub-rewrite sweep per the C.0 disposition table: surviving rules become ≤40-line **doctrine compact forms in `adapters/claude-code/doctrine/`** (enforcement pointer + trigger + one-screen substance; these are what doctrine-jit injects); full prose moves to `doctrine/<name>-full.md` where worth keeping, else deleted. **The auto-load `rules/` dir keeps ONLY the constitution set** — stubs do NOT stay in `rules/` (review finding 10). Run as parallel cluster tasks (≈8 rules per cluster, ≤5 clusters concurrent) — Model: haiku (sonnet for the 5 largest files) — Parallelizable: yes — Verification: mechanical
  - Done-when per cluster: every compact form ≤ 3000 bytes; content-checklist greps from specs-c pass; `doctrine/` twin exists for each disposition-table row.
- [ ] C.5 The move + cutover (SERIAL): relocate non-constitution rules out of the auto-load dir into `doctrine/`; leave exit-0-shim-equivalent handling per the live-session safety rule (retired rule files need no shims — they are data not executables — but install must DELETE stale live copies); update install.sh mapping; regenerate INDEX from manifest (or retire INDEX per C.0 decision); tag `pre-wave-c-cutover`; install + doctor. Pre-condition: C.2's live probe passed — Model: sonnet — Parallelizable: no — Verification: mechanical
  - Done-when: post-install `cat ~/.claude/rules/*.md | wc -c` ≤ 30000; `harness-doctor.sh --quick` green incl. new byte-budget check; golden evals pass.
- [ ] C.6 Agent/skill/template reference sweep: update every `~/.claude/rules/<name>.md` reference across agents/skills/templates/hooks to constitution-or-doctrine paths — Model: haiku — Parallelizable: yes — Verification: mechanical
  - Done-when: `grep -rl "claude/rules/" adapters/claude-code/{agents,skills,templates}` matches only constitution-set files.

### Wave D — Phase 2: Gate consolidation

- [ ] D.0 Wave-spec refinement + design freeze of the final gate map (ADR 058 D5 refined by Wave B/C learnings + ledger data; operator veto window on the retirement list closes here). The frozen map MUST explicitly disposition: `workstreams-task-binding.sh` × `task-completed-evidence-gate.sh` (the audit-addendum mutual-unsatisfiability) and the unreachable `bypass_evidence_check` hatch (review finding 5) — Model: opus — Parallelizable: no — Verification: mechanical
  - Done-when: specs-d exists with the frozen Stop/SessionStart/PreToolUse target lists + per-retired-gate behavior-relocation notes, incl. explicit rows for the two named hooks.
- [ ] D.1 `hooks/lib/signal-ledger.sh`: append-only JSONL event lib (block/warn/waiver/downgrade/skip; HARNESS_SELFTEST sandboxing built in) — Model: sonnet — Parallelizable: yes — Verification: mechanical
  - Done-when: `--self-test` exits 0; retry-guard lib routes its downgrade events through it.
- [ ] D.2 `hooks/work-integrity-gate.sh`: merge pre-stop-verifier + product-acceptance + worktree-uncommitted checks, scoped to session-touched plans/files (transcript-derived), retry-guard integrated, ledger-logging. MUST register itself in `RETRY_GUARD_VERIFICATION_HOOKS` (lib default currently `"pre-stop-verifier product-acceptance-gate"`) so its blocks remain non-downgradeable while DONE is claimed — otherwise the 2026-06-09 DONE-riding class returns (review finding 4) — Model: sonnet — Parallelizable: yes — Verification: mechanical
  - Done-when: `--self-test` ≥12 scenarios exits 0 incl. "orthogonal ACTIVE plan does NOT block" (the waiver-tax killer), "session-touched plan with unchecked tasks DOES block", and "DONE-claimed + this gate blocking is NOT downgraded by retry-guard".
- [ ] D.3 `hooks/session-honesty-gate.sh`: marker contract (DONE/PAUSING/BLOCKED, continuation-enforcer semantics live at last, plus an explicit CONTINUING form for turns ending with verified-running background work) + merged narrative heuristics demoted to ledger warnings; blocks ONLY on marker-absence/format or DONE-vs-verification-block contradiction — Model: sonnet — Parallelizable: yes — Verification: mechanical
  - Done-when: `--self-test` ≥10 scenarios exits 0 incl. "waiting-on-operator turn with PAUSING passes" (the audit's false-positive case) and "DONE while work-integrity blocked this session fails".
- [ ] D.4 Relocate retired-gate behaviors: completion-criteria → `close-plan.sh` + PR-merge path (also closes GAP-53's preview-deploy false-pass); customer-facing-review → spawn-time PreToolUse warn + ledger; pr-health → digest feed; decision-context enforcement retired (emit writers kept); vaporware-volume → CI — Model: sonnet — Parallelizable: yes — Verification: mechanical
  - Done-when: per-relocation grep/self-test assertions from specs-d pass.
- [ ] D.5 Cutover (SERIAL): rewrite template Stop chain to the ≤6 target and SessionStart to ≤8; retire old gates to `attic/` with exit-0 shims at old live paths (live-session safety); tag `pre-wave-d-cutover`; install; doctor + golden evals + full self-test sweep — Model: sonnet, orchestrator-supervised — Parallelizable: no — Verification: mechanical
  - Done-when: `node -e` chain-count assertions (Stop ≤6, SessionStart ≤8) pass on BOTH template and live; doctor --full green; golden evals green; every retired live path still exits 0.
- [ ] D.6 PreToolUse rationalization: retire tool-call-budget attestation loop (soft counter → ledger/digest), fold dag-review-waiver into spawn validator, keep artifact gates — Model: sonnet — Parallelizable: yes — Verification: mechanical
  - Done-when: specs-d assertions pass; blocking-gate count ≤12 (doctor check).

### Wave E — Phases 3+4: Signal loop + telemetry

- [ ] E.0 Wave-spec refinement for Wave E — Model: opus — Parallelizable: no — Verification: mechanical
  - Done-when: specs-e exists.
- [ ] E.1 Digest: one SessionStart block (≤15 lines; merges the 12 surfacers' feeds: discoveries, stale plans, monitor alerts, spawned-task results, pending decisions, git freshness, worktree advice, doctor --quick, ledger summary; dedup + auto-expiry + auto-ack of repeats) + mirror into workstreams GUI — Model: sonnet — Parallelizable: yes — Verification: mechanical
  - Done-when: `--self-test` exits 0; SessionStart chain shows digest replacing the retired surfacers (count assertion).
- [ ] E.2 HARNESS_SELFTEST sandbox sweep: every hook's self-test writes state/ledger to sandbox (shared helper from D.1); purge existing self-test pollution from production logs — Model: haiku — Parallelizable: yes — Verification: mechanical
  - Done-when: in a TEMP-HOME install, running the full self-test sweep leaves the manifest-derived list of production state/ledger files hash-identical before/after (review finding 9 — never asserted against the live machine's mutating state dir).
- [ ] E.3 Waiver-density alarm: ledger analysis in digest; ≥3 waivers/wk per gate → auto-append "fix or retire <gate>" backlog entry — Model: sonnet — Parallelizable: yes — Verification: mechanical
  - Done-when: fixture ledger with 3 waivers produces the backlog entry (self-test).
- [ ] E.4 Synthetic-session-runner: golden scenarios (commit-without-tests, false-DONE, secret-paste, scope-creep, unwired-gate, legacy-path-drift, marker-missing, waiver-abuse) runnable locally + CI weekly. CI workflow files land via a `Mode: design-skip` companion plan (systems-design-gate requirement; review finding 3) — Model: sonnet — Parallelizable: yes — Verification: mechanical
  - Done-when: `evals/synthetic/run-all.sh` exits 0 locally; design-skip plan exists; CI workflow file present + green on the program branch.
- [ ] E.5 KPI script: weekly numbers from ledger (waiver+downgrade rate per gate, doctor drift, FM recurrence) → `docs/reviews/harness-kpis-<date>.md`; scheduled task registration documented — Model: haiku — Parallelizable: yes — Verification: mechanical
  - Done-when: script produces the report from fixture + live ledger; numbers match fixture expectations.

### Wave F — Phase 5: Governance + closure

- [ ] F.1 Budgets in doctor: Stop ≤6 / SessionStart ≤8 / blocking ≤12 / always-loaded ≤30KB enforced as doctor checks; new-gate evidence bar (named golden scenario + FP expectation + retirement condition) added to the constitution's harness-change section — Model: sonnet — Parallelizable: yes — Verification: mechanical
  - Done-when: doctor red-fixtures for each budget violation pass self-test.
- [ ] F.2 Docs regeneration: harness-architecture.md rewritten from manifest; best-practices.md updated; failure-modes + findings entries for the program's fixed classes — Model: sonnet — Parallelizable: yes — Verification: mechanical
  - Done-when: architecture doc inventory counts match manifest counts (script assertion).
- [ ] F.3 Plan-estate + discovery dispositions: batch proposal to operator for the 6 pre-program ACTIVE plans, 1 DRAFT, 3 pending discoveries (recommendations prepared; operator approves per the no-silent-deferral rule; includes permanent dispositions for the two administratively-frozen plans from B.11) — Model: opus (main session) — Parallelizable: no — Verification: mechanical
  - Done-when: every listed artifact carries a terminal or explicitly-renewed status recorded with operator approval in Decisions Log.
- [ ] F.4 Program retro vs baseline (B.10) + refutation-criteria check (ADR 058) + completion report — Model: opus — Parallelizable: no — Verification: mechanical
  - Done-when: `docs/reviews/nl-overhaul-completion-2026-07.md` exists with before/after numbers for all six baseline metrics.

## Files to Modify/Create

- `adapters/claude-code/hooks/**` — new: harness-doctor.sh, doctrine-jit.sh, work-integrity-gate.sh, session-honesty-gate.sh, lib/nl-paths.sh, lib/signal-ledger.sh; modified: most existing hooks (ledger integration, path fixes, sandboxing); retired → `adapters/claude-code/attic/**` (+ temporary exit-0 shims at old paths)
- `adapters/claude-code/rules/**` — split into constitution set + relocation to `adapters/claude-code/doctrine/**`
- `adapters/claude-code/manifest.json`, `adapters/claude-code/schemas/manifest.schema.json`, `adapters/claude-code/scripts/**` (manifest-check, KPI, helpers)
- `adapters/claude-code/settings.json.template`, `adapters/claude-code/CLAUDE.md`, `install.sh`, `adapters/claude-code/templates/**`, `adapters/claude-code/agents/**`, `adapters/claude-code/skills/**`, `adapters/claude-code/patterns/**`, `adapters/claude-code/examples/**`, `adapters/claude-code/tests/**`, `adapters/claude-code/work-shapes/**`
- `evals/**` (golden + new synthetic), `.github/workflows/**` (via the E.4 design-skip companion plan)
- `docs/plans/**` (this plan, per-wave spec appendices, the E.4 design-skip companion, estate dispositions incl. header edits to other plans per B.11/F.3), `docs/decisions/**` (ADR 058 + index), `docs/backlog.md`, `docs/reviews/**`, `docs/harness-architecture.md`, `docs/best-practices.md`, `docs/failure-modes.md`, `docs/findings.md`, `docs/discoveries/**`, `docs/DECISIONS.md`
- Live mirror `~/.claude/**` via install.sh runs only; main-checkout git state (B.7); git remotes config (B.8)

## In-flight scope updates
- 2026-07-02: `docs/reviews/nl-overhaul-baseline-2026-07.md` — B.10 baseline snapshot (same scope-gate first-backtick parser limitation as the CLAUDE.md line below; second independent builder hit it in one wave — now an explicit D.0 gate-map row). Filename is mandated verbatim by the Closure Contract and does not match the docs/reviews date-prefix gitignore allowlist; tracked via one-time `git add -f` (documented exception; the file stays tracked thereafter).
- 2026-07-02: `adapters/claude-code/CLAUDE.md` — B.5 doc-truth-sweep touches this file directly (per its own §B.5 done-when: CLAUDE.md ≤200-line trim); already covered by this plan's `## Scope` IN clause and by line 134's `## Files to Modify/Create` bullet, but the scope-enforcement-gate's parser only extracts the first backtick-quoted path per bullet line — adding this explicit In-flight line satisfies the gate without editing anyone else's scope declaration.

## Assumptions

- Claude Code auto-loads `~/.claude/CLAUDE.md` + every file in `~/.claude/rules/` into all sessions on this machine (verified empirically 2026-07-01 — the diet mechanism depends on it; if a future Claude Code version changes autoload behavior, the doctor's byte-budget check surfaces it).
- PostToolUse `hookSpecificOutput.additionalContext` reaches model context (precedent exists in-repo: `gh-account-blindness-hint.sh`; C.2's REAL live-session probe re-verifies before Wave C cutover relies on it).
- Agent/Workflow dispatch accepts per-call `model` + `effort` overrides (verified against the live tool schemas 2026-07-02).
- The operator is available for two checkpoints: C.3 constitution approval and F.3 estate dispositions; D.0's retirement-list veto window.
- `origin` remote access is fixable from this machine (B.8); until then, branch pushes may need the personal remote or account switch.
- Existing golden evals (`evals/golden/*.sh`) remain the regression floor throughout; no wave may leave them red.

## Edge Cases

- **Sessions alive during a cutover install:** Claude Code snapshots hook config at session start; retired live hook paths therefore keep exit-0 shims for one release, and cutovers note "long-lived sessions (Dispatch orchestrators) should be drained or will no-op harmlessly on retired paths" (review finding 6).
- **Other machines:** they gain the new harness only after their own install run; the existing session-start auto-install mechanism covers deployment where wired, and B.6/C.5/D.5 notes name the manual install step for machines without it (review finding 12).
- **A retired gate turns out load-bearing:** attic/ retention + shims + rollback tags; behavior-relocation notes in specs-d name where each retired behavior went; refutation criteria in ADR 058 force a pause rather than re-sprawl.
- **JIT injection fails the live probe:** C.5 cutover is gated on C.2's probe; fallback documented in specs-c (UserPromptSubmit injection form or constitution pointer lines).
- **Parallel builders colliding on shared files:** serialization points declared in the execution model; worktree isolation + cherry-pick protocol per orchestrator-pattern; B.4 (hooks) and B.5 (rules/docs) are file-disjoint by construction.
- **Spec-freeze collisions with other ACTIVE plans:** unfrozen claimers administratively frozen in B.11; any new ACTIVE plan created mid-program that claims program files is a Decisions-Log-recorded coordination event.
- **Self-test slowness on Windows (45s+ observed):** doctor --full uses per-hook timeout 120s and runs in CI/weekly, not at SessionStart; --quick never runs self-tests.

## Acceptance Scenarios

n/a — acceptance-exempt (harness-internal program). The acceptance artifacts are: harness-doctor --full green, golden evals green, synthetic-runner green, and the F.4 retro against the B.10 baseline.

## Out-of-scope scenarios

- Cloud/Dispatch sessions gaining `~/.claude` enforcement (ADR 011/031 accepted gap; unchanged by this program).
- Workstreams-ui feature work beyond the digest mirror touchpoint.

## Closure Contract

- **Commands that run:** `bash adapters/claude-code/hooks/harness-doctor.sh --full`; `for t in evals/golden/*.sh; do bash "$t"; done`; `bash evals/synthetic/run-all.sh`; `cat ~/.claude/rules/*.md | wc -c`; chain-count assertions via node on live settings.json and template.
- **Expected outputs:** doctor --full exit 0; all golden + synthetic evals exit 0; always-loaded rules total ≤ 30,000 bytes; Stop entries ≤ 6, SessionStart ≤ 8, blocking gates ≤ 12.
- **On-disk artifact location:** `docs/reviews/nl-overhaul-completion-2026-07.md` (F.4 retro with before/after vs `docs/reviews/nl-overhaul-baseline-2026-07.md`).
- **Done when:** all Wave B–F checkboxes verified-flipped, the closure commands above pass on a fresh install to a temp HOME AND on the live mirror, and the F.4 completion report exists with the six baseline metrics compared.

## Testing Strategy

Mechanical throughout (rung 1): every new/modified hook ships `--self-test` (sandboxed via HARNESS_SELFTEST); every task's Done-when is a command assertion; golden evals are the standing regression floor per wave; the synthetic runner (E.4) becomes the program's end-to-end proof; fresh-install-to-temp-HOME is the deployment test (B.3, E.2, closure). No agent-judgment verification except task-verifier's standard checkbox mandate.

## Walking Skeleton

B.1 (harness-doctor) + B.6 (first green run against the live mirror) is the walking skeleton: the thinnest end-to-end slice of the program's core loop — *claimed enforcement is mechanically compared to actual, red is surfaced, and the system is brought to green*. Every later wave extends what the doctor checks (manifest, budgets) and what feeds it (ledger), but the loop exists end-to-end at the end of Wave B.

## Decisions Log

### Decision: Backlog absorption deferred to task B.9 rather than declared in header
- **Tier:** 1 — **Status:** proceeded with recommendation — **Chosen:** `Backlog items absorbed: none` at creation; B.9 performs the absorption markings with per-ID greps. — **Reasoning:** the backlog is itself stale (audit §3) and lives on a diverged main checkout at plan-creation time; atomically editing it in the creation commit would race B.7's surgery. The atomicity contract's intent (no double-tracking) is honored by B.9's Done-when. — **To reverse:** edit header + backlog in one commit later.

### Decision: Gate-retirement map locked at D.0, operator veto window until then
- **Tier:** 2 — **Status:** proceeded with recommendation (program greenlit "full program") — **Chosen:** ADR 058 D5's retirement list stands as the working design; the operator may strike items any time before D.0 closes. Notably: workstreams emit-side writers are KEPT (they feed the GUI — the one consumed channel); only fence ENFORCEMENT retires. — **Checkpoint:** ADR 058. — **To reverse:** strike items in D.0's specs-d; attic retention makes post-cutover reversal a settings re-add.

### Decision: rung 1 / all-mechanical verification for this program
- **Tier:** 1 — **Status:** proceeded — **Chosen:** every task `Verification: mechanical`; no comprehension-gate dispatches. — **Reasoning:** harness work has deterministic oracles (self-tests, greps, evals); agent-judgment verification would burn the token budget the operator explicitly capped without adding assurance. — **To reverse:** raise rung on specific tasks in a wave-spec.

### Decision: Wave-spec refinement pattern (detail JIT, not all upfront)
- **Tier:** 1 — **Status:** proceeded — **Chosen:** interface-level specs here; exact mechanical specs per wave in `*-specs-<wave>.md` authored by the strong model at wave start. — **Reasoning:** keeps every dispatched task lesser-model-buildable (operator requirement) without freezing detail that Waves B/C learnings will invalidate; avoids spec rot — the audit's stale-claims class applied to plans. — **To reverse:** author all specs upfront in one pass.

### Decision: Adversarial review (2026-07-02, REFORMULATE) folded — all 12 findings
- **Tier:** 2 — **Status:** implemented in this revision — **Chosen:** (1) task IDs renamed to the `B.1` shape the plan-edit-validator regex requires [Critical]; (2) B.11 added — administrative freeze of the two unfrozen ACTIVE plans whose file claims collide with Waves C–E; (3) E.4 CI workflow writes routed through a `Mode: design-skip` companion plan; (4) D.2 must extend `RETRY_GUARD_VERIFICATION_HOOKS` (DONE-riding regression guard) + self-test scenario; (5) D.0 must explicitly disposition workstreams-task-binding × task-completed-evidence-gate + the unreachable bypass hatch; (6) cutovers leave exit-0 shims at retired live paths for one release (running-session safety); (7) C.2 pinned to the `hookSpecificOutput.additionalContext` emission form + REAL live-session probe gating C.5; (8) per-call model/effort override noted as verified against live tool schemas; (9) E.2 re-anchored to temp-HOME manifest-derived hash list; (10) C.4/C.5 clarified — stubs are doctrine compact forms, auto-load dir keeps only the constitution; (11) B.1 Done-when re-anchored to enumerated red-fixtures; (12) other-machines install-ordering note added. — **Checkpoint:** review output in session transcript (agent a401d2ef, 2026-07-02); this revision's commit.

### Decision: Haiku tier unusable until the context diet lands (measured 2026-07-02)
- **Tier:** 1 — **Status:** proceeded — **Chosen:** all pre-C.5 tasks re-tiered haiku→sonnet. — **Reasoning:** MEASURED, not hypothesized: Wave-B batch-1's two haiku builders failed to boot — request ~207,334 tokens vs haiku's 200,000 window, with ~4K of it conversation — because every agent inherits the auto-loaded rules corpus. RC1 (context saturation) confirmed at the strongest possible level: the harness is literally too large for lesser models to run under at all. Haiku availability is re-probed at C.0 and expected post-C.5; this measurement goes into the F.4 retro as a baseline datum. — **To reverse:** n/a (environmental fact until the diet lands).

### Decision: B.3 accepted with one assertion re-routed to B.6
- **Tier:** 1 — **Status:** proceeded — **Chosen:** B.3's Done-when accepted on its 3 in-scope self-tests + denylist check; the 4th (decision-context-gate --self-test) is re-routed to B.6 verification against the live machine. — **Reasoning:** the builder PROVED (baseline comparison, zero-install reproduction) that the failure is a pre-existing missing `node_modules` (zod) in the worktree's `neural-lace/workstreams-ui/` — a Node-project provisioning gap outside install.sh's file-sync remit. B.6 re-checks on the live machine (where the GUI runs and node_modules exists); if still red there, B.6 fixes or files it. B.3's added `data/` sync (imperative-evidence-linker pattern library) accepted as same-class install-completeness. — **To reverse:** re-open B.3.

### Decision: Orchestrator integration fix at cherry-pick (doctor self-match)
- **Tier:** 1 — **Status:** done — **Chosen:** harness-doctor.sh patched post-cherry-pick to build its legacy-path grep pattern by string concatenation (and fixture via printf), so the doctor never RED-flags itself and B.2's clean-grep assertion holds on the integrated branch. Self-test re-verified 14/14 after the patch. — **Reasoning:** parallel-build integration artifact (B.1 and B.2 could not see each other's output); exactly the cherry-pick-boundary work the execution model assigns the orchestrator.

### Decision: Administrative freeze of orchestrator-prime + workstreams-completed-filter-fix (B.11)
- **Tier:** 1 — **Status:** proceeded — **Chosen:** flip `frozen: false → true` on both plans with no other change; full disposition (COMPLETED/DEFERRED/ABANDONED) remains the operator-approved F.3 batch. — **Reasoning:** spec-freeze-gate blocks edits to files claimed by ANY unfrozen ACTIVE plan; both plans are ≥14 days commit-stale and their declared scopes are final in practice; freezing is honest ("spec final as declared"), reversible (one-line flip), and unblocks Waves B–E without silently deferring anyone's work. — **To reverse:** flip back to `frozen: false`.

## Pre-Submission Audit

- S1 (Entry-Point Surfacing): swept; every behavior change named in ADR 058 D1–D9 maps to a task (D1→C.3/C.5, D2→C.2, D3→C.1, D4→B.1, D5→D.2–D.6, D6→D.1/E.1/E.3, D7→E.4/E.5, D8→task Model fields, D9→execution model); Files-to-Modify covers all task targets.
- S2 (Existing-Code-Claim Verification): swept; all current-state claims (chain counts 22/24, 6 ACTIVE plans, audit defect lists, validator regex shape, retry-guard verification-hook list, additionalContext precedent) re-measured or reviewer-verified 2026-07-02.
- S3 (Cross-Section Consistency): swept; budget numbers (Stop ≤6, SessionStart ≤8, blocking ≤12, ≤30KB rules, ≤350-line constitution) consistent across Goal/Tasks/Closure Contract/ADR; task-ID shape consistent plan-wide.
- S4 (Numeric-Parameter Sweep): swept for params [30000 bytes, 6, 8, 12, 350 lines, 100 lines, 4–5 builders, 120s timeout, 15-line digest, 3000-byte compact forms]; single value each across plan+ADR.
- S5 (Scope-vs-Analysis Check): swept; all Add/Modify verbs target IN-scope paths; workstreams-ui app code and orchestrator-prime build remain OUT with explicit notes; .github/workflows writes explicitly routed via design-skip companion.

## Definition of Done

- [ ] All Wave B–F tasks checked (task-verifier)
- [ ] Closure Contract commands pass on temp-HOME install AND live mirror
- [ ] Golden + synthetic evals green in CI on master
- [ ] F.4 completion report exists with baseline comparison
- [ ] SCRATCHPAD/backlog/plan-estate reconciled (B.9, F.3)
- [ ] Completion report appended to this plan file
