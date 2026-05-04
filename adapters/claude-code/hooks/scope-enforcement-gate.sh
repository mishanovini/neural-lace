#!/bin/bash
# scope-enforcement-gate.sh — Phase 1d-C-1 (C10)
#
# PreToolUse hook that blocks `git commit` when staged files fall outside
# the active plan's `## Files to Modify/Create` section.
#
# Rule (mechanism): every commit on a plan-governed feature branch must
# stage only files declared in scope. Out-of-scope commits silently expand
# work beyond the plan; this hook surfaces them at commit time and forces
# either a scope amendment or a per-plan waiver.
#
# Trigger:
#   PreToolUse on tool_name == "Bash". Strips leading `cd …` and `&&`
#   chains; matches `git commit` as the next token. Pass-through on
#   non-Bash tool calls and non-commit Bash commands.
#
# Active-plan discovery:
#   Iterates docs/plans/*.md (top-level only — excludes archive/). For
#   each, reads first ~50 lines for `Status: ACTIVE`. If no active plan,
#   pass through (gate doesn't apply when no plan governs the work).
#
# Files-to-modify parsing:
#   Locates `## Files to Modify/Create` heading in each active plan,
#   reads until next `## ` heading or EOF. Extracts file paths from
#   bullet lines (`- ` or `* `). Supports backticked paths (`- \`path\` —
#   description`) and plain paths.
#
# Diff comparison:
#   `git diff --cached --name-only --diff-filter=ACMRD` for staged files.
#   For each, check exact match, glob match (`**`, `*`, `?`), or
#   directory-prefix match (bullet ending in `/`).
#
# Multiple active plans:
#   Required behavior is intersection — a file in scope of plan A but not
#   plan B is out of scope. The error message names which plan rejects
#   which file.
#
# Waiver:
#   .claude/state/scope-waiver-<plan-slug>-*.txt younger than 1 hour with
#   ≥1 non-whitespace line of justification. If present, allow with a
#   stderr warning.
#
# Exit codes:
#   0 — commit allowed (or non-applicable)
#   2 — commit blocked (stderr explains why; JSON {decision: block} on stdout)

# NOTE: `set -u` is intentionally NOT enabled. Bash associative arrays
# under set -u throw "unbound variable" on `${#arr[@]}` and `${!arr[*]}`
# even when declared (a known quirk). The hook handles its own undefined
# states explicitly.

# ============================================================
# --self-test handler (eight scenarios)
# ============================================================
if [[ "${1:-}" == "--self-test" ]]; then
  # We need this script's path for re-invocation under different cwds
  SELF_TEST_HOOK="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)/$(basename "${BASH_SOURCE[0]}")"
  if [[ ! -f "$SELF_TEST_HOOK" ]]; then
    echo "self-test: cannot resolve own path" >&2
    exit 2
  fi

  PASSED=0
  FAILED=0
  TMPROOT=$(mktemp -d 2>/dev/null || mktemp -d -t scope-enforce)
  if [[ -z "$TMPROOT" ]] || [[ ! -d "$TMPROOT" ]]; then
    echo "self-test: cannot create temp directory" >&2
    exit 2
  fi
  trap 'rm -rf "$TMPROOT"' EXIT

  # Helper: build a fresh git repo with a plan + staged files, then
  # invoke the hook against synthesized stdin JSON. Returns hook's
  # exit code.
  #
  # Args: $1 = scenario label
  #       $2 = plan content (full markdown body)
  #       $3 = comma-separated staged file paths (each will be created
  #            empty and `git add`-ed)
  #       $4 = optional waiver content (if non-empty, write to
  #            .claude/state/scope-waiver-<slug>-<ts>.txt)
  _run_scenario() {
    local label="$1" plan_body="$2" staged_csv="$3" waiver_body="${4:-}"
    local repo="$TMPROOT/$label"
    mkdir -p "$repo"
    (
      cd "$repo" || exit 99
      git init -q 2>/dev/null || true
      git config user.email "test@example.com" 2>/dev/null
      git config user.name "Test" 2>/dev/null
      git config commit.gpgsign false 2>/dev/null
      mkdir -p docs/plans
      printf '%s' "$plan_body" > "docs/plans/test-scope-plan.md"
      git add docs/plans/test-scope-plan.md 2>/dev/null
      git commit -q -m "init plan" 2>/dev/null

      IFS=',' read -ra STAGED <<< "$staged_csv"
      for f in "${STAGED[@]}"; do
        [[ -z "$f" ]] && continue
        mkdir -p "$(dirname "$f")" 2>/dev/null
        echo "stub" > "$f"
        git add "$f" 2>/dev/null
      done

      if [[ -n "$waiver_body" ]]; then
        mkdir -p .claude/state
        local ts
        ts=$(date +%Y-%m-%d-%H%M%S)
        printf '%s\n' "$waiver_body" > ".claude/state/scope-waiver-test-scope-plan-$ts.txt"
      fi

      local input='{"tool_name":"Bash","tool_input":{"command":"git commit -m \"test\""}}'
      printf '%s' "$input" | bash "$SELF_TEST_HOOK" >/dev/null 2>&1
      echo $? > rc.txt
    )
    cat "$repo/rc.txt" 2>/dev/null || echo 99
  }

  # Standard plan body templates
  PLAN_NORMAL='# Plan: test
Status: ACTIVE

## Goal
Test goal.

## Files to Modify/Create
- `src/foo.ts` — primary file
- `src/bar.ts` — secondary file
- `src/lib/*.ts` — glob match for any lib file

## Tasks
- [ ] 1. test
'

  PLAN_NO_SCOPE='# Plan: test
Status: ACTIVE

## Goal
Test.

## Tasks
- [ ] 1. test
'

  PLAN_EMPTY_SCOPE='# Plan: test
Status: ACTIVE

## Goal
Test.

## Files to Modify/Create
- [populate me]

## Tasks
- [ ] 1. test
'

  # ---- Scenario 1: PASS — all staged files in plan's scope ----
  RC=$(_run_scenario s1 "$PLAN_NORMAL" "src/foo.ts,src/bar.ts")
  if [[ "$RC" == "0" ]]; then
    echo "self-test (1) all-files-in-scope: PASS" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (1) all-files-in-scope: FAIL (rc=$RC, expected 0)" >&2
    FAILED=$((FAILED+1))
  fi

  # ---- Scenario 2: PASS — waiver present, substantive ----
  WAIVER='Waiver: refactor required emergency hot-fix; out-of-scope file is a test seed.'
  RC=$(_run_scenario s2 "$PLAN_NORMAL" "src/foo.ts,unrelated/file.ts" "$WAIVER")
  if [[ "$RC" == "0" ]]; then
    echo "self-test (2) waiver-present: PASS" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (2) waiver-present: FAIL (rc=$RC, expected 0)" >&2
    FAILED=$((FAILED+1))
  fi

  # ---- Scenario 3: FAIL — one file out of scope, no waiver ----
  RC=$(_run_scenario s3 "$PLAN_NORMAL" "src/foo.ts,unrelated/file.ts")
  if [[ "$RC" == "2" ]]; then
    echo "self-test (3) one-file-out-of-scope: PASS (correctly blocked)" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (3) one-file-out-of-scope: FAIL (rc=$RC, expected 2)" >&2
    FAILED=$((FAILED+1))
  fi

  # ---- Scenario 4: FAIL — multiple files out of scope ----
  RC=$(_run_scenario s4 "$PLAN_NORMAL" "src/foo.ts,unrelated/file.ts,other/thing.ts")
  if [[ "$RC" == "2" ]]; then
    echo "self-test (4) multiple-files-out-of-scope: PASS (correctly blocked)" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (4) multiple-files-out-of-scope: FAIL (rc=$RC, expected 2)" >&2
    FAILED=$((FAILED+1))
  fi

  # ---- Scenario 5: FAIL — plan has no Files-to-Modify section ----
  RC=$(_run_scenario s5 "$PLAN_NO_SCOPE" "src/foo.ts")
  if [[ "$RC" == "2" ]]; then
    echo "self-test (5) plan-missing-scope-section: PASS (correctly blocked)" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (5) plan-missing-scope-section: FAIL (rc=$RC, expected 2)" >&2
    FAILED=$((FAILED+1))
  fi

  # ---- Scenario 6: FAIL — plan scope is placeholder-only ----
  RC=$(_run_scenario s6 "$PLAN_EMPTY_SCOPE" "src/foo.ts")
  if [[ "$RC" == "2" ]]; then
    echo "self-test (6) plan-scope-placeholder-only: PASS (correctly blocked)" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (6) plan-scope-placeholder-only: FAIL (rc=$RC, expected 2)" >&2
    FAILED=$((FAILED+1))
  fi

  # ---- Scenario 7: PASS — glob pattern in plan matches staged file ----
  RC=$(_run_scenario s7 "$PLAN_NORMAL" "src/foo.ts,src/lib/util.ts")
  if [[ "$RC" == "0" ]]; then
    echo "self-test (7) glob-pattern-match: PASS" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (7) glob-pattern-match: FAIL (rc=$RC, expected 0)" >&2
    FAILED=$((FAILED+1))
  fi

  # ---- Scenario 8: FAIL — glob pattern doesn't match outside dir ----
  RC=$(_run_scenario s8 "$PLAN_NORMAL" "src/foo.ts,src/lib/sub/deep.ts")
  # Plan has `src/lib/*.ts` (single-level glob); `src/lib/sub/deep.ts`
  # should NOT match.
  if [[ "$RC" == "2" ]]; then
    echo "self-test (8) glob-pattern-non-match: PASS (correctly blocked)" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (8) glob-pattern-non-match: FAIL (rc=$RC, expected 2)" >&2
    FAILED=$((FAILED+1))
  fi

  echo "" >&2
  echo "self-test summary: $PASSED passed, $FAILED failed (of 8 scenarios)" >&2
  if [[ "$FAILED" -eq 0 ]]; then
    exit 0
  else
    exit 1
  fi
fi

# ============================================================
# Main hook logic
# ============================================================

# --- Read tool input (env var OR stdin, supporting both Claude Code shapes) ---
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

# Tool name must be Bash (support nested + flat shapes)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null)
if [[ "$TOOL_NAME" != "Bash" ]]; then
  exit 0
fi

# Extract command (nested .tool_input.command preferred; flat .command fallback)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // .command // ""' 2>/dev/null)
if [[ -z "$CMD" ]]; then
  exit 0
fi

# --- Detect git commit (after stripping leading `cd …` and `&&`-prefixed blocks) ---
#
# Strategy: split on `&&`, scan each segment, trim leading whitespace +
# leading `cd …;` clauses, then check if the segment starts with
# `git commit`. Skip pure `git commit --help`/`-h` invocations and
# `git commit-tree`/`commit-graph` (different commands sharing a prefix).
IS_GIT_COMMIT=0
# Split CMD on `&&` and `;` to walk each chained command
# Use awk-like splitting that handles spaces around the operators
TMP_CMD="$CMD"
# Normalize separator characters: replace `&&` and `;` with newlines
TMP_CMD=$(echo "$TMP_CMD" | sed -e 's/&&/\n/g' -e 's/;/\n/g')
while IFS= read -r seg; do
  # Trim leading/trailing whitespace
  seg="${seg#"${seg%%[![:space:]]*}"}"
  seg="${seg%"${seg##*[![:space:]]}"}"
  [[ -z "$seg" ]] && continue
  # Skip pure cd segments (they're just navigation, not the actual command)
  if [[ "$seg" =~ ^cd[[:space:]] ]] || [[ "$seg" == "cd" ]]; then
    continue
  fi
  # Match git commit (allowing for surrounding whitespace and any args).
  # Reject git commit-tree / git commit-graph (different commands).
  if [[ "$seg" =~ ^git[[:space:]]+commit($|[[:space:]]+) ]]; then
    # Confirm it's not "commit-tree" or "commit-graph" (won't match the
    # regex above thanks to the trailing constraint, but double-check)
    if [[ ! "$seg" =~ ^git[[:space:]]+commit-(tree|graph) ]]; then
      IS_GIT_COMMIT=1
      break
    fi
  fi
done <<< "$TMP_CMD"

if [[ "$IS_GIT_COMMIT" -eq 0 ]]; then
  exit 0
fi

# --- Locate repo root (where docs/plans/ lives) ---
# Prefer git rev-parse; fall back to walking up from cwd.
REPO_ROOT=""
if command -v git >/dev/null 2>&1; then
  REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
fi
if [[ -z "$REPO_ROOT" ]]; then
  CURRENT="$PWD"
  while [[ -n "$CURRENT" ]] && [[ "$CURRENT" != "/" ]]; do
    if [[ -d "$CURRENT/.git" ]] || [[ -d "$CURRENT/docs/plans" ]]; then
      REPO_ROOT="$CURRENT"
      break
    fi
    PARENT=$(dirname "$CURRENT")
    [[ "$PARENT" == "$CURRENT" ]] && break
    CURRENT="$PARENT"
  done
fi

if [[ -z "$REPO_ROOT" ]] || [[ ! -d "$REPO_ROOT/docs/plans" ]]; then
  # No plans directory — gate doesn't apply
  exit 0
fi

# --- Find active plans (Status: ACTIVE in top-level docs/plans/, exclude archive/) ---
ACTIVE_PLANS=()
for plan in "$REPO_ROOT"/docs/plans/*.md; do
  [[ -f "$plan" ]] || continue
  # Read header (first ~50 lines) and look for `Status: ACTIVE`
  if head -50 "$plan" 2>/dev/null | grep -qE '^Status:[[:space:]]*ACTIVE[[:space:]]*$'; then
    ACTIVE_PLANS+=("$plan")
  fi
done

if [[ "${#ACTIVE_PLANS[@]}" -eq 0 ]]; then
  # No active plan governs this work — gate doesn't apply
  exit 0
fi

# --- Get staged files ---
STAGED=()
if command -v git >/dev/null 2>&1; then
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    STAGED+=("$f")
  done < <(git -C "$REPO_ROOT" diff --cached --name-only --diff-filter=ACMRD 2>/dev/null)
fi

if [[ "${#STAGED[@]}" -eq 0 ]]; then
  # Nothing staged — let git itself complain; we don't gate
  exit 0
fi

# --- Helper: extract scope entries from a plan file ---
# Sets globals: PLAN_SCOPE_ENTRIES (array of paths/globs)
#              PLAN_SCOPE_RAWLEN (chars of non-whitespace content in section)
#              PLAN_SCOPE_FOUND (1 if heading present, 0 otherwise)
extract_scope_entries() {
  local plan_file="$1"
  PLAN_SCOPE_ENTRIES=()
  PLAN_SCOPE_RAWLEN=0
  PLAN_SCOPE_FOUND=0

  # Use awk to extract the section body
  local section_body
  section_body=$(awk '
    BEGIN { in_section = 0; }
    /^## Files to Modify\/Create[[:space:]]*$/ { in_section = 1; next }
    /^## / { if (in_section) { in_section = 0; exit } }
    in_section { print }
  ' "$plan_file" 2>/dev/null)

  # Heading absent => the awk above never set in_section=1, so body is empty
  # Detect the heading explicitly
  if grep -qE '^## Files to Modify/Create[[:space:]]*$' "$plan_file" 2>/dev/null; then
    PLAN_SCOPE_FOUND=1
  fi

  # Compute non-whitespace content length to detect placeholder-only
  PLAN_SCOPE_RAWLEN=$(echo "$section_body" | tr -d '[:space:]' | wc -c | tr -d '[:space:]')

  # Extract bullet paths from each `- ` or `* ` line.
  while IFS= read -r line; do
    # Trim leading whitespace
    line="${line#"${line%%[![:space:]]*}"}"
    [[ -z "$line" ]] && continue
    # Must start with bullet
    case "$line" in
      "- "*|"* "*) ;;
      *) continue ;;
    esac
    # Strip the bullet
    line="${line:2}"
    # Skip placeholder bullets
    case "$line" in
      "[populate me]"*|"[TODO]"*|"TODO"*|"..."*) continue ;;
    esac

    local extracted=""
    # Try backticked path first: `path` — description
    if [[ "$line" == *'`'* ]]; then
      # Find first backtick-delimited token
      local tmp="${line#*\`}"
      extracted="${tmp%%\`*}"
    else
      # Plain path: take the first token until whitespace or em-dash
      # (em-dash forms: "—", " - ", " -- ", "  ")
      # Take everything up to first " — " or " - " or " -- " or end
      extracted="$line"
      extracted="${extracted%% — *}"
      extracted="${extracted%% -- *}"
      extracted="${extracted%% - *}"
      # Trim trailing whitespace
      extracted="${extracted%"${extracted##*[![:space:]]}"}"
      # Bail on whitespace inside (suggests prose, not a path)
      if [[ "$extracted" == *" "* ]]; then
        continue
      fi
    fi

    [[ -z "$extracted" ]] && continue
    # Filter out obvious non-path content (e.g., bare descriptions caught by
    # accident). A path will contain `/` or `.` or end with `/`.
    if [[ "$extracted" != */* ]] && [[ "$extracted" != *.* ]]; then
      continue
    fi

    PLAN_SCOPE_ENTRIES+=("$extracted")
  done <<< "$section_body"
}

# --- Helper: convert a glob pattern to an anchored regex. ---
# Per-char loop avoids the bash-quoting nightmare of nested ${//} substitutions.
# Supports `**` (recursive), `*` (single level, no `/`), `?` (single char no `/`).
# Escapes regex specials: . + ( ) { } [ ] ^ $ | \
glob_to_regex() {
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

# --- Helper: glob match. $1 = pattern, $2 = path. Returns 0 on match. ---
#
# Supports:
#   - exact match
#   - directory prefix (pattern ends with `/`)
#   - `**` (recursive) and `*` (single level) and `?` (single char)
glob_match() {
  local pat="$1" path="$2"

  # Exact match
  if [[ "$pat" == "$path" ]]; then
    return 0
  fi

  # Directory prefix (pattern ends with /)
  if [[ "${pat: -1}" == "/" ]]; then
    if [[ "$path" == "$pat"* ]]; then
      return 0
    fi
    return 1
  fi

  # If pattern has no glob metacharacters and didn't exact-match, fail.
  if [[ "$pat" != *'*'* ]] && [[ "$pat" != *'?'* ]]; then
    return 1
  fi

  local re
  re=$(glob_to_regex "$pat")

  # Anchor and test
  if [[ "$path" =~ ^${re}$ ]]; then
    return 0
  fi
  return 1
}

# --- Helper: derive plan slug from path (filename without .md) ---
plan_slug() {
  local p="$1"
  local b
  b=$(basename "$p")
  echo "${b%.md}"
}

# --- Process each active plan: parse scope, intersect with staged ---
#
# Tracking:
#   OOS_BY_PLAN — for each plan, which staged files are out of scope
#   PLAN_ERRORS — structural issues per plan (no scope section, empty)

declare -a PLAN_ERRORS=()
# Map (plan-index -> oos files joined by '|')
OOS_FILES_PER_PLAN=()

for plan in "${ACTIVE_PLANS[@]}"; do
  extract_scope_entries "$plan"
  slug=$(plan_slug "$plan")

  if [[ "$PLAN_SCOPE_FOUND" -eq 0 ]]; then
    PLAN_ERRORS+=("$slug:NO_SCOPE_SECTION:$plan")
    OOS_FILES_PER_PLAN+=("__STRUCTURAL__")
    continue
  fi

  if [[ "$PLAN_SCOPE_RAWLEN" -lt 20 ]]; then
    PLAN_ERRORS+=("$slug:EMPTY_SCOPE:$plan")
    OOS_FILES_PER_PLAN+=("__STRUCTURAL__")
    continue
  fi

  if [[ "${#PLAN_SCOPE_ENTRIES[@]}" -eq 0 ]]; then
    # Heading present, content present, but no parseable bullet entries
    PLAN_ERRORS+=("$slug:NO_PARSEABLE_ENTRIES:$plan")
    OOS_FILES_PER_PLAN+=("__STRUCTURAL__")
    continue
  fi

  # For each staged file, check if it matches any scope entry
  oos_for_this_plan=""
  for sf in "${STAGED[@]}"; do
    matched=0
    for entry in "${PLAN_SCOPE_ENTRIES[@]}"; do
      if glob_match "$entry" "$sf"; then
        matched=1
        break
      fi
    done
    if [[ "$matched" -eq 0 ]]; then
      if [[ -z "$oos_for_this_plan" ]]; then
        oos_for_this_plan="$sf"
      else
        oos_for_this_plan="$oos_for_this_plan|$sf"
      fi
    fi
  done
  OOS_FILES_PER_PLAN+=("$oos_for_this_plan")
done

# --- Aggregate: a file is out of scope iff EVERY active plan rejects it ---
# (intersection: file allowed if ANY active plan covers it)
declare -A FINAL_OOS

# If any plan has a structural error, that plan can't authorize anything.
# Set: a file is out-of-scope iff for EVERY plan, the file appears in that
# plan's OOS list (or the plan has a structural error, in which case it
# trivially rejects the file).
NUM_PLANS="${#ACTIVE_PLANS[@]}"
for sf in "${STAGED[@]}"; do
  # Count plans that reject this file
  reject_count=0
  rejecting_plans=""
  for ((i=0; i<NUM_PLANS; i++)); do
    plan="${ACTIVE_PLANS[$i]}"
    oos_list="${OOS_FILES_PER_PLAN[$i]}"
    slug=$(plan_slug "$plan")
    if [[ "$oos_list" == "__STRUCTURAL__" ]]; then
      reject_count=$((reject_count+1))
      rejecting_plans="$rejecting_plans $slug"
      continue
    fi
    # Check if sf is in the |-joined list (with explicit boundaries)
    case "|$oos_list|" in
      *"|$sf|"*)
        reject_count=$((reject_count+1))
        rejecting_plans="$rejecting_plans $slug"
        ;;
    esac
  done
  if [[ "$reject_count" -eq "$NUM_PLANS" ]]; then
    FINAL_OOS["$sf"]="$rejecting_plans"
  fi
done

# --- Check waivers (one per plan, 1-hour window, ≥1 non-whitespace line) ---
# A file is allowed if ANY active plan has a fresh substantive waiver.
WAIVER_ACTIVE_PLANS=""
WAIVER_DIR="$REPO_ROOT/.claude/state"

if [[ -d "$WAIVER_DIR" ]]; then
  for plan in "${ACTIVE_PLANS[@]}"; do
    slug=$(plan_slug "$plan")
    # Find waiver files for this plan younger than 1 hour
    while IFS= read -r waiver_file; do
      [[ -z "$waiver_file" ]] && continue
      # Substantive: at least 1 non-whitespace line
      if [[ -n $(grep -E '[^[:space:]]' "$waiver_file" 2>/dev/null | head -1) ]]; then
        WAIVER_ACTIVE_PLANS="$WAIVER_ACTIVE_PLANS $slug"
        break
      fi
    done < <(find "$WAIVER_DIR" -maxdepth 1 -type f -name "scope-waiver-${slug}-*.txt" -newermt '1 hour ago' 2>/dev/null)
  done
fi

# --- Decision ---
if [[ "${#FINAL_OOS[@]}" -eq 0 ]] && [[ "${#PLAN_ERRORS[@]}" -eq 0 ]]; then
  # All files in scope; no structural errors
  exit 0
fi

# If we have a waiver covering at least one active plan AND no structural
# errors, allow with warning. (Structural errors must be fixed; waivers
# don't paper over a missing scope section.)
if [[ -n "$WAIVER_ACTIVE_PLANS" ]] && [[ "${#PLAN_ERRORS[@]}" -eq 0 ]]; then
  echo "" >&2
  echo "[scope-enforcement-gate] WARNING: out-of-scope files staged, but waiver present for plan(s):${WAIVER_ACTIVE_PLANS}" >&2
  echo "[scope-enforcement-gate] Out-of-scope files: ${!FINAL_OOS[*]}" >&2
  echo "[scope-enforcement-gate] Allowed via waiver. Audit the waiver file(s) under .claude/state/ at next /harness-review." >&2
  echo "" >&2
  exit 0
fi

# --- Block: emit structured stderr message + JSON decision ---
{
  echo "================================================================"
  echo "SCOPE ENFORCEMENT GATE — COMMIT BLOCKED"
  echo "================================================================"
  echo ""
  echo "This commit stages files outside the active plan's declared scope."
  echo "Plans active in this repo:"
  for plan in "${ACTIVE_PLANS[@]}"; do
    rel="${plan#$REPO_ROOT/}"
    echo "  • $rel"
  done
  echo ""
  if [[ "${#PLAN_ERRORS[@]}" -gt 0 ]]; then
    echo "Plan structural errors (must be fixed before any commit):"
    for err in "${PLAN_ERRORS[@]}"; do
      slug="${err%%:*}"
      rest="${err#*:}"
      kind="${rest%%:*}"
      path="${rest#*:}"
      relpath="${path#$REPO_ROOT/}"
      case "$kind" in
        NO_SCOPE_SECTION)
          echo "  • $slug: missing '## Files to Modify/Create' section"
          echo "    Plan: $relpath"
          echo "    Fix: add the section listing every file the plan touches."
          ;;
        EMPTY_SCOPE)
          echo "  • $slug: '## Files to Modify/Create' section is empty / placeholder-only"
          echo "    Plan: $relpath"
          echo "    Fix: replace placeholders with real bullet entries."
          ;;
        NO_PARSEABLE_ENTRIES)
          echo "  • $slug: '## Files to Modify/Create' has content but no parseable bullets"
          echo "    Plan: $relpath"
          echo "    Fix: each entry should be a bullet (- or *) with a path (backticked or plain)."
          ;;
      esac
    done
    echo ""
  fi
  if [[ "${#FINAL_OOS[@]}" -gt 0 ]]; then
    echo "Out-of-scope staged files:"
    for f in "${!FINAL_OOS[@]}"; do
      echo "  • $f"
      rejected_by="${FINAL_OOS[$f]}"
      if [[ -n "$rejected_by" ]]; then
        echo "    Rejected by plan(s):${rejected_by}"
      fi
    done
    echo ""
  fi
  echo "To unblock, choose ONE:"
  echo ""
  echo "  1. Add the file(s) to the plan's '## Files to Modify/Create' section."
  echo "     This is the right answer if the work is genuinely in scope and"
  echo "     the plan should reflect it."
  echo ""
  echo "  2. Unstage the out-of-scope files:"
  for f in "${!FINAL_OOS[@]}"; do
    echo "       git restore --staged \"$f\""
  done
  echo ""
  echo "  3. Write a per-plan waiver if this is intentional out-of-scope work"
  echo "     (e.g., touching an unrelated bug as a drive-by). Path pattern:"
  echo "       .claude/state/scope-waiver-<plan-slug>-<timestamp>.txt"
  echo "     Example for the first active plan:"
  for plan in "${ACTIVE_PLANS[@]}"; do
    slug=$(plan_slug "$plan")
    ts=$(date +%Y-%m-%d-%H%M%S 2>/dev/null || echo "TIMESTAMP")
    echo "       echo 'reason: <one-line justification>' > .claude/state/scope-waiver-${slug}-${ts}.txt"
    break
  done
  echo "     The waiver must be ≤ 1 hour old and contain ≥ 1 non-whitespace line."
  echo ""
  echo "Why this gate exists: out-of-scope commits silently expand work beyond"
  echo "the plan, eroding the scope discipline that makes plans verifiable."
  echo "See ~/.claude/rules/planning.md and ~/.claude/rules/vaporware-prevention.md."
  echo "================================================================"
} >&2

# JSON decision for Claude Code
cat <<'JSON'
{"decision": "block", "reason": "scope-enforcement-gate: staged files fall outside active plan's '## Files to Modify/Create' scope and no waiver is present. See stderr for details and unblock options."}
JSON

exit 2
