# install-daily-harness-eval-task.ps1
#
# Installs a Windows Scheduled Task that runs the harness-evaluator
# daily wrapper at 5:00 PM local time. Per Misha 2026-05-28:
#   - 5 PM daily cadence
#   - Output: harness-evaluator daily packet at
#     .claude/state/harness-eval/YYYY-MM-DD-harness-self-eval.md
#   - Side-effect: when high-severity drift detected, an alert marker
#     is written to ~/.claude/state/external-monitor-alerts/ which
#     the SessionStart hook surfaces on the next interactive Code session
#     (the "Dispatch wakeup" transport — no ntfy.sh / phone / email)
#
# Run this script ONCE per machine as a normal (non-elevated) user.
# Re-running is safe (idempotent — task is re-registered with same name).
#
# Usage:
#   pwsh -File adapters/claude-code/scripts/install-daily-harness-eval-task.ps1
#   pwsh -File ... -RepoPath "$env:USERPROFILE\dev\<work-org>\neural-lace"
#   pwsh -File ... -Time "17:00"
#   pwsh -File ... -Uninstall
#
# Verification after install:
#   Get-ScheduledTask -TaskName 'NeuralLace-HarnessEvaluator-Daily'
#   Start-ScheduledTask -TaskName 'NeuralLace-HarnessEvaluator-Daily'  # one-shot test

[CmdletBinding()]
param(
    [string]$RepoPath = "$HOME\dev\<work-org>\neural-lace",
    [string]$Time = "17:00",
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'
$TaskName = 'NeuralLace-HarnessEvaluator-Daily'

if ($Uninstall) {
    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Host "Uninstalled scheduled task: $TaskName"
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

$scriptPath = Join-Path $RepoPath 'adapters\claude-code\scripts\harness-evaluator-daily.sh'
$liveMirror = "$HOME\.claude\scripts\harness-evaluator-daily.sh"
$invokeScript = if (Test-Path $liveMirror) { $liveMirror } else { $scriptPath }

if (-not (Test-Path $invokeScript)) {
    Write-Error "harness-evaluator-daily.sh not found. Run install.sh first to populate ~/.claude/scripts/."
    exit 1
}

# Convert Windows path → POSIX path for bash invocation
$posixScript = $invokeScript -replace '\\', '/' -replace '^C:', '/c'
$posixRepo   = $RepoPath -replace '\\', '/' -replace '^C:', '/c'

# Build the action: cd into repo + invoke wrapper. Capture output to a log
# under .claude/state/harness-eval/cron-YYYY-MM-DD.log for retro debugging.
$cronLogDir = Join-Path $RepoPath '.claude\state\harness-eval'
if (-not (Test-Path $cronLogDir)) { New-Item -ItemType Directory -Path $cronLogDir -Force | Out-Null }
$logTemplate = "$cronLogDir\cron-`$(date +%Y-%m-%d).log".Replace('\', '/').Replace('C:', '/c')

# Use a single bash -c invocation that does: cd, run wrapper, redirect log
$bashCmd = "cd '$posixRepo' && bash '$posixScript' >> '$logTemplate' 2>&1"
$Action = New-ScheduledTaskAction -Execute $bash -Argument "-l -c `"$bashCmd`""

# Daily trigger at $Time
$Trigger = New-ScheduledTaskTrigger -Daily -At $Time

# Settings: run only when user logged in (matches Code-session usage shape);
# don't queue if missed (skip if PC was off — harness state survives anyway);
# allow start on battery; up-to-1-hour late OK.
$Settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Hours 1) `
    -MultipleInstances IgnoreNew

$Description = "Daily 5-PM harness-evaluator packet generation. Writes Dispatch-wakeup alert marker on high-severity drift. Source: adapters/claude-code/scripts/install-daily-harness-eval-task.ps1"

if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    Set-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Settings $Settings | Out-Null
    Write-Host "Updated existing scheduled task: $TaskName"
} else {
    Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Settings $Settings -Description $Description | Out-Null
    Write-Host "Installed scheduled task: $TaskName"
}

Write-Host ""
Write-Host "Schedule: daily at $Time local time"
Write-Host "Repo:     $RepoPath"
Write-Host "Wrapper:  $invokeScript"
Write-Host "Log:      $cronLogDir\cron-<date>.log"
Write-Host ""
Write-Host "One-shot test (runs immediately, doesn't wait for 5 PM):"
Write-Host "  Start-ScheduledTask -TaskName '$TaskName'"
Write-Host ""
Write-Host "Uninstall:"
Write-Host "  pwsh -File '$($MyInvocation.MyCommand.Path)' -Uninstall"
