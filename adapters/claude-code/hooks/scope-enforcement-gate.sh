#!/bin/bash
# scope-enforcement-gate.sh — Phase 1d-C-1 (C10), 2026-05-04 second-pass redesign
#
# PreToolUse hook that blocks `git commit` when staged files fall outside
# the active plan's declared scope.
#
# Rule (mechanism): every commit on a plan-governed feature branch must
# stage only files declared in scope. Out-of-scope commits silently expand
# work beyond the plan; this hook surfaces them at commit time and forces
# either a scope amendment, a new plan to claim the work, or a deferral.
#
# Trigger:
#   PreToolUse on tool_name == "Bash". Strips leading `cd …` and `&&`
#   chains; matches `git commit` as the next token. Pass-through on
#   non-Bash tool calls and non-commit Bash commands.
#
# System-managed-path allowlist (2026-05-04):
#   `docs/plans/archive/*` and `docs/plans/archive/*-evidence.md` are
#   exempt — these files are moved by `plan-lifecycle.sh` on Status:
#   COMPLETED/DEFERRED/ABANDONED/SUPERSEDED transitions, not by builder
#   plan work. If ALL staged files are system-managed, allow the commit
#   unconditionally with a brief stderr note. If a mix, do the normal
#   scope-check on the non-system files only.
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
#   description`) and plain paths. ALSO parses the optional
#   `## In-flight scope updates` section (format:
#   `- <YYYY-MM-DD>: <path> — <reason>`); a file matching either
#   section is in-scope. Backward compatible — plans without the
#   in-flight section continue to work as before.
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
# Waivers:
#   REMOVED 2026-05-04. The block-message no longer offers a waiver
#   path. Three structural options (update plan / open new plan / defer)
#   cover every legitimate case. Emergency override is `git commit
#   --no-verify` per ~/.claude/rules/git.md.
#
# Exit codes:
#   0 — commit allowed (or non-applicable)
#   2 — commit blocked (stderr explains why; JSON {decision: block} on stdout)

# NOTE: `set -u` is intentionally NOT enabled. Bash associative arrays
# under set -u throw "unbound variable" on `${#arr[@]}` and `${!arr[*]}`
# even when declared (a known quirk). The hook handles its own undefined
# states explicitly.

# ============================================================
# Helper: is this path system-managed (exempt from scope-check)?
# Returns 0 (true) for docs/plans/archive/* paths.
# ============================================================
_is_system_managed_path() {
  local p="$1"
  case "$p" in
    docs/plans/archive/*) return 0 ;;
    *) return 1 ;;
  esac
}

# ============================================================
# --self-test handler (twelve scenarios)
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
  #       $2 = plan content (full markdown body); empty = no plan
  #       $3 = comma-separated staged file paths (each will be created
  #            empty and `git add`-ed)
  #       $4 = optional secondary plan content (for new-plan-staged scenario)
  _run_scenario() {
    local label="$1" plan_body="$2" staged_csv="$3" secondary_plan_body="${4:-}"
    local repo="$TMPROOT/$label"
    mkdir -p "$repo"
    (
      cd "$repo" || exit 99
      git init -q 2>/dev/null || true
      git config user.email "test@example.com" 2>/dev/null
      git config user.name "Test" 2>/dev/null
      git config commit.gpgsign false 2>/dev/null
      mkdir -p docs/plans
      if [[ -n "$plan_body" ]]; then
        printf '%s' "$plan_body" > "docs/plans/test-scope-plan.md"
        git add docs/plans/test-scope-plan.md 2>/dev/null
        git commit -q -m "init plan" 2>/dev/null
      else
        # No primary plan — create an empty marker commit so the repo has HEAD
        echo "init" > .gitkeep
        git add .gitkeep 2>/dev/null
        git commit -q -m "init repo" 2>/dev/null
      fi

      IFS=',' read -ra STAGED <<< "$staged_csv"
      for f in "${STAGED[@]}"; do
        [[ -z "$f" ]] && continue
        mkdir -p "$(dirname "$f")" 2>/dev/null
        echo "stub" > "$f"
        git add "$f" 2>/dev/null
      done

      # Optional: stage a secondary plan alongside (for the new-plan-claims-scope scenario)
      if [[ -n "$secondary_plan_body" ]]; then
        printf '%s' "$secondary_plan_body" > "docs/plans/hotfix-newplan.md"
        git add "docs/plans/hotfix-newplan.md" 2>/dev/null
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

  # ---- Scenario 2: PASS — system-managed exempt (docs/plans/archive/*) ----
  # All staged files are under docs/plans/archive/ — this is plan-lifecycle
  # archival territory, not builder plan work. Allow regardless of plans.
  RC=$(_run_scenario s2 "$PLAN_NORMAL" "docs/plans/archive/some-old-plan.md,docs/plans/archive/some-old-plan-evidence.md")
  if [[ "$RC" == "0" ]]; then
    echo "self-test (2) system-managed-archive-exempt: PASS" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (2) system-managed-archive-exempt: FAIL (rc=$RC, expected 0)" >&2
    FAILED=$((FAILED+1))
  fi

  # ---- Scenario 3: FAIL — one file out of scope, no waiver path ----
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

  # ---- Scenario 9: PASS — file matches in-flight-scope-updates entry ----
  # Plan has `## Files to Modify/Create` listing `src/foo.ts`, AND
  # `## In-flight scope updates` listing `src/added.ts` with a date prefix.
  # Staging `src/added.ts` should be allowed via the in-flight section.
  PLAN_INFLIGHT='# Plan: test
Status: ACTIVE

## Goal
Test goal.

## Files to Modify/Create
- `src/foo.ts` — primary file

## In-flight scope updates
- 2026-05-04: `src/added.ts` — added during execution because of late-discovered dependency

## Tasks
- [ ] 1. test
'
  RC=$(_run_scenario s9 "$PLAN_INFLIGHT" "src/foo.ts,src/added.ts")
  if [[ "$RC" == "0" ]]; then
    echo "self-test (9) in-flight-scope-update-match: PASS" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (9) in-flight-scope-update-match: FAIL (rc=$RC, expected 0)" >&2
    FAILED=$((FAILED+1))
  fi

  # ---- Scenario 10: PASS — backward-compat: file in primary section, no in-flight section at all ----
  PLAN_NO_INFLIGHT='# Plan: test
Status: ACTIVE

## Goal
Test.

## Files to Modify/Create
- `src/onlyone.ts` — only file

## Tasks
- [ ] 1. test
'
  RC=$(_run_scenario s10 "$PLAN_NO_INFLIGHT" "src/onlyone.ts")
  if [[ "$RC" == "0" ]]; then
    echo "self-test (10) backward-compat-no-inflight-section: PASS" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (10) backward-compat-no-inflight-section: FAIL (rc=$RC, expected 0)" >&2
    FAILED=$((FAILED+1))
  fi

  # ---- Scenario 11: FAIL — file in neither section; verify three-option message has NO waiver string ----
  PLAN_BOTH='# Plan: test
Status: ACTIVE

## Goal
Test.

## Files to Modify/Create
- `src/foo.ts` — primary

## In-flight scope updates
- 2026-05-04: `src/added.ts` — late-add

## Tasks
- [ ] 1. test
'
  S11_REPO="$TMPROOT/s11"
  mkdir -p "$S11_REPO"
  (
    cd "$S11_REPO" || exit 99
    git init -q 2>/dev/null || true
    git config user.email "test@example.com" 2>/dev/null
    git config user.name "Test" 2>/dev/null
    git config commit.gpgsign false 2>/dev/null
    mkdir -p docs/plans
    printf '%s' "$PLAN_BOTH" > "docs/plans/test-scope-plan.md"
    git add docs/plans/test-scope-plan.md 2>/dev/null
    git commit -q -m "init plan" 2>/dev/null
    echo "stub" > "unrelated.md"
    git add "unrelated.md" 2>/dev/null
    s11_input='{"tool_name":"Bash","tool_input":{"command":"git commit -m \"test\""}}'
    printf '%s' "$s11_input" | bash "$SELF_TEST_HOOK" >stdout.txt 2>stderr.txt
    echo $? > rc.txt
  )
  S11_RC=$(cat "$S11_REPO/rc.txt" 2>/dev/null || echo 99)
  S11_STDERR=$(cat "$S11_REPO/stderr.txt" 2>/dev/null || echo "")
  S11_OK=1
  if [[ "$S11_RC" != "2" ]]; then
    S11_OK=0
    echo "self-test (11) three-option-message: FAIL (rc=$S11_RC, expected 2)" >&2
  fi
  if [[ "$S11_STDERR" != *"UPDATE THE PLAN"* ]]; then
    S11_OK=0
    echo "self-test (11) three-option-message: FAIL (stderr missing 'UPDATE THE PLAN' marker)" >&2
  fi
  if [[ "$S11_STDERR" != *"OPEN A NEW PLAN"* ]]; then
    S11_OK=0
    echo "self-test (11) three-option-message: FAIL (stderr missing 'OPEN A NEW PLAN' marker)" >&2
  fi
  if [[ "$S11_STDERR" != *"DEFER"* ]]; then
    S11_OK=0
    echo "self-test (11) three-option-message: FAIL (stderr missing 'DEFER' marker)" >&2
  fi
  # Critical waiver-removal check: stderr must NOT contain WAIVE/Waiver
  if [[ "$S11_STDERR" == *"WAIVE"* ]] || [[ "$S11_STDERR" == *"Waiver"* ]] || [[ "$S11_STDERR" == *"waiver"* ]]; then
    S11_OK=0
    echo "self-test (11) three-option-message: FAIL (stderr contains forbidden waiver string)" >&2
  fi
  if [[ "$S11_OK" -eq 1 ]]; then
    echo "self-test (11) three-option-message: PASS (correctly blocked, three options present, no waiver references)" >&2
    PASSED=$((PASSED+1))
  else
    FAILED=$((FAILED+1))
  fi

  # ---- Scenario 12: PASS — new plan staged alongside out-of-scope file claims it ----
  # The hook iterates docs/plans/*.md from the filesystem, so a freshly-staged
  # plan file is visible as soon as it lives at the path. The new plan claims
  # `unrelated.md` in its `## Files to Modify/Create`. Multi-plan intersection
  # rules: a file is in-scope iff at least one active plan claims it.
  PLAN_PRIMARY_OOS='# Plan: primary
Status: ACTIVE

## Goal
Primary work.

## Files to Modify/Create
- `src/primary.ts` — primary file

## Tasks
- [ ] 1. test
'
  PLAN_HOTFIX='# Plan: hotfix
Status: ACTIVE
Mode: code
Backlog items absorbed: none
acceptance-exempt: true
acceptance-exempt-reason: Hotfix-only plan; no user-observable surface change.

## Goal
Drive-by hotfix for unrelated.md.

## Files to Modify/Create
- `unrelated.md` — drive-by content fix

## Tasks
- [ ] 1. fix it
'
  # The primary plan is committed; we stage the hotfix plan AND `unrelated.md`
  # together. The gate must read both active plans from disk and let the
  # commit through because plan B claims unrelated.md.
  S12_REPO="$TMPROOT/s12"
  mkdir -p "$S12_REPO"
  (
    cd "$S12_REPO" || exit 99
    git init -q 2>/dev/null || true
    git config user.email "test@example.com" 2>/dev/null
    git config user.name "Test" 2>/dev/null
    git config commit.gpgsign false 2>/dev/null
    mkdir -p docs/plans
    printf '%s' "$PLAN_PRIMARY_OOS" > "docs/plans/test-scope-plan.md"
    git add docs/plans/test-scope-plan.md 2>/dev/null
    git commit -q -m "init plan" 2>/dev/null
    # Now stage both the new hotfix plan AND unrelated.md
    printf '%s' "$PLAN_HOTFIX" > "docs/plans/hotfix-newplan.md"
    git add "docs/plans/hotfix-newplan.md" 2>/dev/null
    echo "stub" > "unrelated.md"
    git add "unrelated.md" 2>/dev/null
    s12_input='{"tool_name":"Bash","tool_input":{"command":"git commit -m \"test\""}}'
    printf '%s' "$s12_input" | bash "$SELF_TEST_HOOK" >/dev/null 2>&1
    echo $? > rc.txt
  )
  S12_RC=$(cat "$S12_REPO/rc.txt" 2>/dev/null || echo 99)
  if [[ "$S12_RC" == "0" ]]; then
    echo "self-test (12) new-plan-staged-claims-scope: PASS" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (12) new-plan-staged-claims-scope: FAIL (rc=$S12_RC, expected 0)" >&2
    FAILED=$((FAILED+1))
  fi

  echo "" >&2
  echo "self-test summary: $PASSED passed, $FAILED failed (of 12 scenarios)" >&2
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
IS_GIT_COMMIT=0
TMP_CMD="$CMD"
TMP_CMD=$(echo "$TMP_CMD" | sed -e 's/&&/\n/g' -e 's/;/\n/g')
while IFS= read -r seg; do
  seg="${seg#"${seg%%[![:space:]]*}"}"
  seg="${seg%"${seg##*[![:space:]]}"}"
  [[ -z "$seg" ]] && continue
  if [[ "$seg" =~ ^cd[[:space:]] ]] || [[ "$seg" == "cd" ]]; then
    continue
  fi
  if [[ "$seg" =~ ^git[[:space:]]+commit($|[[:space:]]+) ]]; then
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
REPO_ROOT=""
if command -v git >/dev/null 2>&1; then
  REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
fi
if [[ -z "$REPO_ROOT" ]]; then
  CURRENT="$PWD"
  while [[ -n "$CURRENT" ]] && [[ "$CURRENT" != "/" ]]; do
    if [[ -e "$CURRENT/.git" ]] || [[ -d "$CURRENT/docs/plans" ]]; then
      REPO_ROOT="$CURRENT"
      break
    fi
    PARENT=$(dirname "$CURRENT")
    [[ "$PARENT" == "$CURRENT" ]] && break
    CURRENT="$PARENT"
  done
fi

if [[ -z "$REPO_ROOT" ]] || [[ ! -d "$REPO_ROOT/docs/plans" ]]; then
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
  exit 0
fi

# --- System-managed-path allowlist (2026-05-04) ---
# If ALL staged files are under docs/plans/archive/, allow unconditionally.
# These are produced by plan-lifecycle.sh's archival, not by builder work.
#
# Also: a newly-staged plan file at docs/plans/<slug>.md with `Status: ACTIVE`
# is self-claiming — the plan exists for the purpose of governing the work
# in the same commit, so it doesn't need a separate plan to claim it. This
# enables option 2 (OPEN A NEW PLAN) of the block-message: the new plan
# stages alongside its target files in a single commit.
_is_self_claiming_active_plan() {
  local p="$1"
  # Must be a top-level docs/plans/*.md (not archive)
  case "$p" in
    docs/plans/*.md)
      ;;
    *)
      return 1
      ;;
  esac
  case "$p" in
    docs/plans/archive/*) return 1 ;;
  esac
  # Must exist on disk (it's been staged + written)
  local full="$REPO_ROOT/$p"
  [[ -f "$full" ]] || return 1
  # Must declare Status: ACTIVE
  head -50 "$full" 2>/dev/null | grep -qE '^Status:[[:space:]]*ACTIVE[[:space:]]*$'
}

ALL_SYSTEM_MANAGED=1
NON_SYSTEM_STAGED=()
for sf in "${STAGED[@]}"; do
  if _is_system_managed_path "$sf"; then
    continue
  elif _is_self_claiming_active_plan "$sf"; then
    # Self-claiming new plan files are inherently in scope (they're the
    # claim itself). Pass through this filter.
    continue
  else
    ALL_SYSTEM_MANAGED=0
    NON_SYSTEM_STAGED+=("$sf")
  fi
done

if [[ "$ALL_SYSTEM_MANAGED" -eq 1 ]]; then
  echo "[scope-enforcement-gate] All staged files are system-managed (docs/plans/archive/* or self-claiming Status: ACTIVE plan files). Allowed without scope-check." >&2
  exit 0
fi

# Replace STAGED with the non-system subset for the rest of the scope-check.
# System-managed paths and self-claiming plan files in a mixed commit are
# inherently in scope; we only scope-check the rest.
STAGED=("${NON_SYSTEM_STAGED[@]}")

if [[ "${#STAGED[@]}" -eq 0 ]]; then
  # Defensive — shouldn't happen since ALL_SYSTEM_MANAGED would have caught it
  exit 0
fi

# --- Find active plans (Status: ACTIVE in top-level docs/plans/, exclude archive/) ---
ACTIVE_PLANS=()
for plan in "$REPO_ROOT"/docs/plans/*.md; do
  [[ -f "$plan" ]] || continue
  if head -50 "$plan" 2>/dev/null | grep -qE '^Status:[[:space:]]*ACTIVE[[:space:]]*$'; then
    ACTIVE_PLANS+=("$plan")
  fi
done

# --- Helper: parse a single section's bullet body and emit extracted paths.
_parse_one_section() {
  local plan_file="$1"
  local section_awk_match="$2"
  local section_grep_pattern="$3"
  SECTION_ENTRIES=()
  SECTION_RAWLEN=0
  SECTION_FOUND=0

  local section_body
  section_body=$(awk -v match_re="$section_awk_match" '
    BEGIN { in_section = 0; }
    {
      if ($0 ~ match_re) { in_section = 1; next }
      if (/^## / && in_section) { in_section = 0; exit }
      if (in_section) print
    }
  ' "$plan_file" 2>/dev/null)

  if grep -qE "$section_grep_pattern" "$plan_file" 2>/dev/null; then
    SECTION_FOUND=1
  fi

  SECTION_RAWLEN=$(echo "$section_body" | tr -d '[:space:]' | wc -c | tr -d '[:space:]')

  while IFS= read -r line; do
    line="${line#"${line%%[![:space:]]*}"}"
    [[ -z "$line" ]] && continue
    case "$line" in
      "- "*|"* "*) ;;
      *) continue ;;
    esac
    line="${line:2}"
    case "$line" in
      "[populate me]"*|"[TODO]"*|"TODO"*|"..."*) continue ;;
    esac

    local extracted=""
    if [[ "$line" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}:[[:space:]]+(.*)$ ]]; then
      line="${BASH_REMATCH[1]}"
    fi

    if [[ "$line" == *'`'* ]]; then
      local tmp="${line#*\`}"
      extracted="${tmp%%\`*}"
    else
      extracted="$line"
      extracted="${extracted%% — *}"
      extracted="${extracted%% -- *}"
      extracted="${extracted%% - *}"
      extracted="${extracted%"${extracted##*[![:space:]]}"}"
      if [[ "$extracted" == *" "* ]]; then
        continue
      fi
    fi

    [[ -z "$extracted" ]] && continue
    if [[ "$extracted" != */* ]] && [[ "$extracted" != *.* ]]; then
      continue
    fi

    SECTION_ENTRIES+=("$extracted")
  done <<< "$section_body"
}

# --- Helper: extract scope entries from a plan file ---
extract_scope_entries() {
  local plan_file="$1"
  PLAN_SCOPE_ENTRIES=()
  PLAN_SCOPE_RAWLEN=0
  PLAN_SCOPE_FOUND=0
  PLAN_INFLIGHT_FOUND=0

  _parse_one_section "$plan_file" \
    '^## Files to Modify\/Create[[:space:]]*$' \
    '^## Files to Modify/Create[[:space:]]*$'
  PLAN_SCOPE_FOUND="$SECTION_FOUND"
  PLAN_SCOPE_RAWLEN="$SECTION_RAWLEN"
  for e in "${SECTION_ENTRIES[@]}"; do
    PLAN_SCOPE_ENTRIES+=("$e")
  done

  _parse_one_section "$plan_file" \
    '^## In-flight scope updates[[:space:]]*$' \
    '^## In-flight scope updates[[:space:]]*$'
  PLAN_INFLIGHT_FOUND="$SECTION_FOUND"
  for e in "${SECTION_ENTRIES[@]}"; do
    PLAN_SCOPE_ENTRIES+=("$e")
  done
}

# --- Helper: convert a glob pattern to an anchored regex. ---
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
glob_match() {
  local pat="$1" path="$2"

  if [[ "$pat" == "$path" ]]; then
    return 0
  fi

  if [[ "${pat: -1}" == "/" ]]; then
    if [[ "$path" == "$pat"* ]]; then
      return 0
    fi
    return 1
  fi

  if [[ "$pat" != *'*'* ]] && [[ "$pat" != *'?'* ]]; then
    return 1
  fi

  local re
  re=$(glob_to_regex "$pat")

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

# --- No active plans: edge case after the system-managed-path filter ---
# If we filtered all staged files to system-managed and have non-system
# staged items left BUT no active plans govern this work, allow.
# (The original gate's "no active plan = pass-through" logic.)
if [[ "${#ACTIVE_PLANS[@]}" -eq 0 ]]; then
  exit 0
fi

# --- Process each active plan: parse scope, intersect with staged ---
declare -a PLAN_ERRORS=()
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
    PLAN_ERRORS+=("$slug:NO_PARSEABLE_ENTRIES:$plan")
    OOS_FILES_PER_PLAN+=("__STRUCTURAL__")
    continue
  fi

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
declare -A FINAL_OOS

NUM_PLANS="${#ACTIVE_PLANS[@]}"
for sf in "${STAGED[@]}"; do
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

# --- Decision ---
if [[ "${#FINAL_OOS[@]}" -eq 0 ]] && [[ "${#PLAN_ERRORS[@]}" -eq 0 ]]; then
  exit 0
fi

# --- Block: emit structured stderr message + JSON decision ---
PRIMARY_PLAN=""
PRIMARY_PLAN_REL=""
PRIMARY_PLAN_SLUG=""
if [[ "${#ACTIVE_PLANS[@]}" -gt 0 ]]; then
  PRIMARY_PLAN="${ACTIVE_PLANS[0]}"
  PRIMARY_PLAN_REL="${PRIMARY_PLAN#$REPO_ROOT/}"
  PRIMARY_PLAN_SLUG=$(plan_slug "$PRIMARY_PLAN")
fi
TODAY=$(date +%Y-%m-%d 2>/dev/null || echo "YYYY-MM-DD")

# When NO active plans exist, option 1 (update-the-plan) has no target.
# Highlight option 2 (open a new plan) as the primary recommendation.
HAS_ACTIVE_PLAN=0
if [[ "${#ACTIVE_PLANS[@]}" -gt 0 ]]; then
  HAS_ACTIVE_PLAN=1
fi

{
  echo "================================================================"
  echo "SCOPE ENFORCEMENT GATE — COMMIT BLOCKED"
  echo "================================================================"
  echo ""
  echo "This commit stages files outside the active plan's declared scope."
  echo ""
  if [[ "$HAS_ACTIVE_PLAN" -eq 1 ]]; then
    echo "Plan(s) active in this repo:"
    for plan in "${ACTIVE_PLANS[@]}"; do
      rel="${plan#$REPO_ROOT/}"
      echo "  • $rel"
    done
  else
    echo "No active plans in this repo. (Option 2 below is your primary path.)"
  fi
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
  echo "Three options, in order of structural-correctness:"
  echo ""
  if [[ "$HAS_ACTIVE_PLAN" -eq 1 ]]; then
    echo "  1. UPDATE THE PLAN (when this file is part of an active plan's work"
    echo "     but wasn't pre-listed)."
    if [[ -n "$PRIMARY_PLAN_REL" ]]; then
      echo "     Add to ${PRIMARY_PLAN_REL}'s \`## In-flight scope updates\` section:"
    else
      echo "     Add to <active-plan-path>'s \`## In-flight scope updates\` section:"
    fi
    for f in "${!FINAL_OOS[@]}"; do
      echo "       - ${TODAY}: ${f} — <one-line reason>"
    done
    echo "     Then re-stage and re-commit. The gate will read the updated section"
    echo "     and allow."
    echo ""
    echo "  2. OPEN A NEW PLAN (when this is genuinely separate work — hotfixes,"
    echo "     drive-by fixes, pre-existing-untracked files, anything not part of"
    echo "     an active plan)."
    echo "     Create docs/plans/<slug>.md with required header (Status: ACTIVE,"
    echo "     Mode: code or design, Backlog items absorbed, acceptance-exempt as"
    echo "     applicable) and a \`## Files to Modify/Create\` section listing the"
    echo "     staged files. Stage the plan alongside the work and re-commit. The"
    echo "     gate iterates the filesystem for active plans, so a freshly-staged"
    echo "     plan is visible immediately."
    echo ""
    echo "  3. DEFER (when this work shouldn't ship at all right now)."
    echo "     Unstage:"
    for f in "${!FINAL_OOS[@]}"; do
      echo "       git restore --staged \"$f\""
    done
    echo "     Add to docs/backlog.md if it should be picked up later, or skip"
    echo "     entirely if it's not actually needed."
    echo ""
  else
    # No active plans — option 2 is the primary recommendation
    echo "  1. UPDATE THE PLAN — N/A (no active plan exists in this repo)."
    echo ""
    echo "  2. OPEN A NEW PLAN  ←  PRIMARY RECOMMENDATION"
    echo "     This is genuinely separate work (hotfixes, drive-by fixes,"
    echo "     pre-existing-untracked files, anything that needs a plan to claim"
    echo "     it). Create docs/plans/<slug>.md with required header (Status:"
    echo "     ACTIVE, Mode: code or design, Backlog items absorbed,"
    echo "     acceptance-exempt as applicable) and a \`## Files to Modify/Create\`"
    echo "     section listing the staged files. Stage the plan alongside the work"
    echo "     and re-commit. The gate iterates the filesystem for active plans,"
    echo "     so a freshly-staged plan is visible immediately."
    echo ""
    echo "  3. DEFER (when this work shouldn't ship at all right now)."
    echo "     Unstage:"
    for f in "${!FINAL_OOS[@]}"; do
      echo "       git restore --staged \"$f\""
    done
    echo "     Add to docs/backlog.md if it should be picked up later, or skip"
    echo "     entirely if it's not actually needed."
    echo ""
  fi
  echo "Why this gate exists: out-of-scope commits silently expand work beyond"
  echo "the plan, eroding the scope discipline that makes plans verifiable."
  echo "Plans are living artifacts (use \`## In-flight scope updates\` for evolution),"
  echo "genuinely-separate work gets its own plan, and work that shouldn't ship"
  echo "goes to backlog. Three options cover every legitimate case."
  echo ""
  echo "Emergency override: \`git commit --no-verify\` bypasses ALL pre-commit hooks"
  echo "including this one. Use only when explicitly authorized (per"
  echo "~/.claude/rules/git.md). The bypass is auditable in git's output."
  echo ""
  echo "================================================================"
} >&2

# JSON decision for Claude Code
cat <<'JSON'
{"decision": "block", "reason": "scope-enforcement-gate: staged files fall outside active plan's declared scope. See stderr for the three structural options (update plan / open new plan / defer)."}
JSON

exit 2
