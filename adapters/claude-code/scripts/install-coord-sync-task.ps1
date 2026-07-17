# install-coord-sync-task.ps1
#
# Installs a Windows Scheduled Task ('NL-CoordSync') that runs coord-sync.sh
# — the cockpit-v2-push-materialized-store Task 3 cross-machine coordination
# cadence (A1, BINDING architecture-review amendment) — every
# -IntervalSeconds (default 600s / 10min), forever, starting ~1 minute after
# install.
#
# WHY A SIBLING INSTALLER (not a third mode on install-weekly-hygiene-
# task.ps1): that script's two modes (default + -Checkin) both use a
# `New-ScheduledTaskTrigger -Weekly` shape (days-of-week + time-of-day,
# optionally every N weeks). A sub-10-minute repeating cadence is a
# STRUCTURALLY different trigger (`-Once -At <time> -RepetitionInterval
# <timespan>`), so bolting it on as a third `if ($X) {...} else {...}` branch
# would make that script's Trigger construction a three-way fork for no
# shared benefit. This file follows its EXACT surrounding pattern instead
# (bash-locate logic, SupportsShouldProcess -WhatIf dry-run discipline,
# cron-log-dir convention, -Uninstall switch) — see that script for the
# precedent this mirrors.
#
# NO-OVERLAP POLICY (A1: "ignore-new-instance + a cheap exporter lock"):
# `-MultipleInstances IgnoreNew` below is the OS-level backstop; coord-
# sync.sh's own mkdir-based lock (STATE_DIR/coord-sync.lock) is the second,
# script-level layer — see that script's header for why both exist (a slow
# cycle running past its 600s slot needs the SCRIPT to refuse to double-run
# even if the OS ever did fire a second instance).
#
# Task name: NL-CoordSync
# Wrapper:   adapters/claude-code/scripts/coord-sync.sh
# Cadence:   every -IntervalSeconds (default 600s), starting ~1 minute after
#            install, repeating for ~10 years (Task Scheduler has no literal
#            "forever"; re-run this installer to renew if it ever expires).
# Output:    <RepoPath>/.claude/state/coord-sync/cron-YYYY-MM-DD.log (this
#            task's own stdout/stderr capture) + coord-sync.sh's own
#            STATE_DIR/cycles.log (the staleness-contract instrumentation
#            plan Task 4 reads from) + an alert marker in
#            ~/.claude/state/external-monitor-alerts/ on a persistent
#            local-commit streak (A2c) — surfaced by the EXISTING
#            external-monitor-alert-surfacer.sh SessionStart hook, zero new
#            wiring.
#
# Run this script ONCE per machine as a normal (non-elevated) user.
# Re-running is safe (idempotent — task is re-registered with the same name).
#
# Usage:
#   pwsh -File adapters/claude-code/scripts/install-coord-sync-task.ps1
#   pwsh -File ... -RepoPath "$env:USERPROFILE\dev\<work-org>\neural-lace"
#   pwsh -File ... -IntervalSeconds 600
#   pwsh -File ... -WhatIf      # dry-run: prints exactly what would be
#                               # registered WITHOUT touching Task Scheduler
#   pwsh -File ... -Uninstall
#
# Verification after install:
#   Get-ScheduledTask -TaskName 'NL-CoordSync'
#   Start-ScheduledTask -TaskName 'NL-CoordSync'   # one-shot test
#
# SupportsShouldProcess (same discipline as install-weekly-hygiene-task.ps1's
# -Checkin addition): -WhatIf is the SANCTIONED verification path for this
# installer — never mutate the operator's live Task Scheduler from a
# builder/self-test run; the operator installs the real task at deploy.
# Default behavior (no -WhatIf) registers/updates the task for real.

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$RepoPath = "$HOME\dev\<work-org>\neural-lace",
    [int]$IntervalSeconds = 600,
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

# Locate bash.exe — prefer Git Bash, fall back to WSL bash.
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

if (-not (Test-Path $RepoPath)) {
    Write-Error "RepoPath '$RepoPath' does not exist. Pass -RepoPath '<path-to-neural-lace>'."
    exit 1
}

$scriptPath = Join-Path $RepoPath "adapters\claude-code\scripts\coord-sync.sh"
$liveMirror = "$HOME\.claude\scripts\coord-sync.sh"
$invokeScript = if (Test-Path $liveMirror) { $liveMirror } else { $scriptPath }

if (-not (Test-Path $invokeScript)) {
    Write-Error "coord-sync.sh not found. Run install.sh first to populate ~/.claude/scripts/."
    exit 1
}

# Convert Windows path -> POSIX path for bash invocation.
$posixScript = $invokeScript -replace '\\', '/' -replace '^C:', '/c'
$posixRepo   = $RepoPath -replace '\\', '/' -replace '^C:', '/c'

# Build the action: invoke the wrapper, redirect output to a per-day log
# under .claude\state\coord-sync\cron-YYYY-MM-DD.log for retro debugging
# (separate from coord-sync.sh's own STATE_DIR/cycles.log, which records
# per-cycle outcome/duration rather than raw stdout/stderr).
$cronLogDir = Join-Path $RepoPath ".claude\state\coord-sync"
if (-not (Test-Path $cronLogDir)) { New-Item -ItemType Directory -Path $cronLogDir -Force | Out-Null }
$logTemplate = "$cronLogDir\cron-`$(date +%Y-%m-%d).log".Replace('\', '/').Replace('C:', '/c')

$bashCmd = "cd '$posixRepo' && bash '$posixScript' >> '$logTemplate' 2>&1"
$Action = New-ScheduledTaskAction -Execute $bash -Argument "-l -c `"$bashCmd`""

# Trigger: run once starting ~1 minute from now, repeating every
# $IntervalSeconds forever. Task Scheduler has no literal "forever" for a
# repeating trigger — RepetitionDuration must be a bounded TimeSpan, so
# ~10 years stands in for "indefinite" (re-run this installer to renew if a
# machine somehow stays on one task registration that long).
$startTime = (Get-Date).AddMinutes(1)
$Trigger = New-ScheduledTaskTrigger -Once -At $startTime `
    -RepetitionInterval (New-TimeSpan -Seconds $IntervalSeconds) `
    -RepetitionDuration (New-TimeSpan -Days 3650)

# Settings: run only when user logged in (matches Code-session usage shape);
# don't queue if missed (skip if PC was off — the next fire just resumes the
# cadence; coord-sync.sh's own staleness contract tolerates gaps, they just
# render as "peer unreachable" on the reading side); allow start on battery;
# MultipleInstances IgnoreNew is the OS-level no-overlap backstop (A1).
$Settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 5) `
    -MultipleInstances IgnoreNew

$Description = "Cross-machine coordination cadence (cockpit-v2-push-materialized-store Task 3 / A1 binding amendment): exporter -> coord-push -> coord-pull every ${IntervalSeconds}s. Staleness contract: export+publish <=600s, pull <=600s => peer view ~20min worst-case behind the peer's disk, ALWAYS labeled. Writes an alert marker into ~/.claude/state/external-monitor-alerts/ on a persistent local-commit streak (A2c). Source: adapters/claude-code/scripts/install-coord-sync-task.ps1"

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
    Write-Host "(-WhatIf) Trigger RepetitionDuration:  $($Trigger.RepetitionDuration)"
    Write-Host "(-WhatIf) Settings MultipleInstances:  IgnoreNew"
    Write-Host "(-WhatIf) Action exec: $($Action.Execute)"
    Write-Host "(-WhatIf) Action args: $($Action.Arguments)"
}

Write-Host ""
Write-Host "Cadence:  every ${IntervalSeconds}s (starting ~1 minute after install)"
Write-Host "Repo:     $RepoPath"
Write-Host "Wrapper:  $invokeScript"
Write-Host "Log:      $cronLogDir\cron-<date>.log"
Write-Host "Findings: ~/.claude/state/external-monitor-alerts/ (persistent local-commit streak; surfaced by hooks/external-monitor-alert-surfacer.sh at next SessionStart)"
Write-Host ""
Write-Host "One-shot test (runs immediately, doesn't wait for the next scheduled fire):"
Write-Host "  Start-ScheduledTask -TaskName '$TaskName'"
Write-Host ""
Write-Host "Uninstall:"
Write-Host "  pwsh -File '$($MyInvocation.MyCommand.Path)' -Uninstall"
