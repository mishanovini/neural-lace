# Handoff — Stage 0 shipped; pending integration + Stage 1 dispatch (2026-08-02)

**Read this with `SCRATCHPAD.md` (bottom section) and `docs/plans/harness-execution-redesign-2026-08.md`.**
Master: `e9c5bc0f` on BOTH remotes (personal + work-org mirrors). Stage 0 complete.

## Machine state at handoff
- CPU ~13% (was pegged 99.9%). `bash` count ~8 (was 111).
- All five `NL-*` maintenance scheduled tasks **Disabled** deliberately (`NL-CoordSync`,
  `NL-SupervisorTick`, `NL-workstreams-heartbeat`, `NL-health-tick`, `NL-session-resumer`).
  `NL-product-health-monitor` left **Ready** (watches the downstream product, not the harness).
  Re-enable only when Stage 1 replaces them: `Enable-ScheduledTask -TaskName '<name>'`.
- **Live settings reconciled on THIS machine**: `~/.claude/settings.json` `.hooks.SessionStart`
  replaced with the template's. Was 4 blocks / 16 hooks (every script incl. doctor+digest ran
  **2×** per start); now 3 blocks / 8 hooks with doctor+digest narrowed to `startup|clear`.
  Backup: `~/.claude/settings.json.bak-20260802-reconcile`.
  Command used: `jq --slurpfile t <template> '.hooks.SessionStart = $t[0].hooks.SessionStart' <live>`.

## OWED #1 — apply these manifest.json deltas (append to `.entries[]`, currently 153)
Builder-authored, verbatim. These are the ONLY copy — the source task notification is gone.

```json
{"id":"single-flight-recursion-guard","kind":"pattern","doctrine_file":"doctrine/single-flight-halt-runbook.md","hooks":[],"events":[],"wired_template":false,"selftest":true,"jit_triggers":{"paths":["adapters/claude-code/hooks/lib/single-flight-lib.sh"],"keywords":["single-flight","recursion guard","sf_guard"]},"blocking":false,"budget_class":"none","honest_status":"universal guard (sf_guard) sourced UNCONDITIONALLY by harness-doctor.sh, session-start-digest.sh, coord-sync.sh, supervisor-tick.sh, health-tick.sh -- a library (no hooks[] entry, matching hook-reentry-guard.sh/sessionstart-singleflight.sh's existing no-manifest-entry convention); wired-vs-claimed proof is the lib's own --self-test (25/25) plus each caller's dedicated scenario (harness-doctor.sh 9b/9c-sfguard-*, session-start-digest.sh S22a-d)"}
```
```json
{"id":"halt-drain-flag","kind":"pattern","doctrine_file":"doctrine/single-flight-halt-runbook.md","hooks":[],"events":[],"wired_template":false,"selftest":true,"jit_triggers":{"paths":["adapters/claude-code/hooks/lib/single-flight-lib.sh"],"keywords":["HALT","drain","sf_halt_set","sf_halt_active"]},"blocking":false,"budget_class":"none","honest_status":"one-gesture operator stop; honored first-line by coord-sync.sh _main(), supervisor-tick.sh run_tick(), health-tick.sh run_tick(), and by sf_guard itself (doctor/digest); proof is each caller's dedicated HALT self-test scenario (coord-sync Scenario 12, supervisor-tick Scenario 6, health-tick Scenario 10)"}
```
```json
{"id":"schedule-manifest-cadence","kind":"pattern","doctrine_file":"doctrine/single-flight-halt-runbook.md","hooks":["harness-doctor.sh"],"events":["SessionStart","manual"],"wired_template":true,"selftest":true,"jit_triggers":{"paths":["adapters/claude-code/config/schedule-manifest.json"],"keywords":["cadence","schedule-manifest"]},"blocking":false,"budget_class":"none","honest_status":"WARN-only (task-1 calibration week; flips to RED in a later task) -- check_schedule_manifest_cadence WARNs when a mechanisms[] entry's declared_cadence_seconds < 2x measured_cycle_seconds; unmeasured entries are silently skipped"}
```
```json
{"id":"budget-bash-hooks","kind":"pattern","doctrine_file":"doctrine/single-flight-halt-runbook.md","hooks":["harness-doctor.sh"],"events":["SessionStart","manual"],"wired_template":true,"selftest":true,"jit_triggers":{"paths":["adapters/claude-code/settings.json.template"],"keywords":["per-Bash","budget-bash-hooks"]},"blocking":false,"budget_class":"none","honest_status":"WARN-only (R3.3 target <=6; real count ~25 today, WARNs on every machine until Stage 2) -- check_budget_bash_hooks counts hook entries across every PreToolUse matcher block whose matcher contains 'Bash', live + template"}
```

## OWED #2 — append to `adapters/claude-code/doctrine/harness-dev.md`
```markdown

## Execution-layer invariants (single-flight-halt-runbook.md)
- Every heavy entry point (doctor, digest, coord-sync, supervisor-tick, health-tick) sources
  `hooks/lib/single-flight-lib.sh` UNCONDITIONALLY and checks `sf_guard`/`sf_halt_active` first —
  wiring markers (`NL_SESSIONSTART_ORIGIN`, `NL_HOOK_REENTRY`) are belt, never braces.
- HALT the whole maintenance layer with one gesture: write a reason line to
  `~/.claude/state/single-flight/HALT`; clear by deleting it. Drain semantics — in-flight work
  finishes, nothing new arms.
- `adapters/claude-code/config/schedule-manifest.json` declares cadence + measured cycle per
  recurring mechanism; doctor WARNs (calibration week) when cadence < 2x cycle.
```

## OWED #3 — task-verifier flips
Tasks 1 and 2 of `docs/plans/harness-execution-redesign-2026-08.md` are BUILT + VERIFIED but the
checkboxes are unflipped (only `task-verifier` may flip them). Evidence: §"What shipped" below.

## OWED #4 — Stage 1 dispatch (the remaining structural fix)
Task 3 of the plan: Windows-native central maintenance (portable bash core + `schtasks`/`launchd`
adapters; completion-anchored scheduling; TTL snapshots; doctor verdict cache).
**BINDING: no WSL dependency** (operator decision 2026-08-02c). WSL is a possible *future* builder-host
experiment only. Recommend a live `architecture-reviewer` pass before the heavy parts.

## OWED #5 — other machines (laptop, Mac mini)
The repo→live sync is **additive-only**: it ships new scripts but will NOT remove duplicate blocks
or narrow matchers. Per machine: `git pull` → start a session (auto-install lands scripts) → then
1. `jq '.hooks.SessionStart|length' ~/.claude/settings.json` — if **4** (not 3), it has the 2× dup.
2. Reconcile with the same `jq --slurpfile` command above (back up first).
3. Disable the five `NL-*` maintenance tasks (`launchctl unload` equivalents on darwin).
4. Do NOT start Stage 1 — claimed by the desktop via the plan's machine-claims section.

## What shipped (evidence, all verified by the orchestrator re-running tests, not builder claims)
- **Stage 0a** (`e9c5bc0f`): `hooks/lib/single-flight-lib.sh` unconditional guard on 5 heavy entry
  points; SessionStart narrowed to `startup|clear`; HALT/drain flag; `config/schedule-manifest.json`
  + cadence check (**already caught a real violation: coord-sync 60 s cadence vs 94–119 s cycle**);
  per-Bash hook-count budget check (25 today vs ≤6 target). Lib self-test **25/25** re-run by orchestrator.
- **Stage 0b** (`ce7cca52`): Gate Philosophy Law on five blocking gates (scope-enforcement,
  pre-commit, concurrent-ownership, harness-hygiene-scan, backlog-plan-atomicity) via shared
  `hooks/lib/gate-contract-lib.sh` — structured WHAT/WHY/FIX/ESCAPE, `--check` pre-flight mode,
  relevance pre-filter + `-body.sh` lazy-source split. Measured: concurrent-ownership **−68%**
  (0.551→0.176 s), scope-enforcement **−24%** (0.249→0.189 s). Self-tests **14/11/21/49**, zero
  regressions. Live proof: the retrofitted scope gate blocked its own builder's first commit and
  the builder recovered via the gate's own FIX text.

## Open findings (not yet actioned)
1. **5 pre-existing doctor self-test FAILs** — `deterministic-process-proof`, `new-gate-evidence-bar`,
   `claim-honesty`, `budget-chains` (jq parity). PROVEN pre-existing (zero changed lines in the
   Stage-0a diff; the one `check_budget_chains` hit is a comment). **Lesson: the doctor self-test
   takes 9–10+ min, so nobody runs it, so it rotted — and the checks that rotted are the honesty/
   evidence ones.** Fix: make it fast enough to run routinely + run it in CI. Generalize: *any check
   that cannot run in ~60 s will eventually stop running; cost is a correctness property.*
2. Live-settings **duplicate SessionStart blocks** (now fixed here, nl-issue filed) — root cause is
   the additive-only sync; Stage 2 owns the mechanized reconcile.
3. `supervisor-tick.sh` had **two product-codename leaks** (redacted in Stage 0a) — the hygiene gate
   was not catching its own estate.
4. Builder-found: **`ulimit -u 256`** on Windows Git-Bash silently kills long self-test suites —
   scenario ordering matters.
5. Estate entropy unchanged: 135 untriaged nl-issues, 1,209 unacked alerts, 23 stale ACTIVE plans,
   6 stranded worktrees. Stage 4 owns the drain; the volume itself makes the doctor O(mess) slow.

## Operator directives standing (binding, from nl-issues 2026-08-02b/c/d)
- **No WSL dependency.** No new hardware; fix-on-Windows; must run on all machines (2 Windows + 1 Mac)
  → portable bash core + thin platform adapters.
- **Anti-bloat:** redesign must MODIFY/REPLACE/DELETE, never add. Success = inventory DOWN
  (hooks-per-Bash 25→~5, scheduled tasks 6→1–2, SessionStart spawns 16→1–2). Retire-before-extend
  is mechanized as invariant 9.
- **Gate Philosophy Law:** gates never block silently; every block message is a complete instruction;
  `--check` pre-flight modes; workaround-as-sensor (a gate generating workarounds is a defective gate);
  incentive-by-design (make the right way the cheapest way).
- **Push fast path + pull anti-entropy floor**; lease/ack + write-ahead intent + brackets + sequence
  numbers for lost-event PREVENTION; **cleanup-as-sensor law** (every cleanup logs what/why/which-
  prevention-failed; a cleanup without a learning record is itself a defect); death certificates via
  process-handle waits.
- **Prevention over cleanup** is the standing posture.

## Operator question awaiting a real answer next session
*"How can I enable you to recognize problems as they arise, root-cause them, design solutions,
document them, and fix them as you go?"* — Partial answer given: (a) grant standing autonomy on
reversible work so the loop stops round-tripping through the operator; (b) the observability daemon
(Stage 1 output) becomes the agent's continuous eyes instead of operator screenshots; (c) the ledger
is already the write-once/any-session-works intake. The self-learning loop (detect→capture→RCA→
propose→review→fix→outcome-track) is Stage 3 + estate-program T8. **This deserves a concrete
proposal next session, not just principles.**
