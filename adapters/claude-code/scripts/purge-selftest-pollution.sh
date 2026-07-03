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
        exit 0
      else
        echo "self-test: FAIL (cleanup left $(wc -l < "$fixture") lines, expected 3)" >&2
        exit 1
      fi
    else
      echo "self-test: FAIL (expected 4 pollution, got $count)" >&2
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
  for f in "$HOME_DIR"/.claude/logs/*.log 2>/dev/null || true; do
    [[ -f "$f" ]] && output=$(_purge_file "$f") && {
      echo "  $output"
      count=$(echo "$output" | grep -oE '[0-9]+' | head -1)
      total_removed=$((total_removed + count))
    }
  done
}

[[ -d "$HOME_DIR/.claude/state" ]] && {
  echo "State:"
  for f in "$HOME_DIR"/.claude/state/*.jsonl 2>/dev/null || true; do
    [[ -f "$f" ]] && output=$(_purge_file "$f") && {
      echo "  $output"
      count=$(echo "$output" | grep -oE '[0-9]+' | head -1)
      total_removed=$((total_removed + count))
    }
  done
}

echo "Total pollution lines: $total_removed"
[[ "$APPLY" == false ]] && echo "(dry-run; use --apply to remove)"

