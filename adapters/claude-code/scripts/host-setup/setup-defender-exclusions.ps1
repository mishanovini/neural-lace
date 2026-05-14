<#
.SYNOPSIS
    Add Windows Defender exclusions for Claude Code development paths.

.DESCRIPTION
    Windows Defender's Antimalware Service Executable real-time-scans every
    file Claude Code touches: worktree creation churn, node_modules I/O,
    bash subprocess output, JSONL transcript writes, harness state files,
    Cowork session storage. On busy machines this regularly burns 15-25%
    CPU even when the user is idle.

    This script adds two tiers of exclusions:

      CORE — Claude Code's own paths and processes. Always relevant when
      Claude Code is installed.

      ADDITIONAL — broader dev-tooling exclusions (package manager caches,
      language servers, common shells). Catches file churn that the
      parent-folder exclusions miss (e.g., npm's per-user cache at
      ~/.npm, TypeScript's language-server cache, VS Code extensions).

    The script is:

      - Idempotent. Re-running checks existing exclusions and only adds
        what is missing.
      - Self-elevating. Re-launches under UAC if not already running as
        administrator. Defender Add-MpPreference requires admin.
        The parent waits (-Wait) for the elevated child to complete.
      - Path-portable. Uses $env:USERPROFILE / $env:APPDATA /
        $env:LOCALAPPDATA so the script works for any Windows user.
      - Honest in reporting. Prints exactly what was added vs already
        present vs skipped (and why).
      - Transcript-logged. When elevated, writes a Start-Transcript log
        to %TEMP%\neural-lace-host-setup\ for after-the-fact review.

    SECURITY TRADEOFF: excluded paths are NOT scanned by Defender's
    real-time protection. Files written into those paths could carry
    malware that Defender will not catch. This is a standard dev-machine
    optimization, but worth knowing. See the companion doc at
    docs/host-setup/windows-defender-exclusions.md for full discussion.

.PARAMETER DryRun
    Print what would be added; do not modify Defender state. Skips the
    elevation check (read-only operations don't need admin).

.PARAMETER LogFile
    Path to a transcript log file. When set, the admin-context run will
    Start-Transcript to that file. Automatically generated and passed
    through during self-elevation so the parent can read the elevated
    child's output.

.PARAMETER Help
    Print usage and exit.

.EXAMPLE
    # Normal run (auto-elevates via UAC):
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
    [switch]$Help,
    [string]$LogFile
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
# can run without elevation. The parent uses -Wait so a Bash caller
# blocks until the elevated child completes.

$isAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole( `
    [Security.Principal.WindowsBuiltInRole] "Administrator")

if (-not $isAdmin -and -not $DryRun) {
    # Generate a default log file path if one wasn't passed in
    if (-not $LogFile) {
        $logDir = "$env:TEMP\neural-lace-host-setup"
        if (-not (Test-Path -LiteralPath $logDir)) {
            New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        }
        $LogFile = "$logDir\setup-defender-exclusions-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
    }

    Write-Host ""
    Write-Host "This script needs administrator privileges to modify Defender." -ForegroundColor Yellow
    Write-Host "Re-launching with UAC elevation prompt. Output will be logged to:" -ForegroundColor Yellow
    Write-Host "  $LogFile" -ForegroundColor Yellow
    Write-Host ""

    $argString = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -LogFile `"$LogFile`""
    if ($DryRun) { $argString += " -DryRun" }

    try {
        Start-Process -FilePath PowerShell.exe -ArgumentList $argString -Verb RunAs -Wait -ErrorAction Stop
    } catch {
        Write-Host "User declined elevation or UAC failed. Aborting." -ForegroundColor Red
        exit 1
    }

    # After the elevated child completes, surface its log content so any
    # non-interactive caller (a Bash subprocess capturing this output) can
    # see what happened in the elevated session.
    if (Test-Path -LiteralPath $LogFile) {
        Write-Host ""
        Write-Host "Elevated run complete. Log content follows:" -ForegroundColor Cyan
        Write-Host "==========================================" -ForegroundColor Cyan
        Get-Content -LiteralPath $LogFile -ErrorAction SilentlyContinue | ForEach-Object {
            Write-Host $_
        }
        Write-Host "==========================================" -ForegroundColor Cyan
        Write-Host "Log saved at: $LogFile" -ForegroundColor DarkGray
    }
    exit 0
}

# ============================================================
# Start transcript (admin context only, when LogFile is set)
# ============================================================

$transcriptStarted = $false
if ($LogFile -and -not $DryRun) {
    try {
        Start-Transcript -Path $LogFile -Force | Out-Null
        $transcriptStarted = $true
    } catch {
        Write-Host "WARN: Failed to start transcript at $LogFile : $($_.Exception.Message)" -ForegroundColor DarkYellow
    }
}

# ============================================================
# Define exclusions
# ============================================================
# Folder exclusions are recursive in Defender by default.
# Process exclusions match by executable name only (no path).
# Add-MpPreference -ExclusionPath accepts files too (e.g., .gitconfig).

$coreFolderExclusions = @(
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

$coreProcessExclusions = @(
    @{ Name = "bash.exe";   Reason = "Git Bash subprocess churn" },
    @{ Name = "node.exe";   Reason = "Node-based tooling, npm install, tsc" },
    @{ Name = "git.exe";    Reason = "Frequent staging/diff/status calls" },
    @{ Name = "claude.exe"; Reason = "Claude Code CLI's own file I/O" }
)

# Additional dev-tooling exclusions — package manager caches, language
# servers, common shells. Catch the file churn the parent-folder
# exclusions above miss (e.g., npm's per-user cache outside any project).
$additionalFolderExclusions = @(
    @{ Path = "$env:USERPROFILE\.cache";                                   Reason = "Generic dev tool cache (Yarn classic, others)" },
    @{ Path = "$env:USERPROFILE\.npm";                                     Reason = "npm package cache (per-user)" },
    @{ Path = "$env:LOCALAPPDATA\npm-cache";                               Reason = "Windows alternate npm cache" },
    @{ Path = "$env:APPDATA\npm";                                          Reason = "Global npm install dir + npm.cmd/npx.cmd shims" },
    @{ Path = "$env:LOCALAPPDATA\Yarn";                                    Reason = "Yarn package manager cache" },
    @{ Path = "$env:LOCALAPPDATA\pnpm";                                    Reason = "pnpm package manager cache + content-addressed store" },
    @{ Path = "$env:LOCALAPPDATA\Microsoft\TypeScript";                    Reason = "TypeScript language server cache" },
    @{ Path = "$env:USERPROFILE\.vscode\extensions";                       Reason = "VS Code extensions (TS / ESLint / Prettier are heavy file readers)" },
    @{ Path = "$env:LOCALAPPDATA\Programs\Microsoft VS Code";              Reason = "VS Code program files (heavy I/O on startup)" },
    @{ Path = "$env:USERPROFILE\.gitconfig";                               Reason = "Git config file (read on every git invocation)" }
)

$additionalProcessExclusions = @(
    @{ Name = "Code.exe";       Reason = "VS Code main process" },
    @{ Name = "tsserver.exe";   Reason = "TypeScript language server (heavy file watching)" },
    @{ Name = "tsc.exe";        Reason = "TypeScript compiler" },
    @{ Name = "eslint.exe";     Reason = "ESLint runner" },
    @{ Name = "prisma.exe";     Reason = "Prisma ORM CLI (schema gen, migrations)" },
    @{ Name = "next.exe";       Reason = "Next.js dev server / build" },
    @{ Name = "python.exe";     Reason = "Python interpreter (project scripts, tooling)" },
    @{ Name = "python3.exe";    Reason = "Python 3 interpreter (alternate name)" },
    @{ Name = "cmd.exe";        Reason = "Windows command shell (subprocess spawner)" },
    @{ Name = "powershell.exe"; Reason = "Windows PowerShell (subprocess spawner)" },
    @{ Name = "pwsh.exe";       Reason = "PowerShell 7+ cross-platform" }
)

# ============================================================
# Processing functions
# ============================================================

function Invoke-FolderExclusionSet {
    param(
        [Parameter(Mandatory)][string]$SectionLabel,
        [Parameter(Mandatory)][array]$Entries,
        [Parameter(Mandatory)][AllowEmptyCollection()][array]$ExistingPaths,
        [bool]$IsDryRun
    )

    Write-Host ""
    Write-Host $SectionLabel -ForegroundColor Cyan
    Write-Host ""

    $added = 0
    $already = 0
    $skipped = 0
    $failed = 0

    foreach ($entry in $Entries) {
        $path = $entry.Path
        $reason = $entry.Reason
        $normalized = $path.TrimEnd('\').ToLower()

        if (-not (Test-Path -LiteralPath $path)) {
            Write-Host "  [SKIP]    $path" -ForegroundColor DarkYellow
            Write-Host "            path does not exist on this machine; skipping" -ForegroundColor DarkGray
            $skipped++
            continue
        }

        if ($ExistingPaths -contains $normalized) {
            Write-Host "  [EXISTS]  $path" -ForegroundColor DarkGreen
            Write-Host "            already excluded; no change needed" -ForegroundColor DarkGray
            $already++
            continue
        }

        if ($IsDryRun) {
            Write-Host "  [WOULD ADD] $path" -ForegroundColor Yellow
            Write-Host "              reason: $reason" -ForegroundColor DarkGray
            $added++
        } else {
            try {
                Add-MpPreference -ExclusionPath $path -ErrorAction Stop
                Write-Host "  [ADDED]   $path" -ForegroundColor Green
                Write-Host "            reason: $reason" -ForegroundColor DarkGray
                $added++
            } catch {
                Write-Host "  [FAIL]    $path" -ForegroundColor Red
                Write-Host "            $($_.Exception.Message)" -ForegroundColor Red
                $failed++
            }
        }
    }

    return [PSCustomObject]@{
        Added   = $added
        Already = $already
        Skipped = $skipped
        Failed  = $failed
    }
}

function Invoke-ProcessExclusionSet {
    param(
        [Parameter(Mandatory)][string]$SectionLabel,
        [Parameter(Mandatory)][array]$Entries,
        [Parameter(Mandatory)][AllowEmptyCollection()][array]$ExistingProcesses,
        [bool]$IsDryRun
    )

    Write-Host ""
    Write-Host $SectionLabel -ForegroundColor Cyan
    Write-Host ""

    $added = 0
    $already = 0
    $failed = 0

    foreach ($entry in $Entries) {
        $name = $entry.Name
        $reason = $entry.Reason
        $normalized = $name.ToLower()

        if ($ExistingProcesses -contains $normalized) {
            Write-Host "  [EXISTS]  $name" -ForegroundColor DarkGreen
            Write-Host "            already excluded; no change needed" -ForegroundColor DarkGray
            $already++
            continue
        }

        if ($IsDryRun) {
            Write-Host "  [WOULD ADD] $name" -ForegroundColor Yellow
            Write-Host "              reason: $reason" -ForegroundColor DarkGray
            $added++
        } else {
            try {
                Add-MpPreference -ExclusionProcess $name -ErrorAction Stop
                Write-Host "  [ADDED]   $name" -ForegroundColor Green
                Write-Host "            reason: $reason" -ForegroundColor DarkGray
                $added++
            } catch {
                Write-Host "  [FAIL]    $name" -ForegroundColor Red
                Write-Host "            $($_.Exception.Message)" -ForegroundColor Red
                $failed++
            }
        }
    }

    return [PSCustomObject]@{
        Added   = $added
        Already = $already
        Failed  = $failed
    }
}

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
    if ($transcriptStarted) { try { Stop-Transcript | Out-Null } catch {} }
    exit 1
}

# Defender stores paths case-insensitively. Normalize for comparison.
$existingPaths = @()
if ($mp.ExclusionPath) {
    $existingPaths = @($mp.ExclusionPath | ForEach-Object { $_.TrimEnd('\').ToLower() })
}
$existingProcesses = @()
if ($mp.ExclusionProcess) {
    $existingProcesses = @($mp.ExclusionProcess | ForEach-Object { $_.ToLower() })
}

# ============================================================
# Apply exclusion sets (core + additional)
# ============================================================

$coreFolderStats = Invoke-FolderExclusionSet `
    -SectionLabel "Folder exclusions (CORE Claude Code paths):" `
    -Entries $coreFolderExclusions `
    -ExistingPaths $existingPaths `
    -IsDryRun $DryRun

$coreProcessStats = Invoke-ProcessExclusionSet `
    -SectionLabel "Process exclusions (CORE Claude Code subprocesses):" `
    -Entries $coreProcessExclusions `
    -ExistingProcesses $existingProcesses `
    -IsDryRun $DryRun

# Re-read Defender state between sections so the "additional" pass sees
# what the "core" pass just added. (Avoids spurious [ADDED] reports if the
# two sets ever overlap in the future.)
if (-not $DryRun) {
    try {
        $mp = Get-MpPreference -ErrorAction Stop
        $existingPaths = @()
        if ($mp.ExclusionPath) { $existingPaths = @($mp.ExclusionPath | ForEach-Object { $_.TrimEnd('\').ToLower() }) }
        $existingProcesses = @()
        if ($mp.ExclusionProcess) { $existingProcesses = @($mp.ExclusionProcess | ForEach-Object { $_.ToLower() }) }
    } catch {}
}

$addFolderStats = Invoke-FolderExclusionSet `
    -SectionLabel "Folder exclusions (ADDITIONAL dev-tooling caches + tools):" `
    -Entries $additionalFolderExclusions `
    -ExistingPaths $existingPaths `
    -IsDryRun $DryRun

$addProcessStats = Invoke-ProcessExclusionSet `
    -SectionLabel "Process exclusions (ADDITIONAL dev-tooling processes):" `
    -Entries $additionalProcessExclusions `
    -ExistingProcesses $existingProcesses `
    -IsDryRun $DryRun

# ============================================================
# Summary
# ============================================================

Write-Host ""
Write-Host "Summary:" -ForegroundColor Cyan
if ($DryRun) {
    Write-Host "  (dry-run: state unchanged)"
    Write-Host ("  Core folders:        would-add={0}, exists={1}, skipped={2}" -f $coreFolderStats.Added, $coreFolderStats.Already, $coreFolderStats.Skipped)
    Write-Host ("  Core processes:      would-add={0}, exists={1}" -f $coreProcessStats.Added, $coreProcessStats.Already)
    Write-Host ("  Additional folders:  would-add={0}, exists={1}, skipped={2}" -f $addFolderStats.Added, $addFolderStats.Already, $addFolderStats.Skipped)
    Write-Host ("  Additional processes:would-add={0}, exists={1}" -f $addProcessStats.Added, $addProcessStats.Already)
} else {
    Write-Host ("  Core folders:        added={0}, already-present={1}, skipped={2}, failed={3}" -f $coreFolderStats.Added, $coreFolderStats.Already, $coreFolderStats.Skipped, $coreFolderStats.Failed)
    Write-Host ("  Core processes:      added={0}, already-present={1}, failed={2}" -f $coreProcessStats.Added, $coreProcessStats.Already, $coreProcessStats.Failed)
    Write-Host ("  Additional folders:  added={0}, already-present={1}, skipped={2}, failed={3}" -f $addFolderStats.Added, $addFolderStats.Already, $addFolderStats.Skipped, $addFolderStats.Failed)
    Write-Host ("  Additional processes:added={0}, already-present={1}, failed={2}" -f $addProcessStats.Added, $addProcessStats.Already, $addProcessStats.Failed)
}
Write-Host ""
Write-Host "Verify state:"
Write-Host "  Get-MpPreference | Select-Object -Expand ExclusionPath | Sort-Object"
Write-Host "  Get-MpPreference | Select-Object -Expand ExclusionProcess | Sort-Object"
Write-Host ""
Write-Host "Remove a single exclusion (if you change your mind):"
Write-Host "  Remove-MpPreference -ExclusionPath '<path>'"
Write-Host "  Remove-MpPreference -ExclusionProcess '<name>'"
Write-Host ""

if ($transcriptStarted) {
    try { Stop-Transcript | Out-Null } catch {}
}

# ============================================================
# OPTIONAL: Granular per-repo node_modules exclusions
# ============================================================
# The CORE folder exclusion above ($env:USERPROFILE\claude-projects) is
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
        $existing = @($mp2.ExclusionPath | ForEach-Object { $_.TrimEnd('\').ToLower() })
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
