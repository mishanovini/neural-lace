#!/bin/bash
# check-harness-sync.sh
#
# RETIRED FROM PreToolUse at NL Overhaul Wave D.6 (§D.0.4 / §D.6 item 6,
# 2026-07-02): this hook's drift-detection remit moves to
# harness-doctor.sh (the doctor is now the single claimed-vs-actual truth
# report for the harness; a second independent drift-checker in the
# PreToolUse hot path was redundant with the doctor's own sync checks).
# Template unwiring (removing the PreToolUse registration in
# settings.json.template) happens at D.5, not here — this file's own
# logic is UNCHANGED and it must keep behaving correctly if some stale
# live wiring still invokes it in the interim. Once D.5 lands and the
# wiring is confirmed removed, this file moves to attic/.
#
# Called by the PreToolUse hook when a git commit is detected.
# Detects drift between ~/.claude/ and the neural-lace repo.
#
# BEHAVIOR:
# - If ~/.claude/ files have been modified (drift from neural-lace), AUTO-SYNCS
#   the changes back to the neural-lace repo, commits, and pushes to both remotes.
# - If new files exist in ~/.claude/ but not in neural-lace, copies them in.
# - Skips when committing inside neural-lace itself (avoids loops).
# - Skips templates/ (deployed from patterns/templates/, not adapters/).

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/nl-paths.sh
source "$SELF_DIR/lib/nl-paths.sh" 2>/dev/null || true

LIVE="$HOME/.claude"
NL_ROOT="${NL_ROOT_OVERRIDE:-$(nl_repo_root 2>/dev/null)}"
REPO="${NL_ROOT:+$NL_ROOT/adapters/claude-code}"

# ============================================================
# --self-test : prove the RWR-27 staging contract in isolation
#   The hook must stage ONLY the files it synced — never `git add -A`,
#   which would sweep unrelated dirty files (batch residue, tree-state.json)
#   into the index and trip the scope-enforcement-gate.
# ============================================================
if [ "${1:-}" = "--self-test" ]; then
  set +e
  PASS=0; FAIL=0
  _t() { if [ "$2" = "$3" ]; then echo "  PASS: $1"; PASS=$((PASS+1)); else echo "  FAIL: $1 (expected '$3', got '$2')"; FAIL=$((FAIL+1)); fi; }

  TMP=$(mktemp -d)
  git -C "$TMP" init -q
  git -C "$TMP" config user.email t@example.com
  git -C "$TMP" config user.name test
  mkdir -p "$TMP/adapters/claude-code/hooks" "$TMP/docs"
  echo "base" > "$TMP/adapters/claude-code/hooks/some-hook.sh"
  echo "base" > "$TMP/docs/harness-architecture.md"
  git -C "$TMP" add -A; git -C "$TMP" commit -qm base

  # Dirty the tree with unrelated out-of-scope residue (the RWR-27 failure inputs)
  echo "residue" > "$TMP/tree-state.json"
  echo "batch residue" > "$TMP/batch-residue.tmp"
  echo "synced-change" > "$TMP/adapters/claude-code/hooks/some-hook.sh"  # the in-scope synced file

  # Simulate the FIXED staging step: stage only the synced path
  SYNCED_PATHS=("adapters/claude-code/hooks/some-hook.sh")
  ( cd "$TMP" && git add -- "${SYNCED_PATHS[@]}" 2>/dev/null )
  STAGED=$(git -C "$TMP" diff --cached --name-only | sort | tr '\n' ',' | sed 's/,$//')
  _t "fixed-staging stages ONLY the synced path" "$STAGED" "adapters/claude-code/hooks/some-hook.sh"

  # Negative control: prove `git add -A` WOULD have polluted the index
  ( cd "$TMP" && git reset -q && git add -A 2>/dev/null )
  STAGED_A=$(git -C "$TMP" diff --cached --name-only | sort | tr '\n' ',' | sed 's/,$//')
  _t "git add -A pollutes the index (the bug we removed)" "$STAGED_A" "adapters/claude-code/hooks/some-hook.sh,batch-residue.tmp,tree-state.json"

  # Confirm the fixed staging excluded the residue
  echo "$STAGED" | grep -q "tree-state.json"; HAS_RESIDUE=$?
  _t "fixed-staging excludes tree-state.json residue" "$HAS_RESIDUE" "1"
  echo "$STAGED" | grep -q "batch-residue.tmp"; HAS_BATCH=$?
  _t "fixed-staging excludes batch residue" "$HAS_BATCH" "1"

  # Confirm the LIVE-SYNC staging step never uses `git add -A`. We check the
  # source below the self-test block (the negative control above intentionally
  # uses `git add -A` to prove the bug, so we scan only past the self-test).
  SYNC_BODY=$(awk '/^# Only run if the neural-lace repo exists/{f=1} f' "${BASH_SOURCE[0]}")
  if echo "$SYNC_BODY" | grep -qE '^[[:space:]]*git add -A'; then
    echo "  FAIL: live-sync logic still contains an active 'git add -A'"; FAIL=$((FAIL+1))
  else
    echo "  PASS: live-sync logic contains no 'git add -A' (uses targeted 'git add --')"; PASS=$((PASS+1))
  fi
  if echo "$SYNC_BODY" | grep -qE '^[[:space:]]*git add -- '; then
    echo "  PASS: live-sync logic stages with targeted 'git add -- <paths>'"; PASS=$((PASS+1))
  else
    echo "  FAIL: live-sync logic missing targeted 'git add -- <paths>'"; FAIL=$((FAIL+1))
  fi

  rm -rf "$TMP"
  echo ""
  echo "self-test: $PASS passed, $FAIL failed"
  [ "$FAIL" -eq 0 ] && exit 0 || exit 1
fi

# Only run if the neural-lace repo exists
[ -d "$NL_ROOT/.git" ] || exit 0

# Skip if we're committing inside neural-lace itself — avoids infinite loop
CURRENT_REPO=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
if echo "$CURRENT_REPO" | grep -q "neural-lace"; then
  exit 0
fi

# ============================================================
# Detect drift
# ============================================================

DRIFT=0
DRIFT_FILES=""
CHANGED_FILES=()

for dir in agents rules hooks scripts; do
  [ -d "$LIVE/$dir" ] && [ -d "$REPO/$dir" ] || continue
  for f in "$LIVE/$dir"/*; do
    [ -f "$f" ] || continue
    base=$(basename "$f")

    if [ ! -f "$REPO/$dir/$base" ]; then
      DRIFT=$((DRIFT + 1))
      DRIFT_FILES="$DRIFT_FILES  NEW: $dir/$base\n"
      CHANGED_FILES+=("$dir/$base")
    elif ! diff -q "$f" "$REPO/$dir/$base" > /dev/null 2>&1; then
      DRIFT=$((DRIFT + 1))
      DRIFT_FILES="$DRIFT_FILES  CHANGED: $dir/$base\n"
      CHANGED_FILES+=("$dir/$base")
    fi
  done
done

# Also check CLAUDE.md
if [ -f "$LIVE/CLAUDE.md" ] && [ -f "$REPO/CLAUDE.md" ]; then
  if ! diff -q "$LIVE/CLAUDE.md" "$REPO/CLAUDE.md" > /dev/null 2>&1; then
    DRIFT=$((DRIFT + 1))
    DRIFT_FILES="$DRIFT_FILES  CHANGED: CLAUDE.md\n"
    CHANGED_FILES+=("CLAUDE.md")
  fi
fi

# Also check docs/ (lives at neural-lace/docs/, not adapter/docs/)
if [ -d "$LIVE/docs" ] && [ -d "$NL_ROOT/docs" ]; then
  for f in "$LIVE/docs"/*; do
    [ -f "$f" ] || continue
    base=$(basename "$f")
    if [ -f "$NL_ROOT/docs/$base" ] && ! diff -q "$f" "$NL_ROOT/docs/$base" > /dev/null 2>&1; then
      DRIFT=$((DRIFT + 1))
      DRIFT_FILES="$DRIFT_FILES  CHANGED: docs/$base (neural-lace/docs/)\n"
      # Handle docs separately since they live at root docs/, not adapter
    fi
  done
fi

# ============================================================
# Auto-sync if drift detected
# ============================================================

if [ $DRIFT -eq 0 ]; then
  exit 0
fi

echo "" >&2
echo "🔄 HARNESS DRIFT DETECTED — $DRIFT file(s) changed in ~/.claude/" >&2
echo -e "$DRIFT_FILES" >&2
echo "Auto-syncing changes back to neural-lace..." >&2

# Copy changed files back to neural-lace, tracking the EXACT repo-relative
# paths we touch so we can stage only those (never `git add -A`).
# SYNCED_PATHS holds paths relative to NL_ROOT (the neural-lace repo root).
SYNCED_PATHS=()
ADAPTER_REL="adapters/claude-code"  # $REPO relative to $NL_ROOT
for relpath in "${CHANGED_FILES[@]}"; do
  if [ "$relpath" = "CLAUDE.md" ]; then
    cp "$LIVE/CLAUDE.md" "$REPO/CLAUDE.md"
    SYNCED_PATHS+=("$ADAPTER_REL/CLAUDE.md")
  else
    dir=$(dirname "$relpath")
    base=$(basename "$relpath")
    mkdir -p "$REPO/$dir"
    cp "$LIVE/$dir/$base" "$REPO/$dir/$base"
    SYNCED_PATHS+=("$ADAPTER_REL/$dir/$base")
  fi
done

# Handle docs separately (these live at neural-lace/docs/, not under the adapter)
for f in "$LIVE/docs"/*; do
  [ -f "$f" ] || continue
  base=$(basename "$f")
  if [ -f "$NL_ROOT/docs/$base" ] && ! diff -q "$f" "$NL_ROOT/docs/$base" > /dev/null 2>&1; then
    cp "$f" "$NL_ROOT/docs/$base"
    SYNCED_PATHS+=("docs/$base")
  fi
done

# Commit and push in neural-lace
cd "$NL_ROOT"

# Stage ONLY the files this hook just synced — NEVER `git add -A`.
# RWR-27: `git add -A` swept the entire working tree (batch residue, live
# tree-state.json, any unrelated dirty files) into the commit index, which
# the scope-enforcement-gate then flagged as out-of-scope and BLOCKED. A
# pre-commit verification hook must never mutate the index with unrelated
# files. We stage exactly the paths we copied above and nothing else.
if [ ${#SYNCED_PATHS[@]} -gt 0 ]; then
  git add -- "${SYNCED_PATHS[@]}" 2>/dev/null
fi

# Only commit if there are staged changes
if ! git diff --cached --quiet 2>/dev/null; then
  # Build a concise commit message listing changed files
  FILE_LIST=$(echo -e "$DRIFT_FILES" | sed 's/^  /  - /' | head -10)

  git commit -m "$(cat <<INNEREOF
chore: auto-sync harness changes from ~/.claude/

Files synced back from live harness:
$FILE_LIST
Source: $(basename "$CURRENT_REPO") session
INNEREOF
)" 2>/dev/null

  echo "  ✓ Changes committed to neural-lace" >&2

  # Push to both remotes (silently, don't block the original commit)
  if [ -f "$NL_ROOT/sync.sh" ]; then
    bash "$NL_ROOT/sync.sh" 2>/dev/null | grep -E "(✓|✗)" >&2
  fi
else
  echo "  (no changes to commit after copy)" >&2
fi

cd "$CURRENT_REPO" 2>/dev/null
echo "" >&2
