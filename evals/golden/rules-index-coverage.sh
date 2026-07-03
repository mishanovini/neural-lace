#!/usr/bin/env bash
# Golden Test: post-Wave-C doctrine invariants (filename kept for CI wiring
# continuity; the check itself is rewritten for the rules/->doctrine/ move).
#
# Invariants enforced:
#   1. adapters/claude-code/rules/ contains EXACTLY the constitution set
#      ({constitution.md}) — no other *.md file may live there.
#   2. adapters/claude-code/doctrine/INDEX.md exists.
#   3. Every non-"-full" doctrine/*.md file (excluding INDEX.md itself) has
#      a row in doctrine/INDEX.md (matched by backtick-quoted basename).
#   4. Every non-"-full" doctrine/*.md file (excluding INDEX.md itself) is
#      <= 3000 bytes (the C.4 compact-form hard cap).
#
# Failure modes this catches:
#   - A rule file lingers in rules/ instead of being moved to doctrine/.
#   - doctrine/INDEX.md is missing or wasn't regenerated after a doctrine
#     file was added/removed.
#   - A doctrine compact grew past the 3000-byte hard cap (verbose content
#     crept back into a compact instead of living in the paired -full.md).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NEURAL_LACE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RULES_DIR="$NEURAL_LACE_ROOT/adapters/claude-code/rules"
DOCTRINE_DIR="$NEURAL_LACE_ROOT/adapters/claude-code/doctrine"
DOCTRINE_INDEX="$DOCTRINE_DIR/INDEX.md"

PASS=0
FAIL=0
FAIL_MESSAGES=()

fail() {
  FAIL=$((FAIL + 1))
  FAIL_MESSAGES+=("$1")
}

# ------------------------------------------------------------
# Invariant 1: rules/ contains exactly {constitution.md}
# ------------------------------------------------------------
if [[ ! -d "$RULES_DIR" ]]; then
  fail "rules/ directory not found at $RULES_DIR"
else
  extra_rules=()
  while IFS= read -r -d '' rule_path; do
    rule_name="$(basename "$rule_path")"
    if [[ "$rule_name" != "constitution.md" ]]; then
      extra_rules+=("$rule_name")
    fi
  done < <(find "$RULES_DIR" -maxdepth 1 -type f -name '*.md' -print0)

  if [[ ! -f "$RULES_DIR/constitution.md" ]]; then
    fail "rules/constitution.md is missing"
  fi

  if [[ ${#extra_rules[@]} -gt 0 ]]; then
    fail "rules/ contains files other than constitution.md: ${extra_rules[*]}"
  else
    PASS=$((PASS + 1))
  fi
fi

# ------------------------------------------------------------
# Invariant 2: doctrine/INDEX.md exists
# ------------------------------------------------------------
if [[ ! -f "$DOCTRINE_INDEX" ]]; then
  fail "doctrine/INDEX.md not found at $DOCTRINE_INDEX"
else
  PASS=$((PASS + 1))
fi

# ------------------------------------------------------------
# Invariants 3 + 4: every non-"-full" doctrine/*.md (excluding INDEX.md)
# has an INDEX row AND is <= 3000 bytes.
#
# doctrine/INDEX.md is manifest-generated (manifest-check.sh --gen-index):
# each row's "doctrine" column is a markdown link whose LINK TARGET is the
# doctrine file's basename, e.g. `[doctrine/foo.md](foo.md)`. Match on that
# form rather than a backtick-quoted basename (the old rules/INDEX.md hand
# -authored convention this file superseded).
# ------------------------------------------------------------
if [[ -d "$DOCTRINE_DIR" && -f "$DOCTRINE_INDEX" ]]; then
  missing_in_index=()
  oversized=()

  while IFS= read -r -d '' doctrine_path; do
    doctrine_name="$(basename "$doctrine_path")"

    # Skip the INDEX file itself and every "-full.md" companion — fulls are
    # verbatim/merged source, exempt from both the INDEX-row requirement and
    # the 3000-byte compact cap.
    if [[ "$doctrine_name" == "INDEX.md" ]]; then
      continue
    fi
    if [[ "$doctrine_name" == *-full.md ]]; then
      continue
    fi

    if grep -F -q "]($doctrine_name)" "$DOCTRINE_INDEX"; then
      : # has a row
    else
      missing_in_index+=("$doctrine_name")
    fi

    byte_count=$(wc -c < "$doctrine_path")
    if [[ "$byte_count" -gt 3000 ]]; then
      oversized+=("$doctrine_name ($byte_count bytes)")
    fi
  done < <(find "$DOCTRINE_DIR" -maxdepth 1 -type f -name '*.md' -print0)

  if [[ ${#missing_in_index[@]} -gt 0 ]]; then
    fail "doctrine compacts lacking an INDEX.md row: ${missing_in_index[*]}"
  else
    PASS=$((PASS + 1))
  fi

  if [[ ${#oversized[@]} -gt 0 ]]; then
    fail "doctrine compacts over the 3000-byte cap: ${oversized[*]}"
  else
    PASS=$((PASS + 1))
  fi
fi

echo "Checks passed: $PASS"
if [[ $FAIL -gt 0 ]]; then
  echo
  for msg in "${FAIL_MESSAGES[@]}"; do
    echo "FAIL: $msg"
  done
  echo
  echo "rules/ should contain ONLY constitution.md (everything else moved to"
  echo "doctrine/ per Wave C). Regenerate doctrine/INDEX.md with:"
  echo "  bash adapters/claude-code/scripts/manifest-check.sh --gen-index"
  echo "Compacts over the 3000-byte cap should trim to a pointer + move the"
  echo "detail into a paired doctrine/<name>-full.md."
  exit 1
fi

echo "PASS: rules/ holds only constitution.md; doctrine/INDEX.md covers every compact within the 3000-byte cap"
exit 0
