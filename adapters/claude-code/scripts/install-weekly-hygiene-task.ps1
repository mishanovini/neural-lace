# install-weekly-hygiene-task.ps1
#
# Installs a Windows Scheduled Task that runs the harness-hygiene weekly
# wrapper every Monday at 9:00 AM local time. Mirrors the structure of
# install-daily-harness-eval-task.ps1.
#
# Cadence: weekly (Monday 9 AM)
# Wrapper: adapters/claude-code/scripts/harness-hygiene-weekly.sh
# Output:  .claude/state/harness-hygiene-weekly.log + alert markers under
#          ~/.claude/state/external-monitor-alerts/ on any finding
# Side-effect: external-monitor-alert-surfacer.sh SessionStart hook
#          surfaces alerts at the next interactive session
#
# Run this script ONCE per machine as a normal (non-elevated) user.
# Re-running is safe (idempotent — task is re-registered with same name).
#
# Usage:
#   pwsh -File adapters/claude-code/scripts/install-weekly-hygiene-task.ps1
#   pwsh -File ... -RepoPath "$env:USERPROFILE\dev\<work-org>\neural-lace"
#   pwsh -File ... -DayOfWeek Monday -Time "09:00"
#   pwsh -File ... -Uninstall
#
# Verification after install:
#   Get-ScheduledTask -TaskName 'NeuralLace-HarnessHygiene-Weekly'
#   Start-ScheduledTask -TaskName 'NeuralLace-HarnessHygiene-Weekly'  # one-shot test
#
# ---------------------------------------------------------------------------
# -Checkin mode (ask-rooted-workstreams-p1 Task 17d): registers a SEPARATE
# scheduled task — 'NeuralLace-AskCockpit-Checkin' — on a 2-WEEK cadence
# (New-ScheduledTaskTrigger -Weekly -WeeksInterval 2) that runs the sibling
# wrapper adapters/claude-code/scripts/ask-cockpit-checkin.sh instead of
# harness-hygiene-weekly.sh. That wrapper writes ONE alert marker (the
# cold-start question, sketch §8 metric 1) into the SAME
# ~/.claude/state/external-monitor-alerts/ directory the weekly-hygiene task
# already writes to, so the existing external-monitor-alert-surfacer.sh
# SessionStart hook surfaces it too — zero new SessionStart entries, zero
# new surfacer code. This is a CALENDAR mechanism (a real Windows Scheduled
# Task the operator can inspect via `Get-ScheduledTask`), not a documented
# convention nobody re-runs.
#
# Usage:
#   pwsh -File adapters/claude-code/scripts/install-weekly-hygiene-task.ps1 -Checkin
#   pwsh -File ... -Checkin -RepoPath "$env:USERPROFILE\dev\<work-org>\neural-lace"
#   pwsh -File ... -Checkin -Uninstall
#
# Verification after install:
#   Get-ScheduledTask -TaskName 'NeuralLace-AskCockpit-Checkin'
#   Start-ScheduledTask -TaskName 'NeuralLace-AskCockpit-Checkin'  # one-shot test
# ---------------------------------------------------------------------------

# SupportsShouldProcess (Task 17d addition): lets a caller pass -WhatIf to
# see exactly what would be registered/unregistered — TaskName, wrapper
# path, Action, Trigger — WITHOUT touching the real Task Scheduler. This is
# the sanctioned verification path for the -Checkin addition (never mutate
# the operator's live Task Scheduler from a builder/self-test run); default
# behavior (no -WhatIf) is unchanged — ShouldProcess returns true and the
# script proceeds exactly as before this addition.
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$RepoPath = "$HOME\dev\<work-org>\neural-lace",
    [string]$DayOfWeek = "Monday",
    [string]$Time = "09:00",
    [switch]$Uninstall,
    [switch]$Checkin
)

$ErrorActionPreference = 'Stop'
$TaskName = if ($Checkin) { 'NeuralLace-AskCockpit-Checkin' } else { 'NeuralLace-HarnessHygiene-Weekly' }

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

$wrapperName = if ($Checkin) { 'ask-cockpit-checkin.sh' } else { 'harness-hygiene-weekly.sh' }
$scriptPath = Join-Path $RepoPath "adapters\claude-code\scripts\$wrapperName"
$liveMirror = "$HOME\.claude\scripts\$wrapperName"
$invokeScript = if (Test-Path $liveMirror) { $liveMirror } else { $scriptPath }

if (-not (Test-Path $invokeScript)) {
    Write-Error "$wrapperName not found. Run install.sh first to populate ~/.claude/scripts/."
    exit 1
}

# Convert Windows path → POSIX path for bash invocation
$posixScript = $invokeScript -replace '\\', '/' -replace '^C:', '/c'
$posixRepo   = $RepoPath -replace '\\', '/' -replace '^C:', '/c'

# Build the action: cd into repo + invoke wrapper. Capture output to a log
# under .claude/state/harness-hygiene/cron-YYYY-MM-DD.log (Checkin mode:
# .claude/state/ask-cockpit-checkin/cron-YYYY-MM-DD.log) for retro debugging.
$cronLogSubdir = if ($Checkin) { '.claude\state\ask-cockpit-checkin' } else { '.claude\state\harness-hygiene' }
$cronLogDir = Join-Path $RepoPath $cronLogSubdir
if (-not (Test-Path $cronLogDir)) { New-Item -ItemType Directory -Path $cronLogDir -Force | Out-Null }
$logTemplate = "$cronLogDir\cron-`$(date +%Y-%m-%d).log".Replace('\', '/').Replace('C:', '/c')

# Use a single bash -c invocation that does: cd, run wrapper, redirect log.
# ask-cockpit-checkin.sh takes NO positional args (it only writes an alert
# marker — no repo-scoped checks to run against); harness-hygiene-weekly.sh
# takes the repo path as its one positional arg. Both redirect to the same
# per-mode cron log for retro debugging.
$bashCmd = if ($Checkin) {
    "cd '$posixRepo' && bash '$posixScript' >> '$logTemplate' 2>&1"
} else {
    "cd '$posixRepo' && bash '$posixScript' '$posixRepo' >> '$logTemplate' 2>&1"
}
$Action = New-ScheduledTaskAction -Execute $bash -Argument "-l -c `"$bashCmd`""

# Trigger: weekly (harness-hygiene) at $Time on $DayOfWeek, OR the Task 17d
# 2-WEEK cadence (Checkin mode) via -WeeksInterval 2 on the same DayOfWeek/Time
# defaults (operator can override both with -DayOfWeek/-Time as usual).
$Trigger = if ($Checkin) {
    New-ScheduledTaskTrigger -Weekly -DaysOfWeek $DayOfWeek -WeeksInterval 2 -At $Time
} else {
    New-ScheduledTaskTrigger -Weekly -DaysOfWeek $DayOfWeek -At $Time
}

# Settings: run only when user logged in (matches Code-session usage shape);
# don't queue if missed (skip if PC was off — harness state survives anyway);
# allow start on battery; up-to-1-hour late OK.
$Settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 15) `
    -MultipleInstances IgnoreNew

$Description = if ($Checkin) {
    "2-week ask-cockpit cold-start check-in (ask-rooted-workstreams-p1 Task 17d, design sketch Sec8 metric 1). Writes an alert marker asking the operator to time a cold-start walkthrough at http://127.0.0.1:7733/. Source: adapters/claude-code/scripts/install-weekly-hygiene-task.ps1 -Checkin"
} else {
    "Weekly harness-hygiene checks (CLAUDE.md size, rules cross-file duplication, INDEX.md sync). Writes Dispatch-wakeup alert marker on findings. Source: adapters/claude-code/scripts/install-weekly-hygiene-task.ps1"
}

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
    Write-Host "(-WhatIf) Trigger DaysOfWeek:   $($Trigger.DaysOfWeek)"
    Write-Host "(-WhatIf) Trigger WeeksInterval: $($Trigger.WeeksInterval)"
    Write-Host "(-WhatIf) Trigger StartBoundary: $($Trigger.StartBoundary)"
    Write-Host "(-WhatIf) Action exec: $($Action.Execute)"
    Write-Host "(-WhatIf) Action args: $($Action.Arguments)"
}

Write-Host ""
if ($Checkin) {
    Write-Host "Schedule: every 2 weeks on $DayOfWeek at $Time local time"
} else {
    Write-Host "Schedule: weekly on $DayOfWeek at $Time local time"
}
Write-Host "Repo:     $RepoPath"
Write-Host "Wrapper:  $invokeScript"
Write-Host "Log:      $cronLogDir\cron-<date>.log"
if ($Checkin) {
    Write-Host "Findings: ~/.claude/state/external-monitor-alerts/ (the cold-start question; surfaced by hooks/external-monitor-alert-surfacer.sh at next SessionStart)"
} else {
    Write-Host "Findings: .claude/state/harness-hygiene-weekly.log + ~/.claude/state/external-monitor-alerts/"
}
Write-Host ""
Write-Host "One-shot test (runs immediately, doesn't wait for the next scheduled fire):"
Write-Host "  Start-ScheduledTask -TaskName '$TaskName'"
Write-Host ""
Write-Host "Uninstall:"
$uninstallSwitch = if ($Checkin) { '-Checkin -Uninstall' } else { '-Uninstall' }
Write-Host "  pwsh -File '$($MyInvocation.MyCommand.Path)' $uninstallSwitch"
