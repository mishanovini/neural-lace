# ADR 058 — The Great Consolidation: NL overhaul architecture

Date: 2026-07-02
Status: Accepted (operator greenlit the full program 2026-07-02: "I am greenlighting the full program. I want you to go build this now.")
Stakeholders: Misha (operator), orchestrator + builder sessions
Supersedes in part: the enforcement-growth trajectory post-ADR-026; complements ADR 026/036.
Companion plan: `docs/plans/nl-overhaul-program-2026-07.md`
Evidence base: `docs/reviews/2026-07-01-neural-lace-effectiveness-audit.md` (root causes RC1–RC6, all claims measured)

## Context

The 2026-07-01 full-harness audit found: ~226–270K tokens of doctrine auto-loaded per session (61 rules, 884KB); Mechanism claims that don't fire (flagship session-end gate wired nowhere; 4 gates in template-but-not-live; Gen-6 trio environmentally broken); heavy gate ride-through (107 recent retry-guard downgrades, 12 acceptance waivers vs 1 real PASS, 0 production decision-fences ever); a 0%-consumption signal loop (0/32 alerts acked, 330/330 wakes dropped, 0 attestations in 10,959 counted calls); gate generation outpacing maintenance (+41 hooks in the 40 days after ADR-026's declared freeze; 6 of the last 9 FM classes are the enforcement layer itself misfiring); and deployment brittleness (partial installs, legacy hardcoded paths, uninstalled fixtures). Conclusion: the harness's *theory* (mechanize, don't moralize) is correct and its artifact-boundary gates work; the failure is 97%-prose delivery, unmaintained mechanism sprawl, and zero measurement.

## Decisions

### D1 — Always-loaded constitution (≤ ~6K tokens)
`~/.claude/rules/` (the Claude Code auto-load directory) will contain ONLY a small constitution set: `CLAUDE.md` shrinks to ≤100 lines (routing + standing directives); one `constitution.md` (~250–350 lines) carrying: Operating Rules 0–7 (compressed), FUNCTIONALITY-OVER-COMPONENTS, bug/work-persistence discipline, session-end marker contract, gate-respect one-liner, credentials pointer, and a one-line pointer to the doctrine index. Everything else leaves the auto-load path.
*Alternatives rejected:* keep corpus + ask model to prioritize (demonstrated failure — compliance follows salience); per-project CLAUDE.md slimming only (global rules dir is the dominant tax).

### D2 — Just-in-time doctrine delivery
Moved rules live in `adapters/claude-code/doctrine/` → mirrored to `~/.claude/doctrine/` (NOT auto-loaded). Delivery becomes: (a) ONE config-driven injector hook `doctrine-jit.sh` (PostToolUse on Edit/Write path-patterns + optional UserPromptSubmit keywords) that injects a doctrine file's compact form the FIRST time a session touches the matching surface (per-session dedup markers); (b) gate block-messages carry their rule's remediation text (already largely true); (c) agents/skills reference doctrine files explicitly when dispatched.
*Alternatives rejected:* N per-surface injector hooks (sprawl — the disease being cured); retrieval-by-model-choice (relies on the failing self-classification).
*Implementation pin (review 2026-07-02):* injection MUST use the PostToolUse JSON `hookSpecificOutput.additionalContext` emission form — plain hook stdout does NOT reach model context. In-repo precedent: `gh-account-blindness-hint.sh`. A real live-session probe (not a fixture) gates the Wave-C cutover on this behavior.

### D3 — Single machine-readable enforcement manifest
`adapters/claude-code/manifest.json`: one entry per unit — {id, kind: gate|pattern|convention, doctrine_file, hooks[], events[], wired_template: bool, selftest: bool, jit_triggers[], blocking: bool, budget_class}. INDEX.md and the enforcement map are GENERATED from it (or retired); harness-doctor and doctrine-jit READ it. Kills the triple-recorded map (~131KB) and makes "claimed vs actual" mechanically checkable.
*Alternatives rejected:* keep prose tables in sync by discipline (the audit shows discipline-sync fails).

### D4 — harness-doctor.sh (the keystone; deployment self-verification)
One script, two modes. `--quick` (<2s, SessionStart): every manifest entry with wired_template=true appears in BOTH live settings.json and template; hook files exist/executable; hooks/lib deps resolve; zero legacy-path references; always-loaded byte budget respected. `--full` (CI + weekly): additionally runs every self-test (per-hook timeout 120s) and manifest↔disk coverage both ways. RED output is one line per defect. Doctor replaces settings-divergence-detector, check-harness-sync's role, and cross-repo-drift-warn's local half.
*Refutation criterion (claims.md):* if doctor runs green for 30 days while a new claimed-but-unwired gate exists, D4 has failed its purpose (checkable via synthetic-runner scenario "unwired-gate").

### D5 — Gate consolidation: fewer, stronger, artifact-anchored
Target budgets (enforced by doctor): **Stop chain ≤ 6 entries; SessionStart ≤ 8; blocking gates ≤ 12 total.** Principles: artifact checks block; narrative checks observe (ledger + digest), except one marker contract. Target Stop chain: (1) `work-integrity-gate.sh` — merges pre-stop-verifier + product-acceptance + worktree-uncommitted-work checks, **scoped to plans/files this session actually touched** (kills the orthogonal-plan waiver tax); (2) `session-honesty-gate.sh` — the DONE/PAUSING/BLOCKED marker contract (continuation-enforcer semantics, finally live) + the merged narrative heuristics (deferral/lie-detector/goal-coverage/narrate-and-wait) DEMOTED to non-blocking ledger warnings; only marker-absence or flagrant self-contradiction blocks; (3) `bug-persistence-gate.sh` (kept — artifact-based, 1 waiver ever); (4) one consolidated workstreams Stop writer (the GUI is the one consumed channel — keep, collapse 5 entries into 1); (5) `signal-ledger` flush; (6) `session-wrap.sh` (non-blocking). Retired as blocking Stop gates (behavior moves, files to `attic/` for one release): narrate-and-wait, deferral-counter, transcript-lie-detector, imperative-evidence-linker, goal-coverage(+extraction), decision-context-gate (fence ENFORCEMENT retired — emit-side writers + pending-decision ledger kept, since they feed the consumed GUI), principles-compliance (→ ledger warn), pr-health (→ digest), customer-facing-review (→ spawn-time PreToolUse warn + ledger), completion-criteria (→ close-plan/PR-merge boundary), register-progress-gate. PreToolUse: keep artifact gates (TDD, scope, credential/env, migration-naming, local-edit, plan-edit-validator, wire-check, force-push inline); retire the tool-call-budget attestation loop (0 attestations in 10,959 calls → soft counter in digest).
*Alternatives rejected:* tune each gate in place (22 tuning projects nobody owns); delete narrative checks outright (they carry real signal — as observations, not blocks).
*Implementation pins (review 2026-07-02):* (a) `work-integrity-gate.sh` MUST be added to `stop-hook-retry-guard.sh`'s `RETRY_GUARD_VERIFICATION_HOOKS` default (currently `"pre-stop-verifier product-acceptance-gate"`) or its blocks become downgradeable-while-DONE-claimed — reintroducing the 2026-06-09 DONE-riding class; self-test scenario required. (b) The D0 design-freeze map must explicitly disposition `workstreams-task-binding.sh` × `task-completed-evidence-gate.sh` (mutually unsatisfiable per the audit addendum) and the unreachable `bypass_evidence_check` hatch. (c) Cutovers leave exit-0 shims at retired live hook paths for one release — sessions alive during an install snapshot their hook config at session start and must not error on Stop.

### D6 — One signal ledger + one digest
All gate events (block/warn/waiver/downgrade/skip) append to one JSONL ledger via a shared lib. ONE SessionStart digest (caps ~15 lines, dedup, auto-expiry, auto-ack of duplicates) replaces the 12 surfacers, and mirrors into the workstreams GUI. Waiver-density alarm: ≥3 waivers/week on one gate auto-opens a "fix or retire this gate" item in the digest+backlog (the 2026-05-24 incentive-audit's #1 unbuilt fix). Self-tests set `HARNESS_SELFTEST=1` → all state/ledger writes go to a sandbox dir, ending log pollution.

### D7 — Compliance telemetry (measure effect, not existence)
`synthetic-session-runner`: golden scenarios (commit-without-tests, false-DONE, secret-paste, scope-creep, unwired-gate, legacy-path-drift, marker-missing, waiver-abuse) executed in CI + weekly against the live harness, scored. Weekly KPIs from the ledger: waiver+downgrade rate per gate, doctor drift count, FM recurrence. New blocking gates require: named golden scenario + measured false-positive expectation + a retirement condition — else not merged.

### D8 — Model tiering for build execution
Every plan task declares `Model: haiku|sonnet|opus`. Routing mechanism: the orchestrator passes `model:` per Agent/Workflow dispatch (both support per-call model + effort overrides). Mapping: design/review/cutover supervision → opus-tier (main session); hook implementation with self-tests → sonnet; mechanical sweeps (path fixes, stub rewrites, doc corrections, deletions) → haiku. (Per-call `model`/`effort` override availability verified against the live Agent and Workflow tool schemas, 2026-07-02.) Verification stays mechanical (self-tests/greps), so lesser-model output is checked by deterministic commands, not by trust.

### D9 — Execution shape: waves with capped fleets
Serial design points (settings.json edits, CLAUDE.md, manifest creation, cutovers) are one-builder tasks; everything else runs in waves of ≤4–5 parallel builders in worktrees (build-parallel, verify-sequential per orchestrator-pattern). Each wave begins with a strong-model "wave-spec refinement" task that turns the plan's interface-level specs into exact mechanical specs using the previous wave's learnings — this keeps every DISPATCHED task lesser-model-buildable without freezing stale detail months ahead. Cutovers get rollback tags. Program lands via short-lived branches merged to master per wave, both remotes synced.

## Consequences

Enables: per-session doctrine tax drops ~85–90% (≈226–270K → ≤ ~15–20K tokens incl. CLAUDE.md + constitution + JIT injections); claimed==actual becomes mechanically enforced (doctor); gate count bounded with an evidence bar for growth; signals get consumed (one digest, one ledger); compliance becomes measurable (KPIs + golden scenarios).
Costs: ~2–3 weeks of wave execution (~1.8–2.8M tokens estimated across all builders + reviews); a migration window where sessions run on a half-migrated harness (mitigated: waves land atomically via install sync + doctor gate); retired-gate behavior changes (mitigated: attic/ retention one release + rollback tags).
Blocks/requires: operator review of the constitution content (Wave C) and of the plan-estate dispositions (Wave F); resolution of the GAP-51 main-checkout state and the origin-fetch account mismatch (Wave B).

## Refutation criteria (program-level, per claims.md)

The program's core hypothesis — "salient-small constitution + JIT doctrine + consolidated artifact gates + measurement will increase rule-following and reduce ride-through" — would be REFUTED by: (a) synthetic-runner compliance scores not improving vs the Wave-B baseline after Waves C–D land, or (b) ledger waiver+downgrade rates per active gate not falling ≥50% within 3 weeks of Wave D cutover. Either result triggers a program pause + re-design, not further gate additions.
