#!/usr/bin/env bash
# Golden Test: every rule file under adapters/claude-code/rules/ has a row
# in adapters/claude-code/rules/INDEX.md, and every INDEX entry points at
# a file that exists.
#
# Expected: PASS if INDEX is in sync with the directory contents.
# Failure mode: a new rule file is added without an INDEX row, OR an INDEX
# row points at a deleted file. Both surface here.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NEURAL_LACE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RULES_DIR="$NEURAL_LACE_ROOT/adapters/claude-code/rules"
INDEX="$RULES_DIR/INDEX.md"

if [[ ! -f "$INDEX" ]]; then
  echo "FAIL: INDEX file not found at $INDEX"
  exit 1
fi

PASS=0
FAIL=0
missing_in_index=()
missing_files=()

# Walk every *.md under rules/ EXCEPT INDEX.md itself.
while IFS= read -r -d '' rule_path; do
  rule_name="$(basename "$rule_path")"
  # Skip the INDEX file itself; it's not a rule.
  if [[ "$rule_name" == "INDEX.md" ]]; then
    continue
  fi
  # The INDEX row references the file as backtick-quoted basename.
  if grep -F -q "\`$rule_name\`" "$INDEX"; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    missing_in_index+=("$rule_name")
  fi
done < <(find "$RULES_DIR" -maxdepth 1 -type f -name '*.md' -print0)

# Walk every backtick-quoted *.md filename that appears as the FIRST cell
# of an INDEX table row (i.e., on a line that starts with `| \``) and verify
# the file exists. Scoping to table rows avoids false positives from cross-
# references at the bottom of the doc (e.g., a link to ../docs/best-practices.md).
mapfile -t indexed_names < <(
  grep -E '^\| `[a-z0-9-]+\.md`' "$INDEX" \
    | grep -oE '`[a-z0-9-]+\.md`' \
    | sed 's/`//g' \
    | sort -u
)

for name in "${indexed_names[@]}"; do
  if [[ ! -f "$RULES_DIR/$name" ]]; then
    FAIL=$((FAIL + 1))
    missing_files+=("$name")
  fi
done

echo "Indexed rules in sync: $PASS"
if [[ ${#missing_in_index[@]} -gt 0 ]]; then
  echo "FAIL: rule files lacking INDEX entry:"
  printf '  - %s\n' "${missing_in_index[@]}"
fi
if [[ ${#missing_files[@]} -gt 0 ]]; then
  echo "FAIL: INDEX entries referencing non-existent files:"
  printf '  - %s\n' "${missing_files[@]}"
fi

if [[ $FAIL -gt 0 ]]; then
  echo
  echo "Add the missing rows to $INDEX (or remove stale rows). The"
  echo "INDEX is intentionally one-line-per-rule; full content lives"
  echo "in the per-rule file."
  exit 1
fi

echo "PASS: INDEX has a row for every rule file, and every row points at an existing file"
exit 0
