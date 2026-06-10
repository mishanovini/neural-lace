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
#   PreToolUse on tool_name == "Bash" OR "PowerShell" (settings matcher
#   "Bash|PowerShell" — HARNESS-GAP-47, 2026-06-10, closed the PowerShell
#   bypass: the PowerShell tool runs `git commit` just like Bash and is
#   parsed with the same command patterns; `cd` is a Set-Location alias and
#   `Set-Location` itself is recognized). Splits the command on `&&` / `;`,
#   tracks `cd` / `Set-Location` targets, matches `git commit` (including
#   `git -C <path> commit`) as a segment. Pass-through on other tools and
#   non-commit commands.
#
# Target-repo resolution (HARNESS-GAP-47, 2026-06-10):
#   The gate evaluates ALL its logic (plan discovery + staged-file listing)
#   against the repo the commit actually TARGETS, not the hook process's own
#   cwd (the session root). Pre-fix, `cd <other-repo> && git commit` was
#   evaluated against the SESSION repo's docs/plans + staged index, and
#   `git -C <other-repo> commit` bypassed the gate entirely (the old
#   `^git\s+commit` regex never matched it). Effective-target priority:
#     1. `git -C <path>` flags on the commit segment — quoted paths with
#        spaces supported, repeated -C composes per git semantics (later
#        relative paths resolve against earlier ones), glued -C<path> too.
#     2. The last `cd <path>` / `Set-Location <path>` segment preceding the
#        git-commit segment (`&&` and `;` chains, quoted paths, ~ expansion,
#        chained relative cds accumulate).
#     3. Fallback: process cwd (the pre-GAP-47 behavior, unchanged).
#   A parsed target that doesn't exist or isn't a git repo passes through
#   with a stderr note — the real git command will fail on its own; there is
#   nothing meaningful to scope-check. Self-test scenarios 26-31 cover this
#   plus the PowerShell tool coverage.
#
# No-docs/plans/ full-skip (2026-06-08):
#   A repo with NO docs/plans/ directory cannot have plan-scoped commits —
#   there is nothing to scope against — so the gate skips the check entirely
#   and allows the commit (with a brief stderr note). This is the correct
#   general fix; it unblocks committing operational state to repos that don't
#   use the plan workflow (e.g. the workstreams-coordination state repo).
#   Self-test scenario 25 covers it.
#
# System-managed-path allowlist (2026-05-04):
#   `docs/plans/archive/*` and `docs/plans/archive/*-evidence.md` are
#   exempt — these files are moved by `plan-lifecycle.sh` on Status:
#   COMPLETED/DEFERRED/ABANDONED/SUPERSEDED transitions, not by builder
#   plan work. If ALL staged files are system-managed, allow the commit
#   unconditionally with a brief stderr note. If a mix, do the normal
#   scope-check on the non-system files only.
#
# Rebase / merge full-skip (HARNESS-GAP-29, 2026-05-27):
#   A `git commit` created WHILE a rebase or merge is in progress stages
#   files that git's replay/merge brought in — e.g. origin/master's files
#   applied to a PR branch during conflict resolution — NOT files the
#   author chose per the plan. Scope-checking author-uncontrolled files is
#   meaningless and produces false blocks on the routine "rebase/merge
#   master into a PR branch" operation. So when a rebase- or
#   merge-in-progress is detected, the ENTIRE scope check is skipped and
#   the exemption is logged to `~/.claude/state/scope-gate-exemptions.log`
#   (commit context + reason) for audit.
#
#   Detection (any sufficient):
#     - rebase:  `$GIT_DIR/rebase-apply` or `$GIT_DIR/rebase-merge` exists
#     - merge:   `$GIT_DIR/MERGE_HEAD` exists, OR the `git commit -m`
#                message begins with "Merge branch" (a true merge commit
#                where MERGE_HEAD may already be absent).
#
#   This SUPERSEDES the narrower HARNESS-GAP-27 behavior (which exempted
#   only commit-numbered migration paths during a merge and still
#   scope-checked everything else). That was insufficient: a master
#   merge/rebase stages app code, configs, and docs too, not just
#   migrations. The migration-path allowlist below (`_is_system_managed_path`
#   under IN_MERGE) is retained as documented defense-in-depth but is
#   subsumed by the earlier full-skip whenever MERGE_HEAD is present.
#   Companion "union of plans active on either side" approach is tracked
#   as a separate ADR (see backlog HARNESS-GAP-27).
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
#
# Always exempt:
#   - docs/plans/archive/*  (moved by plan-lifecycle.sh on terminal status)
#   - docs/plans/deferred/* (moved by plan-lifecycle.sh on DEFERRED — ADR 052)
#
# Additionally exempt when IN_MERGE=1 (per HARNESS-GAP-27):
#   - supabase/migrations/*.sql
#   - prisma/migrations/**
#   - db/migrations/**
#
# Reads global IN_MERGE (set by main flow). Self-test scenarios that
# need merge-context behavior write a $GIT_DIR/MERGE_HEAD file in their
# scenario repo before invoking the hook; the spawned hook process
# then detects merge-context from the filesystem.
# ============================================================
_is_system_managed_path() {
  local p="$1"
  case "$p" in
    docs/plans/archive/*) return 0 ;;
    docs/plans/deferred/*) return 0 ;;
  esac
  if [[ "${IN_MERGE:-0}" == "1" ]]; then
    case "$p" in
      supabase/migrations/*.sql) return 0 ;;
      prisma/migrations/*) return 0 ;;
      prisma/migrations/*/*) return 0 ;;
      db/migrations/*) return 0 ;;
      db/migrations/*/*) return 0 ;;
    esac
  fi
  return 1
}

# ============================================================
# Helper: resolve a git-dir path to absolute form.
#
# `git rev-parse --git-dir` may return:
#   - a POSIX-absolute path (/home/u/repo/.git)
#   - a Windows drive-letter absolute path (C:/Users/u/repo/.git, or rarely
#     the backslash form C:\Users\...\.git) — Git Bash on Windows
#   - a relative path (.git, or worktrees/foo/.git) — resolve vs repo root
#   - empty (could not resolve) — return empty
#
# The Windows drive-letter form is the load-bearing case: a `case` that
# matched only `/*` treated `C:/…/.git` as RELATIVE and re-prefixed it with
# the repo root, producing a nonexistent path. The MERGE_HEAD / rebase-state
# checks then silently never fired on Windows, so the rebase/merge full-skip
# (HARNESS-GAP-29) was lost there. Treat drive-letter paths as already
# absolute.
# ============================================================
_resolve_git_dir_abs() {
  local gd="$1" root="$2"
  case "$gd" in
    "") printf '' ;;                            # could not resolve
    /*) printf '%s' "$gd" ;;                    # POSIX-absolute
    [A-Za-z]:/*|[A-Za-z]:\\*) printf '%s' "$gd" ;;  # Windows drive-letter absolute
    *) printf '%s/%s' "$root" "$gd" ;;          # relative -> resolve vs repo root
  esac
}

# ============================================================
# Helpers: commit-target parsing (HARNESS-GAP-47, 2026-06-10)
#
# The command string may change directory before committing
# (`cd <path> && git commit`) or target another repo inline
# (`git -C <path> commit`). These helpers extract the effective
# target directory so the gate evaluates THAT repo, not the hook
# process's cwd. See the header "Target-repo resolution" section.
# ============================================================

# Expand a leading ~ / ~/ to $HOME.
_expand_tilde() {
  local p="$1"
  case "$p" in
    "~") printf '%s' "$HOME" ;;
    "~/"*) printf '%s/%s' "$HOME" "${p#\~/}" ;;
    *) printf '%s' "$p" ;;
  esac
}

# Is $1 an absolute path (POSIX or Windows drive-letter)?
_is_abs_path_str() {
  case "$1" in
    /*) return 0 ;;
    [A-Za-z]:/*|[A-Za-z]:\\*) return 0 ;;
    *) return 1 ;;
  esac
}

# Tokenize a command segment respecting single/double quotes.
# Populates global array SEG_TOKENS.
_tokenize_segment() {
  local s="$1" i ch n cur="" in_dq=0 in_sq=0 have=0
  SEG_TOKENS=()
  n=${#s}
  for ((i=0; i<n; i++)); do
    ch="${s:i:1}"
    if [[ $in_sq -eq 1 ]]; then
      if [[ "$ch" == "'" ]]; then in_sq=0; else cur+="$ch"; fi
      continue
    fi
    if [[ $in_dq -eq 1 ]]; then
      if [[ "$ch" == '"' ]]; then in_dq=0; else cur+="$ch"; fi
      continue
    fi
    case "$ch" in
      "'") in_sq=1; have=1 ;;
      '"') in_dq=1; have=1 ;;
      ' '|$'\t')
        if [[ -n "$cur" ]] || [[ $have -eq 1 ]]; then
          SEG_TOKENS+=("$cur"); cur=""; have=0
        fi
        ;;
      *) cur+="$ch"; have=1 ;;
    esac
  done
  if [[ -n "$cur" ]] || [[ $have -eq 1 ]]; then
    SEG_TOKENS+=("$cur")
  fi
}

# Compose a directory path: absolute $3 wins; else resolve $3 against the
# accumulated target $1; else against the base $2 (git's effective cwd).
_compose_dir() {
  local cur="$1" base="$2" p="$3"
  p=$(_expand_tilde "$p")
  if _is_abs_path_str "$p"; then
    printf '%s' "$p"
  elif [[ -n "$cur" ]]; then
    printf '%s/%s' "$cur" "$p"
  elif [[ -n "$base" ]]; then
    printf '%s/%s' "$base" "$p"
  else
    printf '%s' "$p"
  fi
}

# Analyze a `git …` segment. Sets globals:
#   GIT_SEG_IS_COMMIT  — 1 iff the segment's subcommand is `commit`
#                        (commit-tree / commit-graph excluded by token equality)
#   GIT_SEG_C_TARGET   — composed `-C` target dir, or "" when no -C present.
#                        Repeated -C composes per git semantics; relative
#                        paths resolve against $2 (git's effective cwd base).
_analyze_git_segment() {
  local seg="$1" base="$2"
  GIT_SEG_IS_COMMIT=0
  GIT_SEG_C_TARGET=""
  _tokenize_segment "$seg"
  local n=${#SEG_TOKENS[@]} i tok
  [[ $n -ge 2 ]] || return 0
  [[ "${SEG_TOKENS[0]}" == "git" ]] || return 0
  for ((i=1; i<n; i++)); do
    tok="${SEG_TOKENS[$i]}"
    case "$tok" in
      -C)
        i=$((i+1))
        [[ $i -lt $n ]] || break
        GIT_SEG_C_TARGET=$(_compose_dir "$GIT_SEG_C_TARGET" "$base" "${SEG_TOKENS[$i]}")
        ;;
      -C?*)
        GIT_SEG_C_TARGET=$(_compose_dir "$GIT_SEG_C_TARGET" "$base" "${tok:2}")
        ;;
      --git-dir|--work-tree|--namespace|-c)
        i=$((i+1))   # global flags whose value is a separate token
        ;;
      -*)
        :            # other global flags (boolean, or value glued with =)
        ;;
      *)
        if [[ "$tok" == "commit" ]]; then
          GIT_SEG_IS_COMMIT=1
        fi
        return 0
        ;;
    esac
  done
  return 0
}

# Parse a `cd <path>` / `Set-Location <path>` segment; echo the resolved
# target (relative paths resolve against $2, the accumulated cd target or
# process cwd). Bare `cd` echoes $HOME.
_parse_cd_target() {
  local seg="$1" base="$2"
  _tokenize_segment "$seg"
  local n=${#SEG_TOKENS[@]}
  if [[ $n -lt 2 ]]; then
    printf '%s' "$HOME"
    return
  fi
  local p="${SEG_TOKENS[1]}"
  # Skip a leading flag (cd -P/-L, Set-Location -LiteralPath/-Path)
  if [[ "$p" == -* ]] && [[ $n -ge 3 ]]; then
    p="${SEG_TOKENS[2]}"
  fi
  p=$(_expand_tilde "$p")
  if _is_abs_path_str "$p"; then
    printf '%s' "$p"
  elif [[ -n "$base" ]]; then
    printf '%s/%s' "$base" "$p"
  else
    printf '%s' "$p"
  fi
}

# ============================================================
# --self-test handler (thirty-one scenarios)
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

  # ---- Scenario 13: PASS — MERGE_HEAD exists, supabase migration is system-managed in merge context ----
  # Plan claims src/foo.ts only. We stage a supabase/migrations/*.sql file
  # plus write .git/MERGE_HEAD to simulate a merge resolution. The migration
  # is NOT in the plan's scope, but the merge-context allowlist (GAP-27)
  # should treat it as system-managed and allow the commit.
  PLAN_MERGE_BASIC='# Plan: merge-test
Status: ACTIVE

## Goal
Test merge-context allowlist.

## Files to Modify/Create
- `src/foo.ts` — only claimed file

## Tasks
- [ ] 1. test
'
  S13_REPO="$TMPROOT/s13"
  mkdir -p "$S13_REPO"
  (
    cd "$S13_REPO" || exit 99
    git init -q 2>/dev/null || true
    git config user.email "test@example.com" 2>/dev/null
    git config user.name "Test" 2>/dev/null
    git config commit.gpgsign false 2>/dev/null
    mkdir -p docs/plans
    printf '%s' "$PLAN_MERGE_BASIC" > "docs/plans/test-scope-plan.md"
    git add docs/plans/test-scope-plan.md 2>/dev/null
    git commit -q -m "init plan" 2>/dev/null
    # Simulate merge-resolution context by writing .git/MERGE_HEAD
    echo "0000000000000000000000000000000000000000" > .git/MERGE_HEAD
    # Stage a supabase migration (not in plan)
    mkdir -p supabase/migrations
    echo "-- migration" > "supabase/migrations/20260514120000_add_index.sql"
    git add "supabase/migrations/20260514120000_add_index.sql" 2>/dev/null
    s13_input='{"tool_name":"Bash","tool_input":{"command":"git commit -m \"merge\""}}'
    printf '%s' "$s13_input" | bash "$SELF_TEST_HOOK" >/dev/null 2>&1
    echo $? > rc.txt
  )
  S13_RC=$(cat "$S13_REPO/rc.txt" 2>/dev/null || echo 99)
  if [[ "$S13_RC" == "0" ]]; then
    echo "self-test (13) merge-context-supabase-migration-allowed: PASS" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (13) merge-context-supabase-migration-allowed: FAIL (rc=$S13_RC, expected 0)" >&2
    FAILED=$((FAILED+1))
  fi

  # ---- Scenario 14: FAIL — NO MERGE_HEAD, supabase migration is NOT magic ----
  # Same setup as s13 but without writing .git/MERGE_HEAD. The migration
  # is out-of-scope and the gate must block — merge-context exemption
  # does NOT apply outside an actual merge.
  S14_REPO="$TMPROOT/s14"
  mkdir -p "$S14_REPO"
  (
    cd "$S14_REPO" || exit 99
    git init -q 2>/dev/null || true
    git config user.email "test@example.com" 2>/dev/null
    git config user.name "Test" 2>/dev/null
    git config commit.gpgsign false 2>/dev/null
    mkdir -p docs/plans
    printf '%s' "$PLAN_MERGE_BASIC" > "docs/plans/test-scope-plan.md"
    git add docs/plans/test-scope-plan.md 2>/dev/null
    git commit -q -m "init plan" 2>/dev/null
    # NO .git/MERGE_HEAD — normal commit context
    mkdir -p supabase/migrations
    echo "-- migration" > "supabase/migrations/20260514120000_add_index.sql"
    git add "supabase/migrations/20260514120000_add_index.sql" 2>/dev/null
    s14_input='{"tool_name":"Bash","tool_input":{"command":"git commit -m \"normal\""}}'
    printf '%s' "$s14_input" | bash "$SELF_TEST_HOOK" >/dev/null 2>&1
    echo $? > rc.txt
  )
  S14_RC=$(cat "$S14_REPO/rc.txt" 2>/dev/null || echo 99)
  if [[ "$S14_RC" == "2" ]]; then
    echo "self-test (14) no-merge-context-supabase-migration-blocked: PASS (correctly blocked)" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (14) no-merge-context-supabase-migration-blocked: FAIL (rc=$S14_RC, expected 2)" >&2
    FAILED=$((FAILED+1))
  fi

  # ---- Scenario 15: PASS — MERGE_HEAD exists; full-skip even for a non-migration out-of-scope file ----
  # BEHAVIOR CHANGE (HARNESS-GAP-29, 2026-05-27): supersedes the prior
  # HARNESS-GAP-27 "narrow targeting" property (where a non-migration file
  # was still blocked during a merge). A merge stages files git's merge
  # brought in — app code, configs, docs — not just migrations, and not
  # author-chosen plan scope. Scope-checking them is meaningless, so a
  # merge-resolution commit now FULL-skips. Here both an out-of-scope
  # migration AND an out-of-scope src/unrelated.ts are staged with
  # MERGE_HEAD present; the gate must allow (exit 0), not block.
  S15_REPO="$TMPROOT/s15"
  mkdir -p "$S15_REPO"
  (
    cd "$S15_REPO" || exit 99
    git init -q 2>/dev/null || true
    git config user.email "test@example.com" 2>/dev/null
    git config user.name "Test" 2>/dev/null
    git config commit.gpgsign false 2>/dev/null
    mkdir -p docs/plans
    printf '%s' "$PLAN_MERGE_BASIC" > "docs/plans/test-scope-plan.md"
    git add docs/plans/test-scope-plan.md 2>/dev/null
    git commit -q -m "init plan" 2>/dev/null
    echo "0000000000000000000000000000000000000000" > .git/MERGE_HEAD
    # Stage both an out-of-scope migration AND an out-of-scope source file.
    mkdir -p supabase/migrations src
    echo "-- migration" > "supabase/migrations/20260514120000_add_index.sql"
    echo "stub" > "src/unrelated.ts"
    git add "supabase/migrations/20260514120000_add_index.sql" "src/unrelated.ts" 2>/dev/null
    s15_input='{"tool_name":"Bash","tool_input":{"command":"git commit -m \"merge\""}}'
    printf '%s' "$s15_input" | bash "$SELF_TEST_HOOK" >stdout.txt 2>stderr.txt
    echo $? > rc.txt
  )
  S15_RC=$(cat "$S15_REPO/rc.txt" 2>/dev/null || echo 99)
  S15_STDERR=$(cat "$S15_REPO/stderr.txt" 2>/dev/null || echo "")
  S15_OK=1
  if [[ "$S15_RC" != "0" ]]; then
    S15_OK=0
    echo "self-test (15) merge-resolution-full-skip: FAIL (rc=$S15_RC, expected 0)" >&2
  fi
  if [[ "$S15_STDERR" != *"merge-resolution detected"* ]]; then
    S15_OK=0
    echo "self-test (15) merge-resolution-full-skip: FAIL (stderr missing 'merge-resolution detected' note)" >&2
  fi
  if [[ "$S15_OK" -eq 1 ]]; then
    echo "self-test (15) merge-resolution-full-skip: PASS (merge context full-skips scope-check)" >&2
    PASSED=$((PASSED+1))
  else
    FAILED=$((FAILED+1))
  fi

  # ---- Scenario 16: PASS — MERGE_HEAD exists, prisma migration is system-managed ----
  # Confirms the merge-context allowlist covers prisma/migrations/** too.
  S16_REPO="$TMPROOT/s16"
  mkdir -p "$S16_REPO"
  (
    cd "$S16_REPO" || exit 99
    git init -q 2>/dev/null || true
    git config user.email "test@example.com" 2>/dev/null
    git config user.name "Test" 2>/dev/null
    git config commit.gpgsign false 2>/dev/null
    mkdir -p docs/plans
    printf '%s' "$PLAN_MERGE_BASIC" > "docs/plans/test-scope-plan.md"
    git add docs/plans/test-scope-plan.md 2>/dev/null
    git commit -q -m "init plan" 2>/dev/null
    echo "0000000000000000000000000000000000000000" > .git/MERGE_HEAD
    mkdir -p prisma/migrations/20260514120000_add_index
    echo "-- migration" > "prisma/migrations/20260514120000_add_index/migration.sql"
    git add "prisma/migrations/20260514120000_add_index/migration.sql" 2>/dev/null
    s16_input='{"tool_name":"Bash","tool_input":{"command":"git commit -m \"merge\""}}'
    printf '%s' "$s16_input" | bash "$SELF_TEST_HOOK" >/dev/null 2>&1
    echo $? > rc.txt
  )
  S16_RC=$(cat "$S16_REPO/rc.txt" 2>/dev/null || echo 99)
  if [[ "$S16_RC" == "0" ]]; then
    echo "self-test (16) merge-context-prisma-migration-allowed: PASS" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (16) merge-context-prisma-migration-allowed: FAIL (rc=$S16_RC, expected 0)" >&2
    FAILED=$((FAILED+1))
  fi

  # ---- Scenario 17: PASS — rebase-in-progress (rebase-apply) full-skips a clearly out-of-scope file ----
  # Simulate `git am`/`git rebase` (apply backend) by creating
  # .git/rebase-apply. The staged file is NOT in the plan's scope; the
  # gate must allow because a rebase replays author-chosen commits and
  # stages files git's replay brought in.
  S17_REPO="$TMPROOT/s17"
  mkdir -p "$S17_REPO"
  (
    cd "$S17_REPO" || exit 99
    git init -q 2>/dev/null || true
    git config user.email "test@example.com" 2>/dev/null
    git config user.name "Test" 2>/dev/null
    git config commit.gpgsign false 2>/dev/null
    mkdir -p docs/plans
    printf '%s' "$PLAN_MERGE_BASIC" > "docs/plans/test-scope-plan.md"
    git add docs/plans/test-scope-plan.md 2>/dev/null
    git commit -q -m "init plan" 2>/dev/null
    # Simulate rebase-in-progress (apply backend).
    mkdir -p .git/rebase-apply
    mkdir -p src
    echo "stub" > "src/way-out-of-scope.ts"
    git add "src/way-out-of-scope.ts" 2>/dev/null
    s17_input='{"tool_name":"Bash","tool_input":{"command":"git commit -m \"replayed commit\""}}'
    printf '%s' "$s17_input" | bash "$SELF_TEST_HOOK" >stdout.txt 2>stderr.txt
    echo $? > rc.txt
  )
  S17_RC=$(cat "$S17_REPO/rc.txt" 2>/dev/null || echo 99)
  S17_STDERR=$(cat "$S17_REPO/stderr.txt" 2>/dev/null || echo "")
  if [[ "$S17_RC" == "0" ]] && [[ "$S17_STDERR" == *"rebase-in-progress detected"* ]]; then
    echo "self-test (17) rebase-apply-full-skip: PASS" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (17) rebase-apply-full-skip: FAIL (rc=$S17_RC, expected 0 with 'rebase-in-progress detected')" >&2
    FAILED=$((FAILED+1))
  fi

  # ---- Scenario 18: PASS — mid-rebase (rebase-merge) takes precedence over bad scope ----
  # The interactive/merge rebase backend uses .git/rebase-merge. Out-of-
  # scope file present; rebase precedence => full-skip (exit 0).
  S18_REPO="$TMPROOT/s18"
  mkdir -p "$S18_REPO"
  (
    cd "$S18_REPO" || exit 99
    git init -q 2>/dev/null || true
    git config user.email "test@example.com" 2>/dev/null
    git config user.name "Test" 2>/dev/null
    git config commit.gpgsign false 2>/dev/null
    mkdir -p docs/plans
    printf '%s' "$PLAN_MERGE_BASIC" > "docs/plans/test-scope-plan.md"
    git add docs/plans/test-scope-plan.md 2>/dev/null
    git commit -q -m "init plan" 2>/dev/null
    # Simulate rebase-in-progress (merge backend).
    mkdir -p .git/rebase-merge
    mkdir -p src
    echo "stub" > "src/another-out-of-scope.ts"
    git add "src/another-out-of-scope.ts" 2>/dev/null
    s18_input='{"tool_name":"Bash","tool_input":{"command":"git commit"}}'
    printf '%s' "$s18_input" | bash "$SELF_TEST_HOOK" >stdout.txt 2>stderr.txt
    echo $? > rc.txt
  )
  S18_RC=$(cat "$S18_REPO/rc.txt" 2>/dev/null || echo 99)
  S18_STDERR=$(cat "$S18_REPO/stderr.txt" 2>/dev/null || echo "")
  if [[ "$S18_RC" == "0" ]] && [[ "$S18_STDERR" == *"rebase-in-progress detected"* ]]; then
    echo "self-test (18) rebase-merge-precedence: PASS" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (18) rebase-merge-precedence: FAIL (rc=$S18_RC, expected 0 with 'rebase-in-progress detected')" >&2
    FAILED=$((FAILED+1))
  fi

  # ---- Scenario 19: PASS — "Merge branch" commit message full-skips (no MERGE_HEAD on disk) ----
  # A true merge commit committed via `-m "Merge branch ..."` where
  # MERGE_HEAD is absent (e.g. re-running the commit). The message
  # fallback must trigger the merge-resolution full-skip.
  S19_REPO="$TMPROOT/s19"
  mkdir -p "$S19_REPO"
  (
    cd "$S19_REPO" || exit 99
    git init -q 2>/dev/null || true
    git config user.email "test@example.com" 2>/dev/null
    git config user.name "Test" 2>/dev/null
    git config commit.gpgsign false 2>/dev/null
    mkdir -p docs/plans
    printf '%s' "$PLAN_MERGE_BASIC" > "docs/plans/test-scope-plan.md"
    git add docs/plans/test-scope-plan.md 2>/dev/null
    git commit -q -m "init plan" 2>/dev/null
    # NO .git/MERGE_HEAD, NO rebase dir — rely on the commit-message fallback.
    mkdir -p src
    echo "stub" > "src/merged-in.ts"
    git add "src/merged-in.ts" 2>/dev/null
    s19_input='{"tool_name":"Bash","tool_input":{"command":"git commit -m \"Merge branch '"'"'master'"'"' into feature\""}}'
    printf '%s' "$s19_input" | bash "$SELF_TEST_HOOK" >stdout.txt 2>stderr.txt
    echo $? > rc.txt
  )
  S19_RC=$(cat "$S19_REPO/rc.txt" 2>/dev/null || echo 99)
  S19_STDERR=$(cat "$S19_REPO/stderr.txt" 2>/dev/null || echo "")
  if [[ "$S19_RC" == "0" ]] && [[ "$S19_STDERR" == *"merge-resolution detected"* ]]; then
    echo "self-test (19) merge-branch-message-full-skip: PASS" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (19) merge-branch-message-full-skip: FAIL (rc=$S19_RC, expected 0 with 'merge-resolution detected')" >&2
    FAILED=$((FAILED+1))
  fi

  # ---- Scenario 20: git-dir resolution — Windows drive-letter is absolute (regression: HARNESS-GAP-29 on Windows) ----
  # On Windows Git Bash, `git rev-parse --git-dir` returns a drive-letter
  # path like C:/Users/u/repo/.git. The pre-fix `case` matched only `/*`,
  # so such a path fell through to relative-handling and got re-prefixed
  # with the repo root — producing a nonexistent path, so the MERGE_HEAD /
  # rebase-state checks never fired and the rebase/merge full-skip was lost.
  # _resolve_git_dir_abs must return drive-letter (and POSIX-absolute) paths
  # unchanged, resolve relative paths vs the repo root, and keep empty empty.
  S20_OK=1
  out=$(_resolve_git_dir_abs "C:/Users/u/repo/.git" "/some/repo/root")
  [[ "$out" == "C:/Users/u/repo/.git" ]] || { S20_OK=0; echo "self-test (20) windows-drive-letter-forward-slash: FAIL (got '$out')" >&2; }
  out=$(_resolve_git_dir_abs 'C:\Users\u\repo\.git' "/some/repo/root")
  [[ "$out" == 'C:\Users\u\repo\.git' ]] || { S20_OK=0; echo "self-test (20) windows-drive-letter-backslash: FAIL (got '$out')" >&2; }
  out=$(_resolve_git_dir_abs "/home/u/repo/.git" "/some/repo/root")
  [[ "$out" == "/home/u/repo/.git" ]] || { S20_OK=0; echo "self-test (20) posix-absolute: FAIL (got '$out')" >&2; }
  out=$(_resolve_git_dir_abs ".git" "/some/repo/root")
  [[ "$out" == "/some/repo/root/.git" ]] || { S20_OK=0; echo "self-test (20) relative-resolves-vs-root: FAIL (got '$out')" >&2; }
  out=$(_resolve_git_dir_abs "" "/some/repo/root")
  [[ -z "$out" ]] || { S20_OK=0; echo "self-test (20) empty-stays-empty: FAIL (got '$out')" >&2; }
  if [[ "$S20_OK" -eq 1 ]]; then
    echo "self-test (20) git-dir-resolution (windows-drive-letter / posix / relative / empty): PASS" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (20) git-dir-resolution: FAIL" >&2
    FAILED=$((FAILED+1))
  fi

  # ---- Scenarios 21-24: HARNESS-GAP-41 trailing-slash pattern semantics ----
  # The parser stores plan declarations like `foo/ — description` with the
  # trailing slash retained. Pre-fix, glob_match treated `foo/` as strict
  # prefix-with-slash and missed bare gitlink paths (`git rm --cached foo`
  # stages `foo` with no trailing slash). Post-fix, `foo/` matches BOTH
  # `foo/bar/baz` (existing behavior) AND bare `foo` (NEW), while still
  # rejecting `foobar` and `foo-extra` (false-positive guard).
  PLAN_GITLINK='# Plan: test
Status: ACTIVE

## Goal
Test gitlink-shaped trailing-slash matching.

## Files to Modify/Create
- `gitlink-dir/` — directory-shaped declaration for a gitlink cleanup

## Tasks
- [ ] 1. test
'

  # ---- Scenario 21: PASS — `foo/` matches bare path `foo` (the gitlink case) ----
  RC=$(_run_scenario s21 "$PLAN_GITLINK" "gitlink-dir")
  if [[ "$RC" == "0" ]]; then
    echo "self-test (21) trailing-slash-matches-bare-path: PASS (gitlink case)" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (21) trailing-slash-matches-bare-path: FAIL (rc=$RC, expected 0)" >&2
    FAILED=$((FAILED+1))
  fi

  # ---- Scenario 22: PASS — `foo/` still matches paths under foo (existing behavior preserved) ----
  RC=$(_run_scenario s22 "$PLAN_GITLINK" "gitlink-dir/nested/file.ts")
  if [[ "$RC" == "0" ]]; then
    echo "self-test (22) trailing-slash-matches-nested-path: PASS (existing behavior preserved)" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (22) trailing-slash-matches-nested-path: FAIL (rc=$RC, expected 0)" >&2
    FAILED=$((FAILED+1))
  fi

  # ---- Scenario 23: FAIL — `foo/` must NOT match `foobar` (false-positive guard) ----
  RC=$(_run_scenario s23 "$PLAN_GITLINK" "gitlink-dirbar")
  if [[ "$RC" == "2" ]]; then
    echo "self-test (23) trailing-slash-does-not-match-substring-prefix: PASS (correctly blocked)" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (23) trailing-slash-does-not-match-substring-prefix: FAIL (rc=$RC, expected 2)" >&2
    FAILED=$((FAILED+1))
  fi

  # ---- Scenario 24: FAIL — `foo/` must NOT match `foo-extra` (hyphen-extended false-positive guard) ----
  RC=$(_run_scenario s24 "$PLAN_GITLINK" "gitlink-dir-extra")
  if [[ "$RC" == "2" ]]; then
    echo "self-test (24) trailing-slash-does-not-match-hyphen-extended: PASS (correctly blocked)" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (24) trailing-slash-does-not-match-hyphen-extended: FAIL (rc=$RC, expected 2)" >&2
    FAILED=$((FAILED+1))
  fi

  # ---- Scenario 25: PASS — repo with NO docs/plans/ → full-skip (2026-06-08) ----
  # A repo that doesn't use the plan workflow (e.g. the workstreams-coordination
  # state repo) has no plans to scope against; the gate must skip the check and
  # allow the commit. _run_scenario always creates docs/plans, so build the
  # no-plans repo inline.
  (
    repo="$TMPROOT/s25"
    mkdir -p "$repo"
    cd "$repo" || exit 99
    git init -q 2>/dev/null || true
    git config user.email "test@example.com" 2>/dev/null
    git config user.name "Test" 2>/dev/null
    git config commit.gpgsign false 2>/dev/null
    # Deliberately NO docs/plans/ — only operational state.
    mkdir -p state
    echo '{"x":1}' > state/tree-state.json
    git add state/tree-state.json 2>/dev/null
    git commit -q -m "init state repo" 2>/dev/null
    echo '{"x":2}' > state/tree-state.json
    git add state/tree-state.json 2>/dev/null
    input='{"tool_name":"Bash","tool_input":{"command":"git commit -m \"state: update\""}}'
    printf '%s' "$input" | bash "$SELF_TEST_HOOK" >/dev/null 2>&1
    echo $? > rc.txt
  )
  RC=$(cat "$TMPROOT/s25/rc.txt" 2>/dev/null || echo 99)
  if [[ "$RC" == "0" ]]; then
    echo "self-test (25) no-docs-plans-repo-skips: PASS (correctly skipped, exit 0)" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (25) no-docs-plans-repo-skips: FAIL (rc=$RC, expected 0)" >&2
    FAILED=$((FAILED+1))
  fi

  # ============================================================
  # Scenarios 26-31 — HARNESS-GAP-47 (target-repo resolution +
  # PowerShell coverage). Each cross-repo scenario builds a SESSION
  # repo (the hook's cwd) and a TARGET repo (named in the command);
  # the gate must evaluate the TARGET, never the session cwd.
  # ============================================================

  # Helper: build a repo at $1. $2 = plan body ("" = NO docs/plans at all).
  # $3 = csv of files to create + stage.
  _build_repo() {
    local dir="$1" plan_body="$2" staged_csv="$3"
    mkdir -p "$dir"
    (
      cd "$dir" || exit 99
      git init -q 2>/dev/null || true
      git config user.email "test@example.com" 2>/dev/null
      git config user.name "Test" 2>/dev/null
      git config commit.gpgsign false 2>/dev/null
      if [[ -n "$plan_body" ]]; then
        mkdir -p docs/plans
        printf '%s' "$plan_body" > docs/plans/test-scope-plan.md
        git add docs/plans/test-scope-plan.md 2>/dev/null
      else
        echo "init" > .gitkeep
        git add .gitkeep 2>/dev/null
      fi
      git commit -q -m "init" 2>/dev/null
      local IFS=','
      local _staged f
      read -ra _staged <<< "$staged_csv"
      for f in "${_staged[@]}"; do
        [[ -z "$f" ]] && continue
        mkdir -p "$(dirname "$f")" 2>/dev/null
        echo "stub" > "$f"
        git add "$f" 2>/dev/null
      done
    )
  }

  # Helper: run the hook from cwd $1 with command $2 and tool name $3
  # (default Bash); echo the hook's exit code. Uses jq to build the input
  # JSON safely (paths may contain spaces).
  _run_hook_cmd() {
    local cwd="$1" cmd="$2" tool="${3:-Bash}"
    (
      cd "$cwd" || exit 99
      local input
      input=$(jq -cn --arg t "$tool" --arg c "$cmd" '{tool_name:$t,tool_input:{command:$c}}')
      printf '%s' "$input" | bash "$SELF_TEST_HOOK" >/dev/null 2>&1
      echo $?
    )
  }

  # ---- Scenario 26 (GAP-47 s-A1): `git -C <other-repo-without-plans>` → full-skip,
  # even though the SESSION repo (process cwd) has an active plan + an
  # out-of-scope staged file (which would BLOCK if evaluated against cwd). ----
  _build_repo "$TMPROOT/s26-session" "$PLAN_NORMAL" "unrelated.md"
  _build_repo "$TMPROOT/s26-target" "" "state/file.txt"
  RC=$(_run_hook_cmd "$TMPROOT/s26-session" "git -C $TMPROOT/s26-target commit -m \"x\"")
  if [[ "$RC" == "0" ]]; then
    echo "self-test (26) gap47-git-C-targets-noplans-repo-skips: PASS (evaluated against TARGET, not session cwd)" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (26) gap47-git-C-targets-noplans-repo-skips: FAIL (rc=$RC, expected 0)" >&2
    FAILED=$((FAILED+1))
  fi

  # ---- Scenario 27 (GAP-47 s-A2): `git -C "<quoted path with spaces>"` into a repo
  # WITH an active plan + out-of-scope staged file → BLOCK, even though the
  # SESSION repo has no docs/plans (would full-skip if evaluated against cwd). ----
  _build_repo "$TMPROOT/s27-session" "" "state/file.txt"
  _build_repo "$TMPROOT/s27 target with space" "$PLAN_NORMAL" "unrelated.md"
  RC=$(_run_hook_cmd "$TMPROOT/s27-session" "git -C \"$TMPROOT/s27 target with space\" commit -m \"x\"")
  if [[ "$RC" == "2" ]]; then
    echo "self-test (27) gap47-git-C-quoted-space-path-blocks-on-target: PASS (correctly blocked against TARGET)" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (27) gap47-git-C-quoted-space-path-blocks-on-target: FAIL (rc=$RC, expected 2)" >&2
    FAILED=$((FAILED+1))
  fi

  # ---- Scenario 28 (GAP-47 s-A3): `cd <other> && git commit` follows the cd target ----
  _build_repo "$TMPROOT/s28-session" "$PLAN_NORMAL" "unrelated.md"
  _build_repo "$TMPROOT/s28-target" "" "state/file.txt"
  RC=$(_run_hook_cmd "$TMPROOT/s28-session" "cd $TMPROOT/s28-target && git commit -m \"x\"")
  if [[ "$RC" == "0" ]]; then
    echo "self-test (28) gap47-cd-then-commit-follows-cd-target: PASS" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (28) gap47-cd-then-commit-follows-cd-target: FAIL (rc=$RC, expected 0)" >&2
    FAILED=$((FAILED+1))
  fi

  # ---- Scenario 29 (GAP-47 s-A4): plain `git commit` (no -C / cd) — fallback to
  # process cwd unchanged: out-of-scope staged file in cwd repo still blocks. ----
  _build_repo "$TMPROOT/s29-session" "$PLAN_NORMAL" "unrelated.md"
  RC=$(_run_hook_cmd "$TMPROOT/s29-session" "git commit -m \"x\"")
  if [[ "$RC" == "2" ]]; then
    echo "self-test (29) gap47-plain-commit-cwd-fallback-unchanged: PASS (correctly blocked)" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (29) gap47-plain-commit-cwd-fallback-unchanged: FAIL (rc=$RC, expected 2)" >&2
    FAILED=$((FAILED+1))
  fi

  # ---- Scenario 30 (GAP-47): repeated -C composes per git semantics —
  # `git -C <abs-tmproot> -C s30-target commit` resolves to $TMPROOT/s30-target. ----
  _build_repo "$TMPROOT/s30-session" "$PLAN_NORMAL" "unrelated.md"
  _build_repo "$TMPROOT/s30-target" "" "state/file.txt"
  RC=$(_run_hook_cmd "$TMPROOT/s30-session" "git -C $TMPROOT -C s30-target commit -m \"x\"")
  if [[ "$RC" == "0" ]]; then
    echo "self-test (30) gap47-repeated-dash-C-composes: PASS" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (30) gap47-repeated-dash-C-composes: FAIL (rc=$RC, expected 0)" >&2
    FAILED=$((FAILED+1))
  fi

  # ---- Scenario 31 (GAP-47 defect B): tool_name "PowerShell" is gated with the
  # same semantics — out-of-scope staged file in cwd repo blocks. Pre-fix the
  # hook exited 0 on any non-Bash tool, so PowerShell commits ran unexamined. ----
  _build_repo "$TMPROOT/s31-session" "$PLAN_NORMAL" "unrelated.md"
  RC=$(_run_hook_cmd "$TMPROOT/s31-session" "git commit -m \"x\"" "PowerShell")
  if [[ "$RC" == "2" ]]; then
    echo "self-test (31) gap47-powershell-tool-gated: PASS (correctly blocked)" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (31) gap47-powershell-tool-gated: FAIL (rc=$RC, expected 2)" >&2
    FAILED=$((FAILED+1))
  fi

  echo "" >&2
  echo "self-test summary: $PASSED passed, $FAILED failed (of 31 scenarios)" >&2
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

# Tool name must be Bash or PowerShell (support nested + flat shapes).
# HARNESS-GAP-47: the PowerShell tool runs `git commit` too; gating only
# Bash left a silent bypass. The settings matcher is "Bash|PowerShell".
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null)
if [[ "$TOOL_NAME" != "Bash" ]] && [[ "$TOOL_NAME" != "PowerShell" ]]; then
  exit 0
fi

# Extract command (nested .tool_input.command preferred; flat .command fallback)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // .command // ""' 2>/dev/null)
if [[ -z "$CMD" ]]; then
  exit 0
fi

# --- Detect git commit + parse the effective commit-target (HARNESS-GAP-47) ---
# Track `cd` / `Set-Location` segments as they accumulate, then when the
# git-commit segment is found, extract its `-C` flags. Priority for the
# effective target dir: -C composition > last cd target > process cwd ("").
IS_GIT_COMMIT=0
TARGET_DIR=""
CD_TARGET=""
TMP_CMD="$CMD"
TMP_CMD=$(echo "$TMP_CMD" | sed -e 's/&&/\n/g' -e 's/;/\n/g')
while IFS= read -r seg; do
  seg="${seg#"${seg%%[![:space:]]*}"}"
  seg="${seg%"${seg##*[![:space:]]}"}"
  [[ -z "$seg" ]] && continue
  if [[ "$seg" =~ ^cd($|[[:space:]]) ]] || [[ "$seg" =~ ^[Ss]et-[Ll]ocation($|[[:space:]]) ]]; then
    CD_TARGET=$(_parse_cd_target "$seg" "${CD_TARGET:-$PWD}")
    continue
  fi
  if [[ "$seg" =~ ^git([[:space:]]|$) ]]; then
    _analyze_git_segment "$seg" "${CD_TARGET:-$PWD}"
    if [[ "$GIT_SEG_IS_COMMIT" -eq 1 ]]; then
      IS_GIT_COMMIT=1
      if [[ -n "$GIT_SEG_C_TARGET" ]]; then
        TARGET_DIR="$GIT_SEG_C_TARGET"
      elif [[ -n "$CD_TARGET" ]]; then
        TARGET_DIR="$CD_TARGET"
      fi
      break
    fi
  fi
done <<< "$TMP_CMD"

if [[ "$IS_GIT_COMMIT" -eq 0 ]]; then
  exit 0
fi

# --- Locate the COMMIT TARGET's repo root (where docs/plans/ lives) ---
# HARNESS-GAP-47: when a target dir was parsed from the command, ALL gate
# logic (plan discovery + staged-file listing) runs against that repo.
# With no parsed target, behavior is unchanged (process cwd).
REPO_ROOT=""
if [[ -n "$TARGET_DIR" ]]; then
  if [[ ! -d "$TARGET_DIR" ]]; then
    # Parsed target doesn't exist — the real `git commit` will fail on its
    # own; nothing meaningful to scope-check. Err toward allow.
    echo "[scope-enforcement-gate] parsed commit-target dir '$TARGET_DIR' does not exist — scope-check skipped (the git command will fail on its own)." >&2
    exit 0
  fi
  if command -v git >/dev/null 2>&1; then
    REPO_ROOT=$(git -C "$TARGET_DIR" rev-parse --show-toplevel 2>/dev/null || echo "")
  fi
  if [[ -z "$REPO_ROOT" ]]; then
    echo "[scope-enforcement-gate] parsed commit-target dir '$TARGET_DIR' is not inside a git repo — scope-check skipped (the git command will fail on its own)." >&2
    exit 0
  fi
else
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
fi

# Could not locate a repo root at all → cannot reason about scope; pass through.
if [[ -z "$REPO_ROOT" ]]; then
  exit 0
fi

# --- Full-skip: repo has NO docs/plans/ directory (2026-06-08) ---
# A repository with no docs/plans/ cannot have plan-scoped commits — there are
# no plans to scope against, so the scope check is vacuous and would only
# false-block. This is the correct GENERAL fix (it unblocks committing
# operational state to repos that simply don't use the plan workflow, e.g. the
# workstreams-coordination state repo), superseding any per-repo carve-out.
# Skip explicitly + audibly (the prior silent `! -d docs/plans` early-exit gave
# no signal); errs toward allow, consistent with the other full-skip branches.
if [[ ! -d "$REPO_ROOT/docs/plans" ]]; then
  echo "[scope-enforcement-gate] no docs/plans/ in repo '$REPO_ROOT' — scope-check skipped (a repo without plans cannot have plan-scoped commits)." >&2
  exit 0
fi

# --- Full-skip: rebase or merge-resolution context (HARNESS-GAP-29, 2026-05-27) ---
# A commit created WHILE a rebase or merge is in progress stages files
# git's replay/merge brought in (not author-chosen plan scope). Scope-
# checking those is meaningless and false-blocks the routine "rebase/merge
# master into a PR branch" operation. Detect the in-progress state from
# the per-worktree git dir, full-skip the scope check, and log for audit.
# This supersedes the narrower migration-only merge exemption below.
GIT_DIR_PATH=$(git -C "$REPO_ROOT" rev-parse --git-dir 2>/dev/null || echo "")
GIT_DIR_PATH=$(_resolve_git_dir_abs "$GIT_DIR_PATH" "$REPO_ROOT")

SKIP_REASON=""
if [[ -n "$GIT_DIR_PATH" ]]; then
  if [[ -d "$GIT_DIR_PATH/rebase-apply" ]] || [[ -d "$GIT_DIR_PATH/rebase-merge" ]]; then
    SKIP_REASON="rebase-in-progress"
  elif [[ -e "$GIT_DIR_PATH/MERGE_HEAD" ]]; then
    SKIP_REASON="merge-resolution"
  fi
fi
# Fallback: explicit "Merge branch …" commit message (a true merge commit
# where MERGE_HEAD may already be absent — e.g. re-running the commit).
if [[ -z "$SKIP_REASON" ]] \
   && echo "$CMD" | grep -Eq "(^|[[:space:]])-m[[:space:]]+[\"']?Merge[[:space:]]+branch"; then
  SKIP_REASON="merge-resolution"
fi

if [[ -n "$SKIP_REASON" ]]; then
  # Audit log (best-effort; never fail the hook on a logging error). At
  # PreToolUse time the new commit's SHA does not exist yet, so we log the
  # current HEAD (the parent) for context.
  EXEMPT_LOG="$HOME/.claude/state/scope-gate-exemptions.log"
  HEAD_SHA=$(git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || echo "unknown")
  CUR_BRANCH=$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
  TS=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "unknown")
  { mkdir -p "$(dirname "$EXEMPT_LOG")" 2>/dev/null \
      && printf '%s\treason=%s\thead=%s\tbranch=%s\trepo=%s\n' \
         "$TS" "$SKIP_REASON" "$HEAD_SHA" "$CUR_BRANCH" "$REPO_ROOT" >> "$EXEMPT_LOG"; } 2>/dev/null || true
  echo "[scope-enforcement-gate] $SKIP_REASON detected — scope-check skipped (commit stages files from git's replay/merge, not author-chosen plan scope). Logged to ~/.claude/state/scope-gate-exemptions.log" >&2
  exit 0
fi

# --- Detect merge-resolution context (HARNESS-GAP-27, 2026-05-14) ---
# When `$GIT_DIR/MERGE_HEAD` exists, this commit is resolving a merge.
# Migration paths from the merged-in branch are then exempt from
# scope-check (the merge-resolution plan author can't predict which
# commit-numbered migrations master generated since divergence).
IN_MERGE=0
if command -v git >/dev/null 2>&1; then
  GIT_DIR_PATH=$(git -C "$REPO_ROOT" rev-parse --git-dir 2>/dev/null || echo "")
  GIT_DIR_PATH=$(_resolve_git_dir_abs "$GIT_DIR_PATH" "$REPO_ROOT")
  if [[ -n "$GIT_DIR_PATH" ]] && [[ -e "$GIT_DIR_PATH/MERGE_HEAD" ]]; then
    IN_MERGE=1
  fi
fi
export IN_MERGE

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
  if [[ "$IN_MERGE" == "1" ]]; then
    echo "[scope-enforcement-gate] All staged files are system-managed (docs/plans/archive/*, self-claiming Status: ACTIVE plan files, or merge-context migration paths). Allowed without scope-check." >&2
  else
    echo "[scope-enforcement-gate] All staged files are system-managed (docs/plans/archive/* or self-claiming Status: ACTIVE plan files). Allowed without scope-check." >&2
  fi
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
    # Trailing-slash pattern matches:
    #  (a) any path under that prefix: "foo/" matches "foo/bar/baz"
    #  (b) the bare path with no slash: "foo/" matches "foo"
    # Case (b) is required for gitlink-shaped paths — `git rm --cached <dir>`
    # produces a bare path in the staged tree (no trailing slash), so a
    # plan declaring `foo/` must still match that staged entry.
    # HARNESS-GAP-41 (2026-05-24).
    if [[ "$path" == "$pat"* ]]; then
      return 0
    fi
    local pat_no_slash="${pat%/}"
    if [[ "$path" == "$pat_no_slash" ]]; then
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
