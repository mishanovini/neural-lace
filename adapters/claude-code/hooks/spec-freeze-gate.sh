#!/bin/bash
# spec-freeze-gate.sh — Phase 1d-C-2 (C2), 2026-05-04
#
# PreToolUse hook that blocks Edit/Write/MultiEdit on a file declared in
# any ACTIVE plan's `## Files to Modify/Create` section UNLESS that plan's
# header has `frozen: true`.
#
# Rule (mechanism, Build Doctrine §6 C2): once a plan has been authored
# and reviewed, its declared files should not be edited freely until the
# spec is explicitly frozen. Freezing captures the plan at a known-good
# state; thawing requires an explicit `frozen: false` flip with rationale.
# This is the load-bearing gate against silent spec drift mid-build.
#
# Trigger:
#   PreToolUse on tool_name in {Edit, Write, MultiEdit}. Reads
#   `tool_input.file_path`. Pass-through on other tool names and missing
#   paths.
#
# Self-bypass for plan files:
#   `docs/plans/<slug>.md` (top-level OR archive) is ALWAYS allowed —
#   plans must edit themselves to flip `frozen:`, append evidence blocks,
#   add in-flight scope updates, mark Status terminal, etc. Without this
#   bypass the gate would deadlock the freeze workflow.
#
# Logic:
#   1. Extract target file path. Normalize forward-slash for Windows.
#   2. Self-bypass on `docs/plans/.*\.md` (any depth — covers archive too).
#   3. Iterate every `docs/plans/*.md` (top-level only, exclude archive).
#      For each plan with `Status: ACTIVE`:
#        - Parse `## Files to Modify/Create` into a list of paths.
#        - Compare against the target. Match = the plan claims this file.
#   4. If NO plan claims the file → ALLOW.
#   5. If one or more plans claim the file:
#        - Read each claiming plan's `frozen:` header field.
#        - If ALL claiming plans have `frozen: true` → ALLOW.
#        - If ANY claiming plan has `frozen: false` OR missing → BLOCK,
#          naming the unfrozen plan(s).
#
# Degradation:
#   On any plan parse error (malformed header, missing section, awk
#   failure), the hook degrades to ALLOW for that plan (treats it as if
#   it doesn't claim the file) and emits a stderr WARN. Hook bugs must
#   not lock the maintainer out of routine edits.
#
# Exit codes:
#   0 — allow (edit proceeds, incl. via the waiver release valve below)
#   1 — block (stderr explains why)
#   2 — input parse error (only when stdin malformed; plan-parse errors
#       degrade to ALLOW per the rule above)
#
# WAIVER (F.5 waiver-parity audit row 27 / ADR 059 D4 fix): the previous
# only remedy for a time-boxed, substantive need to touch a frozen plan's
# file WITHOUT formally unfreezing it was "edit the plan to flip frozen, OR
# temporarily use a non-Edit/Write tool" — the second option is a literal
# bypass-via-different-tool, not a waiver, with no ledger trail of why.
# ADR 059 D4 is a hard design rule ("every blocking check MUST ship a
# structured waiver path") and this block is a world-state assertion (the
# plan's frozen field), not a session-honesty assertion — squarely inside
# D4's waiver-eligible scope. Fixed: a fresh (<1h) structured waiver at
# .claude/state/spec-freeze-waiver-<slug>-*.txt naming BOTH purpose clauses
# (lib/waiver-purpose-clause.sh) ALLOWS the edit, ledger-logged. This is
# DISTINCT from — and does not replace — actually unfreezing the plan,
# which remains the durable, non-time-boxed remedy.
#
# References:
#   - adapters/claude-code/hooks/scope-enforcement-gate.sh — the parallel
#     pattern (iterates ACTIVE plans, parses Files to Modify/Create).
#   - adapters/claude-code/hooks/prd-validity-gate.sh — newest stdin
#     parsing + self-test runner pattern.
#   - adapters/claude-code/hooks/plan-edit-validator.sh — header-field
#     extraction precedent.
#   - adapters/claude-code/hooks/bug-persistence-gate.sh — the canonical
#     structured-waiver shape this fix mirrors.

# ============================================================
# Helper: normalize a path (forward-slash; trim)
# ============================================================
_normalize_path() {
  local p="$1"
  # Convert backslashes to forward slashes (Windows compatibility)
  p="${p//\\//}"
  printf '%s' "$p"
}

# ============================================================
# Shared backtick-token extraction (§D.0.7 fix, NL Overhaul Wave D.6).
# Loops ALL backtick pairs on a bullet line instead of only the first
# (the pre-fix bug both this file and scope-enforcement-gate.sh shared).
# ============================================================
_SFG_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
# shellcheck source=lib/extract-backtick-paths.sh
source "$_SFG_SELF_DIR/lib/extract-backtick-paths.sh" 2>/dev/null || true
# shellcheck source=lib/waiver-purpose-clause.sh
source "$_SFG_SELF_DIR/lib/waiver-purpose-clause.sh" 2>/dev/null || true
# shellcheck source=lib/signal-ledger.sh
source "$_SFG_SELF_DIR/lib/signal-ledger.sh" 2>/dev/null || true

# _sfg_has_fresh_waiver <plan-slug>
# Fresh (<1h) .claude/state/spec-freeze-waiver-<plan-slug>-*.txt naming
# BOTH purpose clauses (lib/waiver-purpose-clause.sh). Mirrors
# bug-persistence-gate.sh waiver semantics. Prints the matched file path
# and returns 0 on success.
_sfg_has_fresh_waiver() {
  local plan_slug="$1"
  local state_dir="${CLAUDE_STATE_DIR:-.claude/state}"
  [[ -d "$state_dir" ]] || return 1
  local safe_slug
  safe_slug=$(printf '%s' "$plan_slug" | tr -c 'A-Za-z0-9._-' '-')
  local glob="spec-freeze-waiver-${safe_slug}-*.txt"
  local f
  while IFS= read -r f; do
    [[ -f "$f" ]] || continue
    if declare -F waiver_has_purpose_clauses >/dev/null 2>&1; then
      if waiver_has_purpose_clauses "$f"; then
        printf '%s' "$f"
        return 0
      fi
    fi
  done < <(find "$state_dir" -maxdepth 1 -type f -name "$glob" -newermt '1 hour ago' 2>/dev/null)
  return 1
}

# ============================================================
# Helper: convert any path (absolute or relative) into a repo-relative
# path against $REPO_ROOT. If path doesn't fall under repo root, returns
# the path unchanged (so cross-repo edits still get sensible matching).
# ============================================================
_to_repo_relative() {
  local p="$1"
  local root="${2:-$REPO_ROOT}"
  p=$(_normalize_path "$p")
  if [[ -n "$root" ]]; then
    root=$(_normalize_path "$root")
    # Strip trailing slash from root for clean prefix-comparison
    root="${root%/}"
    # If path starts with root + /, strip the prefix
    if [[ "$p" == "$root/"* ]]; then
      p="${p#$root/}"
    elif [[ "$p" == "$root" ]]; then
      p=""
    fi
  fi
  printf '%s' "$p"
}

# ============================================================
# Helper: is this path a plan file (docs/plans/*.md at any depth)?
# Returns 0 if yes (self-bypass), 1 otherwise.
# ============================================================
_is_plan_file() {
  local p
  p=$(_normalize_path "$1")
  case "$p" in
    *docs/plans/*.md) return 0 ;;
    *) return 1 ;;
  esac
}

# ============================================================
# Helper: locate repo root from a file path's directory.
# Walks up looking for .git or docs/plans/. Echoes path or empty.
# ============================================================
_find_repo_root() {
  local start_dir="$1"
  local current="$start_dir"
  while [[ -n "$current" ]] && [[ "$current" != "/" ]] && [[ "$current" != "." ]]; do
    if [[ -d "$current/.git" ]] || [[ -d "$current/docs/plans" ]]; then
      printf '%s' "$current"
      return 0
    fi
    local parent
    parent=$(dirname "$current")
    [[ "$parent" == "$current" ]] && break
    current="$parent"
  done
  return 1
}

# ============================================================
# Helper: extract `frozen:` field from a plan file. Echoes the
# trimmed value (e.g., "true", "false") or empty if missing.
# Searches first 30 lines.
# ============================================================
_extract_frozen() {
  local plan_file="$1"
  awk 'NR<=30 && /^frozen:[[:space:]]/ {
    sub(/^frozen:[[:space:]]*/, "")
    sub(/[[:space:]]+$/, "")
    print
    exit
  }' "$plan_file" 2>/dev/null
}

# ============================================================
# Helper: extract `Status:` field from a plan file. Echoes the
# trimmed value (e.g., "ACTIVE", "COMPLETED").
# ============================================================
_extract_status() {
  local plan_file="$1"
  awk 'NR<=50 && /^Status:[[:space:]]/ {
    sub(/^Status:[[:space:]]*/, "")
    sub(/[[:space:]]+$/, "")
    print
    exit
  }' "$plan_file" 2>/dev/null
}

# ============================================================
# Helper: derive plan slug from a plan file path.
# ============================================================
_plan_slug() {
  local p="$1"
  local b
  b=$(basename "$p")
  echo "${b%.md}"
}

# ============================================================
# Helper: parse the `## Files to Modify/Create` section of a plan
# file and emit each declared path on stdout, one per line.
# Tolerates: backticked paths (`- \`path\` — desc`), plain paths
# (`- path/to/file —`), bullet markers `-` and `*`. Ignores
# placeholders.
# ============================================================
_parse_files_section() {
  local plan_file="$1"
  awk '
    /^## Files to Modify\/Create[[:space:]]*$/ { in_section = 1; next }
    /^## / && in_section { in_section = 0; exit }
    in_section { print }
  ' "$plan_file" 2>/dev/null | while IFS= read -r line; do
    # Trim leading whitespace
    line="${line#"${line%%[![:space:]]*}"}"
    [[ -z "$line" ]] && continue
    # Must start with bullet marker
    case "$line" in
      "- "*|"* "*) ;;
      *) continue ;;
    esac
    # Strip the bullet
    line="${line:2}"
    # Skip placeholder rows
    case "$line" in
      "[populate me]"*|"[TODO]"*|"TODO"*|"..."*|"[tbd]"*|"[TBD]"*) continue ;;
    esac

    local extracted=""
    if [[ "$line" == *'`'* ]]; then
      # §D.0.7 fix: loop ALL backtick pairs on the line (a bullet can name
      # multiple paths, e.g. "- `a/b.ts` and `c/d.ts` — desc"), not just
      # the first. Each valid token is emitted independently below.
      local tok
      while IFS= read -r tok; do
        [[ -z "$tok" ]] && continue
        if [[ "$tok" != */* ]] && [[ "$tok" != *.* ]]; then
          continue
        fi
        printf '%s\n' "$tok"
      done < <(extract_backtick_paths "$line")
      continue
    else
      # Plain path: take up to first em-dash, double-hyphen, or single
      # hyphen separator with surrounding whitespace.
      extracted="$line"
      extracted="${extracted%% — *}"
      extracted="${extracted%% -- *}"
      extracted="${extracted%% - *}"
      # Trim trailing whitespace
      extracted="${extracted%"${extracted##*[![:space:]]}"}"
      # If the resulting "path" still has a bare space, it's prose, skip.
      if [[ "$extracted" == *" "* ]]; then
        continue
      fi
    fi

    [[ -z "$extracted" ]] && continue
    # Sanity: an actual path has either / or .
    if [[ "$extracted" != */* ]] && [[ "$extracted" != *.* ]]; then
      continue
    fi
    printf '%s\n' "$extracted"
  done
}

# ============================================================
# Helper: does plan claim this file? Returns 0 (yes), 1 (no).
# Args: $1 = plan_file, $2 = target_file (repo-relative)
# Uses simple match: exact, glob (*, **, ?), or directory-prefix
# (entry ending in `/`).
# ============================================================
_plan_claims_file() {
  local plan_file="$1"
  local target="$2"
  local entry
  while IFS= read -r entry; do
    [[ -z "$entry" ]] && continue
    if _glob_match "$entry" "$target"; then
      return 0
    fi
  done < <(_parse_files_section "$plan_file")
  return 1
}

# ============================================================
# Helper: convert a glob pattern to an anchored regex
# (mirrors scope-enforcement-gate.sh's glob_to_regex).
# ============================================================
_glob_to_regex() {
  local pat="$1"
  local out=""
  local i ch next
  local n=${#pat}
  local bs="\\"
  for ((i=0; i<n; i++)); do
    ch="${pat:i:1}"
    case "$ch" in
      '*')
        next="${pat:i+1:1}"
        if [[ "$next" == "*" ]]; then
          out="${out}.*"
          ((i++))
        else
          out="${out}[^/]*"
        fi
        ;;
      '?')
        out="${out}[^/]"
        ;;
      '.'|'+'|'('|')'|'{'|'}'|'['|']'|'^'|'$'|'|')
        out="${out}${bs}${ch}"
        ;;
      '\')
        out="${out}${bs}${bs}"
        ;;
      *)
        out="${out}${ch}"
        ;;
    esac
  done
  printf '%s' "$out"
}

# ============================================================
# Helper: glob match. $1 = pattern, $2 = path. Returns 0 on match.
# ============================================================
_glob_match() {
  local pat="$1" path="$2"

  # Exact match
  if [[ "$pat" == "$path" ]]; then
    return 0
  fi
  # Directory-prefix match: pattern ends with /
  if [[ "${pat: -1}" == "/" ]]; then
    if [[ "$path" == "$pat"* ]]; then
      return 0
    fi
    return 1
  fi
  # No glob metacharacters → no match (already exact-checked)
  if [[ "$pat" != *'*'* ]] && [[ "$pat" != *'?'* ]]; then
    return 1
  fi
  local re
  re=$(_glob_to_regex "$pat")
  if [[ "$path" =~ ^${re}$ ]]; then
    return 0
  fi
  return 1
}

# ============================================================
# --self-test handler (seven scenarios)
# ============================================================
if [[ "${1:-}" == "--self-test" ]]; then
  SELF_TEST_HOOK="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)/$(basename "${BASH_SOURCE[0]}")"
  if [[ ! -f "$SELF_TEST_HOOK" ]]; then
    echo "self-test: cannot resolve own path" >&2
    exit 2
  fi

  PASSED=0
  FAILED=0
  TMPROOT=$(mktemp -d 2>/dev/null || mktemp -d -t spec-freeze)
  if [[ -z "$TMPROOT" ]] || [[ ! -d "$TMPROOT" ]]; then
    echo "self-test: cannot create temp directory" >&2
    exit 2
  fi
  trap 'rm -rf "$TMPROOT"' EXIT

  # Helper: build a synthetic repo with N plan files, then invoke the
  # hook against an Edit on a target file. Returns hook's exit code.
  #
  # Args:
  #   $1 = scenario label
  #   $2 = target file path (RELATIVE to repo root; will be created)
  #   $3 = newline-separated list of plan-spec strings; each spec is
  #        "<slug>|<frozen-value>|<status>|<files-csv>"
  #        Example: "alpha|true|ACTIVE|src/foo.ts,src/bar.ts"
  _run_scenario() {
    local label="$1" target_rel="$2" plans_spec="$3"
    local repo="$TMPROOT/$label"
    mkdir -p "$repo/docs/plans"
    (cd "$repo" && git init -q 2>/dev/null || true)

    # Capture the canonical repo path via the same code path the hook
    # will use (`git rev-parse --show-toplevel`). On Windows Git Bash
    # this returns C:/-style paths even when $repo is /tmp/-style;
    # using the same form here keeps the JSON file_path in the same
    # namespace as the hook's repo-root resolution.
    local canonical_repo
    canonical_repo=$(cd "$repo" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null || echo "$repo")

    # Materialize each plan
    while IFS= read -r spec; do
      [[ -z "$spec" ]] && continue
      local slug frozen status files_csv
      IFS='|' read -r slug frozen status files_csv <<< "$spec"
      local plan_path="$repo/docs/plans/${slug}.md"
      {
        echo "# Plan: $slug"
        echo "Status: $status"
        echo "frozen: $frozen"
        echo ""
        echo "## Goal"
        echo "Test plan for self-test."
        echo ""
        echo "## Files to Modify/Create"
        IFS=',' read -ra FILES <<< "$files_csv"
        for f in "${FILES[@]}"; do
          [[ -z "$f" ]] && continue
          echo "- \`$f\` — test file"
        done
        echo ""
        echo "## Tasks"
        echo "- [ ] 1. test"
      } > "$plan_path"
    done <<< "$plans_spec"

    # Materialize the target file (it may need to exist for the Edit
    # tool to apply, though the hook only reads file_path from JSON).
    local target_full="$repo/$target_rel"
    mkdir -p "$(dirname "$target_full")" 2>/dev/null
    [[ -f "$target_full" ]] || echo "stub" > "$target_full"

    # Use canonical-repo-rooted path so git rev-parse output namespace
    # matches the JSON file_path.
    local target_canonical="$canonical_repo/$target_rel"
    local file_path_json
    file_path_json=$(printf '%s' "$target_canonical" | jq -Rs . 2>/dev/null)
    if [[ -z "$file_path_json" ]]; then
      file_path_json='""'
    fi
    local input
    input=$(printf '{"tool_name":"Edit","tool_input":{"file_path":%s,"old_string":"stub","new_string":"updated"}}' \
      "$file_path_json")

    printf '%s' "$input" | bash "$SELF_TEST_HOOK" >"$repo/stdout.txt" 2>"$repo/stderr.txt"
    echo $?
  }

  # ---- Scenario 1: PASS — no plan claims the file ----
  RC=$(_run_scenario s1 "src/unrelated.ts" "alpha|false|ACTIVE|src/foo.ts,src/bar.ts")
  if [[ "$RC" == "0" ]]; then
    echo "self-test (1) PASS-no-plan-claims: PASS (rc=$RC, expected 0)" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (1) PASS-no-plan-claims: FAIL (rc=$RC, expected 0)" >&2
    cat "$TMPROOT/s1/stderr.txt" >&2
    FAILED=$((FAILED+1))
  fi

  # ---- Scenario 2: PASS — file in a frozen plan ----
  RC=$(_run_scenario s2 "src/foo.ts" "alpha|true|ACTIVE|src/foo.ts,src/bar.ts")
  if [[ "$RC" == "0" ]]; then
    echo "self-test (2) PASS-frozen-plan: PASS (rc=$RC, expected 0)" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (2) PASS-frozen-plan: FAIL (rc=$RC, expected 0)" >&2
    cat "$TMPROOT/s2/stderr.txt" >&2
    FAILED=$((FAILED+1))
  fi

  # ---- Scenario 3: FAIL — file in an unfrozen plan ----
  RC=$(_run_scenario s3 "src/foo.ts" "alpha|false|ACTIVE|src/foo.ts,src/bar.ts")
  if [[ "$RC" == "1" ]]; then
    echo "self-test (3) FAIL-unfrozen-plan: PASS (rc=$RC, expected 1; correctly blocked)" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (3) FAIL-unfrozen-plan: FAIL (rc=$RC, expected 1)" >&2
    cat "$TMPROOT/s3/stderr.txt" >&2
    FAILED=$((FAILED+1))
  fi

  # ---- Scenario 4: PASS — multiple plans, ALL frozen ----
  RC=$(_run_scenario s4 "src/foo.ts" \
"alpha|true|ACTIVE|src/foo.ts,src/bar.ts
beta|true|ACTIVE|src/foo.ts,src/baz.ts")
  if [[ "$RC" == "0" ]]; then
    echo "self-test (4) PASS-multiple-plans-all-frozen: PASS (rc=$RC, expected 0)" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (4) PASS-multiple-plans-all-frozen: FAIL (rc=$RC, expected 0)" >&2
    cat "$TMPROOT/s4/stderr.txt" >&2
    FAILED=$((FAILED+1))
  fi

  # ---- Scenario 5: FAIL — multiple plans, one frozen one not ----
  RC=$(_run_scenario s5 "src/foo.ts" \
"alpha|true|ACTIVE|src/foo.ts,src/bar.ts
beta|false|ACTIVE|src/foo.ts,src/baz.ts")
  if [[ "$RC" == "1" ]]; then
    echo "self-test (5) FAIL-multiple-plans-one-unfrozen: PASS (rc=$RC, expected 1; correctly blocked)" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (5) FAIL-multiple-plans-one-unfrozen: FAIL (rc=$RC, expected 1)" >&2
    cat "$TMPROOT/s5/stderr.txt" >&2
    FAILED=$((FAILED+1))
  fi

  # ---- Scenario 6: PASS — target IS a plan file (self-bypass) ----
  # Even if some other plan claims `docs/plans/<slug>.md` and is
  # unfrozen, edits to plan files themselves must always be allowed.
  RC=$(_run_scenario s6 "docs/plans/alpha.md" \
"alpha|false|ACTIVE|src/foo.ts,docs/plans/alpha.md
beta|false|ACTIVE|docs/plans/alpha.md")
  if [[ "$RC" == "0" ]]; then
    echo "self-test (6) PASS-plan-file-itself: PASS (rc=$RC, expected 0)" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (6) PASS-plan-file-itself: FAIL (rc=$RC, expected 0)" >&2
    cat "$TMPROOT/s6/stderr.txt" >&2
    FAILED=$((FAILED+1))
  fi

  # ---- Scenario 7 (§D.0.7): multi-path-per-line bullet — a single bullet
  # naming TWO backticked paths ("- `a/multi1.ts` and `a/multi2.ts` — desc")
  # must produce TWO scope entries, so an unfrozen plan blocks edits to
  # EITHER named path — not just the first backtick pair (the pre-fix
  # bug this hook shared with scope-enforcement-gate.sh). This scenario
  # writes the plan file directly (the _run_scenario CSV helper always
  # emits one bullet per file) and targets the SECOND path in the bullet;
  # pre-fix this would have ALLOWED (second token silently dropped). ----
  _run_multi_path_scenario() {
    local label="$1" target_rel="$2"
    local repo="$TMPROOT/$label"
    mkdir -p "$repo/docs/plans"
    (cd "$repo" && git init -q 2>/dev/null || true)
    local canonical_repo
    canonical_repo=$(cd "$repo" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null || echo "$repo")

    cat > "$repo/docs/plans/multi.md" <<'PLANEOF'
# Plan: multi
Status: ACTIVE
frozen: false

## Goal
Test plan for multi-path-bullet self-test.

## Files to Modify/Create
- `src/multi1.ts` and `src/multi2.ts` — two-file bullet (§D.0.7)

## Tasks
- [ ] 1. test
PLANEOF

    local target_full="$repo/$target_rel"
    mkdir -p "$(dirname "$target_full")" 2>/dev/null
    [[ -f "$target_full" ]] || echo "stub" > "$target_full"

    local target_canonical="$canonical_repo/$target_rel"
    local file_path_json
    file_path_json=$(printf '%s' "$target_canonical" | jq -Rs . 2>/dev/null)
    [[ -z "$file_path_json" ]] && file_path_json='""'
    local input
    input=$(printf '{"tool_name":"Edit","tool_input":{"file_path":%s,"old_string":"stub","new_string":"updated"}}' \
      "$file_path_json")

    printf '%s' "$input" | bash "$SELF_TEST_HOOK" >"$repo/stdout.txt" 2>"$repo/stderr.txt"
    echo $?
  }

  RC=$(_run_multi_path_scenario s7 "src/multi2.ts")
  if [[ "$RC" == "1" ]]; then
    echo "self-test (7) multi-path-per-line-bullet-second-token-blocks: PASS (rc=$RC, expected 1; correctly blocked)" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (7) multi-path-per-line-bullet-second-token-blocks: FAIL (rc=$RC, expected 1)" >&2
    cat "$TMPROOT/s7/stderr.txt" >&2
    FAILED=$((FAILED+1))
  fi

  # ---- Structured-waiver scenarios (F.5 audit row 27 / ADR 059 D4 fix) ----
  # Reuses the s1-style unfrozen-plan setup (plan slug "alpha", claims
  # src/foo.ts) but writes a waiver into the fixture's .claude/state/
  # before invoking the hook, via CLAUDE_STATE_DIR.
  _run_waiver_scenario() {
    local label="$1" waiver_body="$2" backdate="$3"
    local repo="$TMPROOT/$label"
    mkdir -p "$repo/docs/plans" "$repo/.claude/state"
    (cd "$repo" && git init -q 2>/dev/null || true)
    local canonical_repo
    canonical_repo=$(cd "$repo" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null || echo "$repo")

    cat > "$repo/docs/plans/alpha.md" <<'PLANEOF'
# Plan: alpha
Status: ACTIVE
frozen: false

## Goal
Test plan for waiver self-test.

## Files to Modify/Create
- `src/foo.ts` — test file

## Tasks
- [ ] 1. test
PLANEOF

    if [[ -n "$waiver_body" ]]; then
      printf '%s' "$waiver_body" > "$repo/.claude/state/spec-freeze-waiver-alpha-selftest.txt"
      if [[ "$backdate" == "1" ]]; then
        touch -d '2 hours ago' "$repo/.claude/state/spec-freeze-waiver-alpha-selftest.txt" 2>/dev/null \
          || touch -t "$(date -d '2 hours ago' +%Y%m%d%H%M.%S 2>/dev/null)" "$repo/.claude/state/spec-freeze-waiver-alpha-selftest.txt" 2>/dev/null \
          || true
      fi
    fi

    local target_full="$repo/src/foo.ts"
    mkdir -p "$(dirname "$target_full")" 2>/dev/null
    [[ -f "$target_full" ]] || echo "stub" > "$target_full"

    local target_canonical="$canonical_repo/src/foo.ts"
    local file_path_json
    file_path_json=$(printf '%s' "$target_canonical" | jq -Rs . 2>/dev/null)
    [[ -z "$file_path_json" ]] && file_path_json='""'
    local input
    input=$(printf '{"tool_name":"Edit","tool_input":{"file_path":%s,"old_string":"stub","new_string":"updated"}}' \
      "$file_path_json")

    (cd "$repo" && printf '%s' "$input" | \
      CLAUDE_STATE_DIR="$repo/.claude/state" bash "$SELF_TEST_HOOK" >"$repo/stdout.txt" 2>"$repo/stderr.txt")
    echo $?
  }

  # (8) waiver-absent-blocks: no waiver file → BLOCK (rc=1)
  RC=$(_run_waiver_scenario s8 "" 0)
  if [[ "$RC" == "1" ]]; then
    echo "self-test (8) waiver-absent-blocks: PASS (rc=$RC, expected 1)" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (8) waiver-absent-blocks: FAIL (rc=$RC, expected 1)" >&2
    FAILED=$((FAILED+1))
  fi

  # (9) waiver-honored: fresh waiver with BOTH purpose clauses → ALLOW (rc=0)
  W9_BODY=$'Purpose: this gate exists to prevent silent spec drift mid-build\nBecause: this is a self-test scenario exercising the waiver valve\n'
  RC=$(_run_waiver_scenario s9 "$W9_BODY" 0)
  if [[ "$RC" == "0" ]]; then
    echo "self-test (9) waiver-honored: PASS (rc=$RC, expected 0)" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (9) waiver-honored: FAIL (rc=$RC, expected 0)" >&2
    cat "$TMPROOT/s9/stderr.txt" >&2
    FAILED=$((FAILED+1))
  fi

  # (10) waiver-stale-rejected: same valid waiver but backdated >1h → BLOCK
  RC=$(_run_waiver_scenario s10 "$W9_BODY" 1)
  if [[ "$RC" == "1" ]]; then
    echo "self-test (10) waiver-stale-rejected: PASS (rc=$RC, expected 1)" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (10) waiver-stale-rejected: FAIL (rc=$RC, expected 1)" >&2
    FAILED=$((FAILED+1))
  fi

  # (11) regression (pin f): non-empty waiver without purpose-clause pair
  # does NOT open the valve → BLOCK
  RC=$(_run_waiver_scenario s11 "just trust me on this one" 0)
  if [[ "$RC" == "1" ]]; then
    echo "self-test (11) weak-waiver-no-purpose-clauses: PASS (rc=$RC, expected 1)" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (11) weak-waiver-no-purpose-clauses: FAIL (rc=$RC, expected 1)" >&2
    FAILED=$((FAILED+1))
  fi

  echo "" >&2
  echo "self-test summary: $PASSED passed, $FAILED failed (of 11 scenarios)" >&2
  if [[ "$FAILED" -eq 0 ]]; then
    exit 0
  else
    exit 1
  fi
fi

# ============================================================
# Main hook logic
# ============================================================

# --- Read tool input (env var OR stdin) ---
INPUT="${CLAUDE_TOOL_INPUT:-}"
if [[ -z "$INPUT" ]] && [[ ! -t 0 ]]; then
  INPUT=$(cat 2>/dev/null || echo "")
fi
if [[ -z "$INPUT" ]]; then
  exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
  # Without jq we can't safely parse — pass through (errs toward allow).
  exit 0
fi

# Tool name must be Edit, Write, or MultiEdit
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null)
case "$TOOL_NAME" in
  Edit|Write|MultiEdit) ;;
  *) exit 0 ;;
esac

# Extract file_path
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .file_path // ""' 2>/dev/null)
if [[ -z "$FILE_PATH" ]]; then
  exit 0
fi

# Self-bypass: any docs/plans/*.md edit is allowed (plans must edit themselves)
if _is_plan_file "$FILE_PATH"; then
  echo "[spec-freeze] file=$FILE_PATH verdict=ALLOW (plan-file self-bypass)" >&2
  exit 0
fi

# --- Locate repo root ---
FILE_DIR=$(dirname "$FILE_PATH" 2>/dev/null || echo "")
REPO_ROOT=""
if command -v git >/dev/null 2>&1; then
  REPO_ROOT=$(cd "$FILE_DIR" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null || echo "")
fi
if [[ -z "$REPO_ROOT" ]]; then
  REPO_ROOT=$(_find_repo_root "$FILE_DIR" 2>/dev/null || echo "")
fi
if [[ -z "$REPO_ROOT" ]]; then
  # No repo context — pass through.
  exit 0
fi

if [[ ! -d "$REPO_ROOT/docs/plans" ]]; then
  # No plans directory — nothing to gate against.
  exit 0
fi

# Normalize target to repo-relative
TARGET_REL=$(_to_repo_relative "$FILE_PATH" "$REPO_ROOT")
if [[ -z "$TARGET_REL" ]]; then
  exit 0
fi

# --- Iterate ACTIVE plans, find the ones claiming this file ---
declare -a CLAIMING_PLANS=()
declare -a UNFROZEN_CLAIMERS=()

for plan in "$REPO_ROOT"/docs/plans/*.md; do
  [[ -f "$plan" ]] || continue
  # Status check
  status=$(_extract_status "$plan" 2>/dev/null || echo "")
  if [[ "$status" != "ACTIVE" ]]; then
    continue
  fi

  # Does this plan claim the target file? (Degrades to "no" on parse error.)
  if ! _plan_claims_file "$plan" "$TARGET_REL" 2>/dev/null; then
    continue
  fi

  CLAIMING_PLANS+=("$plan")
  frozen=$(_extract_frozen "$plan" 2>/dev/null || echo "")
  if [[ "$frozen" != "true" ]]; then
    UNFROZEN_CLAIMERS+=("$plan")
  fi
done

NUM_CLAIMERS=${#CLAIMING_PLANS[@]}

# --- Decide ---
if [[ "$NUM_CLAIMERS" -eq 0 ]]; then
  echo "[spec-freeze] file=$TARGET_REL matched-plans=0 verdict=ALLOW (no claiming plan)" >&2
  exit 0
fi

NUM_UNFROZEN=${#UNFROZEN_CLAIMERS[@]}

if [[ "$NUM_UNFROZEN" -eq 0 ]]; then
  echo "[spec-freeze] file=$TARGET_REL matched-plans=$NUM_CLAIMERS verdict=ALLOW (all frozen)" >&2
  exit 0
fi

# --- Block: emit message ---
PRIMARY_UNFROZEN="${UNFROZEN_CLAIMERS[0]}"
PRIMARY_SLUG=$(_plan_slug "$PRIMARY_UNFROZEN")
OTHER_COUNT=$((NUM_UNFROZEN - 1))

# --- Waiver release valve (F.5 audit row 27 / ADR 059 D4 fix). Checked
# against EVERY unfrozen claiming plan's slug (not just the primary) so a
# waiver scoped to the actually-relevant plan is honored even when a
# different plan happens to sort first. ---
SFG_WAIVER_FILE=""
SFG_WAIVER_PLAN=""
for _sfg_plan in "${UNFROZEN_CLAIMERS[@]}"; do
  _sfg_slug=$(_plan_slug "$_sfg_plan")
  if SFG_WAIVER_FILE=$(_sfg_has_fresh_waiver "$_sfg_slug"); then
    SFG_WAIVER_PLAN="$_sfg_slug"
    break
  fi
done
if [[ -n "$SFG_WAIVER_FILE" ]]; then
  command -v ledger_emit >/dev/null 2>&1 && ledger_emit "spec-freeze-gate" "waiver" "plan=$SFG_WAIVER_PLAN file=$TARGET_REL waiver=$SFG_WAIVER_FILE"
  echo "[spec-freeze] ALLOW: fresh substantive spec-freeze-waiver present for plan '$SFG_WAIVER_PLAN' (release valve) — file=$TARGET_REL" >&2
  exit 0
fi

{
  echo "================================================================"
  echo "SPEC-FREEZE GATE — FILE EDIT BLOCKED"
  echo "================================================================"
  echo ""
  echo "[spec-freeze] BLOCKED — file '$TARGET_REL' is declared in plan"
  echo "'$PRIMARY_SLUG'$([ "$OTHER_COUNT" -gt 0 ] && echo " (and $OTHER_COUNT others)") whose spec is not frozen."
  echo "Either flip 'frozen: true' in $PRIMARY_SLUG's header (after a final"
  echo "spec review), OR move the file out of that plan's"
  echo "'## Files to Modify/Create' list."
  echo ""
  echo "See ~/.claude/doctrine/spec-freeze.md for the freeze-thaw protocol."
  echo ""
  echo "Unfrozen plans claiming this file:"
  for p in "${UNFROZEN_CLAIMERS[@]}"; do
    rel="${p#$REPO_ROOT/}"
    echo "  • $(_plan_slug "$p")  ($rel)"
  done
  if [[ "$NUM_CLAIMERS" -gt "$NUM_UNFROZEN" ]]; then
    echo ""
    echo "Frozen plans also claiming this file (already OK):"
    for p in "${CLAIMING_PLANS[@]}"; do
      frozen=$(_extract_frozen "$p" 2>/dev/null || echo "")
      if [[ "$frozen" == "true" ]]; then
        rel="${p#$REPO_ROOT/}"
        echo "  • $(_plan_slug "$p")  ($rel)"
      fi
    done
  fi
  echo ""
  echo "Hatch (cost: allows edits to THIS file under THIS plan's freeze,"
  echo "until the waiver expires in <1h, ledger-logged — does NOT flip"
  echo "frozen: true, so the block returns on the next call unless you also"
  echo "unfreeze or the waiver is renewed):"
  echo "  A genuine, time-boxed, substantive need to touch a frozen plan's"
  echo "  file WITHOUT formally unfreezing it gets a fresh (<1h) structured"
  echo "  waiver naming BOTH purpose clauses:"
  echo "    mkdir -p .claude/state && \\"
  echo "    { printf 'Purpose: this gate exists to prevent <X>\\n'; \\"
  echo "      printf 'Because: <Y>\\n'; \\"
  echo "    } > .claude/state/spec-freeze-waiver-${PRIMARY_SLUG}-\$(date +%s).txt"
  echo "  Re-run the edit after writing the waiver."
  echo ""
  echo "Durable remedy: edit the plan to flip frozen, OR temporarily"
  echo "use a non-Edit/Write tool (per ~/.claude/doctrine/git.md)."
  echo ""
  echo "NOTE: this block prevented the ENTIRE command from running — including any"
  echo "fix/edit/\`git add\` prefix before the \`git commit\`. Nothing was executed."
  echo "Re-run the non-commit part as its own call first, then commit separately."
  echo "================================================================"
} >&2

exit 1
