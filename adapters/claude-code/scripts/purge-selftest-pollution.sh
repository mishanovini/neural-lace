#!/bin/bash
# purge-selftest-pollution.sh — identify and remove self-test pollution

set -e

APPLY=false
grep_pattern='selftest|self-test|signal-ledger-selftest|orthogonal-plan|pass-acceptance|waived-plan|exempt|multi-clean|wigst|scenario s'

_count_pollution() {
  [[ -f "$1" ]] || { echo 0; return; }
  grep -cE "$grep_pattern" "$1" 2>/dev/null || echo 0
}

_purge_file() {
  local filepath="$1" count
  count=$(_count_pollution "$filepath")
  [[ $count -eq 0 ]] && return 0
  [[ "$APPLY" == true ]] && {
    grep -vE "$grep_pattern" "$filepath" > "$filepath.tmp" 2>/dev/null || true
    [[ -f "$filepath.tmp" ]] && mv "$filepath.tmp" "$filepath"
  }
  echo "$filepath: $count lines"
}

# Whole-FILE pollution (as opposed to polluted LINES within an otherwise-real
# file, handled by _purge_file above). env-local-protection.sh's
# backup_env_local() slugifies the source path into the backup filename via
# slugify_path() — a self-test tempdir path like /tmp/tmp.XXXXXXXXXX/.env.local
# slugifies to tmp-tmp.XXXXXXXXXX-.env.local-<timestamp>.bak. Any backup file
# whose slug starts with the mktemp prefix (tmp-tmp. on Linux/macOS runners,
# or the Windows Git-Bash equivalent) is self-test pollution end to end — a
# REAL .env.local backup is always slugified from a project path (starts with
# a drive letter or /home, /Users, /c, etc., never from a bare tmp mount).
# NL-FINDING-025-family fix (E.2): prior to sandboxing the hook's self-test
# (env-local-protection.sh BACKUP_ROOT), every local self-test run left behind
# real files here — 58 accumulated before this fix, reproduced at 63.
selftest_backup_pattern='^tmp-tmp\.[A-Za-z0-9]+-\.env\.local-[0-9TZ]+\.bak$'

_count_backup_pollution() {
  local dir="$1" count=0 f base
  [[ -d "$dir" ]] || { echo 0; return; }
  for f in "$dir"/*.bak; do
    [[ -f "$f" ]] || continue
    base=$(basename "$f")
    echo "$base" | grep -qE "$selftest_backup_pattern" && count=$((count + 1))
  done
  echo "$count"
}

# Lists (and, if APPLY, deletes) polluted backup files under $1. Writes one
# "  <path>" line per removed file to stdout so the caller can echo them,
# then a final bare-integer line with the total count (mirrors the
# "$filepath: $count lines" + grep -oE '[0-9]+' convention _purge_file's
# caller already uses below, adapted for whole-file rather than in-file counts).
_purge_backup_files() {
  local dir="$1" removed=0 f base
  [[ -d "$dir" ]] || { echo 0; return; }
  for f in "$dir"/*.bak; do
    [[ -f "$f" ]] || continue
    base=$(basename "$f")
    if echo "$base" | grep -qE "$selftest_backup_pattern"; then
      echo "  $f"
      [[ "$APPLY" == true ]] && rm -f "$f"
      removed=$((removed + 1))
    fi
  done
  echo "$removed"
}

case "${1:-}" in
  --self-test)
    tmpdir=$(mktemp -d 2>/dev/null || mktemp -d -t purgst)
    trap "rm -rf '$tmpdir'" EXIT
    fixture="$tmpdir/fixture.log"
    cat > "$fixture" << 'FIXTURE'
2026-07-03T10:00:00Z: real production line
2026-07-03T10:00:01Z: orthogonal-plan fixture (pollution)
2026-07-03T10:00:02Z: another real line
2026-07-03T10:00:03Z: scenario s1 pollution
signal-ledger-selftest pollution
wigst temp reference
another real line here
FIXTURE
    
    count=$(_count_pollution "$fixture")
    if [[ $count -eq 4 ]]; then
      echo "self-test: PASS (detected 4 pollution lines)" >&2
      APPLY=true
      _purge_file "$fixture" >/dev/null
      if [[ $(wc -l < "$fixture") -eq 3 ]]; then
        echo "self-test: PASS (preserved 3 real lines)" >&2
      else
        echo "self-test: FAIL (cleanup left $(wc -l < "$fixture") lines, expected 3)" >&2
        exit 1
      fi
    else
      echo "self-test: FAIL (expected 4 pollution, got $count)" >&2
      exit 1
    fi

    # Whole-file backup pollution (env-local-protection.sh BACKUP_ROOT class,
    # NL-FINDING-025 family). Sandboxed fixture dir — never touches the real
    # ~/.claude/backups/env-local/.
    bdir="$tmpdir/backups-env-local"
    mkdir -p "$bdir"
    : > "$bdir/tmp-tmp.068d1jwrUT-.env.local-20260705T184603Z.bak"
    : > "$bdir/tmp-tmp.7TSpjhlD7E-.env.local-20260705T182300Z.bak"
    : > "$bdir/c-Users-misha-dev-Personal-foresight-.env.local-20260702T060353Z.bak"

    bcount=$(_count_backup_pollution "$bdir")
    if [[ "$bcount" -eq 2 ]]; then
      echo "self-test: PASS (detected 2 polluted backup files)" >&2
      APPLY=true
      _purge_backup_files "$bdir" >/dev/null
      remaining=$(ls -1 "$bdir" 2>/dev/null | wc -l | tr -d '[:space:]')
      if [[ "$remaining" -eq 1 ]] && [[ -f "$bdir/c-Users-misha-dev-Personal-foresight-.env.local-20260702T060353Z.bak" ]]; then
        echo "self-test: PASS (preserved the 1 real backup file)" >&2
        exit 0
      else
        echo "self-test: FAIL (cleanup left $remaining file(s), expected 1 real file preserved)" >&2
        exit 1
      fi
    else
      echo "self-test: FAIL (expected 2 polluted backup files, got $bcount)" >&2
      exit 1
    fi
    ;;
  --apply)
    APPLY=true
    ;;
esac

# Main
HOME_DIR="${HOME:=${USERPROFILE}}"
echo "=== Self-test pollution purge ($(if [[ "$APPLY" == true ]]; then echo 'APPLY'; else echo 'dry-run'; fi)) ==="
echo

total_removed=0
[[ -d "$HOME_DIR/.claude/logs" ]] && {
  echo "Logs:"
  for f in "$HOME_DIR"/.claude/logs/*.log; do
    [[ -f "$f" ]] && output=$(_purge_file "$f") && {
      echo "  $output"
      count=$(echo "$output" | grep -oE '[0-9]+' | head -1)
      total_removed=$((total_removed + count))
    }
  done
}

[[ -d "$HOME_DIR/.claude/state" ]] && {
  echo "State:"
  for f in "$HOME_DIR"/.claude/state/*.jsonl; do
    [[ -f "$f" ]] && output=$(_purge_file "$f") && {
      echo "  $output"
      count=$(echo "$output" | grep -oE '[0-9]+' | head -1)
      total_removed=$((total_removed + count))
    }
  done
}

[[ -d "$HOME_DIR/.claude/backups/env-local" ]] && {
  echo "Backups (env-local):"
  output=$(_purge_backup_files "$HOME_DIR/.claude/backups/env-local")
  # Last line is the bare count; preceding lines (if any) are the per-file listing.
  echo "$output" | sed '$d'
  count=$(echo "$output" | tail -1 | grep -oE '[0-9]+' | head -1)
  echo "  $count file(s)"
  total_removed=$((total_removed + count))
}

echo "Total pollution lines/files: $total_removed"
[[ "$APPLY" == false ]] && echo "(dry-run; use --apply to remove)"

