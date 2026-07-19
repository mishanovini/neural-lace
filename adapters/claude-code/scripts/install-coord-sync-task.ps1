# install-coord-sync-task.ps1
#
# Installs a Windows Scheduled Task ('NL-CoordSync') that runs coord-sync.sh
# every -IntervalSeconds (default 60s — cockpit-roadmap-redesign Task 7 / A5:
# each fire is a cheap MARKER CHECK; coord-sync.sh itself decides
# event/floor/skip, so the ~60s cadence costs one bash spawn per minute and
# publishes within ~1min of a real status change while the FULL cycle still
# runs at least every COORD_SYNC_FLOOR_SECONDS=600s — see coord-sync.sh's
# header for the binding mechanics).
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
# Task name: NL-CoordSync
# Cadence:   every -IntervalSeconds (default 60s), repeating ~10 years.
# Output:    ~/.claude/state/coord-sync/cron-YYYY-MM-DD.log (tick stdout)
#            + STATE_DIR/cycles.log (one line per FULL cycle)
#            + STATE_DIR/debounce.log (marker-check-only fires)
#            + an alert marker in ~/.claude/state/external-monitor-alerts/
#              on a persistent local-commit streak (A2c).
#
# Run ONCE per machine as a normal (non-elevated) user. Re-running is safe
# (idempotent). OPERATOR/ORCHESTRATOR-APPLIED: agent sessions treat schtasks/
# ScheduledTasks mutation as persistence — verify with -WhatIf only.
#
# Usage:
#   powershell -File adapters/claude-code/scripts/install-coord-sync-task.ps1
#   powershell -File ... -RepoPath "$env:USERPROFILE\dev\<work-org>\neural-lace"
#   powershell -File ... -IntervalSeconds 60
#   powershell -File ... -WhatIf      # dry-run: prints wrapper contents +
#                                     # registration WITHOUT touching disk
#                                     # or Task Scheduler
#   powershell -File ... -Uninstall
#
# Verification after install:
#   Get-ScheduledTask -TaskName 'NL-CoordSync'
#   Start-ScheduledTask -TaskName 'NL-CoordSync'   # one-shot (may debounce-skip;
#   #   for a guaranteed full cycle run: bash ~/.claude/scripts/coord-sync.sh --force)
#   schtasks /Query /TN NL-CoordSync /V | findstr "Last Result"  # 0 = healthy

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$RepoPath = "$HOME\dev\<work-org>\neural-lace",
    [int]$IntervalSeconds = 60,
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'
$TaskName = 'NL-CoordSync'

if ($Uninstall) {
    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
        if ($PSCmdlet.ShouldProcess($TaskName, 'Unregister scheduled task')) {
            Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
            Write-Host "Uninstalled scheduled task: $TaskName"
        }
    } else {
        Write-Host "No scheduled task '$TaskName' found -- nothing to uninstall."
    }
    exit 0
}

# Locate bash.exe — prefer Git Bash.
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

# Invoke the LIVE mirror (never wiped mid-life by installs, always synced by
# install.sh); repo copy is the fallback for machines that never ran install.
$liveMirror = "$env:USERPROFILE\.claude\scripts\coord-sync.sh"
$repoScript = Join-Path $RepoPath "adapters\claude-code\scripts\coord-sync.sh"
$invokeScript = if (Test-Path $liveMirror) { $liveMirror } else { $repoScript }
if (-not (Test-Path $invokeScript)) {
    Write-Error "coord-sync.sh not found at $liveMirror or $repoScript. Run install.sh first."
    exit 1
}

# PowerShell 5.1-safe Windows->POSIX path conversion (no scriptblock -replace).
function ConvertTo-Posix([string]$p) {
    $s = $p -replace '\\', '/'
    if ($s -match '^([A-Za-z]):(.*)$') { $s = '/' + $Matches[1].ToLower() + $Matches[2] }
    return $s
}

$posixScript = ConvertTo-Posix $invokeScript
$posixLogDir = ConvertTo-Posix "$env:USERPROFILE\.claude\state\coord-sync"

# ------------------------------------------------------------------
# Wrapper files (runbook §Registration pattern) — machine STATE dir.
# ------------------------------------------------------------------
$wrapperDir = Join-Path $env:USERPROFILE ".claude\state\task-wrappers"
$vbsPath    = Join-Path $wrapperDir "run-hidden.vbs"
$cmdPath    = Join-Path $wrapperDir "coord-sync-tick.cmd"

$vbsContent = @'
Set sh = CreateObject("WScript.Shell")
cmd = ""
For i = 0 To WScript.Arguments.Count - 1
  cmd = cmd & """" & WScript.Arguments(i) & """" & " "
Next
sh.Run Trim(cmd), 0, False
'@

# NOTE the doubled %% — batch-file semantics: %%Y reaches bash as %Y. A
# single % would be parsed as a (missing) batch variable and stripped.
$cmdContent = @"
@echo off
"$bash" -c "export PATH=/usr/bin:/mingw64/bin:`$PATH; mkdir -p '$posixLogDir'; bash '$posixScript' >> '$posixLogDir/cron-`$(date +%%Y-%%m-%%d).log' 2>&1"
"@

if ($PSCmdlet.ShouldProcess($wrapperDir, 'Write task wrapper files (run-hidden.vbs if absent + coord-sync-tick.cmd)')) {
    if (-not (Test-Path $wrapperDir)) { New-Item -ItemType Directory -Path $wrapperDir -Force | Out-Null }
    if (-not (Test-Path $vbsPath)) { Set-Content -Path $vbsPath -Value $vbsContent -Encoding ASCII }
    Set-Content -Path $cmdPath -Value $cmdContent -Encoding ASCII
    Write-Host "Wrote wrapper: $cmdPath"
} else {
    Write-Host "(-WhatIf) Would write $vbsPath (if absent) and $cmdPath with:"
    Write-Host $cmdContent
}

# ------------------------------------------------------------------
# Scheduled task: wscript (hidden) -> .cmd -> bash coord-sync.sh
# ------------------------------------------------------------------
$wscript = Join-Path $env:SystemRoot "System32\wscript.exe"
$Action = New-ScheduledTaskAction -Execute $wscript -Argument "`"$vbsPath`" `"$cmdPath`""

$startTime = (Get-Date).AddMinutes(1)
$Trigger = New-ScheduledTaskTrigger -Once -At $startTime `
    -RepetitionInterval (New-TimeSpan -Seconds $IntervalSeconds) `
    -RepetitionDuration (New-TimeSpan -Days 3650)

$Settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 5) `
    -MultipleInstances IgnoreNew

$Description = "Cross-machine coordination cadence (cockpit-roadmap-redesign Task 7 / A5): every ${IntervalSeconds}s fire is a marker check; coord-sync.sh runs the FULL exporter->push->pull cycle on a dirty marker (event path, ~1min publish latency) and ALWAYS at least every COORD_SYNC_FLOOR_SECONDS=600s regardless of the marker (keepalive-honesty floor + git-blind-mutation coverage). Wrapper pattern per docs/runbooks/session-resumer.md §Registration. Source: adapters/claude-code/scripts/install-coord-sync-task.ps1"

$taskExists = [bool](Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue)
if ($PSCmdlet.ShouldProcess($TaskName, $(if ($taskExists) { 'Update scheduled task' } else { 'Register scheduled task' }))) {
    if ($taskExists) {
        Set-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Settings $Settings | Out-Null
        Write-Host "Updated existing scheduled task: $TaskName"
    } else {
        Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Settings $Settings -Description $Description | Out-Null
        Write-Host "Installed scheduled task: $TaskName"
    }
} else {
    Write-Host "(-WhatIf) Would $(if ($taskExists) { 'update' } else { 'register' }) scheduled task: $TaskName"
    Write-Host "(-WhatIf) Trigger StartBoundary:      $startTime"
    Write-Host "(-WhatIf) Trigger RepetitionInterval: $IntervalSeconds seconds"
    Write-Host "(-WhatIf) Settings MultipleInstances:  IgnoreNew"
    Write-Host "(-WhatIf) Settings ExecutionTimeLimit: 5 minutes"
    Write-Host "(-WhatIf) Action exec: $wscript"
    Write-Host "(-WhatIf) Action args: `"$vbsPath`" `"$cmdPath`""
}

Write-Host ""
Write-Host "Cadence:  every ${IntervalSeconds}s marker-check (full cycle on event or >=600s floor)"
Write-Host "Wrapper:  $cmdPath -> $invokeScript"
Write-Host "Log:      $env:USERPROFILE\.claude\state\coord-sync\cron-<date>.log"
Write-Host ""
Write-Host "One-shot full-cycle test (bypasses the debounce):"
Write-Host "  bash '$posixScript' --force"
Write-Host ""
Write-Host "Uninstall:"
Write-Host "  powershell -File '$($MyInvocation.MyCommand.Path)' -Uninstall"
