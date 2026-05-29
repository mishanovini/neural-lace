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

[CmdletBinding()]
param(
    [string]$RepoPath = "$HOME\dev\<work-org>\neural-lace",
    [string]$DayOfWeek = "Monday",
    [string]$Time = "09:00",
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'
$TaskName = 'NeuralLace-HarnessHygiene-Weekly'

if ($Uninstall) {
    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Host "Uninstalled scheduled task: $TaskName"
    } else {
        Write-Host "No scheduled task '$TaskName' found — nothing to uninstall."
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

$scriptPath = Join-Path $RepoPath 'adapters\claude-code\scripts\harness-hygiene-weekly.sh'
$liveMirror = "$HOME\.claude\scripts\harness-hygiene-weekly.sh"
$invokeScript = if (Test-Path $liveMirror) { $liveMirror } else { $scriptPath }

if (-not (Test-Path $invokeScript)) {
    Write-Error "harness-hygiene-weekly.sh not found. Run install.sh first to populate ~/.claude/scripts/."
    exit 1
}

# Convert Windows path → POSIX path for bash invocation
$posixScript = $invokeScript -replace '\\', '/' -replace '^C:', '/c'
$posixRepo   = $RepoPath -replace '\\', '/' -replace '^C:', '/c'

# Build the action: cd into repo + invoke wrapper. Capture output to a log
# under .claude/state/harness-hygiene/cron-YYYY-MM-DD.log for retro debugging.
$cronLogDir = Join-Path $RepoPath '.claude\state\harness-hygiene'
if (-not (Test-Path $cronLogDir)) { New-Item -ItemType Directory -Path $cronLogDir -Force | Out-Null }
$logTemplate = "$cronLogDir\cron-`$(date +%Y-%m-%d).log".Replace('\', '/').Replace('C:', '/c')

# Use a single bash -c invocation that does: cd, run wrapper, redirect log
$bashCmd = "cd '$posixRepo' && bash '$posixScript' '$posixRepo' >> '$logTemplate' 2>&1"
$Action = New-ScheduledTaskAction -Execute $bash -Argument "-l -c `"$bashCmd`""

# Weekly trigger at $Time on $DayOfWeek
$Trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek $DayOfWeek -At $Time

# Settings: run only when user logged in (matches Code-session usage shape);
# don't queue if missed (skip if PC was off — harness state survives anyway);
# allow start on battery; up-to-1-hour late OK.
$Settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 15) `
    -MultipleInstances IgnoreNew

$Description = "Weekly harness-hygiene checks (CLAUDE.md size, rules cross-file duplication, INDEX.md sync). Writes Dispatch-wakeup alert marker on findings. Source: adapters/claude-code/scripts/install-weekly-hygiene-task.ps1"

if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    Set-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Settings $Settings | Out-Null
    Write-Host "Updated existing scheduled task: $TaskName"
} else {
    Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Settings $Settings -Description $Description | Out-Null
    Write-Host "Installed scheduled task: $TaskName"
}

Write-Host ""
Write-Host "Schedule: weekly on $DayOfWeek at $Time local time"
Write-Host "Repo:     $RepoPath"
Write-Host "Wrapper:  $invokeScript"
Write-Host "Log:      $cronLogDir\cron-<date>.log"
Write-Host "Findings: .claude/state/harness-hygiene-weekly.log + ~/.claude/state/external-monitor-alerts/"
Write-Host ""
Write-Host "One-shot test (runs immediately, doesn't wait for Monday 9 AM):"
Write-Host "  Start-ScheduledTask -TaskName '$TaskName'"
Write-Host ""
Write-Host "Uninstall:"
Write-Host "  pwsh -File '$($MyInvocation.MyCommand.Path)' -Uninstall"
