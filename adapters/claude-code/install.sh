#!/bin/bash
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
#   ./install.sh
#
# Or from neural-lace root:
#   ./adapters/claude-code/install.sh
#
# Re-run anytime to refresh (safe — existing symlinks are replaced).

set -e

# Resolve paths relative to this script's location
ADAPTER_DIR="$(cd "$(dirname "$0")" && pwd)"
NEURAL_LACE_ROOT="$(cd "$ADAPTER_DIR/../.." && pwd)"
CLAUDE_DIR="$HOME/.claude"
NEURAL_LACE_DATA="$HOME/.neural-lace"

echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║  Neural Lace — Claude Code Adapter Installer ║"
echo "╠══════════════════════════════════════════════╣"
echo "║  Adapter: $ADAPTER_DIR"
echo "║  Target:  $CLAUDE_DIR"
echo "╚══════════════════════════════════════════════╝"
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
    echo "  ✓ linked $label"
  else
    rm -f "$dst"
    cp "$src" "$dst"
    echo "  ✓ copied $label (symlinks unavailable)"
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
    echo "  ✓ linked $label/"
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
  echo "  ✓ synced $label/ ($count files)"
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
    echo "  ✓ set global git core.hooksPath to: $ADAPTER_DIR/git-hooks"
    if [ -n "$current_hooks_path" ]; then
      echo "    (was: $current_hooks_path)"
    fi
  else
    echo "  ✓ global git core.hooksPath already correct"
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
    echo "  ✓ created settings.json from template"
    echo ""
    echo "  ACTION REQUIRED: Edit $CLAUDE_DIR/settings.json and replace placeholders"
  fi
else
  echo "  ✓ settings.json exists (not overwritten)"
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
      echo "  ✓ ~/.claude/local/$target_name exists (not overwritten)"
    else
      cp "$example" "$target"
      echo "  ✓ created ~/.claude/local/$target_name from example"
      seeded_any=1
    fi
  done
  shopt -u nullglob 2>/dev/null || true

  if [ "$seeded_any" -eq 1 ]; then
    echo ""
    echo "  ACTION: edit files in ~/.claude/local/ to match your setup. See adapters/claude-code/schemas/ for each schema."
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

echo "╔══════════════════════════════════════════════╗"
echo "║  Neural Lace installed successfully.         ║"
echo "╚══════════════════════════════════════════════╝"
echo ""
echo "Pre-push security scanner active on all repos."
echo "Telemetry data directory: $NEURAL_LACE_DATA/telemetry/"
echo ""
echo "Update: cd $NEURAL_LACE_ROOT && git pull && $0"
echo ""
