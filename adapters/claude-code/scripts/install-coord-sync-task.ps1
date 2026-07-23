# install-coord-sync-task.ps1
#
# Installs TWO Windows Scheduled Tasks in ONE operator run — the fold the
# continuous-operation design promised (docs/reviews/2026-07-19-continuous-
# operation-design-input.md round 2, Q6 disposition: "the standalone
# NL-CoordSync installer is RETIRED as an operator ask ... cross-machine
# status ships as part of the supervisor installer when the continuous-
# operation plan builds" — this file IS that fold: it still installs
# NL-CoordSync exactly as before, and now ALSO installs NL-SupervisorTick,
# so the operator runs this ONE script once instead of two):
#
#   1. 'NL-CoordSync' — runs coord-sync.sh every -IntervalSeconds (default
#      60s — cockpit-roadmap-redesign Task 7 / A5: each fire is a cheap
#      MARKER CHECK; coord-sync.sh itself decides event/floor/skip, so the
#      ~60s cadence costs one bash spawn per minute and publishes within
#      ~1min of a real status change while the FULL cycle still runs at
#      least every COORD_SYNC_FLOOR_SECONDS=600s — see coord-sync.sh's
#      header for the binding mechanics).
#   2. 'NL-SupervisorTick' — runs supervisor-tick.sh every
#      -SupervisorIntervalSeconds (default 300s = 5min): the operator's
#      never-stall mechanism (docs/reviews/2026-07-19-continuous-operation-
#      design-input.md — "I told you to design this system so that it is
#      continuously always making progress and never stops"). Each fire
#      runs the deployed worktree-hygiene-sweep.sh --stranded --porcelain
#      detector + the heartbeat lib to find orphaned work obligations (a
#      dead session's uncommitted worktree fixes) and durably alerts
#      (NEEDS-YOU.md + the existing external-monitor-alerts surface) —
#      never destroys anything, never spawns claude. See
#      supervisor-tick.sh's own header for the full contract.
#
# Both tasks share the SAME hidden-window wrapper infrastructure below
# (registration pattern, quoting + hidden-window lessons per
# docs/runbooks/session-resumer.md §Registration): the action is NEVER an
# inline bash -c command (schtasks/TaskScheduler quote collapse) and NEVER
# a bare .cmd (a visible console window would flash on every fire). Each
# task gets its own <task>-tick.cmd wrapper; both share ONE run-hidden.vbs
# launcher (written once, reused).
#
# REGISTRATION PATTERN (REQUIRED — docs/runbooks/session-resumer.md
# §Registration, quoting + hidden-window lessons 2026-07-06/07): the task
# action is NEVER an inline bash -c command (schtasks/TaskScheduler quote
# collapse) and NEVER a bare .cmd (a visible console window would flash
# EVERY MINUTE at this cadence). Instead this installer writes two wrapper
# files into %USERPROFILE%\.claude\state\task-wrappers\ (machine STATE —
# never ~/.claude/scripts, which install.sh re-syncs and would wipe them):
#   1. run-hidden.vbs   — shared hidden-window launcher (written only if
#                          absent; other NL tasks share it).
#   2. coord-sync-tick.cmd — invokes bash on the LIVE mirror
#                          ~/.claude/scripts/coord-sync.sh (repo copy as
#                          fallback), output appended to
#                          ~/.claude/state/coord-sync/cron-<date>.log.
# The action is then: wscript.exe <vbs> <cmd> — all paths space-free, so
# quote-collapse-proof.
#
# NO-OVERLAP POLICY (A1 + A5 iv): -MultipleInstances IgnoreNew is the
# OS-level backstop; coord-sync.sh's own mkdir lock (STATE_DIR/
# coord-sync.lock, 900s stale reclaim) is the script-level layer. The 900s
# threshold remains correct at the 60s cadence BECAUSE the
# ExecutionTimeLimit below hard-bounds a live cycle at 5min (300s) — a lock
# older than 900s is provably a crashed holder. coord-sync.sh's self-test
# Scenario 9 greps THIS file to pin that cross-file invariant; keep the
# literal `ExecutionTimeLimit (New-TimeSpan -Minutes 5)` shape.
#
# Task names: NL-CoordSync, NL-SupervisorTick
# Cadences:  NL-CoordSync every -IntervalSeconds (default 60s);
#            NL-SupervisorTick every -SupervisorIntervalSeconds (default
#            300s = 5min) — both repeating ~10 years.
# Output:    ~/.claude/state/coord-sync/cron-YYYY-MM-DD.log (NL-CoordSync
#              tick stdout) + STATE_DIR/cycles.log + STATE_DIR/debounce.log
#              + an alert marker in ~/.claude/state/external-monitor-alerts/
#              on a persistent local-commit streak (A2c).
#            ~/.claude/state/supervisor/cron-YYYY-MM-DD.log (NL-SupervisorTick
#              tick stdout) + STATE_DIR/tick.log (rotated ~200KB, one line
#              per fire) + STATE_DIR/orphans/*.json (per-orphan ledger) +
#              an alert marker in ~/.claude/state/external-monitor-alerts/
#              on any newly-detected orphaned worktree obligation.
#
# Run ONCE per machine as a normal (non-elevated) user. Re-running is safe
# (idempotent — both tasks are Set- if already present, Register- if not).
# OPERATOR/ORCHESTRATOR-APPLIED: agent sessions treat schtasks/
# ScheduledTasks mutation as persistence — verify with -WhatIf only.
#
# Usage:
#   powershell -File adapters/claude-code/scripts/install-coord-sync-task.ps1
#   powershell -File ... -RepoPath "$env:USERPROFILE\dev\<work-org>\neural-lace"
#   powershell -File ... -IntervalSeconds 60 -SupervisorIntervalSeconds 300
#   powershell -File ... -WhatIf      # dry-run: prints wrapper contents +
#                                     # registration for BOTH tasks WITHOUT
#                                     # touching disk or Task Scheduler
#   powershell -File ... -Uninstall  # unregisters BOTH tasks
#
# Verification after install:
#   Get-ScheduledTask -TaskName 'NL-CoordSync','NL-SupervisorTick'
#   Start-ScheduledTask -TaskName 'NL-CoordSync'      # one-shot (may debounce-skip;
#   #   for a guaranteed full cycle run: bash ~/.claude/scripts/coord-sync.sh --force)
#   Start-ScheduledTask -TaskName 'NL-SupervisorTick' # one-shot full tick
#   schtasks /Query /TN NL-CoordSync /V | findstr "Last Result"       # 0 = healthy
#   schtasks /Query /TN NL-SupervisorTick /V | findstr "Last Result"  # 0 = healthy

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$RepoPath = "$HOME\dev\<work-org>\neural-lace",
    [int]$IntervalSeconds = 60,
    [int]$SupervisorIntervalSeconds = 300,
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'
$AllTaskNames = @('NL-CoordSync', 'NL-SupervisorTick')

if ($Uninstall) {
    foreach ($tn in $AllTaskNames) {
        if (Get-ScheduledTask -TaskName $tn -ErrorAction SilentlyContinue) {
            if ($PSCmdlet.ShouldProcess($tn, 'Unregister scheduled task')) {
                Unregister-ScheduledTask -TaskName $tn -Confirm:$false
                Write-Host "Uninstalled scheduled task: $tn"
            }
        } else {
            Write-Host "No scheduled task '$tn' found -- nothing to uninstall."
        }
    }
    exit 0
}

# Locate bash.exe — prefer Git Bash. Shared prerequisite for both tasks.
$bashCandidates = @(
    "$env:ProgramFiles\Git\bin\bash.exe",
    "$env:ProgramFiles\Git\usr\bin\bash.exe",
    "$env:ProgramFiles(x86)\Git\bin\bash.exe",
    "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe"
)
$bash = $bashCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $bash) {
    Write-Error "Could not find bash.exe (Git Bash). Install Git for Windows or edit this script with the bash path."
    exit 1
}

# PowerShell 5.1-safe Windows->POSIX path conversion (no scriptblock -replace).
function ConvertTo-Posix([string]$p) {
    $s = $p -replace '\\', '/'
    if ($s -match '^([A-Za-z]):(.*)$') { $s = '/' + $Matches[1].ToLower() + $Matches[2] }
    return $s
}

# ------------------------------------------------------------------
# Shared wrapper dir + hidden-window VBS launcher (written once, reused
# by BOTH tasks' .cmd wrappers) — machine STATE dir (runbook §Registration
# pattern), never ~/.claude/scripts (install.sh re-syncs and would wipe it).
# ------------------------------------------------------------------
$wrapperDir = Join-Path $env:USERPROFILE ".claude\state\task-wrappers"
$vbsPath    = Join-Path $wrapperDir "run-hidden.vbs"
$vbsContent = @'
Set sh = CreateObject("WScript.Shell")
cmd = ""
For i = 0 To WScript.Arguments.Count - 1
  cmd = cmd & """" & WScript.Arguments(i) & """" & " "
Next
sh.Run Trim(cmd), 0, False
'@
if ($PSCmdlet.ShouldProcess($wrapperDir, 'Write shared run-hidden.vbs launcher (if absent)')) {
    if (-not (Test-Path $wrapperDir)) { New-Item -ItemType Directory -Path $wrapperDir -Force | Out-Null }
    if (-not (Test-Path $vbsPath)) { Set-Content -Path $vbsPath -Value $vbsContent -Encoding ASCII }
} else {
    Write-Host "(-WhatIf) Would write $vbsPath (if absent)"
}

$wscript = Join-Path $env:SystemRoot "System32\wscript.exe"

# ------------------------------------------------------------------
# Per-task config. Each entry: TaskName, script basename, cmd wrapper
# basename, cadence (seconds), log-dir basename under ~/.claude/state/,
# description, and a one-shot test hint shown in the final summary.
# ------------------------------------------------------------------
$Tasks = @(
    [PSCustomObject]@{
        TaskName    = 'NL-CoordSync'
        ScriptName  = 'coord-sync.sh'
        CmdName     = 'coord-sync-tick.cmd'
        Interval    = $IntervalSeconds
        LogDirName  = 'coord-sync'
        Description = "Cross-machine coordination cadence (cockpit-roadmap-redesign Task 7 / A5): every ${IntervalSeconds}s fire is a marker check; coord-sync.sh runs the FULL exporter->push->pull cycle on a dirty marker (event path, ~1min publish latency) and ALWAYS at least every COORD_SYNC_FLOOR_SECONDS=600s regardless of the marker (keepalive-honesty floor + git-blind-mutation coverage). Wrapper pattern per docs/runbooks/session-resumer.md §Registration. Source: adapters/claude-code/scripts/install-coord-sync-task.ps1"
        TestHint    = 'One-shot full-cycle test (bypasses the debounce): bash ''<script>'' --force'
    },
    [PSCustomObject]@{
        TaskName    = 'NL-SupervisorTick'
        ScriptName  = 'supervisor-tick.sh'
        CmdName     = 'supervisor-tick-tick.cmd'
        Interval    = $SupervisorIntervalSeconds
        LogDirName  = 'supervisor'
        Description = "Per-machine never-stall supervisor tick (continuous-operation program, docs/reviews/2026-07-19-continuous-operation-design-input.md round 2 Q6 disposition): every ${SupervisorIntervalSeconds}s runs the deployed worktree-hygiene-sweep.sh --stranded --porcelain detector + the session-heartbeat lib to find orphaned work obligations (a dead session's uncommitted/unintegrated worktree) and durably alerts via needs-you.sh (NEEDS-YOU.md) + the existing external-monitor-alerts surface -- observe-first, idempotent per fire, never destroys anything, never spawns claude. Wrapper pattern per docs/runbooks/session-resumer.md §Registration. Source: adapters/claude-code/scripts/install-coord-sync-task.ps1"
        TestHint    = 'One-shot test (safe to run any time -- observe-only): bash ''<script>'''
    }
)

# NO-OVERLAP POLICY (A1 + A5 iv, applies to both tasks): -MultipleInstances
# IgnoreNew is the OS-level backstop; each script's own internal bounding
# (coord-sync.sh's mkdir lock; supervisor-tick.sh's timeout-wrapped forks +
# SUPERVISOR_TICK_BUDGET_SECS) is the script-level layer. The 900s stale-
# lock-reclaim threshold coord-sync.sh relies on remains correct BECAUSE
# the ExecutionTimeLimit below hard-bounds a live cycle at 5min (300s) — a
# lock older than 900s is provably a crashed holder. coord-sync.sh's
# self-test Scenario 9 greps THIS file to pin that cross-file invariant;
# keep the literal `ExecutionTimeLimit (New-TimeSpan -Minutes 5)` shape for
# EVERY task registered below.
foreach ($t in $Tasks) {
    Write-Host ""
    Write-Host "=== $($t.TaskName) ==="

    # Invoke the LIVE mirror (never wiped mid-life by installs, always
    # synced by install.sh); repo copy is the fallback for machines that
    # never ran install.sh.
    $liveMirror = "$env:USERPROFILE\.claude\scripts\$($t.ScriptName)"
    $repoScript = Join-Path $RepoPath "adapters\claude-code\scripts\$($t.ScriptName)"
    $invokeScript = if (Test-Path $liveMirror) { $liveMirror } else { $repoScript }
    if (-not (Test-Path $invokeScript)) {
        # Write-Warning, NOT Write-Error: $ErrorActionPreference='Stop' (set
        # above) would make Write-Error TERMINATE the whole script instead
        # of just skipping this one task -- a missing script for ONE task
        # (e.g. supervisor-tick.sh not yet merged to this machine's main
        # checkout while NL-CoordSync's script already exists) must not
        # block registering the OTHER task in the same run.
        Write-Warning "$($t.ScriptName) not found at $liveMirror or $repoScript. Run install.sh first (or pass -RepoPath). Skipping $($t.TaskName) this run -- re-run once the script is present."
        continue
    }

    $posixScript = ConvertTo-Posix $invokeScript
    $posixLogDir = ConvertTo-Posix "$env:USERPROFILE\.claude\state\$($t.LogDirName)"
    $cmdPath = Join-Path $wrapperDir $t.CmdName

    # NOTE the doubled %% — batch-file semantics: %%Y reaches bash as %Y. A
    # single % would be parsed as a (missing) batch variable and stripped.
    $cmdContent = @"
@echo off
"$bash" -c "export PATH=/usr/bin:/mingw64/bin:`$PATH; mkdir -p '$posixLogDir'; bash '$posixScript' >> '$posixLogDir/cron-`$(date +%%Y-%%m-%%d).log' 2>&1"
"@

    if ($PSCmdlet.ShouldProcess($cmdPath, 'Write task wrapper .cmd')) {
        Set-Content -Path $cmdPath -Value $cmdContent -Encoding ASCII
        Write-Host "Wrote wrapper: $cmdPath"
    } else {
        Write-Host "(-WhatIf) Would write $cmdPath with:"
        Write-Host $cmdContent
    }

    $Action = New-ScheduledTaskAction -Execute $wscript -Argument "`"$vbsPath`" `"$cmdPath`""

    $startTime = (Get-Date).AddMinutes(1)
    $Trigger = New-ScheduledTaskTrigger -Once -At $startTime `
        -RepetitionInterval (New-TimeSpan -Seconds $t.Interval) `
        -RepetitionDuration (New-TimeSpan -Days 3650)

    $Settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -StartWhenAvailable `
        -ExecutionTimeLimit (New-TimeSpan -Minutes 5) `
        -MultipleInstances IgnoreNew

    $taskExists = [bool](Get-ScheduledTask -TaskName $t.TaskName -ErrorAction SilentlyContinue)
    if ($PSCmdlet.ShouldProcess($t.TaskName, $(if ($taskExists) { 'Update scheduled task' } else { 'Register scheduled task' }))) {
        if ($taskExists) {
            Set-ScheduledTask -TaskName $t.TaskName -Action $Action -Trigger $Trigger -Settings $Settings | Out-Null
            Write-Host "Updated existing scheduled task: $($t.TaskName)"
        } else {
            Register-ScheduledTask -TaskName $t.TaskName -Action $Action -Trigger $Trigger -Settings $Settings -Description $t.Description | Out-Null
            Write-Host "Installed scheduled task: $($t.TaskName)"
        }
    } else {
        Write-Host "(-WhatIf) Would $(if ($taskExists) { 'update' } else { 'register' }) scheduled task: $($t.TaskName)"
        Write-Host "(-WhatIf) Trigger StartBoundary:      $startTime"
        Write-Host "(-WhatIf) Trigger RepetitionInterval: $($t.Interval) seconds"
        Write-Host "(-WhatIf) Settings MultipleInstances:  IgnoreNew"
        Write-Host "(-WhatIf) Settings ExecutionTimeLimit: 5 minutes"
        Write-Host "(-WhatIf) Action exec: $wscript"
        Write-Host "(-WhatIf) Action args: `"$vbsPath`" `"$cmdPath`""
    }

    Write-Host ""
    Write-Host "Cadence:  every $($t.Interval)s"
    Write-Host "Wrapper:  $cmdPath -> $invokeScript"
    Write-Host "Log:      $env:USERPROFILE\.claude\state\$($t.LogDirName)\cron-<date>.log"
    Write-Host $t.TestHint.Replace('<script>', $posixScript)
}

Write-Host ""
Write-Host "Both tasks registered from ONE run (continuous-operation round-2 Q6 fold)."
Write-Host "Uninstall (removes BOTH):"
Write-Host "  powershell -File '$($MyInvocation.MyCommand.Path)' -Uninstall"
