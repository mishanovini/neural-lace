# Wave C specs — exact per-task build specs (appendix to nl-overhaul-program-2026-07.md)
Status: REFERENCE (spec appendix, not an independent plan — task C.0 deliverable)
prd-ref: n/a — harness-development

Builder contract (applies to every dispatched task): you work on a worker branch cut from `claude/nl-overhaul-wave-c` (first action: `git checkout -b worker-<task-id> claude/nl-overhaul-wave-c`; verify with `git log --oneline -1` that HEAD is at or past commit `82da767`). Read the master plan section for your task + this appendix section. Edit ONLY the files your section names (plus new files it names). Run your Done-when assertions before committing. Commit on your worker branch with message `overhaul(<task-id>): <summary>`. Do NOT invoke task-verifier, do NOT edit the plan file or this appendix, do NOT edit `settings.json.template` (the orchestrator owns wiring), do NOT touch `~/.claude/` (live mirror is install-only), do NOT touch `adapters/claude-code/rules/` or `INDEX.md` (C.5 owns all deletions/moves there). Return: verdict, commit SHAs, ≤5-sentence summary, blockers.

## §C.0 Disposition table — all 61 files in `adapters/claude-code/rules/`

Legend — **Disposition:** `constitution` (stays in rules/), `compact` (≤40-line/≤3000-byte doctrine compact, full prose dropped), `compact+full` (compact + verbatim-or-merged full at `doctrine/<name>-full.md`), `merge→<target>` (content folds into a shared compact), `full-only` (verbatim move, no compact — constitution IS its compact), `delete` (content dropped; git history is the archive), `retire` (superseded by a generated artifact). **JIT:** path patterns injected by `doctrine-jit.sh` (— = delivered via gate block messages / agent prompts / doctrine INDEX instead). **Cluster:** C.4 dispatch cluster (— = not C.4 work).

| Row | File | Size | Disposition | Doctrine target | JIT trigger paths | Cluster |
|---|---|---|---|---|---|---|
| R01 | `acceptance-scenarios.md` | 25K | compact+full | `doctrine/acceptance-scenarios.md` | — | CL1 |
| R02 | `agent-teams.md` | 19K | compact+full | `doctrine/agent-teams.md` | — | CL4 |
| R03 | `api-routes.md` | 0.6K | merge→code-conventions | `doctrine/code-conventions.md` | `src/app/api/` | CL6 |
| R04 | `automation-modes.md` | 39K | compact+full | `doctrine/automation-modes.md` | — | CL4 |
| R05 | `background-work-tracking.md` | 8K | compact | `doctrine/background-work-tracking.md` | — | CL3 |
| R06 | `branch-hygiene.md` | 9K | merge→git | `doctrine/git.md` | — | CL2 |
| R07 | `calibration-loop.md` | 13K | delete | — | — | CL4 |
| R08 | `claims.md` | 14K | compact+full | `doctrine/claims.md` | — | CL3 |
| R09 | `completion-criteria.md` | 12K | compact | `doctrine/completion-criteria.md` | — | CL4 |
| R10 | `comprehension-gate.md` | 17K | compact+full | `doctrine/comprehension-gate.md` | — | CL1 |
| R11 | `consolidation-discipline.md` | 8K | compact | `doctrine/consolidation-discipline.md` | — | CL3 |
| R12 | `constitution.md` | 8K | constitution | stays `rules/constitution.md` | — (always loaded) | — |
| R13 | `customer-facing-review.md` | 7K | compact | `doctrine/customer-facing-review.md` | — | CL4 |
| R14 | `database-migrations.md` | 0.9K | merge→code-conventions | `doctrine/code-conventions.md` | `/migrations/` | CL6 |
| R15 | `decision-context.md` | 36K | compact+full | `doctrine/decision-context.md` | — | CL4 |
| R16 | `definition-on-first-use.md` | 9K | compact | `doctrine/definition-on-first-use.md` | `build-doctrine/` | CL5 |
| R17 | `deploy-to-production.md` | 4K | merge→git | `doctrine/git.md` | — | CL2 |
| R18 | `design-mode-planning.md` | 30K | compact+full | `doctrine/design-mode-planning.md` | `.github/workflows/`, `Dockerfile`, `vercel.json` | CL1 |
| R19 | `diagnosis.md` | 17K | compact+full | `doctrine/diagnosis.md` | — | CL3 |
| R20 | `discovery-protocol.md` | 21K | compact+full | `doctrine/discovery-protocol.md` | `docs/discoveries/` | CL5 |
| R21 | `dispatch-relay-protocol.md` | 3K | delete | — (premise refuted per discovery 2026-05-25; orchestrator-prime deferred) | — | CL4 |
| R22 | `documentation.md` | 0.6K | merge→code-conventions | `doctrine/code-conventions.md` | — | CL6 |
| R23 | `findings-ledger.md` | 17K | compact+full | `doctrine/findings-ledger.md` | `docs/findings.md` | CL5 |
| R24 | `friction-reflexion.md` | 15K | compact | `doctrine/friction-reflexion.md` | — | CL3 |
| R25 | `gate-respect.md` | 14K | compact | `doctrine/gate-respect.md` (constitution §7 is the core) | — | CL3 |
| R26 | `git.md` | 5K | merge→git | `doctrine/git.md` + `doctrine/git-full.md` | — | CL2 |
| R27 | `git-discipline.md` | 17K | merge→git (+full) | `doctrine/git.md` + `doctrine/git-full.md` | — | CL2 |
| R28 | `harness-hygiene.md` | 15K | merge→harness-dev (+full) | `doctrine/harness-dev.md` + `doctrine/harness-hygiene-full.md` | `adapters/claude-code/` | CL5 |
| R29 | `harness-maintenance.md` | 3K | merge→harness-dev | `doctrine/harness-dev.md` | `adapters/claude-code/` | CL5 |
| R30 | `INDEX.md` | 19K | retire | superseded by `doctrine/INDEX.md` generated from `manifest.json` (C.1 `--gen-index`; C.5 deletes this file + rewrites the golden eval) | — | — |
| R31 | `information-architecture.md` | 14K | merge→harness-dev | `doctrine/harness-dev.md` | `adapters/claude-code/` | CL5 |
| R32 | `interactive-process-fidelity.md` | 16K | compact | `doctrine/interactive-process-fidelity.md` | — | CL3 |
| R33 | `local-edit-authorization.md` | 3K | compact (near as-is) | `doctrine/local-edit-authorization.md` | — | CL5 |
| R34 | `mechanical-evidence.md` | 10K | compact+full | `doctrine/mechanical-evidence.md` | — | CL1 |
| R35 | `merge-completed-work.md` | 3K | merge→git | `doctrine/git.md` | — | CL2 |
| R36 | `observed-errors-first.md` | 2K | compact (as-is; already stub-form) | `doctrine/observed-errors-first.md` | — | CL5 |
| R37 | `orchestrator-pattern.md` | 42K | compact+full | `doctrine/orchestrator-pattern.md` | — | CL1 |
| R38 | `parallel-dev-discipline.md` | 19K | compact+full | `doctrine/parallel-dev-discipline.md` | — | CL2 |
| R39 | `planning.md` | 75K | compact+full | `doctrine/planning.md` | `docs/plans/` | CL1 |
| R40 | `pr-health-snapshot.md` | 4K | compact | `doctrine/pr-health-snapshot.md` (D.4 relocates the gate → digest) | — | CL4 |
| R41 | `prd-validity.md` | 20K | compact+full | `doctrine/prd-validity.md` | `docs/prd.md` | CL1 |
| R42 | `principles.md` | 21K | full-only | `doctrine/principles-full.md` (verbatim move; constitution §1–§3 IS the compact) | — | CL3 |
| R43 | `react.md` | 0.4K | merge→frontend | `doctrine/frontend-conventions.md` | — | CL6 |
| R44 | `risk-tiered-verification.md` | 15K | compact+full | `doctrine/risk-tiered-verification.md` | — | CL1 |
| R45 | `secret-hygiene.md` | 10K | merge→security (+full) | `doctrine/security.md` + `doctrine/security-full.md` | — | CL2 |
| R46 | `security.md` | 2K | merge→security | `doctrine/security.md` | — | CL2 |
| R47 | `session-end-protocol.md` | 15K | compact | `doctrine/session-end-protocol.md` (D.3 session-honesty-gate rewrites the mechanism; constitution §6 is the core) | — | CL3 |
| R48 | `spawn-task-report-back.md` | 16K | compact+full | `doctrine/spawn-task-report-back.md` | — | CL4 |
| R49 | `spec-freeze.md` | 19K | compact+full | `doctrine/spec-freeze.md` | — | CL1 |
| R50 | `teaching-moments.md` | 6K | compact | `doctrine/teaching-moments.md` | `docs/teaching-examples/` | CL3 |
| R51 | `testing.md` | 21K | compact+full | `doctrine/testing.md` | `.test.`, `.spec.`, `/tests/`, `/e2e/` | CL6 |
| R52 | `typescript.md` | 0.4K | merge→code-conventions | `doctrine/code-conventions.md` | — | CL6 |
| R53 | `ui-components.md` | 1K | merge→frontend | `doctrine/frontend-conventions.md` | — | CL6 |
| R54 | `ux-design.md` | 0.9K | merge→frontend | `doctrine/frontend-conventions.md` | — | CL6 |
| R55 | `ux-standards.md` | 6K | merge→frontend | `doctrine/frontend-conventions.md` | `src/components/`, `.tsx` | CL6 |
| R56 | `vaporware-prevention.md` | 31K | compact | `doctrine/vaporware-prevention.md` (the 3×-recorded enforcement TABLE is superseded by `manifest.json`; the compact keeps the pattern-recognition stop-list + manifest pointer) | — | CL5 |
| R57 | `verification-pipeline.md` | 22K | delete (audit §4: "almost entirely re-narration"; the four agents' own prompts + manifest carry the substance) | — | — | CL4 |
| R58 | `work-shapes.md` | 8K | compact | `doctrine/work-shapes.md` | — | CL5 |
| R59 | `workstream-memory-ecology.md` | 16K | compact | `doctrine/workstream-memory-ecology.md` | — | CL3 |
| R60 | `workstreams-state.md` | 34K | compact+full | `doctrine/workstreams-state.md` | `workstreams-ui/` | CL4 |
| R61 | `worktree-isolation.md` | 9K | compact | `doctrine/worktree-isolation.md` | — | CL2 |

Count assertion (C.0 Done-when): `grep -c "^| R[0-6][0-9] | " docs/plans/nl-overhaul-program-2026-07-specs-c.md` = 61.

**Net shape after C.4+C.5:** `rules/` = {constitution.md} (~8.3KB ≤ 30,000-byte budget). `doctrine/` = 42 compacts + 24 kept fulls + generated INDEX.md. Deletes: calibration-loop (never used per audit §2), dispatch-relay-protocol (premise refuted; plan deferred), verification-pipeline (re-narration). Retire: rules/INDEX.md (manifest-generated doctrine/INDEX.md replaces it; constitution footer already points there).

### Two-tier reversibility supersession (operator directive 2026-07-02 — binding on CL1)

`planning.md`'s **Mid-Build Decisions Tier 1/2/3 model is SUPERSEDED** by constitution §8's two-tier model: (a) reversible (undo = one revert or one flip) → decide-and-go: log options+recommendation+why in the plan's Decisions Log, proceed on the recommendation immediately, batch-present all such decisions in the completion report; (b) genuinely hard-to-reverse (backups / schema or prod-data surgery / third parties / unrecoverable spend / unretractable exposure) → pause with options + recommendation prepared. The `doctrine/planning.md` compact MUST state the two-tier model and MUST NOT carry Tier-1/2/3 language. `doctrine/planning-full.md` keeps the historical text but gets a supersession banner at the top of the Mid-Build Decisions section: `> SUPERSEDED (2026-07-02, operator directive): the Tier 1/2/3 model below is replaced by the two-tier reversibility model in constitution.md §8.` `decision-log-entry.md` template semantics (Tier field) are untouched until D.3/F-wave template work — the compact just doesn't teach tiers.

### Compact-form format contract (every C.4 compact)

```markdown
# <Title> — compact
> Enforcement: <hook names, or "Pattern — self-applied">. Full: doctrine/<name>-full.md (omit line if no full kept)
> Applies: <one line — when this matters>

<imperative one-screen substance>
```

Hard caps per compact file: ≤40 lines AND ≤3000 bytes (`wc -c`). Content is imperative rules, not narration: no "Why this exists" history, no Classification paragraphs, no Enforcement tables (the manifest owns that), no cross-reference lists. A compact that merges several rules names each source in its `> Enforcement:` line. Compacts reference hooks by bare filename (no `~/.claude/hooks/` prefix). References to other doctrine use `doctrine/<name>.md` form.

## §C.1 manifest.json + schema + manifest-check.sh (serial-first: C.2 reads its output)

New files:
1. `adapters/claude-code/manifest.json` — one entry per enforcement/doctrine unit. Fields per entry: `id` (kebab slug), `kind` (`gate`|`writer`|`surfacer`|`pattern`|`convention`), `doctrine_file` (path under `adapters/claude-code/doctrine/`, or `rules/constitution.md`, or `null` for hook-only units), `hooks` (array of hook basenames under `hooks/`, may be empty), `events` (array: `Stop`|`SessionStart`|`PreToolUse`|`PostToolUse`|`UserPromptSubmit`|`TaskCreated`|`TaskCompleted`|`precommit`|`prepush`|`manual`), `wired_template` (bool — every hook basename appears in `settings.json.template`), `selftest` (bool — hook contains `--self-test`), `jit_triggers` (object `{paths: [], keywords: []}` — paths from the §C.0 table; keywords reserved, empty in v1), `blocking` (bool), `honest_status` (string, REQUIRED when a `kind: gate` entry has `wired_template: false` — e.g. `"pending Wave D"`; else omit/null), `budget_class` (`stop`|`session-start`|`pretool`|`posttool`|`none`).
   Coverage requirement: every `*.sh` under `hooks/` (excluding `lib/`, excluding `attic/`) appears in ≥1 entry's `hooks[]`; every doctrine target named in the §C.0 table appears as some entry's `doctrine_file` (the C.4 files may not exist yet — see check semantics below). Derive `wired_template` by parsing `settings.json.template` for each basename; derive `selftest` by grep. Deletes (R07/R21/R57) and the retired INDEX get NO entry.
2. `adapters/claude-code/schemas/manifest.schema.json` — JSON Schema draft 2020-12 (mirror `schemas/evidence.schema.json` conventions), locking the shape above; `additionalProperties: false` per entry.
3. `adapters/claude-code/scripts/manifest-check.sh` — subcommands:
   - default/`check`: (a) manifest parses + validates against the schema (node with graceful jq-only degradation); (b) hooks[]→disk existence both ways (RED per miss); (c) `wired_template: true` entries' hooks all present in `settings.json.template` (RED per miss); (d) `doctrine_file` existence — WARN while `adapters/claude-code/doctrine/` does not exist yet (pre-C.4), RED once it does; (e) `kind: gate` + `wired_template: false` without `honest_status` → RED. Exit 0 iff zero RED.
   - `--gen-index`: write `adapters/claude-code/doctrine/INDEX.md` from the manifest (one line per entry: id, kind, doctrine link, hooks, blocking, honest_status). Deterministic output (sorted by id).
   - `--self-test`: fixture suite in `mktemp -d` (HARNESS_SELFTEST=1): valid manifest GREEN; missing-hook-file RED; unlisted-disk-hook RED; wired_template-false-gate-without-honest_status RED; gen-index golden compare.
4. Doctor upgrade (edit `hooks/harness-doctor.sh`): replace check 5's embedded checklist with manifest-driven claim-honesty (every `kind: gate` entry either `wired_template: true` + wired in live settings, or carries `honest_status`); add manifest presence + `manifest-check.sh` invocation to `--quick` when the manifest exists (graceful WARN when absent — pre-C.1 machines). Keep all existing checks + self-test scenarios green; add one red-fixture pair for the manifest check.

Done-when: `bash adapters/claude-code/scripts/manifest-check.sh` exits 0; `bash adapters/claude-code/scripts/manifest-check.sh --self-test` exits 0; `bash adapters/claude-code/hooks/harness-doctor.sh --self-test` exits 0 (extended); `grep -c manifest adapters/claude-code/hooks/harness-doctor.sh` ≥ 3.

## §C.2 doctrine-jit.sh (after C.1 is cherry-picked)

New file `adapters/claude-code/hooks/doctrine-jit.sh` — PostToolUse writer hook (matcher `Edit|Write|MultiEdit`; the orchestrator wires it, not you). Behavior:
1. Read PostToolUse JSON from stdin: `session_id`, `tool_input.file_path`. Missing/malformed → exit 0 silently. EVERY code path exits 0 (writer hook — never blocks; precedent `gh-account-blindness-hint.sh`).
2. Resolve manifest: `~/.claude/manifest.json`, fallback `<repo>/adapters/claude-code/manifest.json` via `lib/nl-paths.sh`. Absent → exit 0.
3. Normalize `file_path` (backslashes→slashes). For each manifest entry with non-empty `jit_triggers.paths`: substring/glob match against the normalized path (bash `case` globs; a trigger `docs/plans/` matches any path containing it).
4. First matching entry whose per-session marker is absent: read its compact at `~/.claude/doctrine/<basename>` (fallback repo `doctrine/`), emit via the sanctioned channel: `jq -n --arg ctx "$content" '{hookSpecificOutput:{hookEventName:"PostToolUse", additionalContext:$ctx}}'` with a one-line header (`[doctrine-jit] <id> — injected once for this session (trigger: <path pattern>)`). Write marker `$STATE_DIR/<session_id>--<id>`; `STATE_DIR=~/.claude/state/doctrine-jit` (or `$HARNESS_SELFTEST_DIR` sandbox when `HARNESS_SELFTEST=1`). Cap: ≤1 injection per event; ≤1 per doctrine file per session (marker); compact >6000 bytes → truncate at 6000 with a `[truncated — read <path>]` tail (defensive; C.4 caps at 3000).
5. Marker hygiene: on each run, delete markers older than 48h (mtime).
6. `--self-test` ≥7 scenarios: (1) match → valid additionalContext JSON containing the compact text; (2) same session+file again → silent (dedup); (3) non-matching path → silent; (4) missing manifest → silent exit 0; (5) malformed stdin → exit 0; (6) two different doctrine files inject on separate events; (7) markers land in the HARNESS_SELFTEST sandbox, not production state.

Done-when: `bash adapters/claude-code/hooks/doctrine-jit.sh --self-test` exits 0. (The REAL live-session probe is the ORCHESTRATOR's step, recorded in the addendum below; it gates C.5 — plan review finding 7.)

### Live-probe protocol (orchestrator-executed after C.2+C.4 cherry-pick)

1. Wire `doctrine-jit.sh` into `settings.json.template` PostToolUse (`Edit|Write|MultiEdit` group) + node-merge the same into live `~/.claude/settings.json`; copy hook + manifest + ≥1 compact to live paths.
2. Headless probe: in a scratch git repo, run `claude -p` with a prompt that Edits `docs/plans/probe.md` (allowedTools Edit); locate the session transcript JSONL under `~/.claude/projects/<slug>/`; `grep` it for the `[doctrine-jit]` header + a distinctive compact token.
3. Record PASS/FAIL + transcript path in the `## C.2 live-probe result` addendum of this file. FAIL → C.5 does NOT proceed; fallback per master plan Edge Cases (UserPromptSubmit form or constitution pointer lines).

## §C.4 stub-rewrite clusters (six parallel dispatches, ≤5 concurrent, sonnet)

Shared contract for every cluster builder: CREATE files under `adapters/claude-code/doctrine/` ONLY (the dir may not exist — `mkdir -p`). Never edit/delete anything in `rules/`, never touch `INDEX.md`, `manifest.json`, or `settings.json.template`. For `compact+full` rows: the full is the source file's prose copied verbatim-then-trimmed (drop Enforcement-table/Classification/Scope/cross-ref scaffolding ONLY when the file is a merge; otherwise verbatim copy is fine) to `doctrine/<name>-full.md`. Every compact obeys the §C.0 format contract (≤40 lines, ≤3000 bytes). Per-cluster Done-when: every listed doctrine file exists; `for f in <your compacts>; do [ $(wc -c < $f) -le 3000 ]; done`; required-token greps below pass; `bash adapters/claude-code/hooks/harness-hygiene-scan.sh --files <your new files>` silent.

- **CL1 planning & verification** (sources: planning, orchestrator-pattern, design-mode-planning, acceptance-scenarios, prd-validity, spec-freeze, risk-tiered-verification, mechanical-evidence, comprehension-gate → 9 compacts + 9 fulls). Required tokens — `doctrine/planning.md`: "FUNCTIONALITY OVER COMPONENTS" pointer to constitution §4, "task-verifier" (sole checkbox-flipper), "Status: COMPLETED" auto-archival, "two-tier" + "decide-and-go" (supersession above), "docs/decisions/" (Tier-2+ ADR duty), sweep-decomposition ("one sub-task per file"). `doctrine/orchestrator-pattern.md`: "isolation: \"worktree\"", "cherry-pick", "verify sequentially", "≤5", worker-branch first-action, "artifact" (confirm evidence on disk, never trust builder claims). `doctrine/design-mode-planning.md`: "Mode: design" triggers list, "10 sections", "systems-designer", "design-skip". `doctrine/acceptance-scenarios.md`: "acceptance-exempt", "PASS artifact", "plan_commit_sha", "scenarios-shared, assertions-private". `doctrine/prd-validity.md`: "prd-ref:", "n/a — harness-development", "seven". `doctrine/spec-freeze.md`: "frozen: true", "In-flight scope updates", thaw protocol. `doctrine/risk-tiered-verification.md`: "Verification:", "mechanical", "contract", "full", default-full. `doctrine/mechanical-evidence.md`: "write-evidence.sh", ".evidence.json", "prose_supplement". `doctrine/comprehension-gate.md`: "rung: 2", four sub-section names.
- **CL2 git & safety** (sources: git, git-discipline, branch-hygiene, merge-completed-work, deploy-to-production → ONE `doctrine/git.md` compact + ONE merged `doctrine/git-full.md`; parallel-dev-discipline → own compact+full; worktree-isolation → compact; secret-hygiene + security → ONE `doctrine/security.md` compact + merged `doctrine/security-full.md`). Required tokens — `doctrine/git.md`: "NEVER force-push", "--ff-only" post-merge sync, "pathspec" staged-set verify (`git commit -- <path>`), WIP-prefix list ("wip/", "feat/", "fix/"), "merge before reporting DONE" (green-PR classes), customer-tier ("full-auto" vs "review-before-deploy"). `doctrine/parallel-dev-discipline.md`: "timestamp" migration prefix + "migration-naming-gate.sh", "pull-before-work", "one authoritative remote", "merge queue". `doctrine/worktree-isolation.md`: "preserve", "never `--force`", exemption classes one-liner. `doctrine/security.md`: "NEVER commit", "--private", "pre-push-scan.sh", three-layer summary, "no destructive operations".
- **CL3 session & epistemics** (sources: claims, diagnosis, session-end-protocol, gate-respect, background-work-tracking, friction-reflexion, consolidation-discipline, interactive-process-fidelity, teaching-moments, workstream-memory-ecology → 10 compacts; claims+diagnosis keep fulls; principles.md → verbatim `doctrine/principles-full.md`, NO compact). Required tokens — `doctrine/claims.md`: "PROVEN", "HYPOTHESIZED", "REFUTED by". `doctrine/diagnosis.md`: "runtime logs" first tool call, "failure-modes.md" grep-first, "Fix the Class", "Class-sweep:". `doctrine/session-end-protocol.md`: "DONE:", "PAUSING:", "BLOCKED:", "exact ask", "never out-wait a gate". `doctrine/gate-respect.md`: "diagnose", "waiver", "--no-verify" needs operator say-so. `doctrine/background-work-tracking.md`: "journal", "started > result", "verify before claiming". `doctrine/interactive-process-fidelity.md`: "authority", "structure", "carry-forward". `doctrine/workstream-memory-ecology.md`: four tiers T1–T4 one-liners. Others: self-evident one-screen compressions.
- **CL4 workstreams & dispatch** (sources: workstreams-state, decision-context, spawn-task-report-back, automation-modes, agent-teams, customer-facing-review, pr-health-snapshot, completion-criteria → 8 compacts; workstreams-state/decision-context/spawn-task-report-back/automation-modes/agent-teams keep fulls. verification-pipeline, calibration-loop, dispatch-relay-protocol → NO output files: deletes happen in C.5). Required tokens — `doctrine/workstreams-state.md`: "semantically true", "Dispatch-only", "state.js" facade, "ADR-054" builder-dispatch tier. `doctrine/decision-context.md`: "constitution §3" (the operator-facing format that REPLACED the fence), "emit-side writers kept", "D.4" retirement note, sole-normative "decision-context-schema.js". `doctrine/spawn-task-report-back.md`: "Report-back: task-id=", ".claude/state/spawned-task-results/", ".acked". `doctrine/automation-modes.md`: five modes one-line each, "project `.claude/`" cloud caveat. `doctrine/agent-teams.md`: "disabled by default", flag path, "orchestrator-pattern" preferred. `doctrine/completion-criteria.md`: the eight criterion keys, "COMPLETION_GATE_SKIP", "D.4" relocation note. `doctrine/customer-facing-review.md`: both agent-family lists, "[skip-ux-review:". `doctrine/pr-health-snapshot.md`: "## PR Health Snapshot", "active-repos.txt", "digest" (D.4 destination).
- **CL5 harness-dev & knowledge** (sources: harness-hygiene + harness-maintenance + information-architecture → ONE `doctrine/harness-dev.md` compact + `doctrine/harness-hygiene-full.md`; work-shapes, findings-ledger, discovery-protocol, definition-on-first-use, local-edit-authorization, observed-errors-first, vaporware-prevention → own compacts; findings-ledger + discovery-protocol keep fulls). Required tokens — `doctrine/harness-dev.md`: "no sensitive data" + denylist pointer, "global by default", sync-to-repo + "diff", "harness-architecture.md" update duty, content-kind routing one-liner ("rules/ constitution-only; doctrine/ everything else; decisions docs/decisions/"). `doctrine/vaporware-prevention.md`: "manifest.json" (the enforcement map lives there now), the pattern-recognition stop-list verbatim ("I built X and it typechecks…" etc. — the audit's most-load-bearing 10 lines), "file:line". `doctrine/findings-ledger.md`: six field names, "docs/findings.md". `doctrine/discovery-protocol.md`: "docs/discoveries/", seven types list, "status: pending". `doctrine/work-shapes.md`: six shape ids. `doctrine/definition-on-first-use.md`: regex + scope one-liner. `doctrine/local-edit-authorization.md`: "/grant-local-edit", "30 minutes". `doctrine/observed-errors-first.md`: "observed-errors.md", "fix-class".
- **CL6 testing & conventions** (sources: testing → compact+full; ux-standards + ux-design + ui-components + react → ONE `doctrine/frontend-conventions.md`; typescript + api-routes + database-migrations + documentation → ONE `doctrine/code-conventions.md`). Required tokens — `doctrine/testing.md`: "functionality, not components", three layers, "no `test.skip`", mock discipline ("never mock the SUT"), "bug persistence" same-response rule, "E2E" boundary rule. `doctrine/frontend-conventions.md`: "purple" = AI-only, "dark:" variant mandate, "filled background" buttons, four states ("loading, empty, error, success"), "semantic HTML". `doctrine/code-conventions.md`: "strict", "no `any`", "import type", NOT-NULL-default migration rule, "RLS", API-route doc duty, ".env.example".

## §C.5 the move + cutover (SERIAL, orchestrator-supervised; after C.1/C.2/C.4 verified + live probe PASS)

Repo edits (builder or orchestrator inline):
1. Delete from `rules/`: every §C.0 row except R12 (constitution) — `git rm` the 59 files + `INDEX.md` (R30). (C.4 already created every doctrine twin; deletes + creates land as the move.)
2. Run `manifest-check.sh --gen-index` → commit `doctrine/INDEX.md`. `manifest-check.sh` must now be fully RED-enforcing on doctrine_file existence (post-C.4 semantics).
3. `install.sh`: add `doctrine` to the copy-dir list; add a rules-prune step (delete `~/.claude/rules/*.md` whose basename is absent from repo `rules/` — NEVER touches other dirs); update `PRINCIPLES_SRC` to `adapters/claude-code/doctrine/principles-full.md`.
4. `hooks/session-start-auto-install.sh`: add `doctrine` to its synced-subdir list (never-delete semantics are fine — canon stops carrying the old rules after the master merge).
5. Rewrite `evals/golden/rules-index-coverage.sh` → new invariant: repo `rules/` contains exactly the constitution set ({constitution.md}); `doctrine/INDEX.md` exists and has a row for every non-`-full` `doctrine/*.md`; every compact ≤3000 bytes. Keep the filename (CI wiring references it).
6. `adapters/claude-code/CLAUDE.md`: verify the C.3 ≤100-line rewrite is in place (orchestrator authors it before C.5; it must NOT `@`-reference `rules/principles.md`).

Cutover (orchestrator-executed, live machine):
7. `git tag pre-wave-c-cutover` on the program branch tip; push tag.
8. Land Wave C on master via PR (the Wave-B PR #68 precedent; direct master push is classifier-blocked). CI must be green.
9. From the main checkout at merged master: run `install.sh` (or `--verify`); then `bash ~/.claude/hooks/harness-doctor.sh --quick` → GREEN required; `cat ~/.claude/rules/*.md | wc -c` ≤ 30000; write `30000` to `~/.claude/local/doctor-budget` (bash redirect — Edit-tool local writes are gated); re-run doctor (byte-budget now enforcing).
10. Golden evals all green; spot-check one JIT injection fires in a fresh session (repeat probe §C.2 form).
Rollback: `git checkout pre-wave-c-cutover -- adapters/claude-code/ && bash install.sh` (one command + reinstall, per the operator-approved reversibility basis).

## §C.6 reference sweep (after C.5; FIRST haiku re-probe — if the builder fails to boot, redispatch sonnet)

Update every `rules/<name>.md` reference in `adapters/claude-code/{agents,skills,templates,hooks}` per the §C.0 table mapping: merged targets map to the merge target (e.g. `rules/git-discipline.md` → `doctrine/git.md`); deleted files' references map to the nearest surviving surface (verification-pipeline → the agent's own prompt or `manifest.json`; calibration-loop → `skills/calibrate.md`; dispatch-relay-protocol → drop the sentence); `rules/principles.md` → `rules/constitution.md` (behavioral references) or `doctrine/principles-full.md` (deep references); `rules/planning.md` → `doctrine/planning.md`; likewise 1:1 rows. `~/.claude/rules/` path forms become `~/.claude/doctrine/` forms. Do NOT edit `attic/`, `docs/`, or rule files themselves.
Done-when: `grep -rl "claude/rules/" adapters/claude-code/agents adapters/claude-code/skills adapters/claude-code/templates` returns only files whose matches all point at `constitution.md` (verify with `grep -rn "claude/rules/" ... | grep -v constitution.md` → empty); same assertion for `adapters/claude-code/hooks` excluding `attic/`.

## §B.12 sync-daemon interactive-session lock (parallel with batch 1)

Context: discovery `docs/discoveries/2026-06-02-component-c-sync-daemon-thrashes-live-checkout.md` (status already `decided`, absorbed as B.12). The Component-C sync-events daemon itself never landed (its branch is deferred); the surviving in-repo daemon-class mutator is `scripts/sync-pt-to-personal.sh` (checkout/cherry-pick/reset on a working tree, runnable unattended). Deliverables:
1. New `adapters/claude-code/hooks/lib/interactive-session-lock.sh` (sourced lib): `isl_live_session <repo-root>` → exit 0 ("locked") when EITHER (a) an explicit lock file `<repo-root>/.claude/state/interactive-session.lock` exists with mtime < `ISL_WINDOW_MIN` (default 15) minutes, OR (b) any transcript `*.jsonl` under `~/.claude/projects/<project-slug-of-repo-root>/` (slug = absolute path with `[/:\\ .]`→`-`, matching Claude Code's convention — derive it the same way `stalled-work-surfacer.sh` does) has mtime < `ISL_WINDOW_MIN` minutes; else exit 1. Plus `isl_refuse_log <repo-root> <daemon-name>` → appends a one-line refusal to `~/.claude/logs/interactive-session-lock.log`. Header documents the contract: EVERY unattended script that mutates a working tree (checkout/cherry-pick/reset/install trigger) MUST call `isl_live_session` first and refuse+log when locked; the future Component-C daemon inherits this contract; option C (dedicated sync clone) remains the durable fix (Wave E/F).
2. Wire the guard at the top of `scripts/sync-pt-to-personal.sh`'s mutation path (skippable via `ISL_BYPASS=1` for operator-attended runs, logged).
3. `--self-test` in the lib (≥4 scenarios, HARNESS_SELFTEST sandbox): fresh-transcript → locked; stale-transcript-only → unlocked; explicit lock file → locked; refusal line lands in the sandboxed log.
4. Verify the discovery file cites B.12 (it does — no edit unless the cite is missing).
Done-when: `bash adapters/claude-code/hooks/lib/interactive-session-lock.sh --self-test` exits 0; `grep -c "isl_live_session" adapters/claude-code/scripts/sync-pt-to-personal.sh` ≥ 1.

## Dispatch map

Batch 1 (parallel, 5): C.1 sonnet · B.12 sonnet · CL1 sonnet · CL2 sonnet · CL3 sonnet — file-disjoint (C.1: manifest/schema/manifest-check/doctor edit; B.12: lib + sync script; CL*: doctrine/ creations only).
Batch 2 (after batch-1 cherry-pick + verify, parallel, 4): C.2 sonnet · CL4 · CL5 · CL6 — file-disjoint (C.2: hooks/doctrine-jit.sh only).
Orchestrator serial: C.3 remainder (CLAUDE.md ≤100 rewrite) · C.2 wiring + live probe · C.5 · then C.6 (haiku probe → sonnet fallback).

## C.2 live-probe result

**PASS — 2026-07-02 (gates C.5: OPEN).** Probe: a real sonnet sub-agent session (worktree-isolated) executed a Write of `tests/jit-probe.test.ts`; the live-wired `~/.claude/hooks/doctrine-jit.sh` matched the manifest `tdd-gate` entry's `.test.` trigger and injected the testing compact via PostToolUse `hookSpecificOutput.additionalContext`. Three independent witnesses, all PROVEN:
1. Dedup marker on disk: `~/.claude/state/doctrine-jit/<session-id>--tdd-gate` (mtime = probe run; only the hook writes this naming scheme).
2. Agent-uneditable transcript (`~/.claude/projects/<project-slug>/<session-id>/subagents/agent-a2e9fdd2d16c316f8.jsonl`): `grep -c "doctrine-jit"` = 4; exact header present: `[doctrine-jit] tdd-gate — injected once for this session (trigger: .test.)`; `hookSpecificOutput|additionalContext` keys = 2.
3. The probe agent's verbatim report quotes the injected compact's first lines, matching `doctrine/testing.md`.
Notes: (a) a first probe attempt was refused by the agent as suspected prompt-injection (doctrine-jit absent from its loaded rules — built this same session); grounding the prompt in the plan/specs/hook files resolved it; (b) the headless `claude -p` probe form is NOT viable on this machine (desktop-host-managed auth: `CLAUDE_CODE_SDK_HAS_HOST_AUTH_REFRESH=1`, no standalone CLI credentials) — the sub-agent probe form is the reproducible pattern here; (c) sub-agent sessions demonstrably pick up the live settings wiring added mid-parent-session.
