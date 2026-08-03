# install-maintenance-task.ps1 — Windows schtasks adapter for
# nl-maintenance.sh (harness-execution-redesign-2026-08, Task 3 / Stage 1).
#
# WHAT THIS REGISTERS: exactly ONE recurring Windows scheduled task,
# `NL-Maintenance`, that fires `nl-maintenance.sh --watchdog` on a fixed
# interval (default 300s). `--watchdog` is deterministic (no model calls,
# no heavy check logic itself): it reads the daemon's heartbeat freshness
# and, only if stale, relaunches `nl-maintenance.sh --daemon` in the
# background (nohup+disown). The daemon then runs the SIX maintenance
# mechanisms as internal jobs on their own completion-anchored cadences
# (schedule-manifest.json) — this is "one remaining recurring OS task per
# machine" (R3.3), not six.
#
# SAME conventions as the sibling installers (install-limit-resume-
# task.ps1 is the most recent reference): Git-Bash candidate resolution,
# a SHARED hidden-window VBS launcher under
# %USERPROFILE%\.claude\state\task-wrappers (never ~/.claude/scripts,
# which install.sh's live-mirror sync would overwrite), MultipleInstances
# IgnoreNew (the OS-level overlap backstop — nl-maintenance.sh's own
# sf_guard single-flight is the second, script-level backstop, invariant 4
# belt-and-braces), StartWhenAvailable (Edge Case 2: a missed fire while
# the machine is asleep/off DELAYS, never STACKS), -WhatIf dry-run support
# via SupportsShouldProcess.
#
# SAME-STAGE LEGACY DISABLE (invariant 9: "registrations disabled same-
# stage, deleted at +30-day Stage 4 pass"): after registering NL-Maintenance,
# this script reads `legacy_task_name` from every `managed_by:
# "nl-maintenance"` entry in config/schedule-manifest.json and
# Disable-ScheduledTask's each one that is still Enabled — idempotent
# (already-Disabled tasks are a silent no-op) and tolerant of a task not
# existing at all on this machine. Pass -SkipLegacyDisable to opt out (e.g.
# to install NL-Maintenance first and disable the legacy tasks by hand on
# your own schedule). `downstream-product-health-monitor` and
# `NL-LimitResume` are deliberately NEVER touched by this script (see
# schedule-manifest.json's own notes on both).
#
# USAGE
#   powershell -File install-maintenance-task.ps1
#   powershell -File install-maintenance-task.ps1 -WhatIf
#   powershell -File install-maintenance-task.ps1 -SkipLegacyDisable
#   powershell -File install-maintenance-task.ps1 -Uninstall
#   powershell -File install-maintenance-task.ps1 -Rollback   # uninstall
#       NL-Maintenance AND re-enable every legacy task this script
#       previously disabled (the documented rollback path, plan Behavioral
#       Contracts section: "Enable-ScheduledTask on the six disabled tasks
#       + HALT on the core")
#
# Verification after install (operator-run, not agent-run):
#   Get-ScheduledTask -TaskName 'NL-Maintenance'
#   Start-ScheduledTask -TaskName 'NL-Maintenance'   # one-shot watchdog tick
#   schtasks /Query /TN NL-Maintenance /V | findstr "Last Result"
#   Get-Content "$env:USERPROFILE\.claude\state\nl-maintenance\logs\daemon.stdout.log"

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$RepoPath = "$HOME\dev\<work-org>\neural-lace",
    [int]$WatchdogIntervalSeconds = 300,
    [switch]$SkipLegacyDisable,
    [switch]$Uninstall,
    [switch]$Rollback
)

$ErrorActionPreference = 'Stop'
$TaskName = 'NL-Maintenance'

function Get-LegacyTaskNames {
    # Reads legacy_task_name from every managed_by:"nl-maintenance" entry
    # in schedule-manifest.json. Prefers the live mirror copy (matches the
    # scripts it disables being live-mirror scheduled tasks); falls back
    # to the repo copy for a fresh checkout that has not run install.sh
    # yet. Returns an empty array (never errors) if neither is readable.
    $liveManifest = Join-Path $env:USERPROFILE ".claude\config\schedule-manifest.json"
    $repoManifest = Join-Path $RepoPath "adapters\claude-code\config\schedule-manifest.json"
    $manifestPath = if (Test-Path $liveManifest) { $liveManifest } else { $repoManifest }
    if (-not (Test-Path $manifestPath)) {
        Write-Warning "schedule-manifest.json not found at $liveManifest or $repoManifest -- cannot resolve legacy task names to disable/rollback."
        return @()
    }
    try {
        $manifest = Get-Content -Raw -Path $manifestPath | ConvertFrom-Json
    } catch {
        Write-Warning "Could not parse $manifestPath as JSON -- skipping legacy task resolution."
        return @()
    }
    $names = $manifest.mechanisms |
        Where-Object { $_.managed_by -eq 'nl-maintenance' -and $_.legacy_task_name } |
        ForEach-Object { $_.legacy_task_name }
    return @($names)
}

if ($Uninstall -or $Rollback) {
    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
        if ($PSCmdlet.ShouldProcess($TaskName, 'Unregister scheduled task')) {
            Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
            Write-Host "Uninstalled scheduled task: $TaskName"
        }
    } else {
        Write-Host "No scheduled task '$TaskName' found -- nothing to uninstall."
    }
    if ($Rollback) {
        $legacyNames = Get-LegacyTaskNames
        foreach ($name in $legacyNames) {
            $t = Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue
            if (-not $t) {
                Write-Host "  (rollback) '$name' not found on this machine -- skipping."
                continue
            }
            if ($PSCmdlet.ShouldProcess($name, 'Enable scheduled task (rollback)')) {
                Enable-ScheduledTask -TaskName $name | Out-Null
                Write-Host "  (rollback) Re-enabled: $name"
            }
        }
    }
    exit 0
}

# Locate bash.exe -- same candidate list as the sibling installers.
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

function ConvertTo-Posix([string]$p) {
    $s = $p -replace '\\', '/'
    if ($s -match '^([A-Za-z]):(.*)$') { $s = '/' + $Matches[1].ToLower() + $Matches[2] }
    return $s
}

# Shared wrapper dir + hidden-window VBS launcher (machine STATE dir --
# never ~/.claude/scripts, which install.sh re-syncs and would wipe it;
# reuses the SAME run-hidden.vbs another NL task may already have written).
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

# Resolve nl-maintenance.sh -- prefer the live mirror, fallback to the repo
# copy (same pattern as every sibling installer).
$liveScript = "$env:USERPROFILE\.claude\scripts\nl-maintenance.sh"
$repoScript = Join-Path $RepoPath "adapters\claude-code\scripts\nl-maintenance.sh"
$coreScript = if (Test-Path $liveScript) { $liveScript } else { $repoScript }

if (-not (Test-Path $coreScript)) {
    Write-Warning "nl-maintenance.sh not found at $liveScript or $repoScript. Run install.sh first (or pass -RepoPath)."
    exit 1
}

$posixScript = ConvertTo-Posix $coreScript
$posixLogDir = ConvertTo-Posix (Join-Path $env:USERPROFILE ".claude\state\task-wrappers")
$cmdPath = Join-Path $wrapperDir "nl-maintenance-watchdog.cmd"

# `--watchdog` itself is cheap (one heartbeat-freshness check; relaunches
# the daemon only when stale) -- safe to fire every WatchdogIntervalSeconds
# forever. Doubled %% (batch semantics: %%Y reaches bash as %Y), matching
# the sibling wrappers' convention.
$cmdContent = @"
@echo off
"$bash" -c "export PATH=/usr/bin:/mingw64/bin:`$PATH; mkdir -p '$posixLogDir'; bash '$posixScript' --watchdog >> '$posixLogDir/nl-maintenance-watchdog-`$(date +%%Y-%%m-%%d).log' 2>&1"
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
    -RepetitionInterval (New-TimeSpan -Seconds $WatchdogIntervalSeconds) `
    -RepetitionDuration (New-TimeSpan -Days 3650)

# ExecutionTimeLimit generous: --watchdog itself returns near-instantly
# (the relaunch it may trigger is backgrounded/non-blocking, mirroring
# ensure-cockpit.sh's dispatch contract) -- this ceiling is a safety net,
# not an expected runtime.
$Settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 5) `
    -MultipleInstances IgnoreNew

$taskExists = [bool](Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue)
if ($PSCmdlet.ShouldProcess($TaskName, $(if ($taskExists) { 'Update scheduled task' } else { 'Register scheduled task' }))) {
    if ($taskExists) {
        Set-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Settings $Settings | Out-Null
        Write-Host "Updated existing scheduled task: $TaskName"
    } else {
        Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Settings $Settings `
            -Description "harness-execution-redesign-2026-08 Task 3: the ONE remaining recurring OS task for harness maintenance. Every ${WatchdogIntervalSeconds}s runs nl-maintenance.sh --watchdog (cheap heartbeat-freshness check; relaunches the daemon only if stale). The daemon hosts coord-sync/supervisor-tick/workstreams-heartbeat/session-resumer/health-tick/doctor-verdict-refresh as completion-anchored internal jobs (config/schedule-manifest.json). Source: adapters/claude-code/scripts/install-maintenance-task.ps1" | Out-Null
        Write-Host "Installed scheduled task: $TaskName"
    }
} else {
    Write-Host "(-WhatIf) Would $(if ($taskExists) { 'update' } else { 'register' }) scheduled task: $TaskName"
    Write-Host "(-WhatIf) Trigger StartBoundary:      $startTime"
    Write-Host "(-WhatIf) Trigger RepetitionInterval: $WatchdogIntervalSeconds seconds"
    Write-Host "(-WhatIf) Settings MultipleInstances:  IgnoreNew"
    Write-Host "(-WhatIf) Settings ExecutionTimeLimit: 5 minutes"
    Write-Host "(-WhatIf) Action exec: $wscript"
    Write-Host "(-WhatIf) Action args: `"$vbsPath`" `"$cmdPath`""
}

if (-not $SkipLegacyDisable) {
    $legacyNames = Get-LegacyTaskNames
    if ($legacyNames.Count -eq 0) {
        Write-Host "No legacy task names resolved from schedule-manifest.json -- nothing to disable."
    }
    foreach ($name in $legacyNames) {
        $t = Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue
        if (-not $t) {
            Write-Host "  Legacy task '$name' not found on this machine -- skipping (nothing to disable)."
            continue
        }
        if ($t.State -eq 'Disabled') {
            Write-Host "  Legacy task '$name' already Disabled -- no-op."
            continue
        }
        if ($PSCmdlet.ShouldProcess($name, 'Disable scheduled task (superseded by NL-Maintenance)')) {
            Disable-ScheduledTask -TaskName $name | Out-Null
            Write-Host "  Disabled (superseded by NL-Maintenance): $name"
        } else {
            Write-Host "  (-WhatIf) Would disable: $name"
        }
    }
    Write-Host "(NOTE: registrations are DISABLED, not deleted -- the +30-day Stage 4 pass deletes them after the soak proves out. Rollback: powershell -File install-maintenance-task.ps1 -Rollback)"
} else {
    Write-Host "-SkipLegacyDisable set -- legacy scheduled tasks left untouched."
}
