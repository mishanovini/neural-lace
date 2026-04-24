#!/bin/bash
# plan-deletion-protection.sh
#
# PreToolUse Bash hook that mechanically blocks destructive filesystem
# commands targeting plan files under docs/plans/ (excluding archive/).
#
# Plan files represent significant authored work. The only legitimate
# transformation after creation is `git mv` to docs/plans/archive/ on a
# terminal-status transition. Every other deletion path (rm, git clean,
# git stash -u, git checkout/restore, git reset --hard, mv-to-elsewhere)
# can wipe plan content — sometimes uncommitted, sometimes committed.
#
# This hook detects those command shapes BEFORE they execute and blocks
# (or warns) when they would touch active plan files.
#
# Detection covers:
#   * rm   (with -r/-rf/-f/-i flag handling)
#   * git clean   (via dry-run probe)
#   * git stash -u / --include-untracked / push -u
#   * git checkout . / git restore . / git checkout -- docs/plans/...
#   * git reset --hard   (warn only — too common to hard-block)
#   * mv / git mv   (allow only when destination is docs/plans/archive/)
#
# Bias: false-positive blocks are acceptable friction; false-negative
# passes are not. Detection biases toward blocking on uncertainty.
#
# Self-test:
#   bash plan-deletion-protection.sh --self-test
#
# Exit codes:
#   0 — command is allowed (silent) or non-blocking warning emitted
#   1 — command is blocked (stderr explains why)

set -e

# ============================================================
# Self-test entry point (handled BEFORE input parsing)
# ============================================================
if [[ "${1:-}" == "--self-test" ]]; then
  # Defined further down; jump to it
  SELF_TEST=1
fi

# ============================================================
# Input loading — support both CLAUDE_TOOL_INPUT and stdin
# ============================================================
load_input() {
  local input="${CLAUDE_TOOL_INPUT:-}"
  if [[ -z "$input" ]]; then
    if [[ ! -t 0 ]]; then
      input=$(cat 2>/dev/null || echo "")
    fi
  fi
  printf '%s' "$input"
}

# ============================================================
# Shared emitters
# ============================================================

# emit_block <title> <body>
# Prints structured BLOCKED message to stderr and exits 1.
emit_block() {
  local title="$1"
  local body="$2"
  cat >&2 <<MSG

================================================================
BLOCKED: plan-deletion-protection — $title
================================================================
$body

Plan files are protected from accidental destruction. The only
legitimate move from docs/plans/<file>.md is:
  git mv docs/plans/<file>.md docs/plans/archive/<file>.md

Escape hatches if you genuinely need this command:
  - Commit the plan first (git history then preserves it)
  - Use git mv to archive/ instead of deletion
  - For genuine cleanup of archive files: target the archive path
    explicitly (rm docs/plans/archive/<file>.md is allowed)
MSG
  exit 1
}

# emit_warn <title> <body>
# Prints non-blocking warning and exits 0.
emit_warn() {
  local title="$1"
  local body="$2"
  cat >&2 <<MSG

----------------------------------------------------------------
WARN: plan-deletion-protection — $title
----------------------------------------------------------------
$body
MSG
  return 0
}

# ============================================================
# Path helpers
# ============================================================

# normalize_path <path>
# Collapses backslashes to forward slashes (Windows Git Bash safety).
normalize_path() {
  printf '%s' "$1" | tr '\\' '/'
}

# is_plan_path <path>
# Returns 0 if path is under docs/plans/ but NOT under docs/plans/archive/.
# Handles relative, absolute, and nested forms.
is_plan_path() {
  local p
  p=$(normalize_path "$1")
  case "$p" in
    *docs/plans/archive/*)
      return 1
      ;;
    *docs/plans/*)
      return 0
      ;;
    docs/plans/archive/*)
      return 1
      ;;
    docs/plans/*)
      return 0
      ;;
  esac
  return 1
}

# is_archive_path <path>
# Returns 0 if path is under docs/plans/archive/.
is_archive_path() {
  local p
  p=$(normalize_path "$1")
  case "$p" in
    *docs/plans/archive/*) return 0 ;;
    docs/plans/archive/*)  return 0 ;;
  esac
  return 1
}

# ============================================================
# Tokenizer — split a shell command into argv-like words.
#
# Handles simple cases: spaces, single-quoted strings, double-quoted
# strings, and backslash escapes outside quotes. Does NOT handle
# nested-eval or complex parameter expansion. That's accepted residual
# risk per the plan's Assumptions section.
# ============================================================
tokenize() {
  local cmd="$1"
  # Use python-like parser via awk for portable quote handling.
  # Each token is emitted on its own line.
  printf '%s' "$cmd" | awk '
    BEGIN {
      tok = ""
      in_single = 0
      in_double = 0
      escape = 0
    }
    {
      n = length($0)
      for (i = 1; i <= n; i++) {
        c = substr($0, i, 1)
        if (escape) {
          tok = tok c
          escape = 0
          continue
        }
        if (c == "\\" && !in_single) {
          escape = 1
          continue
        }
        if (c == "\x27" && !in_double) {  # single quote
          in_single = !in_single
          continue
        }
        if (c == "\"" && !in_single) {
          in_double = !in_double
          continue
        }
        if (c == " " && !in_single && !in_double) {
          if (length(tok) > 0) { print tok; tok = "" }
          continue
        }
        tok = tok c
      }
      # End of line — also a separator unless mid-quote
      if (length(tok) > 0) { print tok; tok = "" }
    }
  '
}

# ============================================================
# Sub-command splitter — split a command on &&, ||, ;, |
#
# The hook is conservative: if ANY clause matches a destructive pattern,
# the whole command is blocked. We split first, then run detection per
# clause.
# ============================================================
split_clauses() {
  local cmd="$1"
  # Replace separators with newlines (outside quotes — best effort).
  # We use a simple approach: substitute the operators with NUL, then
  # split. This may over-split if operators appear inside quoted
  # strings, which is fine — it only causes more aggressive scanning.
  printf '%s' "$cmd" | sed -E 's/(\&\&|\|\||;|\| )/\n/g'
}

# ============================================================
# Detection helpers
# ============================================================

# clause_program <clause>
# Returns the first non-flag, non-env-var word of a clause.
# E.g., "FOO=bar git clean -fd" -> "git"
clause_program() {
  local clause="$1"
  local toks tok
  toks=$(tokenize "$clause")
  while IFS= read -r tok; do
    [[ -z "$tok" ]] && continue
    # Skip env var assignments like KEY=value
    case "$tok" in
      *=*)
        # Only skip if it's an assignment (no path separators)
        case "$tok" in
          */*) printf '%s' "$tok"; return 0 ;;
          *)   continue ;;
        esac
        ;;
    esac
    printf '%s' "$tok"
    return 0
  done <<<"$toks"
  return 0
}

# clause_subcommand <clause>
# For "git X args", returns "git X". Otherwise returns the program word.
clause_subcommand() {
  local clause="$1"
  local toks first second
  toks=$(tokenize "$clause")
  first=""
  second=""
  while IFS= read -r tok; do
    [[ -z "$tok" ]] && continue
    case "$tok" in
      *=*)
        case "$tok" in
          */*) ;;  # Path-like, not an env assignment
          *)   continue ;;
        esac
        ;;
    esac
    if [[ -z "$first" ]]; then
      first="$tok"
      continue
    fi
    if [[ -z "$second" ]]; then
      second="$tok"
      break
    fi
  done <<<"$toks"
  if [[ "$first" == "git" && -n "$second" ]]; then
    printf 'git %s' "$second"
  else
    printf '%s' "$first"
  fi
}

# ============================================================
# Detection: rm
# ============================================================
detect_rm() {
  local clause="$1"
  local prog
  prog=$(clause_subcommand "$clause")
  [[ "$prog" == "rm" ]] || return 0

  local toks tok
  toks=$(tokenize "$clause")
  local seen_program=0
  local hit=""
  while IFS= read -r tok; do
    [[ -z "$tok" ]] && continue
    if [[ $seen_program -eq 0 ]]; then
      # Skip leading env assignments
      case "$tok" in
        *=*)
          case "$tok" in
            */*) ;;
            *)   continue ;;
          esac
          ;;
      esac
      if [[ "$tok" == "rm" ]]; then
        seen_program=1
      fi
      continue
    fi
    # Skip flags
    case "$tok" in
      -*) continue ;;
    esac
    # Strip trailing slash for directory-form like docs/plans/
    local clean="${tok%/}"
    if is_plan_path "$clean" || is_plan_path "$clean/"; then
      hit="$tok"
      break
    fi
    # Also catch literal "docs/plans/" with trailing slash directly
    if [[ "$clean" == *"docs/plans" ]] || [[ "$tok" == *"docs/plans/" ]]; then
      # Bare directory targeting — block
      case "$tok" in
        *docs/plans/archive*) ;;
        *) hit="$tok"; break ;;
      esac
    fi
  done <<<"$toks"

  if [[ -n "$hit" ]]; then
    emit_block "rm targets a plan file" "Command: $clause
Offending path: $hit

Use one of:
  git mv $hit docs/plans/archive/$(basename "$hit")
  rm docs/plans/archive/<file>  (if cleaning archive)"
  fi
  return 0
}

# ============================================================
# Detection: git clean
# ============================================================
detect_git_clean() {
  local clause="$1"
  local prog
  prog=$(clause_subcommand "$clause")
  [[ "$prog" == "git clean" ]] || return 0

  local toks tok
  toks=$(tokenize "$clause")
  # Collect flags only (skip program tokens)
  local flags=""
  local saw_git=0 saw_clean=0
  local has_dryrun=0
  local has_help=0
  while IFS= read -r tok; do
    [[ -z "$tok" ]] && continue
    if [[ $saw_git -eq 0 ]]; then
      if [[ "$tok" == "git" ]]; then saw_git=1; fi
      continue
    fi
    if [[ $saw_clean -eq 0 ]]; then
      if [[ "$tok" == "clean" ]]; then saw_clean=1; fi
      continue
    fi
    case "$tok" in
      --help|-h) has_help=1 ;;
      -n|--dry-run) has_dryrun=1 ;;
      -*) flags="$flags $tok" ;;
    esac
  done <<<"$toks"

  # Pass-through: dry-run or help — non-destructive
  [[ $has_help -eq 1 ]] && return 0
  [[ $has_dryrun -eq 1 ]] && return 0

  # Are we in a git repo?
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    return 0
  fi

  # Use git clean -n to probe what WOULD be removed.
  # Build probe flags character-by-character so combined short flags
  # like -fd are handled correctly. Naive sed substitution `s/-f//g`
  # would turn -fd into d (no dash) which git clean treats as a path,
  # not the -d flag. We iterate each character, skip 'f' (we're using
  # -n instead), and re-emit -d, -x, -X individually.
  local probe_flags="-n"
  local has_d=0 has_x=0 has_X=0
  local tok2
  for tok2 in $flags; do
    case "$tok2" in
      -[a-zA-Z]*)
        local chars="${tok2#-}"
        local i c
        for (( i=0; i<${#chars}; i++ )); do
          c="${chars:$i:1}"
          case "$c" in
            f) ;;  # skip; we're using -n already
            d) has_d=1 ;;
            x) has_x=1 ;;
            X) has_X=1 ;;
          esac
        done
        ;;
    esac
  done
  [[ $has_d -eq 1 ]] && probe_flags="$probe_flags -d"
  [[ $has_x -eq 1 ]] && probe_flags="$probe_flags -x"
  [[ $has_X -eq 1 ]] && probe_flags="$probe_flags -X"
  # shellcheck disable=SC2086
  local dry_output
  dry_output=$(git clean $probe_flags 2>/dev/null || true)

  # Parse dry-run output. Lines look like:
  #   "Would remove path/to/file"
  #   "Would remove some/dir/"   (with -d, dirs end in /)
  # We need to handle both: direct file matches AND directory matches
  # whose tree contains plan files.
  local at_risk=""
  while IFS= read -r line; do
    [[ "$line" =~ ^"Would remove " ]] || continue
    local target="${line#Would remove }"
    # Direct hit: line names a plan file
    case "$target" in
      *docs/plans/archive/*) continue ;;
      *docs/plans/*)
        at_risk="$at_risk
$target"
        continue ;;
    esac
    # Directory hit: enumerate plan files under this dir
    if [[ "$target" == */ ]]; then
      local target_dir="${target%/}"
      if [[ -d "$target_dir" ]]; then
        # Find docs/plans/*.md files inside (excluding archive).
        # Note: pattern is `*docs/plans/*` not `*/docs/plans/*` so it
        # matches relative paths that start with docs/plans/ — `find`'s
        # `-path` matches against the full traversal path including the
        # starting dir, which has no leading slash for relative inputs.
        local found
        found=$(find "$target_dir" -path '*docs/plans/*' \
                  -not -path '*docs/plans/archive/*' \
                  -name '*.md' -type f 2>/dev/null || true)
        if [[ -n "$found" ]]; then
          at_risk="$at_risk
$found"
        fi
      fi
    fi
  done <<<"$dry_output"
  at_risk=$(printf '%s' "$at_risk" | sed '/^$/d')

  if [[ -n "$at_risk" ]]; then
    emit_block "git clean would remove plan files" "Command: $clause

Plan files at risk:
$at_risk

Either commit those plan files first, or git mv them to
docs/plans/archive/ if they should be retired."
  fi
  return 0
}

# ============================================================
# Detection: git stash -u
# ============================================================
detect_git_stash() {
  local clause="$1"
  local prog
  prog=$(clause_subcommand "$clause")
  [[ "$prog" == "git stash" ]] || return 0

  # Look for -u, --include-untracked, or push -u
  local has_u=0
  case " $clause " in
    *" -u "*|*" -u")           has_u=1 ;;
    *" --include-untracked "*|*" --include-untracked") has_u=1 ;;
  esac
  # Also detect -u as part of combined flags like push -u
  if [[ $has_u -eq 0 ]]; then
    return 0
  fi

  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    return 0
  fi

  # Find untracked files matching docs/plans/*.md (excluding archive/).
  # Use --untracked-files=all so we get individual files, not just the
  # parent dir for entirely-untracked subtrees.
  local untracked
  untracked=$(git status --porcelain --untracked-files=all 2>/dev/null | awk '
    /^\?\? / {
      sub(/^\?\? /, "", $0)
      if ($0 ~ /docs\/plans\/archive\//) next
      if ($0 ~ /docs\/plans\/.*\.md/) print $0
    }
  ')

  if [[ -n "$untracked" ]]; then
    emit_block "git stash -u would discard untracked plan files" "Command: $clause

Untracked plan files at risk:
$untracked

Run \`git add\` on them first, then stash:
$(printf '%s\n' "$untracked" | sed 's|^|  git add |')
  git stash push -m \"<msg>\""
  fi
  return 0
}

# ============================================================
# Detection: git checkout / restore / reset --hard
# ============================================================
detect_git_checkout_restore_reset() {
  local clause="$1"
  local prog
  prog=$(clause_subcommand "$clause")

  case "$prog" in
    "git checkout"|"git restore"|"git reset")
      ;;
    *) return 0 ;;
  esac

  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    return 0
  fi

  # Determine sub-mode
  local toks tok
  toks=$(tokenize "$clause")
  local seen_subcmd=0
  local args=""
  local is_hard=0
  while IFS= read -r tok; do
    [[ -z "$tok" ]] && continue
    if [[ $seen_subcmd -lt 2 ]]; then
      case "$tok" in
        git|checkout|restore|reset) seen_subcmd=$((seen_subcmd+1)); continue ;;
        *=*) case "$tok" in */*) ;; *) continue ;; esac ;;
      esac
    fi
    [[ "$tok" == "--hard" ]] && is_hard=1
    args="$args $tok"
  done <<<"$toks"

  # Compute modified plan files
  local modified
  modified=$(git status --porcelain 2>/dev/null | awk '
    /^.M / || /^MM / || /^AM / {
      path = substr($0, 4)
      if (path ~ /docs\/plans\/archive\//) next
      if (path ~ /docs\/plans\/.*\.md/) print path
    }
  ')

  case "$prog" in
    "git reset")
      # Only WARN for --hard, and only if plans modified
      if [[ $is_hard -eq 1 && -n "$modified" ]]; then
        emit_warn "git reset --hard would discard modified plan files" "Command: $clause

Plan files with uncommitted changes:
$modified

This warning is non-blocking — hard reset is commonly intentional.
If you meant to keep these plan changes, stash or commit them first."
      fi
      return 0
      ;;
    "git checkout"|"git restore")
      # Detect bulk discard: "." or no path (restore .) or explicit plan path
      local has_bulk=0 has_plan_target=0
      case " $args " in
        *" . "*|*" ."|*". "*) has_bulk=1 ;;
      esac
      # Check explicit plan path among args
      for tok in $args; do
        case "$tok" in
          *docs/plans/archive/*) ;;
          *docs/plans/*) has_plan_target=1 ;;
        esac
      done

      if [[ $has_bulk -eq 1 || $has_plan_target -eq 1 ]] && [[ -n "$modified" ]]; then
        emit_block "$prog would discard modified plan files" "Command: $clause

Plan files with uncommitted changes:
$modified

To keep these changes:
  git add $(printf '%s' "$modified" | head -1) && git commit -m '...'

To discard a SPECIFIC non-plan file, name it explicitly rather
than using \`.\`."
      fi
      return 0
      ;;
  esac
  return 0
}

# ============================================================
# Detection: mv / git mv
# ============================================================
detect_mv() {
  local clause="$1"
  local prog
  prog=$(clause_subcommand "$clause")

  local is_mv=0
  case "$prog" in
    "mv"|"git mv") is_mv=1 ;;
  esac
  [[ $is_mv -eq 1 ]] || return 0

  local toks tok
  toks=$(tokenize "$clause")
  # Collect non-flag, non-program tokens as positional args
  local seen_subcmd=0
  local positionals=()
  while IFS= read -r tok; do
    [[ -z "$tok" ]] && continue
    if [[ $seen_subcmd -eq 0 ]]; then
      if [[ "$tok" == "mv" || "$tok" == "git" ]]; then
        seen_subcmd=$((seen_subcmd+1))
        continue
      fi
      case "$tok" in
        *=*) case "$tok" in */*) ;; *) continue ;; esac ;;
      esac
    fi
    if [[ "$prog" == "git mv" && "$tok" == "mv" ]]; then
      continue
    fi
    case "$tok" in
      -*) continue ;;
    esac
    positionals+=("$tok")
  done <<<"$toks"

  local n=${#positionals[@]}
  [[ $n -lt 2 ]] && return 0

  # Last positional is destination; all others are sources.
  local dest="${positionals[$((n-1))]}"
  local i
  for ((i=0; i<n-1; i++)); do
    local src="${positionals[$i]}"
    # Source must be under docs/plans/ AND not under archive/
    if is_plan_path "$src"; then
      # Destination acceptable forms:
      #   - Under docs/plans/archive/  → allowed
      # Anything else → block
      if is_archive_path "$dest"; then
        continue
      fi
      # Heuristic: if destination ends with a "/" and resolves to archive
      # via the source filename appended, also allow.
      case "$dest" in
        *docs/plans/archive/) continue ;;
        *docs/plans/archive)  continue ;;
      esac
      emit_block "$prog moves a plan file outside docs/plans/archive/" "Command: $clause
Source: $src
Destination: $dest

Plan files may only move to docs/plans/archive/. Use:
  git mv $src docs/plans/archive/$(basename "$src")

If the plan is genuinely being deleted (not archived), commit the
deletion explicitly with a justifying message and bypass this hook
by editing the source out manually."
    fi
  done
  return 0
}

# ============================================================
# Master dispatch
# ============================================================
inspect_command() {
  local cmd="$1"
  [[ -z "$cmd" ]] && return 0

  # Split on shell separators; check each clause.
  local clauses
  clauses=$(split_clauses "$cmd")

  local clause
  while IFS= read -r clause; do
    # Trim leading/trailing whitespace
    clause=$(printf '%s' "$clause" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')
    [[ -z "$clause" ]] && continue

    # Each detector exits 1 itself on block (via emit_block).
    detect_rm "$clause"
    detect_git_clean "$clause"
    detect_git_stash "$clause"
    detect_git_checkout_restore_reset "$clause"
    detect_mv "$clause"
  done <<<"$clauses"

  return 0
}

# ============================================================
# Self-test
# ============================================================
run_self_test() {
  local total=0 passed=0 failed_names=""

  # run_scenario <name> <expect: BLOCK|PASS|WARN> <pre-setup-fn> <command>
  run_scenario() {
    local name="$1"
    local expect="$2"
    local setup_fn="$3"
    local cmd="$4"
    total=$((total+1))

    # Per-scenario fixture dir
    local fixture
    fixture=$(mktemp -d -t pdpst-XXXXXX) || { echo "[$name] mktemp FAIL"; return 1; }
    local prev_pwd="$PWD"
    pushd "$fixture" >/dev/null

    # Initialize git fixture
    git init -q
    git config user.email "test@example.test"
    git config user.name "Test"
    mkdir -p docs/plans/archive
    # Seed an initial commit so HEAD exists
    echo "init" > .keep
    git add .keep
    git commit -q -m "init" 2>/dev/null || true

    # Per-scenario setup
    if [[ -n "$setup_fn" ]]; then
      "$setup_fn"
    fi

    # Construct tool-input JSON the way Claude Code emits it
    local json
    json=$(printf '{"tool_name":"Bash","tool_input":{"command":%s}}' \
      "$(printf '%s' "$cmd" | python -c 'import json,sys; print(json.dumps(sys.stdin.read()))' 2>/dev/null \
         || printf '"%s"' "$(printf '%s' "$cmd" | sed 's/\\/\\\\/g; s/"/\\"/g')")")

    # Run the hook in a subshell, capturing exit code.
    # We invoke this script (without --self-test) feeding the JSON via stdin.
    local exit_code stderr_capture
    stderr_capture=$(CLAUDE_TOOL_INPUT="$json" bash "$SELF_PATH" 2>&1 >/dev/null) || true
    # Actually: get exit code
    set +e
    CLAUDE_TOOL_INPUT="$json" bash "$SELF_PATH" >/dev/null 2>/tmp/pdpst-stderr.$$
    exit_code=$?
    set -e

    local got=""
    if [[ $exit_code -eq 0 ]]; then
      if grep -q "WARN: plan-deletion-protection" /tmp/pdpst-stderr.$$ 2>/dev/null; then
        got="WARN"
      else
        got="PASS"
      fi
    elif [[ $exit_code -eq 1 ]]; then
      got="BLOCK"
    else
      got="ERROR($exit_code)"
    fi

    rm -f /tmp/pdpst-stderr.$$
    popd >/dev/null
    rm -rf "$fixture"
    cd "$prev_pwd" 2>/dev/null || true

    if [[ "$got" == "$expect" ]]; then
      passed=$((passed+1))
      printf '  ok   %-3d %s\n' "$total" "$name"
    else
      failed_names="$failed_names\n  fail $name (expected $expect, got $got)"
      printf '  FAIL %-3d %s (expected %s, got %s)\n' "$total" "$name" "$expect" "$got"
    fi
  }

  # Setup helpers (run while in fixture dir)
  setup_uncommitted_plan() {
    echo "# untracked plan" > docs/plans/foo.md
  }
  setup_committed_modified_plan() {
    echo "# original" > docs/plans/foo.md
    git add docs/plans/foo.md
    git commit -q -m "add foo plan"
    echo "# modified" >> docs/plans/foo.md
  }
  setup_committed_clean_plan() {
    echo "# original" > docs/plans/foo.md
    git add docs/plans/foo.md
    git commit -q -m "add foo plan"
  }
  setup_archive_plan() {
    echo "# archived" > docs/plans/archive/old.md
    git add docs/plans/archive/old.md
    git commit -q -m "add archived plan"
  }
  setup_no_plan() {
    :
  }

  echo "plan-deletion-protection self-test"
  echo "==================================="

  run_scenario "1.  rm docs/plans/foo.md → BLOCK" \
    BLOCK setup_uncommitted_plan \
    "rm docs/plans/foo.md"

  run_scenario "2.  rm -rf docs/plans/ → BLOCK" \
    BLOCK setup_uncommitted_plan \
    "rm -rf docs/plans/"

  run_scenario "3.  rm docs/plans/archive/old.md → PASS (archive cleanup)" \
    PASS setup_archive_plan \
    "rm docs/plans/archive/old.md"

  run_scenario "4.  rm README.md → PASS (non-plan file)" \
    PASS setup_no_plan \
    "rm README.md"

  run_scenario "5.  git clean -fd with untracked plans → BLOCK" \
    BLOCK setup_uncommitted_plan \
    "git clean -fd"

  run_scenario "6.  git clean -fd with no plans affected → PASS" \
    PASS setup_no_plan \
    "git clean -fd"

  run_scenario "7.  git clean -n -d (dry-run) → PASS" \
    PASS setup_uncommitted_plan \
    "git clean -n -d"

  run_scenario "8.  git stash -u with untracked plans → BLOCK" \
    BLOCK setup_uncommitted_plan \
    "git stash -u"

  run_scenario "9.  git stash (no -u) → PASS" \
    PASS setup_uncommitted_plan \
    "git stash"

  run_scenario "10. git checkout . with modified plans → BLOCK" \
    BLOCK setup_committed_modified_plan \
    "git checkout ."

  run_scenario "11. git reset --hard with modified plans → WARN (not block)" \
    WARN setup_committed_modified_plan \
    "git reset --hard"

  run_scenario "12. mv docs/plans/foo.md docs/plans/archive/foo.md → PASS" \
    PASS setup_committed_clean_plan \
    "mv docs/plans/foo.md docs/plans/archive/foo.md"

  run_scenario "13. mv docs/plans/foo.md /tmp/foo.md → BLOCK" \
    BLOCK setup_committed_clean_plan \
    "mv docs/plans/foo.md /tmp/foo.md"

  run_scenario "14. git mv docs/plans/foo.md docs/plans/archive/foo.md → PASS" \
    PASS setup_committed_clean_plan \
    "git mv docs/plans/foo.md docs/plans/archive/foo.md"

  echo "==================================="
  echo "passed: $passed / $total"
  if [[ $passed -ne $total ]]; then
    printf 'FAILURES:%b\n' "$failed_names"
    exit 1
  fi
  echo "self-test: OK"
  exit 0
}

# ============================================================
# Entry point
# ============================================================

# Resolve own path for self-test re-entry
SELF_PATH="${BASH_SOURCE[0]}"
case "$SELF_PATH" in
  /*) ;;
  *) SELF_PATH="$PWD/$SELF_PATH" ;;
esac

if [[ "${SELF_TEST:-0}" == "1" ]]; then
  run_self_test
fi

# Production path: load tool input, extract command, dispatch detectors.
INPUT=$(load_input)
[[ -z "$INPUT" ]] && exit 0

COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // .command // ""' 2>/dev/null || true)
[[ -z "$COMMAND" ]] && exit 0

# Tool name guard — only Bash invocations are in scope.
TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null || true)
if [[ -n "$TOOL_NAME" && "$TOOL_NAME" != "Bash" ]]; then
  exit 0
fi

inspect_command "$COMMAND"
exit 0
