<#
.SYNOPSIS
    Add Windows Defender exclusions for Claude Code development paths.

.DESCRIPTION
    Windows Defender's Antimalware Service Executable real-time-scans every
    file Claude Code touches: worktree creation churn, node_modules I/O,
    bash subprocess output, JSONL transcript writes, harness state files,
    Cowork session storage. On busy machines this regularly burns 15-25%
    CPU even when the user is idle.

    This script adds the development paths and processes to Defender's
    exclusion list so they are skipped by real-time scanning. The script is:

      - Idempotent. Re-running checks existing exclusions and only adds
        what is missing.
      - Self-elevating. Re-launches under UAC if not already running as
        administrator. Defender Add-MpPreference requires admin.
      - Path-portable. Uses $env:USERPROFILE / $env:APPDATA so the script
        works for any Windows user (not hardcoded to one home dir).
      - Honest in reporting. Prints exactly what was added vs already
        present vs skipped (and why).

    SECURITY TRADEOFF: excluded paths are NOT scanned by Defender's
    real-time protection. Files written into those paths could carry
    malware that Defender will not catch. This is a standard dev-machine
    optimization, but worth knowing. See the companion doc at
    docs/host-setup/windows-defender-exclusions.md for full discussion.

.PARAMETER DryRun
    Print what would be added; do not modify Defender state. Skips the
    elevation check (read-only operations don't need admin).

.PARAMETER Help
    Print usage and exit.

.EXAMPLE
    # Normal run (auto-elevates):
    powershell -ExecutionPolicy Bypass -File .\setup-defender-exclusions.ps1

    # Preview without modifying state:
    powershell -ExecutionPolicy Bypass -File .\setup-defender-exclusions.ps1 -DryRun

.NOTES
    Source: neural-lace harness, adapters/claude-code/scripts/host-setup/
    Companion doc: docs/host-setup/windows-defender-exclusions.md
    Verify state: Get-MpPreference | Select-Object -Expand ExclusionPath
                  Get-MpPreference | Select-Object -Expand ExclusionProcess
    Remove later: Remove-MpPreference -ExclusionPath <path>
                  Remove-MpPreference -ExclusionProcess <name>
#>

#Requires -Version 5.1

[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$Help
)

# ============================================================
# --help
# ============================================================

if ($Help) {
    Get-Help -Full $PSCommandPath
    exit 0
}

# ============================================================
# Self-elevate via UAC if not running as administrator
# ============================================================
# Add-MpPreference requires admin. Get-MpPreference does not, so DryRun
# can run without elevation.

$isAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole( `
    [Security.Principal.WindowsBuiltInRole] "Administrator")

if (-not $isAdmin -and -not $DryRun) {
    Write-Host ""
    Write-Host "This script needs administrator privileges to modify Defender." -ForegroundColor Yellow
    Write-Host "Re-launching with UAC elevation prompt..." -ForegroundColor Yellow
    Write-Host ""

    $argString = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    if ($DryRun) { $argString += " -DryRun" }

    try {
        Start-Process -FilePath PowerShell.exe -ArgumentList $argString -Verb RunAs -ErrorAction Stop
    } catch {
        Write-Host "User declined elevation or UAC failed. Aborting." -ForegroundColor Red
        exit 1
    }
    exit 0
}

# ============================================================
# Define exclusions
# ============================================================
# Folder exclusions are recursive in Defender by default.
# Process exclusions match by executable name only (no path).

$folderExclusions = @(
    @{
        Path = "$env:USERPROFILE\claude-projects"
        Reason = "Worktree churn + node_modules I/O + dev file edits"
    },
    @{
        Path = "$env:USERPROFILE\.claude"
        Reason = "Harness state, hooks, agents, JSONL transcripts, cache"
    },
    @{
        Path = "$env:APPDATA\Claude"
        Reason = "Cowork session storage (Cache, Code Cache, IndexedDB, etc.)"
    }
)

$processExclusions = @(
    @{ Name = "bash.exe";   Reason = "Git Bash subprocess churn" },
    @{ Name = "node.exe";   Reason = "Node-based tooling, npm install, tsc" },
    @{ Name = "git.exe";    Reason = "Frequent staging/diff/status calls" },
    @{ Name = "claude.exe"; Reason = "Claude Code CLI's own file I/O" }
)

# ============================================================
# Read current Defender state
# ============================================================

Write-Host ""
Write-Host "Windows Defender Exclusions Setup (Neural Lace host-setup)" -ForegroundColor Cyan
Write-Host "===========================================================" -ForegroundColor Cyan
if ($DryRun) {
    Write-Host "MODE: DRY RUN (no changes will be made)" -ForegroundColor Yellow
}
Write-Host ""

try {
    $mp = Get-MpPreference -ErrorAction Stop
} catch {
    Write-Host "ERROR: Get-MpPreference failed. Is Windows Defender available on this system?" -ForegroundColor Red
    Write-Host "       (On non-Windows or systems without Defender, this script is a no-op.)" -ForegroundColor Red
    Write-Host "       Underlying error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Defender stores paths case-insensitively. Normalize for comparison.
$existingPaths = @()
if ($mp.ExclusionPath) {
    $existingPaths = $mp.ExclusionPath | ForEach-Object { $_.TrimEnd('\').ToLower() }
}
$existingProcesses = @()
if ($mp.ExclusionProcess) {
    $existingProcesses = $mp.ExclusionProcess | ForEach-Object { $_.ToLower() }
}

# ============================================================
# Process folder exclusions
# ============================================================

Write-Host "Folder exclusions:" -ForegroundColor Cyan
Write-Host ""

$added = 0
$already = 0
$skipped = 0

foreach ($entry in $folderExclusions) {
    $path = $entry.Path
    $reason = $entry.Reason
    $normalized = $path.TrimEnd('\').ToLower()

    if (-not (Test-Path -LiteralPath $path)) {
        Write-Host "  [SKIP]    $path" -ForegroundColor DarkYellow
        Write-Host "            path does not exist on this machine; skipping" -ForegroundColor DarkGray
        $skipped++
        continue
    }

    if ($existingPaths -contains $normalized) {
        Write-Host "  [EXISTS]  $path" -ForegroundColor DarkGreen
        Write-Host "            already excluded; no change needed" -ForegroundColor DarkGray
        $already++
        continue
    }

    if ($DryRun) {
        Write-Host "  [WOULD ADD] $path" -ForegroundColor Yellow
        Write-Host "              reason: $reason" -ForegroundColor DarkGray
    } else {
        try {
            Add-MpPreference -ExclusionPath $path -ErrorAction Stop
            Write-Host "  [ADDED]   $path" -ForegroundColor Green
            Write-Host "            reason: $reason" -ForegroundColor DarkGray
            $added++
        } catch {
            Write-Host "  [FAIL]    $path" -ForegroundColor Red
            Write-Host "            $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

# ============================================================
# Process executable exclusions
# ============================================================

Write-Host ""
Write-Host "Process exclusions:" -ForegroundColor Cyan
Write-Host ""

$procAdded = 0
$procAlready = 0

foreach ($entry in $processExclusions) {
    $name = $entry.Name
    $reason = $entry.Reason
    $normalized = $name.ToLower()

    if ($existingProcesses -contains $normalized) {
        Write-Host "  [EXISTS]  $name" -ForegroundColor DarkGreen
        Write-Host "            already excluded; no change needed" -ForegroundColor DarkGray
        $procAlready++
        continue
    }

    if ($DryRun) {
        Write-Host "  [WOULD ADD] $name" -ForegroundColor Yellow
        Write-Host "              reason: $reason" -ForegroundColor DarkGray
    } else {
        try {
            Add-MpPreference -ExclusionProcess $name -ErrorAction Stop
            Write-Host "  [ADDED]   $name" -ForegroundColor Green
            Write-Host "            reason: $reason" -ForegroundColor DarkGray
            $procAdded++
        } catch {
            Write-Host "  [FAIL]    $name" -ForegroundColor Red
            Write-Host "            $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

# ============================================================
# Summary
# ============================================================

Write-Host ""
Write-Host "Summary:" -ForegroundColor Cyan
if ($DryRun) {
    Write-Host "  (dry-run: state unchanged)"
} else {
    Write-Host "  Folder exclusions:  added=$added, already-present=$already, skipped=$skipped"
    Write-Host "  Process exclusions: added=$procAdded, already-present=$procAlready"
}
Write-Host ""
Write-Host "Verify state:"
Write-Host "  Get-MpPreference | Select-Object -Expand ExclusionPath"
Write-Host "  Get-MpPreference | Select-Object -Expand ExclusionProcess"
Write-Host ""
Write-Host "Remove a single exclusion (if you change your mind):"
Write-Host "  Remove-MpPreference -ExclusionPath '<path>'"
Write-Host "  Remove-MpPreference -ExclusionProcess '<name>'"
Write-Host ""

# ============================================================
# OPTIONAL: Granular per-repo node_modules exclusions
# ============================================================
# The parent-folder exclusion above ($env:USERPROFILE\claude-projects) is
# recursive and already covers every node_modules directory underneath it.
# You do NOT need the granular block below as long as the parent exclusion
# is in place.
#
# Use the granular block ONLY if you later remove the parent-folder
# exclusion (e.g., you decide you want Defender to scan your dev sources
# but not the dependency trees). In that scenario, the function below
# enumerates every node_modules directory under your claude-projects tree
# at runtime and excludes each one individually.
#
# To activate: uncomment the call to Add-NodeModulesExclusions at the end
# of this block, then re-run the script.

function Get-ClaudeProjectsNodeModulesPaths {
    <#
    .SYNOPSIS
        Find every node_modules directory under ~/claude-projects.
    .OUTPUTS
        Array of full paths.
    #>
    $root = "$env:USERPROFILE\claude-projects"
    if (-not (Test-Path -LiteralPath $root)) {
        Write-Host "  Root not found: $root" -ForegroundColor DarkYellow
        return @()
    }
    # -Force includes hidden dirs (e.g., .claude/worktrees/*/node_modules).
    # -ErrorAction SilentlyContinue swallows permission denials on stale dirs.
    Get-ChildItem -Path $root -Recurse -Force -Directory `
        -Filter "node_modules" `
        -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty FullName
}

function Add-NodeModulesExclusions {
    <#
    .SYNOPSIS
        Add a Defender exclusion for each node_modules directory under
        ~/claude-projects. Idempotent. Requires admin.
    #>
    $mp2 = Get-MpPreference
    $existing = @()
    if ($mp2.ExclusionPath) {
        $existing = $mp2.ExclusionPath | ForEach-Object { $_.TrimEnd('\').ToLower() }
    }

    $paths = Get-ClaudeProjectsNodeModulesPaths
    if ($paths.Count -eq 0) {
        Write-Host "  No node_modules directories found under ~/claude-projects."
        return
    }

    Write-Host ""
    Write-Host "Granular node_modules exclusions:" -ForegroundColor Cyan
    Write-Host ""
    $addedNm = 0
    foreach ($p in $paths) {
        $norm = $p.TrimEnd('\').ToLower()
        if ($existing -contains $norm) {
            Write-Host "  [EXISTS]  $p" -ForegroundColor DarkGreen
            continue
        }
        try {
            Add-MpPreference -ExclusionPath $p -ErrorAction Stop
            Write-Host "  [ADDED]   $p" -ForegroundColor Green
            $addedNm++
        } catch {
            Write-Host "  [FAIL]    $p" -ForegroundColor Red
            Write-Host "            $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    Write-Host ""
    Write-Host "  Total node_modules exclusions added: $addedNm"
}

# UNCOMMENT THE LINE BELOW to enable granular per-node_modules exclusions
# (only do this AFTER removing the ~/claude-projects parent exclusion):
#
# Add-NodeModulesExclusions
