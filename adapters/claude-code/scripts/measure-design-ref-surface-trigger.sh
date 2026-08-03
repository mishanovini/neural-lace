#!/bin/bash
# measure-design-ref-surface-trigger.sh — corpus measurement (arch-M4,
# gated-pipeline-master-2026-08 Task 14, REQ-B5+B7): the adapters/claude-code/**
# surface-trigger fire-rate over the FULL plan corpus (docs/plans/*.md +
# docs/plans/archive/*.md), measured BEFORE any G1 flip date is honored (the
# design's own evidence-bar rule, "4/§10: "measured, not modeled"). This is
# the SAME extraction plan-reviewer.sh Checks 20-22 use (grep the
# '## Files to Modify/Create' section for an 'adapters/claude-code/' path) —
# kept as one committed, re-runnable script rather than an ad-hoc one-off so
# the number can be re-measured on demand as the corpus grows (Check 17's own
# convention: doctrine/artifact-evidence-bar-full.md documents its corpus
# study the same way).
#
# Usage: bash adapters/claude-code/scripts/measure-design-ref-surface-trigger.sh
# Prints: total plans, fired count, fire-rate percentage. Exit 0 always
# (a measurement script, not a gate).
set -u

_dir="$(cd -- "${BASH_SOURCE[0]%/*}" 2>/dev/null && pwd)"
REPO_ROOT="$(cd -- "$_dir/../../.." 2>/dev/null && pwd)"
cd "$REPO_ROOT" || exit 1

total=0
fired=0
FIRED_LIST=""

for f in docs/plans/*.md docs/plans/archive/*.md; do
  [[ -f "$f" ]] || continue
  total=$((total + 1))
  sec=$(awk '
    /^## Files to Modify\/Create[[:space:]]*$/ { grab = 1; next }
    /^## / && grab == 1 { grab = 0 }
    grab == 1 { print }
  ' "$f" 2>/dev/null)
  if printf '%s\n' "$sec" | grep -qE 'adapters/claude-code/'; then
    fired=$((fired + 1))
    FIRED_LIST+="$f"$'\n'
  fi
done

echo "corpus (docs/plans/*.md + docs/plans/archive/*.md): $total files"
echo "adapters/claude-code/** surface-trigger fired: $fired"
if [[ "$total" -gt 0 ]]; then
  awk -v t="$total" -v f="$fired" 'BEGIN { printf "fire-rate: %.1f%%\n", 100.0 * f / t }'
fi

if [[ "${1:-}" == "--list" ]]; then
  echo "--- fired files ---"
  printf '%s' "$FIRED_LIST"
fi

exit 0
