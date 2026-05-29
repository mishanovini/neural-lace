#!/usr/bin/env bash
# credentials-reference-check-test.sh — self-test for install.sh's
# Phase 4c (item 10) credentials-reference check.
#
# Exercises three scenarios under a sandbox HOME so the real machine's
# ~/.claude/ is never touched:
#   T1: file MISSING → WARNING about missing file
#   T2: file is the unfilled template (contains a stub marker) → WARNING
#       about unfilled template (with the matched marker reported)
#   T3: file is populated (no stub markers) → no warning
#
# The check function lives in install.sh; this test invokes install.sh
# in --dry-run mode under sandbox HOME and asserts on its Phase 4c output.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ADAPTER_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
INSTALL_SH="$ADAPTER_DIR/install.sh"
EXAMPLE="$ADAPTER_DIR/examples/credentials-reference.example.md"

if [ ! -f "$INSTALL_SH" ]; then
  echo "FAIL: install.sh not found at $INSTALL_SH" >&2
  exit 1
fi

PASS=0
FAIL=0

run_scenario() {
  local name="$1"
  local setup_fn="$2"
  local expected_substr="$3"
  local expected_to_match="$4"  # "yes" or "no"

  local sandbox
  sandbox=$(mktemp -d -t cred-check-test.XXXXXX 2>/dev/null) || sandbox="/tmp/cred-check-test.$$"
  mkdir -p "$sandbox/.claude/local"

  # Call the scenario-specific setup.
  "$setup_fn" "$sandbox"

  # Run install.sh --dry-run under sandbox HOME.
  local out
  out=$(HOME="$sandbox" bash "$INSTALL_SH" --dry-run 2>&1 || true)

  # Extract just the Phase 4c block (defensive — limit search scope).
  local phase4c
  phase4c=$(printf '%s\n' "$out" | sed -n '/Phase 4c/,/^$/p')

  if [ "$expected_to_match" = "yes" ]; then
    if echo "$phase4c" | grep -qF -- "$expected_substr"; then
      echo "  $name: PASS"
      PASS=$((PASS+1))
    else
      echo "  $name: FAIL (expected substring not found: $expected_substr)" >&2
      echo "    Phase 4c output was:" >&2
      printf '      %s\n' "$phase4c" | head -10 >&2
      FAIL=$((FAIL+1))
    fi
  else
    if echo "$phase4c" | grep -qF -- "$expected_substr"; then
      echo "  $name: FAIL (unexpected substring found: $expected_substr)" >&2
      FAIL=$((FAIL+1))
    else
      echo "  $name: PASS"
      PASS=$((PASS+1))
    fi
  fi

  rm -rf "$sandbox"
}

setup_t1_missing() {
  local sandbox="$1"
  # Do nothing — the file should be absent.
  rm -f "$sandbox/.claude/local/credentials-reference.md"
}

setup_t2_unfilled() {
  local sandbox="$1"
  # Use the template directly (it contains the stub markers).
  cp "$EXAMPLE" "$sandbox/.claude/local/credentials-reference.md"
}

setup_t3_populated() {
  local sandbox="$1"
  # Write a populated file with no stub markers.
  cat > "$sandbox/.claude/local/credentials-reference.md" <<'EOF'
# Credentials Reference — Example Operator (test sandbox)

> Read me when you need a credential and want to know which convention is in play.

Last updated: 2026-05-29

## The convention

Vault: doppler (project: example-app).
GitHub CLI: gh authenticated to one account.
Vercel: vercel CLI authenticated.
Supabase: token cached at ~/.supabase/tokens/example.
EOF
}

echo "[credentials-reference-check] self-test"

run_scenario "T1 missing-file" setup_t1_missing "credentials-reference.md MISSING" yes
run_scenario "T2 unfilled-template" setup_t2_unfilled "UNFILLED TEMPLATE" yes
run_scenario "T3 populated-no-warning" setup_t3_populated "WARN" no

echo ""
if [ "$FAIL" -eq 0 ]; then
  echo "SELF-TEST: all scenarios passed ($PASS/$PASS)"
  exit 0
else
  echo "SELF-TEST: $FAIL scenario(s) failed" >&2
  exit 1
fi
