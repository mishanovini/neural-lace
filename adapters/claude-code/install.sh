#!/bin/bash
# NEURAL-LACE-INSTALLER
# install.sh — Deploy Neural Lace's Claude Code adapter to ~/.claude/
#
# What it does:
#   1. Syncs rules/agents/templates/hooks/docs/scripts into ~/.claude/
#   2. Copies settings.json.template to ~/.claude/settings.json (if missing)
#   3. Makes all hook scripts executable
#   4. Sets `git config --global core.hooksPath` for the pre-push scanner
#   5. Creates ~/.claude/business-patterns.d/ for team-shared pattern files
#   6. Creates ~/.neural-lace/ for telemetry and trust data (future)
#
# Usage:
#   cd /path/to/neural-lace/adapters/claude-code
#   ./install.sh                   # install or refresh
#   ./install.sh --dry-run         # print what would change, don't execute
#   ./install.sh --replace-settings  # install settings.json, back up existing
#   ./install.sh --uninstall       # best-effort uninstall (see --help)
#   ./install.sh --help            # full usage reference
#
# Re-run anytime to refresh (safe — existing symlinks are replaced).

set -e

# ============================================================
# Flag parsing
# ============================================================

MODE="install"
for arg in "$@"; do
  case "$arg" in
    --help|-h)
      MODE="help"
      ;;
    --dry-run)
      MODE="dry-run"
      ;;
    --replace-settings)
      MODE="replace-settings"
      ;;
    --uninstall)
      MODE="uninstall"
      ;;
    *)
      echo "install.sh: unknown argument: $arg" >&2
      echo "Run './install.sh --help' for usage." >&2
      exit 2
      ;;
  esac
done

# Resolve paths relative to this script's location
ADAPTER_DIR="$(cd "$(dirname "$0")" && pwd)"
NEURAL_LACE_ROOT="$(cd "$ADAPTER_DIR/../.." && pwd)"
CLAUDE_DIR="$HOME/.claude"
NEURAL_LACE_DATA="$HOME/.neural-lace"

# ============================================================
# --help
# ============================================================

if [ "$MODE" = "help" ]; then
  cat <<'HELP'
Neural Lace -- Claude Code Adapter Installer

USAGE
  ./install.sh                     Install or refresh Neural Lace in ~/.claude/
  ./install.sh --dry-run           Print what would change; don't execute
  ./install.sh --replace-settings  Install settings.json from template, backing up existing
  ./install.sh --uninstall         Best-effort uninstall (restores most recent backup)
  ./install.sh --help, -h          This message

NOTES
  - Re-running without flags is safe; existing files are backed up before overwrite.
  - settings.json is NOT overwritten by default; use --replace-settings to override.
  - ~/.claude/local/ is NEVER touched by the installer (personal config layer).
  - For a true revert to a pre-Neural-Lace state, take a whole-directory snapshot
    of ~/.claude/ BEFORE first install and restore it if needed. See SETUP.md.
HELP
  exit 0
fi

# ============================================================
# --uninstall
# ============================================================

if [ "$MODE" = "uninstall" ]; then
  echo ""
  echo "Neural Lace -- Uninstaller"
  echo ""

  # Detect Neural Lace install via symlink target OR sentinel header
  has_nl_signal=0
  if [ -L "$CLAUDE_DIR/CLAUDE.md" ]; then
    target=$(readlink "$CLAUDE_DIR/CLAUDE.md" 2>/dev/null || echo "")
    if echo "$target" | grep -q "neural-lace"; then
      has_nl_signal=1
    fi
  fi
  if [ -f "$CLAUDE_DIR/CLAUDE.md" ] && ! [ -L "$CLAUDE_DIR/CLAUDE.md" ]; then
    if head -3 "$CLAUDE_DIR/CLAUDE.md" 2>/dev/null | grep -q "Global Claude Code Standards"; then
      has_nl_signal=1
    fi
  fi

  if [ "$has_nl_signal" -eq 0 ]; then
    echo "  No Neural Lace install detected at $CLAUDE_DIR."
    echo "  Nothing to uninstall."
    echo ""
    exit 0
  fi

  # Find most recent backup directory
  most_recent_backup=""
  shopt -s nullglob 2>/dev/null || true
  for dir in "$CLAUDE_DIR"/.backup-*; do
    [ -d "$dir" ] || continue
    if [ -z "$most_recent_backup" ] || [ "$dir" \> "$most_recent_backup" ]; then
      most_recent_backup="$dir"
    fi
  done
  shopt -u nullglob 2>/dev/null || true

  # Count symlinks pointing at neural-lace
  symlink_count=0
  shopt -s nullglob 2>/dev/null || true
  for entry in "$CLAUDE_DIR"/*; do
    [ -L "$entry" ] || continue
    target=$(readlink "$entry" 2>/dev/null || echo "")
    if echo "$target" | grep -q "neural-lace"; then
      symlink_count=$((symlink_count + 1))
    fi
  done
  shopt -u nullglob 2>/dev/null || true

  # Count sentinel-bearing files (copy-mode installs)
  sentinel_count=0
  if [ -d "$CLAUDE_DIR/hooks" ] && ! [ -L "$CLAUDE_DIR/hooks" ]; then
    shopt -s nullglob 2>/dev/null || true
    for f in "$CLAUDE_DIR/hooks"/*.sh; do
      [ -f "$f" ] || continue
      if head -3 "$f" 2>/dev/null | grep -q "NEURAL-LACE-"; then
        sentinel_count=$((sentinel_count + 1))
      fi
    done
    shopt -u nullglob 2>/dev/null || true
  fi

  echo "  Detected Neural Lace install at $CLAUDE_DIR"
  if [ -n "$most_recent_backup" ]; then
    echo "  Most recent backup: $most_recent_backup"
  else
    echo "  Most recent backup: (none found)"
  fi
  echo ""
  echo "  This will:"
  echo "    - Remove symlinks pointing at the Neural Lace repo ($symlink_count found)"
  echo "    - Remove Neural Lace-originated file copies ($sentinel_count files detected by presence of sentinel)"
  if [ -n "$most_recent_backup" ]; then
    echo "    - Restore contents of $most_recent_backup to $CLAUDE_DIR"
  else
    echo "    - (No backup to restore from)"
  fi
  echo ""
  echo "  This will NOT:"
  echo "    - Remove $CLAUDE_DIR/local/ (personal config -- remove manually if desired)"
  echo "    - Remove other $CLAUDE_DIR/.backup-*/ directories (kept for 30 days per retention)"
  echo "    - Reset global git core.hooksPath (run: git config --global --unset core.hooksPath)"
  echo "    - Guarantee a pristine pre-Neural-Lace state (the backup dir only contains"
  echo "      files Neural Lace overwrote during install -- not your full prior state)."
  echo "      For a true revert, use your own pre-install whole-directory snapshot"
  echo "      (see SETUP.md \"Trying Neural Lace alongside an existing harness\")."
  echo ""
  printf "  Proceed? [y/N] "
  read -r reply
  if [ "$reply" != "y" ] && [ "$reply" != "Y" ]; then
    echo ""
    echo "  Aborted."
    exit 0
  fi
  echo ""

  # Execute: remove symlinks
  removed=0
  shopt -s nullglob 2>/dev/null || true
  for entry in "$CLAUDE_DIR"/*; do
    if [ -L "$entry" ]; then
      target=$(readlink "$entry" 2>/dev/null || echo "")
      if echo "$target" | grep -q "neural-lace"; then
        rm -f "$entry"
        removed=$((removed + 1))
      fi
    fi
  done
  shopt -u nullglob 2>/dev/null || true
  echo "  Removed $removed Neural Lace symlinks."

  # Remove sentinel-bearing files in hooks/
  sentinel_removed=0
  if [ -d "$CLAUDE_DIR/hooks" ] && ! [ -L "$CLAUDE_DIR/hooks" ]; then
    shopt -s nullglob 2>/dev/null || true
    for f in "$CLAUDE_DIR/hooks"/*.sh; do
      [ -f "$f" ] || continue
      if head -3 "$f" 2>/dev/null | grep -q "NEURAL-LACE-"; then
        rm -f "$f"
        sentinel_removed=$((sentinel_removed + 1))
      fi
    done
    shopt -u nullglob 2>/dev/null || true
  fi
  echo "  Removed $sentinel_removed Neural Lace-originated files."

  # Restore from backup
  if [ -n "$most_recent_backup" ] && [ -d "$most_recent_backup" ]; then
    restored=0
    shopt -s nullglob 2>/dev/null || true
    for item in "$most_recent_backup"/*; do
      [ -e "$item" ] || continue
      name=$(basename "$item")
      cp -r "$item" "$CLAUDE_DIR/$name"
      restored=$((restored + 1))
    done
    shopt -u nullglob 2>/dev/null || true
    echo "  Restored $restored items from $most_recent_backup."
  fi

  echo ""
  echo "  Uninstall complete (best-effort)."
  echo "  Reminder: run 'git config --global --unset core.hooksPath' if desired."
  echo ""
  exit 0
fi

# ============================================================
# --replace-settings
# ============================================================

if [ "$MODE" = "replace-settings" ]; then
  echo ""
  echo "Neural Lace -- Settings Replace"

  if [ ! -f "$ADAPTER_DIR/settings.json.template" ]; then
    echo "  ERROR: $ADAPTER_DIR/settings.json.template not found." >&2
    exit 1
  fi

  BACKUP_DIR_RS="$CLAUDE_DIR/.backup-$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$CLAUDE_DIR"

  if [ -f "$CLAUDE_DIR/settings.json" ] || [ -L "$CLAUDE_DIR/settings.json" ]; then
    mkdir -p "$BACKUP_DIR_RS"
    mv "$CLAUDE_DIR/settings.json" "$BACKUP_DIR_RS/settings.json"
    echo "  Backed up: $CLAUDE_DIR/settings.json -> $BACKUP_DIR_RS/settings.json"
  else
    echo "  (No existing settings.json to back up)"
  fi

  cp "$ADAPTER_DIR/settings.json.template" "$CLAUDE_DIR/settings.json"
  echo "  Installed: $CLAUDE_DIR/settings.json from template"
  echo ""
  echo "  ACTION REQUIRED: Edit $CLAUDE_DIR/settings.json and replace placeholders"
  echo ""
  exit 0
fi

# ============================================================
# --dry-run
# ============================================================

if [ "$MODE" = "dry-run" ]; then
  echo ""
  echo "Neural Lace -- Dry Run (no changes will be made)"
  echo "  Adapter: $ADAPTER_DIR"
  echo "  Target:  $CLAUDE_DIR"
  echo ""

  changes=0
  backups=0

  # Directories
  echo "[Phase 1: Directories]"
  for d in "$CLAUDE_DIR" "$CLAUDE_DIR/business-patterns.d" "$NEURAL_LACE_DATA/telemetry" "$CLAUDE_DIR/local"; do
    if [ -d "$d" ]; then
      echo "  [WOULD SKIP -- already exists]     $d"
    else
      echo "  [WOULD CREATE]                     $d"
      changes=$((changes + 1))
    fi
  done
  echo ""

  # Stale backup pruning
  echo "[Phase 2: Backup pruning (stale > 30 days)]"
  now_epoch=$(date +%s)
  cutoff_epoch=$((now_epoch - 30 * 24 * 60 * 60))
  stale_seen=0
  shopt -s nullglob 2>/dev/null || true
  for dir in "$CLAUDE_DIR"/.backup-*; do
    [ -d "$dir" ] || continue
    base=$(basename "$dir")
    ts="${base#.backup-}"
    if ! echo "$ts" | grep -Eq '^[0-9]{8}-[0-9]{6}$'; then
      continue
    fi
    ymd="${ts%-*}"
    hms="${ts#*-}"
    y="${ymd:0:4}"; mo="${ymd:4:2}"; d="${ymd:6:2}"
    h="${hms:0:2}"; mi="${hms:2:2}"; se="${hms:4:2}"
    dir_epoch=$(date -d "$y-$mo-$d $h:$mi:$se" +%s 2>/dev/null \
      || date -j -f "%Y-%m-%d %H:%M:%S" "$y-$mo-$d $h:$mi:$se" +%s 2>/dev/null \
      || echo "")
    [ -z "$dir_epoch" ] && continue
    if [ "$dir_epoch" -lt "$cutoff_epoch" ]; then
      echo "  [WOULD REMOVE -- stale backup]     $dir"
      stale_seen=$((stale_seen + 1))
    fi
  done
  shopt -u nullglob 2>/dev/null || true
  if [ "$stale_seen" -eq 0 ]; then
    echo "  (no stale backups to prune)"
  fi
  echo ""

  # File syncs
  echo "[Phase 3: File/directory syncs]"
  check_sync_target() {
    local src="$1"
    local dst="$2"
    local label="$3"
    if [ -e "$dst" ] && [ ! -L "$dst" ]; then
      echo "  [WOULD REPLACE -- backup existing] $dst ($label)"
      backups=$((backups + 1))
      changes=$((changes + 1))
    elif [ -L "$dst" ]; then
      echo "  [WOULD REPLACE -- relink]          $dst ($label)"
      changes=$((changes + 1))
    else
      echo "  [WOULD CREATE]                     $dst ($label)"
      changes=$((changes + 1))
    fi
  }

  check_sync_target "$ADAPTER_DIR/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md" "CLAUDE.md"
  for dir in rules agents hooks scripts pipeline-prompts pipeline-templates commands; do
    if [ -d "$ADAPTER_DIR/$dir" ]; then
      check_sync_target "$ADAPTER_DIR/$dir" "$CLAUDE_DIR/$dir" "$dir/"
    fi
  done
  if [ -d "$NEURAL_LACE_ROOT/patterns/templates" ]; then
    check_sync_target "$NEURAL_LACE_ROOT/patterns/templates" "$CLAUDE_DIR/templates" "templates/"
  fi
  if [ -d "$NEURAL_LACE_ROOT/docs" ]; then
    check_sync_target "$NEURAL_LACE_ROOT/docs" "$CLAUDE_DIR/docs" "docs/"
  fi
  echo ""

  # Global git hooks
  echo "[Phase 4: Global git core.hooksPath]"
  current_hooks_path=$(git config --global --get core.hooksPath 2>/dev/null || echo "")
  if [ "$current_hooks_path" = "$ADAPTER_DIR/git-hooks" ]; then
    echo "  [WOULD SKIP -- already set]        core.hooksPath=$ADAPTER_DIR/git-hooks"
  elif [ -n "$current_hooks_path" ]; then
    echo "  [WOULD CHANGE]                     core.hooksPath: $current_hooks_path -> $ADAPTER_DIR/git-hooks"
    changes=$((changes + 1))
  else
    echo "  [WOULD SET]                        core.hooksPath=$ADAPTER_DIR/git-hooks"
    changes=$((changes + 1))
  fi
  echo ""

  # Legacy hook cleanup
  echo "[Phase 5: Legacy per-repo hook cleanup]"
  CLAUDE_PROJECTS_ROOT="$HOME/claude-projects"
  if [ -d "$CLAUDE_PROJECTS_ROOT" ]; then
    echo "  Would scan for legacy hooks under: $CLAUDE_PROJECTS_ROOT/*/.git and $CLAUDE_PROJECTS_ROOT/*/*/.git"
    legacy_seen=0
    shopt -s nullglob 2>/dev/null || true
    for repo in \
      "$CLAUDE_PROJECTS_ROOT"/*/.git \
      "$CLAUDE_PROJECTS_ROOT"/*/*/.git \
    ; do
      [ -d "$repo" ] || continue
      hook="$(dirname "$repo")/.git/hooks/pre-push"
      [ -e "$hook" ] || continue
      if [ -L "$hook" ]; then
        target=$(readlink "$hook" 2>/dev/null || echo "")
        if echo "$target" | grep -q "claude-config/hooks/pre-push-scan.sh"; then
          echo "  [WOULD REMOVE -- legacy symlink]   $hook"
          legacy_seen=$((legacy_seen + 1))
          changes=$((changes + 1))
          continue
        fi
      fi
      if [ -f "$hook" ] && grep -q "pre-push-scan.sh" "$hook" 2>/dev/null; then
        echo "  [WOULD REMOVE -- legacy copy]      $hook"
        legacy_seen=$((legacy_seen + 1))
        changes=$((changes + 1))
      fi
    done
    shopt -u nullglob 2>/dev/null || true
    if [ "$legacy_seen" -eq 0 ]; then
      echo "  (no legacy hooks found)"
    fi
  else
    echo "  (no $CLAUDE_PROJECTS_ROOT directory -- nothing to scan)"
  fi
  echo ""

  # settings.json
  echo "[Phase 6: settings.json]"
  if [ -f "$CLAUDE_DIR/settings.json" ]; then
    echo "  [WOULD SKIP -- not overwritten]    $CLAUDE_DIR/settings.json"
    echo "    (use --replace-settings to force install from template)"
  else
    if [ -f "$ADAPTER_DIR/settings.json.template" ]; then
      echo "  [WOULD CREATE]                     $CLAUDE_DIR/settings.json (from template)"
      changes=$((changes + 1))
    else
      echo "  (no template available)"
    fi
  fi
  echo ""

  # Seed ~/.claude/local/
  echo "[Phase 7: Seed ~/.claude/local/ from examples]"
  if [ -d "$ADAPTER_DIR/examples" ]; then
    shopt -s nullglob 2>/dev/null || true
    for example in "$ADAPTER_DIR/examples"/*.example.json; do
      [ -f "$example" ] || continue
      base=$(basename "$example")
      target_name="${base%.example.json}.json"
      target="$CLAUDE_DIR/local/$target_name"
      if [ -e "$target" ]; then
        echo "  [WOULD SKIP -- already exists]     $target"
      else
        echo "  [WOULD CREATE]                     $target (from $base)"
        changes=$((changes + 1))
      fi
    done
    for example in "$ADAPTER_DIR/examples"/*.example.md; do
      [ -f "$example" ] || continue
      base=$(basename "$example")
      target_name="${base%.example.md}.md"
      target="$CLAUDE_DIR/local/$target_name"
      if [ -e "$target" ]; then
        echo "  [WOULD SKIP -- already exists]     $target"
      else
        echo "  [WOULD CREATE]                     $target (from $base)"
        changes=$((changes + 1))
      fi
    done
    shopt -u nullglob 2>/dev/null || true
  else
    echo "  (no examples/ directory in adapter)"
  fi
  echo ""

  # Summary
  echo "[Summary]"
  echo "  $changes change(s) would be made."
  echo "  $backups existing file(s) would be backed up."
  echo ""
  echo "Dry run complete. No changes made."
  echo ""
  exit 0
fi

# ============================================================
# Normal install flow
# ============================================================

echo ""
echo "========================================================"
echo "  Neural Lace -- Claude Code Adapter Installer"
echo "--------------------------------------------------------"
echo "  Adapter: $ADAPTER_DIR"
echo "  Target:  $CLAUDE_DIR"
echo "========================================================"
echo ""

mkdir -p "$CLAUDE_DIR"
mkdir -p "$CLAUDE_DIR/business-patterns.d"
mkdir -p "$NEURAL_LACE_DATA/telemetry"

# ============================================================
# Auto-prune stale backup directories (older than 30 days)
# ============================================================
# Each install creates a new $CLAUDE_DIR/.backup-<timestamp>/ to hold displaced
# real files. These accumulate forever otherwise. Parse the timestamp from the
# directory name (not mtime, which is unreliable) and remove any older than 30d.

prune_stale_backups() {
  local now_epoch
  now_epoch=$(date +%s)
  local cutoff_epoch=$((now_epoch - 30 * 24 * 60 * 60))
  local pruned=0

  # Iterate without failing if no matches exist
  shopt -s nullglob 2>/dev/null || true
  for dir in "$CLAUDE_DIR"/.backup-*; do
    # Skip if not a real directory (file, symlink, missing)
    [ -d "$dir" ] || continue
    [ -L "$dir" ] && continue

    local base
    base=$(basename "$dir")
    # Expected format: .backup-YYYYMMDD-HHMMSS
    # Extract the date portion; require the exact pattern to avoid malformed names
    local ts="${base#.backup-}"
    # ts should look like YYYYMMDD-HHMMSS
    if ! echo "$ts" | grep -Eq '^[0-9]{8}-[0-9]{6}$'; then
      continue
    fi
    local ymd="${ts%-*}"
    local hms="${ts#*-}"
    # Reformat to "YYYY-MM-DD HH:MM:SS" for date parsing portability
    local y="${ymd:0:4}"
    local mo="${ymd:4:2}"
    local d="${ymd:6:2}"
    local h="${hms:0:2}"
    local mi="${hms:2:2}"
    local se="${hms:4:2}"
    local dir_epoch
    # Try GNU date first, then BSD date fallback
    dir_epoch=$(date -d "$y-$mo-$d $h:$mi:$se" +%s 2>/dev/null \
      || date -j -f "%Y-%m-%d %H:%M:%S" "$y-$mo-$d $h:$mi:$se" +%s 2>/dev/null \
      || echo "")
    [ -z "$dir_epoch" ] && continue

    if [ "$dir_epoch" -lt "$cutoff_epoch" ]; then
      if rm -rf "$dir" 2>/dev/null; then
        pruned=$((pruned + 1))
      else
        echo "  warning: could not remove stale backup $dir (permissions?)" >&2
      fi
    fi
  done
  shopt -u nullglob 2>/dev/null || true

  if [ "$pruned" -gt 0 ]; then
    echo "Pruned $pruned stale backup directories (older than 30 days)"
  fi
}

prune_stale_backups

BACKUP_DIR="$CLAUDE_DIR/.backup-$(date +%Y%m%d-%H%M%S)"
BACKED_UP=0

backup_if_real_file() {
  local target="$1"
  if [ -e "$target" ] && [ ! -L "$target" ]; then
    mkdir -p "$BACKUP_DIR"
    mv "$target" "$BACKUP_DIR/"
    BACKED_UP=1
  fi
}

# Sync a file: prefer symlink, fall back to copy (Windows Git Bash)
sync_file() {
  local src="$1"
  local dst="$2"
  local label="$3"

  backup_if_real_file "$dst"
  rm -f "$dst"
  ln -s "$src" "$dst" 2>/dev/null || true

  if [ -L "$dst" ]; then
    echo "  linked $label"
  else
    rm -f "$dst"
    cp "$src" "$dst"
    echo "  copied $label (symlinks unavailable)"
  fi
}

# Sync a directory: prefer symlink, fall back to file-by-file copy
sync_directory() {
  local src="$1"
  local dst="$2"
  local label="$3"

  backup_if_real_file "$dst"
  [ -L "$dst" ] && rm -f "$dst"

  ln -s "$src" "$dst" 2>/dev/null || true
  if [ -L "$dst" ]; then
    echo "  linked $label/"
    return 0
  fi

  rm -rf "$dst"
  mkdir -p "$dst"
  local count=0
  while IFS= read -r -d '' rel; do
    local rel_path="${rel#./}"
    [ "$rel_path" = "." ] && continue
    local src_file="$src/$rel_path"
    local dst_file="$dst/$rel_path"
    if [ -d "$src_file" ]; then
      mkdir -p "$dst_file"
    else
      mkdir -p "$(dirname "$dst_file")"
      cp "$src_file" "$dst_file"
      count=$((count + 1))
    fi
  done < <(cd "$src" && find . -print0)
  echo "  synced $label/ ($count files)"
}

echo "Deploying Claude Code adapter..."
echo ""

# Sync CLAUDE.md
sync_file "$ADAPTER_DIR/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md" "CLAUDE.md"

# Sync adapter directories to ~/.claude/
for dir in rules agents hooks scripts pipeline-prompts pipeline-templates commands; do
  if [ -d "$ADAPTER_DIR/$dir" ]; then
    sync_directory "$ADAPTER_DIR/$dir" "$CLAUDE_DIR/$dir" "$dir"
  fi
done

# Sync shared templates from patterns/ (tool-agnostic)
if [ -d "$NEURAL_LACE_ROOT/patterns/templates" ]; then
  sync_directory "$NEURAL_LACE_ROOT/patterns/templates" "$CLAUDE_DIR/templates" "templates (from patterns/)"
fi

# Sync docs from neural-lace root
if [ -d "$NEURAL_LACE_ROOT/docs" ]; then
  sync_directory "$NEURAL_LACE_ROOT/docs" "$CLAUDE_DIR/docs" "docs"
fi

# Make scripts executable
chmod +x "$ADAPTER_DIR/hooks/"*.sh 2>/dev/null || true
chmod +x "$ADAPTER_DIR/git-hooks/"* 2>/dev/null || true

# ============================================================
# Global git hooks
# ============================================================

if [ -d "$ADAPTER_DIR/git-hooks" ]; then
  current_hooks_path=$(git config --global --get core.hooksPath 2>/dev/null || echo "")
  if [ "$current_hooks_path" != "$ADAPTER_DIR/git-hooks" ]; then
    git config --global core.hooksPath "$ADAPTER_DIR/git-hooks"
    echo ""
    echo "  set global git core.hooksPath to: $ADAPTER_DIR/git-hooks"
    if [ -n "$current_hooks_path" ]; then
      echo "    (was: $current_hooks_path)"
    fi
  else
    echo "  global git core.hooksPath already correct"
  fi
fi

# ============================================================
# Clean up legacy per-repo hooks
# ============================================================

cleanup_legacy_hook() {
  local repo="$1"
  local hook="$repo/.git/hooks/pre-push"
  [ -e "$hook" ] || return 0

  if [ -L "$hook" ]; then
    local target
    target=$(readlink "$hook" 2>/dev/null || echo "")
    if echo "$target" | grep -q "claude-config/hooks/pre-push-scan.sh"; then
      rm -f "$hook"
      echo "  removed legacy hook (symlink): $hook"
      return 0
    fi
  fi

  if [ -f "$hook" ] && grep -q "pre-push-scan.sh" "$hook" 2>/dev/null; then
    rm -f "$hook"
    echo "  removed legacy hook (copy): $hook"
  fi
}

CLAUDE_PROJECTS_ROOT="$HOME/claude-projects"
if [ -d "$CLAUDE_PROJECTS_ROOT" ]; then
  # Scan depth 1 (repos directly under ~/claude-projects/) AND depth 2
  # (repos under ~/claude-projects/<sub-org>/) without enumerating specific
  # sub-organization names. Any .git directory found is a candidate for
  # legacy-hook cleanup.
  shopt -s nullglob 2>/dev/null || true
  for repo in \
    "$CLAUDE_PROJECTS_ROOT"/*/.git \
    "$CLAUDE_PROJECTS_ROOT"/*/*/.git \
  ; do
    [ -d "$repo" ] || continue
    cleanup_legacy_hook "$(dirname "$repo")"
  done
  shopt -u nullglob 2>/dev/null || true
fi

# ============================================================
# settings.json
# ============================================================

echo ""
if [ ! -f "$CLAUDE_DIR/settings.json" ]; then
  if [ -f "$ADAPTER_DIR/settings.json.template" ]; then
    cp "$ADAPTER_DIR/settings.json.template" "$CLAUDE_DIR/settings.json"
    echo "  created settings.json from template"
    echo ""
    echo "  ACTION REQUIRED: Edit $CLAUDE_DIR/settings.json and replace placeholders"
  fi
else
  # Loud, actionable warning: existing settings.json means Neural Lace's hooks
  # are NOT installed in the user's actual config. A silent skip would leave
  # the harness effectively dormant. Call this out clearly with three paths
  # forward.
  echo "  ##########################################################"
  echo "  # WARNING: settings.json exists -- NOT overwritten."
  echo "  #"
  echo "  # IMPORTANT: Neural Lace's hooks live inside settings.json."
  echo "  # Your existing settings.json does NOT contain them, which"
  echo "  # means most Neural Lace features are currently INACTIVE"
  echo "  # (public-repo block, automation-mode gate, first-run"
  echo "  # prompt, pre-commit-gate, SessionStart account switcher,"
  echo "  # etc.)."
  echo "  #"
  echo "  # To activate Neural Lace, you have three options:"
  echo "  #"
  echo "  #   (a) Manually merge hooks from:"
  echo "  #         $ADAPTER_DIR/settings.json.template"
  echo "  #       into your existing $CLAUDE_DIR/settings.json"
  echo "  #       (merge the \"hooks\" section)."
  echo "  #"
  echo "  #   (b) Replace your settings.json with the template"
  echo "  #       (existing file will be backed up first):"
  echo "  #         ./install.sh --replace-settings"
  echo "  #"
  echo "  #   (c) Remove your existing settings.json and re-run"
  echo "  #       install.sh -- the template will install fresh"
  echo "  #       (your old settings.json backed up to"
  echo "  #       .backup-<timestamp>/ as usual)."
  echo "  ##########################################################"
fi

# ============================================================
# Seed ~/.claude/local/ from example files (first-install only)
# ============================================================
# The harness uses a two-layer config: shared examples ship in the repo at
# adapters/claude-code/examples/*.example.json; user-specific copies live at
# ~/.claude/local/*.json and are NEVER overwritten once created.

mkdir -p "$CLAUDE_DIR/local"

if [ -d "$ADAPTER_DIR/examples" ]; then
  echo ""
  seeded_any=0
  shopt -s nullglob 2>/dev/null || true
  for example in "$ADAPTER_DIR/examples"/*.example.json; do
    [ -f "$example" ] || continue
    base=$(basename "$example")          # e.g. foo.example.json
    target_name="${base%.example.json}.json"  # e.g. foo.json
    target="$CLAUDE_DIR/local/$target_name"

    if [ -e "$target" ]; then
      echo "  $CLAUDE_DIR/local/$target_name exists (not overwritten)"
    else
      cp "$example" "$target"
      echo "  created $CLAUDE_DIR/local/$target_name from example"
      seeded_any=1
    fi
  done
  # Also seed markdown templates (e.g., credentials-inventory.example.md)
  for example in "$ADAPTER_DIR/examples"/*.example.md; do
    [ -f "$example" ] || continue
    base=$(basename "$example")          # e.g. credentials-inventory.example.md
    target_name="${base%.example.md}.md"  # e.g. credentials-inventory.md
    target="$CLAUDE_DIR/local/$target_name"

    if [ -e "$target" ]; then
      echo "  $CLAUDE_DIR/local/$target_name exists (not overwritten)"
    else
      cp "$example" "$target"
      echo "  created $CLAUDE_DIR/local/$target_name from example"
      seeded_any=1
    fi
  done
  shopt -u nullglob 2>/dev/null || true

  if [ "$seeded_any" -eq 1 ]; then
    echo ""
    echo "  ACTION: edit files in $CLAUDE_DIR/local/ to match your setup. See adapters/claude-code/schemas/ for each schema."
  fi
fi

# ============================================================
# Summary
# ============================================================

echo ""
if [ $BACKED_UP -eq 1 ]; then
  echo "Existing files backed up to: $BACKUP_DIR"
  echo ""
fi

echo "========================================================"
echo "  Neural Lace installed successfully."
echo "========================================================"
echo ""
echo "Pre-push security scanner active on all repos."
echo "Telemetry data directory: $NEURAL_LACE_DATA/telemetry/"
echo ""

# ============================================================
# Windows-only: host performance tuning notice
# ============================================================
# Defender real-time scanning of Claude Code's file churn (worktrees,
# node_modules, bash subprocess output, JSONL transcripts) regularly burns
# 15-25% CPU on idle Windows machines. The host-setup script adds the dev
# paths and processes to Defender's exclusion list. Surface it here so a
# fresh install picks it up.

case "$(uname -s 2>/dev/null)" in
  MINGW*|MSYS*|CYGWIN*|Windows_NT)
    echo "Optional (Windows): reduce Defender CPU overhead from dev file scanning:"
    echo "  powershell -ExecutionPolicy Bypass -File \\"
    echo "    $ADAPTER_DIR/scripts/host-setup/setup-defender-exclusions.ps1"
    echo "  See: $NEURAL_LACE_ROOT/docs/host-setup/windows-defender-exclusions.md"
    echo ""
    ;;
esac

echo "Update: cd $NEURAL_LACE_ROOT && git pull && $0"
echo ""
