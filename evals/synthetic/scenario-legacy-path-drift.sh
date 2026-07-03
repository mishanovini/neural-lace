#!/usr/bin/env bash
# Synthetic Scenario: legacy-path-drift
#
# Exercises harness-doctor.sh check 3 (legacy-paths): no live hook or
# script may reference the retired legacy repo path family
# (claude-projects/neural-lace). Bad case: a fixture hooks dir contains a
# hook whose source text references the retired path → doctor REDs (rc
# 1). Good case: a clean fixture hooks dir with no legacy references →
# doctor exits GREEN (rc 0).
#
# Invocation contract (verified against the doctor's own --self-test
# fixtures): `HARNESS_DOCTOR_HOME=<live-dir> bash harness-doctor.sh
# --quick <repo-root>`. --quick runs checks 1-7 against the given live
# mirror + repo. Exit 0 iff zero RED lines; non-zero otherwise. The
# legacy-path pattern is built by concatenation in both the doctor and
# this fixture, so this scenario file's own text never matches the
# pattern it constructs.
#
# Note: because --quick runs ALL of checks 1-7 (not just legacy-paths in
# isolation), the fixtures below also satisfy checks 1/2/4/5/7 cleanly
# (present hooks referenced correctly in settings.json, no missing lib
# deps, live==template wiring, no manifest present so 5/7 gracefully
# WARN rather than RED) so that a RED verdict in the bad case is
# attributable ONLY to check 3, and the good case is unambiguously GREEN.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NL_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DOCTOR="$NL_ROOT/adapters/claude-code/hooks/harness-doctor.sh"

if [[ ! -f "$DOCTOR" ]]; then
  echo "FAIL: harness-doctor.sh not found at $DOCTOR"
  exit 1
fi

FAILS=0

_scenario_dir() {
  local dir="$1"
  mkdir -p "$dir/live/hooks" "$dir/live/rules" "$dir/live/scripts" "$dir/live/local"
  mkdir -p "$dir/repo/adapters/claude-code/hooks" "$dir/repo/adapters/claude-code/scripts" \
           "$dir/repo/adapters/claude-code/rules" "$dir/repo/adapters/claude-code/schemas"
}

_write_settings() {
  local path="$1"; shift
  local body='{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":['
  local first=1
  local name
  for name in "$@"; do
    if [[ "$first" -eq 0 ]]; then body="${body},"; fi
    first=0
    body="${body}{\"type\":\"command\",\"command\":\"bash ~/.claude/hooks/${name}\"}"
  done
  body="${body}]}]}}"
  printf '%s' "$body" > "$path"
}

_run_quick() {
  local dir="$1"
  HARNESS_DOCTOR_HOME="$dir/live" bash "$DOCTOR" --quick "$dir/repo" 2>&1
}

# ---- Bad case: a hook's source references the retired legacy path ----
BAD_DIR=$(mktemp -d)
trap 'rm -rf "$BAD_DIR"' EXIT
_scenario_dir "$BAD_DIR"
{
  printf '%s\n' '#!/bin/bash'
  # Concatenation so this scenario file itself never contains the literal
  # pattern the doctor detects (and so harness-hygiene-scan.sh never
  # flags this file either).
  printf 'SRC="$HOME/claude-projects/neural%s"\n' '-lace/adapters/claude-code'
  printf 'echo "legacy hook"\n'
} > "$BAD_DIR/live/hooks/legacy.sh"
chmod +x "$BAD_DIR/live/hooks/legacy.sh"
_write_settings "$BAD_DIR/live/settings.json" "legacy.sh"
cp "$BAD_DIR/live/settings.json" "$BAD_DIR/repo/adapters/claude-code/settings.json.template"
cp "$BAD_DIR/live/hooks/legacy.sh" "$BAD_DIR/repo/adapters/claude-code/hooks/legacy.sh"

OUT="$(_run_quick "$BAD_DIR")"
RC=$?
if [[ "$RC" -ne 0 ]] && printf '%s' "$OUT" | grep -q 'RED legacy-paths'; then
  echo "PASS: hook referencing the retired legacy path was correctly REDed (rc=$RC)"
else
  echo "FAIL: hook referencing the retired legacy path should have REDed on legacy-paths (rc=$RC)"
  echo "--- doctor output ---"
  printf '%s\n' "$OUT"
  FAILS=$((FAILS + 1))
fi

# ---- Good case: a hook with no legacy references ----
GOOD_DIR=$(mktemp -d)
trap 'rm -rf "$BAD_DIR" "$GOOD_DIR"' EXIT
_scenario_dir "$GOOD_DIR"
cat > "$GOOD_DIR/live/hooks/modern.sh" <<'EOF'
#!/bin/bash
echo "clean"
EOF
chmod +x "$GOOD_DIR/live/hooks/modern.sh"
_write_settings "$GOOD_DIR/live/settings.json" "modern.sh"
cp "$GOOD_DIR/live/settings.json" "$GOOD_DIR/repo/adapters/claude-code/settings.json.template"
cp "$GOOD_DIR/live/hooks/modern.sh" "$GOOD_DIR/repo/adapters/claude-code/hooks/modern.sh"

OUT="$(_run_quick "$GOOD_DIR")"
RC=$?
if [[ "$RC" -eq 0 ]]; then
  echo "PASS: clean hooks dir was correctly GREEN (rc=$RC)"
else
  echo "FAIL: clean hooks dir should have been GREEN (rc=$RC, expected 0)"
  echo "--- doctor output ---"
  printf '%s\n' "$OUT"
  FAILS=$((FAILS + 1))
fi

if [[ "$FAILS" -eq 0 ]]; then
  echo "scenario-legacy-path-drift: ALL PASSED"
  exit 0
fi
echo "scenario-legacy-path-drift: $FAILS FAILURE(S)"
exit 1
