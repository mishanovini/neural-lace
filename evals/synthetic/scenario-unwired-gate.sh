#!/usr/bin/env bash
# Synthetic Scenario: unwired-gate
#
# Exercises harness-doctor.sh check 5 (claim-honesty, manifest-driven):
# every `kind: gate` entry in manifest.json must EITHER declare
# wired_template true (with the hook present in live settings.json) OR
# carry a non-empty honest_status explaining how it fires. Bad case: a
# manifest gate entry has wired_template:false and NO honest_status →
# doctor REDs claim-honesty (rc 1). Good case: the same shape but WITH a
# non-empty honest_status → doctor is GREEN (rc 0).
#
# Invocation contract: `HARNESS_DOCTOR_HOME=<live-dir> bash
# harness-doctor.sh --quick <repo-root>`, where <repo-root>/adapters/
# claude-code/manifest.json is the fixture manifest under test. Exit 0
# iff zero RED lines.
#
# Expected: bad case REDs on claim-honesty (rc 1), good case is GREEN
# (rc 0).

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

# Writes a fixture manifest with one live-wired gate (satisfies check 1/4)
# plus one "pending-gate" entry whose honest_status presence is
# controlled by $2. No manifest-check.sh is copied into the fixture repo,
# so check 7 gracefully WARNs (manifest-check skipped) rather than RED —
# isolating any RED verdict to check 5 (claim-honesty) alone.
_write_manifest_fixture() {
  local dir="$1" variant="$2"
  printf '#!/bin/bash\nexit 0\n' > "$dir/repo/adapters/claude-code/hooks/wired-gate.sh"
  printf '#!/bin/bash\nexit 0\n' > "$dir/live/hooks/wired-gate.sh"
  # pending-gate hook exists on disk in both cases here (this scenario
  # isolates the honest_status axis only — check 7's ghost-hook axis is
  # not this scenario's concern).
  printf '#!/bin/bash\nexit 0\n' > "$dir/repo/adapters/claude-code/hooks/pending-gate.sh"

  local honest_line=""
  if [[ "$variant" == "green" ]]; then
    honest_line='      "honest_status": "invoked via a chain script; not directly wired",'
  fi

  cat > "$dir/repo/adapters/claude-code/manifest.json" <<MANIFEST_EOF
{
  "schema_version": 1,
  "entries": [
    {
      "id": "wired-gate",
      "kind": "gate",
      "doctrine_file": null,
      "hooks": ["wired-gate.sh"],
      "events": ["Stop"],
      "wired_template": true,
      "selftest": false,
      "jit_triggers": { "paths": [], "keywords": [] },
      "blocking": true,
      "budget_class": "stop"
    },
    {
      "id": "pending-gate",
      "kind": "gate",
      "doctrine_file": null,
      "hooks": ["pending-gate.sh"],
      "events": ["precommit"],
      "wired_template": false,
      "selftest": false,
      "jit_triggers": { "paths": [], "keywords": [] },
      "blocking": true,
${honest_line}
      "budget_class": "none"
    }
  ]
}
MANIFEST_EOF

  # "no-honest" variant leaves an empty line where honest_status was —
  # strip it so the JSON stays parseable.
  if [[ "$variant" != "green" ]]; then
    grep -v '^$' "$dir/repo/adapters/claude-code/manifest.json" > "$dir/repo/adapters/claude-code/manifest.json.tmp" \
      && mv "$dir/repo/adapters/claude-code/manifest.json.tmp" "$dir/repo/adapters/claude-code/manifest.json"
  fi

  _write_settings "$dir/live/settings.json" "wired-gate.sh"
  cp "$dir/live/settings.json" "$dir/repo/adapters/claude-code/settings.json.template"
}

# ---- Bad case: manifest gate entry with wired_template:false and no
#      honest_status ("unwired and unexplained") ----
BAD_DIR=$(mktemp -d)
trap 'rm -rf "$BAD_DIR"' EXIT
_scenario_dir "$BAD_DIR"
_write_manifest_fixture "$BAD_DIR" "no-honest"

OUT="$(_run_quick "$BAD_DIR")"
RC=$?
if [[ "$RC" -ne 0 ]] && printf '%s' "$OUT" | grep -q 'RED claim-honesty'; then
  echo "PASS: unwired gate with no honest_status was correctly REDed (rc=$RC)"
else
  echo "FAIL: unwired gate with no honest_status should have REDed on claim-honesty (rc=$RC)"
  echo "--- doctor output ---"
  printf '%s\n' "$OUT"
  FAILS=$((FAILS + 1))
fi

# ---- Good case: same shape, but WITH honest_status explaining how it fires ----
GOOD_DIR=$(mktemp -d)
trap 'rm -rf "$BAD_DIR" "$GOOD_DIR"' EXIT
_scenario_dir "$GOOD_DIR"
_write_manifest_fixture "$GOOD_DIR" "green"

OUT="$(_run_quick "$GOOD_DIR")"
RC=$?
if [[ "$RC" -eq 0 ]]; then
  echo "PASS: unwired gate WITH honest_status was correctly GREEN (rc=$RC)"
else
  echo "FAIL: unwired gate WITH honest_status should have been GREEN (rc=$RC, expected 0)"
  echo "--- doctor output ---"
  printf '%s\n' "$OUT"
  FAILS=$((FAILS + 1))
fi

if [[ "$FAILS" -eq 0 ]]; then
  echo "scenario-unwired-gate: ALL PASSED"
  exit 0
fi
echo "scenario-unwired-gate: $FAILS FAILURE(S)"
exit 1
