# Plan: PS 5.1 em-dash parse hotfix (scheduled-task installers)
Status: ACTIVE
Execution Mode: direct
Mode: code
Backlog items absorbed: none
acceptance-exempt: true
acceptance-exempt-reason: Harness-internal installer scripts with no product user; the PS5.1 ParseFile sweep, -WhatIf runs, and Get-ScheduledTask state are the demonstration.
tier: 1
rung: 1
architecture: coding-harness
frozen: true
lifecycle-schema: v2
owner: Misha
target-completion-date: 2026-07-17
prd-ref: n/a — harness-development
ask-id: none — no linked ask

## Goal
Fix a latent whole-file parse failure in three PowerShell scripts caused by a
UTF-8 em-dash (U+2014, bytes E2 80 94) inside a double-quoted string in a
BOM-less .ps1 file. Windows PowerShell 5.1 decodes BOM-less files as ANSI
(cp1252), so the em-dash's third byte 0x94 decodes to U+201D (curly right
quote) which PS treats as a string DELIMITER — the string terminates early,
the trailing real quote opens a runaway string, and the ENTIRE file fails to
parse ("Missing closing '}'"). pwsh (PS7) reads BOM-less as UTF-8 and never
hits it — and pwsh is NOT installed on the dev machine, so these installers
have never successfully run there: NeuralLace-HarnessHygiene-Weekly,
NeuralLace-AskCockpit-Checkin, and NeuralLace-HarnessEvaluator-Daily were all
confirmed unregistered (Get-ScheduledTask, 2026-07-17). Reported from the
cockpit-v2 Task 3 build session (install-coord-sync-task.ps1 sibling work).

## User-facing Outcome
n/a — harness-internal: the maintainer is the user. The demonstration is
(a) the PS5.1 parse sweep returning zero errors across all nine repo .ps1
files, (b) both installer modes running end-to-end under powershell.exe
(-WhatIf, exit 0), and (c) the three harness scheduled tasks actually
registered on the dev machine with a NextRunTime.

## Scope
- IN: the one-line em-dash→`--` fix in each of the three affected scripts
  (`install-weekly-hygiene-task.ps1:77`, `install-daily-harness-eval-task.ps1:41`,
  `neural-lace/workstreams-ui/scripts/register-reconciler.ps1:119`); a
  PS5.1 ParseFile class-sweep over every repo .ps1; registration of the three
  harness scheduled tasks on the dev machine.
- OUT: em-dashes in comments (verified harmless — the tokenizer discards to
  EOL); adding a PS5.1 parse gate to precommit/harness-doctor (filed to the
  nl-issue ledger for triage instead — a new gate needs its own golden
  scenario per constitution §10); the Disabled NL-workstreams-heartbeat task
  and workstreams reconciler registration (workstreams-ui operational state,
  deliberately untouched); adding BOMs or re-encoding files.

## Tasks

- [ ] 1. Replace the em-dash with `--` inside the double-quoted strings of the three affected .ps1 files (code strings only; comments untouched) — Verification: mechanical — Docs impact: none — one-character string fix, no doc surface
- [ ] 2. Prove parseability and runnability under Windows PowerShell 5.1: ParseFile sweep over all repo .ps1 files returns zero errors; `install-weekly-hygiene-task.ps1 -WhatIf` exits 0 in both default and `-Checkin` modes — Verification: mechanical — Docs impact: none — verification-only task
- [ ] 3. Register the three harness scheduled tasks on the dev machine (`NeuralLace-HarnessHygiene-Weekly`, `NeuralLace-AskCockpit-Checkin`, `NeuralLace-HarnessEvaluator-Daily`) against the main checkout and confirm each shows State=Ready with a NextRunTime — Verification: mechanical — Docs impact: none — machine-state operation recorded in this plan's completion report
  - BLOCKED 2026-07-17 (dependency-blocked, not narrowed): the permission
    classifier denied `Register-ScheduledTask` from this agent session —
    Task Scheduler mutation needs operator approval. Exact commands filed in
    NEEDS-YOU.md (id: see "Open questions", 2026-07-17). Installer
    correctness is already proven by Task 2's -WhatIf runs; this task flips
    when the operator runs the three commands or approves a retry.

## Files to Modify/Create
- `adapters/claude-code/scripts/install-weekly-hygiene-task.ps1` — line 77 em-dash→`--` (reported instance)
- `adapters/claude-code/scripts/install-daily-harness-eval-task.ps1` — line 41 em-dash→`--` (same copy-pasted line, found by class sweep)
- `neural-lace/workstreams-ui/scripts/register-reconciler.ps1` — line 119 em-dash→`--` (found by class sweep)

## In-flight scope updates
n/a

## Assumptions
- Windows PowerShell 5.1 (`powershell.exe`) is the only PowerShell on the dev
  machine (verified: `Get-Command pwsh` fails), so 5.1-parseability is the
  binding constraint for every .ps1 the harness runs or registers.
- Em-dashes inside `#` line comments and `<# #>` block comments are safe under
  cp1252 mojibake (verified during investigation: the tokenizer discards
  comment bytes to EOL/`#>`; the sweep passes with comment em-dashes present).
- The scheduled-task Action references the live-mirror wrapper under
  `~/.claude/scripts/` and the MAIN checkout path, so registering from a
  worktree copy of the fixed installer bakes no worktree path into the task.

## Edge Cases
- A future .ps1 edit could reintroduce a non-ASCII byte in a code string; the
  sweep command in Testing Strategy is the recurring check (gate proposal
  filed to the nl-issue ledger, deliberately out of scope here).
- Re-running the installers is idempotent by design (Set-ScheduledTask update
  path when the task already exists), so re-registration on a machine where a
  task DOES exist updates rather than duplicates.
- `install-daily-harness-eval-task.ps1` has no SupportsShouldProcess, so it
  cannot be smoke-run without real registration; its parse-check plus the
  weekly sibling's -WhatIf run (shared structure) is the pre-registration
  evidence, and its real registration is Task 3's demonstration.

## Acceptance Scenarios
n/a — acceptance-exempt harness-dev plan; see acceptance-exempt-reason in the
header. Closure evidence is the mechanical sweep + registration state.

## Out-of-scope scenarios
None — all verification surfaces are covered by the three mechanical tasks.

## Closure Contract
- **Commands that run:** (1) PS5.1 sweep: `[System.Management.Automation.Language.Parser]::ParseFile()` over every `*.ps1` in the repo, reporting per-file error counts; (2) `powershell.exe -NoProfile -File adapters\claude-code\scripts\install-weekly-hygiene-task.ps1 -WhatIf [-Checkin] -RepoPath <repo>`; (3) `Get-ScheduledTask -TaskName <each of the three task names>`.
- **Expected outputs:** (1) "0 failing file(s) of 9"; (2) exit 0 with correct trigger lines (WeeksInterval 1 default / 2 for -Checkin); (3) each task present with State=Ready and a populated NextRunTime.
- **On-disk artifact location:** `docs/plans/ps51-emdash-parse-hotfix-evidence/task-<n>.evidence.json` (write-evidence.sh capture) plus the completion report appended to this plan.
- **Done when:** all three checkboxes are flipped per mechanical routing AND the evidence artifacts exist with pass outcomes AND the fix commit is merged to master.

## Testing Strategy
- Task 1: `grep -n $'\xe2' <file> | grep -v "^[0-9]*:\s*#"` returns no code-line
  hits in any of the three files (comment hits acceptable).
- Task 2: sweep command over all repo .ps1 → "0 failing file(s) of 9"; both
  -WhatIf invocations exit 0 under powershell.exe.
- Task 3: `Get-ScheduledTask` for the three names → State=Ready, NextRunTime
  populated; one-shot `Start-ScheduledTask` of the weekly-hygiene task writes
  its dated cron log (end-to-end action proof).

Walking Skeleton: n/a — three one-character string fixes plus machine-state
registration; no new architectural layers.

## Decisions Log
- 2026-07-17 (decide-and-go, constitution §8 — reversible): register the three
  harness scheduled tasks on the dev machine as part of this hotfix rather
  than only fixing the parse bug. Rationale: the installers' headers say "run
  ONCE per machine", the alert-surfacer hook consumes their markers, and the
  daily 5 PM cadence was operator-specified (2026-05-28) — registration IS the
  intended standing state and was only missing because the installer could
  never parse. Reversal is one `Unregister-ScheduledTask` per task.
- 2026-07-17: leave `NL-workstreams-heartbeat` Disabled and the workstreams
  reconciler unregistered — workstreams-ui operational state with explicit
  safety notes (autoSpawn gating); not this plan's call.
- 2026-07-17: fix em-dashes only in code strings, not comments — comments are
  parse-safe (verified) and mass-editing them churns blame for zero behavior.
- 2026-07-17: plan created `frozen: true` at birth — the spec IS the completed
  investigation (fix verified before the plan existed, per the hotfix flow the
  scope gate's scenario 12 sanctions); no thaw needed.

## Definition of Done
- [ ] All tasks checked off
- [ ] All tests pass (sweep = 0 failing of 9; both -WhatIf runs exit 0)
- [ ] Linting/formatting clean (no .ps1 encoding changes, LF endings kept)
- [ ] SCRATCHPAD.md updated with final state
- [ ] Completion report appended to this plan file
