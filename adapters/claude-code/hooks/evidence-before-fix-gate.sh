#!/bin/bash
# evidence-before-fix-gate.sh — Directive 1, "the 5th lesson"
# (harness-governance-batch-2026-07-15, batch task 3).
#
# Classification: Mechanism (hook-enforced PreToolUse blocker)
#
# Rule: docs/lessons/2026-07-14-root-cause-must-be-evidenced-before-fix.md
# Doctrine: adapters/claude-code/doctrine/evidence-before-fix.md (compact)
#           adapters/claude-code/doctrine/diagnosis.md (broadened by this task
#           beyond prod-crashes to any data/behavior/state defect)
#
# WHY THIS IS WIRED AS AN INDEPENDENT PreToolUse HOOK, NOT NESTED IN THE
# pre-commit-gate.sh FRESHNESS_GATES CHAIN
# ============================================================================
# docs-freshness-gate.sh / decisions-index-gate.sh / review-finding-fix-gate.sh
# are invoked from INSIDE pre-commit-gate.sh, itself invoked from a wrapper
# PreToolUse command that does:
#   CMD=$(jq -r '.tool_input.command // ""'); if <CMD matches git commit>; then
#     bash ~/.claude/hooks/pre-commit-gate.sh || exit 1
#   fi
# `jq` there consumes the hook's stdin (the PreToolUse JSON payload) in full to
# populate $CMD; $CMD is a local (non-exported) shell variable, so
# pre-commit-gate.sh and everything it calls inherit NEITHER a populated stdin
# NOR $CMD. review-finding-fix-gate.sh compensates by reading
# `.git/COMMIT_EDITMSG` instead — but PROVEN (reproduced empirically while
# building this gate; see below) that file holds the PREVIOUS commit's
# message at PreToolUse time, not the one about to be made:
#
#   $ git commit -m "first"                  # writes COMMIT_EDITMSG="first"
#   $ git add x && git commit -m "second"    # pre-commit hook sees
#                                             #   COMMIT_EDITMSG == "first"
#                                             #   (git writes the NEW
#                                             #   COMMIT_EDITMSG only once the
#                                             #   commit's message-prep step
#                						#   runs, which is AFTER pre-commit)
#
# A gate that needs the CURRENT message (this one does — it inspects the
# body for a `## Root cause (evidenced)` section and any `frc-...` record
# reference) cannot rely on COMMIT_EDITMSG at PreToolUse time. This is flagged
# as a real, reproduced defect in review-finding-fix-gate.sh's existing
# design (out of scope to fix here; see the build's final report / nl-issue).
# Instead this gate is wired as its OWN top-level PreToolUse "Bash" hooks[]
# entry (same wiring shape as observed-errors-gate.sh), reading the command
# string directly from CLAUDE_TOOL_INPUT / stdin JSON BEFORE the real git
# process ever runs — the only point at which the upcoming message is known.
#
# BEHAVIOR
# ========
#   1. Not a `git commit ...` command                        -> ALLOW
#   2. Merge/rebase/cherry-pick in progress, or message's
#      first line starts with "Merge branch"                 -> ALLOW (skip)
#   3. Subject line does not start with `fix(` or `fix:`      -> ALLOW
#      (`fix-trivial:` never matches either prefix -- the decided lighter
#      path for one-line/typo/no-runtime-symptom fixes; see doctrine file)
#   4. Message body has a `## Root cause (evidenced)` section with >=1
#      `PROVEN`-tagged line carrying a citation-shaped token (file:line,
#      backtick-quoted command/output, or a command:/output:/log: label)
#                                                              -> ALLOW
#   5. Message cites a `frc-YYYYMMDD-xxxxxxxx` review-record id whose record
#      (docs/reviews/records/*.json) has kind fix-root-cause, verdict PASS,
#      covered_files intersecting the staged file set, and
#      payload.root_cause.tag PROVEN (or INFERRED with blast_radius_bounded
#      true)                                                  -> ALLOW
#   6. A fresh (<1h) .claude/state/evidence-before-fix-waiver-*.txt names
#      both purpose clauses (lib/waiver-purpose-clause.sh) AND a Files: line
#      matching >=1 staged file                               -> ALLOW
#   7. None of the above                                      -> BLOCK
#
# HONESTY NOTE (structure-not-truth, named per the task's instruction): this
# gate can verify the SECTION EXISTS, is TAGGED, and CITES a token shaped
# like evidence -- it cannot verify the citation is true, that the command
# was actually run, or that the quoted log excerpt is real. Path 5's record
# reference inherits the SAME residual write-review-record.sh already names
# (Amendment C, docs/design-notes/review-record-primitive.md): the record's
# audit trail (append-only, content-addressed, requiring an actual reviewer
# dispatch to produce a record id) is the compensating control, not a
# guarantee. A determined agent can fabricate a citation-shaped string. This
# gate raises the cost of shipping an inferred-only fix; it does not make
# fabrication impossible.
#
# INVOCATION
#   1. PreToolUse (Bash matcher), independently wired in
#      settings.json.template -- reads CLAUDE_TOOL_INPUT env var or stdin
#      JSON ({"tool_input":{"command": "..."}}), no args.
#   2. Self-test: evidence-before-fix-gate.sh --self-test
#
# EXIT CODES
#   0 -- allowed (or non-applicable / cannot classify -- fails open)
#   1 -- blocked (stderr explains why + remediation)

set -u

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
# shellcheck source=lib/waiver-purpose-clause.sh
source "$SELF_DIR/lib/waiver-purpose-clause.sh" 2>/dev/null || true
# shellcheck source=lib/signal-ledger.sh
source "$SELF_DIR/lib/signal-ledger.sh" 2>/dev/null || true

# ============================================================================
# Commit-message extraction (mirrors observed-errors-gate.sh's proven
# extraction logic -- the same underlying problem: get the message text out
# of a Bash tool_input.command string before the real `git commit` runs).
# ============================================================================
_efg_extract_commit_message() {
  local COMMAND="$1"
  local COMMIT_MSG=""

  if echo "$COMMAND" | grep -qE '\-m[[:space:]]'; then
    COMMIT_MSG=$(echo "$COMMAND" | sed -nE 's/.*-m[[:space:]]+"([^"]*)".*/\1/p' | head -1)
    if [[ -z "$COMMIT_MSG" ]]; then
      COMMIT_MSG=$(echo "$COMMAND" | sed -nE "s/.*-m[[:space:]]+'([^']*)'.*/\\1/p" | head -1)
    fi
  fi

  if [[ -z "$COMMIT_MSG" ]] && echo "$COMMAND" | grep -qE '\-F[[:space:]]'; then
    local msg_file
    msg_file=$(echo "$COMMAND" | sed -nE 's/.*-F[[:space:]]+([^[:space:]]+).*/\1/p' | head -1)
    if [[ -n "$msg_file" && -f "$msg_file" ]]; then
      COMMIT_MSG=$(cat "$msg_file" 2>/dev/null || echo "")
    fi
  fi

  # Heredoc-style (the harness's own documented convention: git commit -m
  # "$(cat <<'EOF' ... EOF)"). This is the DOMINANT real-world shape for any
  # multi-line message (which a "## Root cause (evidenced)" section requires),
  # so it is tried whenever the simple single-line forms above found nothing,
  # AND whenever a heredoc marker is present at all (a heredoc body can itself
  # contain a line that happens to look like `-m "..."`, so prefer the
  # heredoc extraction once we know one is present).
  if echo "$COMMAND" | grep -qE "<<['\"]?EOF['\"]?[[:space:]]*\$"; then
    local heredoc_msg
    heredoc_msg=$(printf '%s\n' "$COMMAND" | awk '/<<[[:space:]]*.?EOF.?[[:space:]]*$/{flag=1; next} /^EOF[[:space:]]*$/{flag=0} flag' 2>/dev/null || echo "")
    if [[ -n "$heredoc_msg" ]]; then
      COMMIT_MSG="$heredoc_msg"
    fi
  fi

  printf '%s' "$COMMIT_MSG"
}

# ============================================================================
# Merge/rebase/cherry-pick detection (scope-enforcement-gate.sh's precedent,
# extended with CHERRY_PICK_HEAD per this task's explicit instruction).
# ============================================================================
_efg_resolve_git_dir_abs() {
  local gd="$1" root="$2"
  case "$gd" in
    "") printf '' ;;
    /*) printf '%s' "$gd" ;;
    [A-Za-z]:/*|[A-Za-z]:\\*) printf '%s' "$gd" ;;
    *) printf '%s/%s' "$root" "$gd" ;;
  esac
}

_efg_in_replay_context() {
  local repo_root="$1" first_line="$2"
  local git_dir git_dir_abs
  git_dir=$(git -C "$repo_root" rev-parse --git-dir 2>/dev/null)
  git_dir_abs=$(_efg_resolve_git_dir_abs "$git_dir" "$repo_root")
  if [[ -n "$git_dir_abs" ]]; then
    [[ -f "$git_dir_abs/MERGE_HEAD" ]] && return 0
    [[ -f "$git_dir_abs/CHERRY_PICK_HEAD" ]] && return 0
    [[ -d "$git_dir_abs/rebase-apply" ]] && return 0
    [[ -d "$git_dir_abs/rebase-merge" ]] && return 0
  fi
  case "$first_line" in
    "Merge branch"*) return 0 ;;
  esac
  return 1
}

# ============================================================================
# "## Root cause (evidenced)" section extraction + PROVEN/citation check.
# ============================================================================
_efg_section_text() {
  local msg="$1"
  printf '%s\n' "$msg" | awk '
    /^## Root cause \(evidenced\)[[:space:]]*$/ { flag=1; next }
    /^## / { if (flag) exit }
    flag { print }
  '
}

_efg_line_has_citation() {
  local line="$1"
  # file:line reference, e.g. adapters/claude-code/hooks/foo.sh:123
  if printf '%s' "$line" | grep -qE '[A-Za-z0-9_./-]+\.[A-Za-z0-9]+:[0-9]+'; then
    return 0
  fi
  # backtick-quoted command or output excerpt
  if printf '%s' "$line" | grep -qE '`[^`]+`'; then
    return 0
  fi
  # explicit command:/output:/log: label with content following
  if printf '%s' "$line" | grep -qiE '(command|output|log)[[:space:]]*:[[:space:]]*[^[:space:]]'; then
    return 0
  fi
  return 1
}

# Sets globals: EFG_SECTION_PRESENT, EFG_SECTION_SATISFIED,
# EFG_SECTION_HAS_PROVEN_NO_CITATION (diagnostic detail for the block message)
_efg_check_inline_section() {
  local msg="$1"
  EFG_SECTION_PRESENT=0
  EFG_SECTION_SATISFIED=0
  EFG_SECTION_HAS_PROVEN_NO_CITATION=0

  local section
  section=$(_efg_section_text "$msg")
  [[ -z "$section" ]] && return 0
  EFG_SECTION_PRESENT=1

  local any_proven_with_citation=0 any_proven=0
  while IFS= read -r line; do
    if printf '%s' "$line" | grep -qE '\bPROVEN\b'; then
      any_proven=1
      if _efg_line_has_citation "$line"; then
        any_proven_with_citation=1
      fi
    fi
  done <<< "$section"

  if [[ "$any_proven_with_citation" -eq 1 ]]; then
    EFG_SECTION_SATISFIED=1
  elif [[ "$any_proven" -eq 1 ]]; then
    EFG_SECTION_HAS_PROVEN_NO_CITATION=1
  fi
  return 0
}

# ============================================================================
# Record-reference path (kind: fix-root-cause).
# ============================================================================
# Sets globals: EFG_RECORD_TOKEN, EFG_RECORD_RESULT (ok|not-found|not-pass|
#   no-coverage|inferred-unbounded), EFG_RECORD_DETAIL
_efg_check_record_reference() {
  local msg="$1" repo_root="$2"
  EFG_RECORD_TOKEN=""
  EFG_RECORD_RESULT="none"
  EFG_RECORD_DETAIL=""

  local token
  token=$(printf '%s' "$msg" | grep -oE 'frc-[0-9]{8}-[0-9a-f]{8}' | head -1)
  [[ -z "$token" ]] && return 0
  EFG_RECORD_TOKEN="$token"

  command -v jq >/dev/null 2>&1 || { EFG_RECORD_RESULT="not-found"; EFG_RECORD_DETAIL="jq unavailable -- cannot verify record"; return 0; }

  local records_dir="$repo_root/docs/reviews/records"
  [[ -d "$records_dir" ]] || { EFG_RECORD_RESULT="not-found"; EFG_RECORD_DETAIL="no docs/reviews/records/ directory"; return 0; }

  local f match=""
  shopt -s nullglob
  for f in "$records_dir"/*.json; do
    local base; base=$(basename "$f")
    [[ "$base" == "index.json" || "$base" == "grandfather-manifest.json" ]] && continue
    if jq -e --arg id "$token" '.record_id == $id' "$f" >/dev/null 2>&1; then
      match="$f"
      break
    fi
  done
  shopt -u nullglob

  if [[ -z "$match" ]]; then
    EFG_RECORD_RESULT="not-found"
    EFG_RECORD_DETAIL="no record file has record_id == $token"
    return 0
  fi

  local kind verdict tag bounded
  kind=$(jq -r '.kind // ""' "$match" 2>/dev/null)
  verdict=$(jq -r '.verdict // ""' "$match" 2>/dev/null)
  tag=$(jq -r '.payload.root_cause.tag // ""' "$match" 2>/dev/null)
  bounded=$(jq -r '.payload.blast_radius_bounded // false' "$match" 2>/dev/null)

  if [[ "$kind" != "fix-root-cause" ]]; then
    EFG_RECORD_RESULT="not-found"
    EFG_RECORD_DETAIL="record $token has kind '$kind', expected fix-root-cause"
    return 0
  fi
  if [[ "$verdict" != "PASS" ]]; then
    EFG_RECORD_RESULT="not-pass"
    EFG_RECORD_DETAIL="record $token has verdict '$verdict', not PASS"
    return 0
  fi

  # Coverage: covered_files must intersect the staged file set.
  local staged="$3"
  local covered=0 p
  while IFS= read -r p; do
    [[ -z "$p" ]] && continue
    if jq -e --arg p "$p" '.covered_files[]? | select(.path == $p)' "$match" >/dev/null 2>&1; then
      covered=1
      break
    fi
  done <<< "$staged"

  if [[ "$covered" -eq 0 ]]; then
    EFG_RECORD_RESULT="no-coverage"
    EFG_RECORD_DETAIL="record $token's covered_files does not include any staged file"
    return 0
  fi

  if [[ "$tag" == "PROVEN" ]]; then
    EFG_RECORD_RESULT="ok"
    return 0
  fi
  if [[ "$tag" == "INFERRED" && "$bounded" == "true" ]]; then
    EFG_RECORD_RESULT="ok"
    return 0
  fi

  EFG_RECORD_RESULT="inferred-unbounded"
  EFG_RECORD_DETAIL="record $token has payload.root_cause.tag='$tag' (blast_radius_bounded=$bounded) -- an INFERRED cause requires blast_radius_bounded=true"
  return 0
}

# ============================================================================
# Structured waiver (harness-hygiene-scan.sh precedent -- NEVER an env var).
# ============================================================================
_efg_waiver_covers_staged() {
  local repo_root="$1" staged="$2"
  local state_dir="$repo_root/.claude/state"
  [[ -d "$state_dir" ]] || return 1

  local f
  while IFS= read -r f; do
    [[ -f "$f" ]] || continue
    if declare -F waiver_has_purpose_clauses >/dev/null 2>&1; then
      waiver_has_purpose_clauses "$f" || continue
    fi
    local named
    named=$(grep -iE '^[[:space:]]*files[[:space:]]*:' "$f" 2>/dev/null \
      | sed -E 's/^[[:space:]]*[Ff][Ii][Ll][Ee][Ss][[:space:]]*:[[:space:]]*//' \
      | tr ', ' '\n\n')
    local p n
    while IFS= read -r p; do
      [[ -z "$p" ]] && continue
      while IFS= read -r n; do
        [[ -z "$n" ]] && continue
        [[ "$p" == "$n" ]] && return 0
      done <<< "$staged"
    done <<< "$named"
  done < <(find "$state_dir" -maxdepth 1 -type f -name 'evidence-before-fix-waiver-*.txt' -newermt '1 hour ago' 2>/dev/null)
  return 1
}

# ============================================================================
# Block message
# ============================================================================
_efg_block() {
  local reason="$1" detail="$2" repo_root="$3"
  {
    echo ""
    echo "================================================================"
    echo "EVIDENCE-BEFORE-FIX GATE — BLOCKED"
    echo "================================================================"
    echo ""
    echo "This commit's subject starts with fix( or fix: but no evidenced root"
    echo "cause was found. Reason: $reason"
    [[ -n "$detail" ]] && echo "  ($detail)"
    echo ""
    echo "Rule: docs/lessons/2026-07-14-root-cause-must-be-evidenced-before-fix.md"
    echo "Doctrine: adapters/claude-code/doctrine/evidence-before-fix.md"
    echo ""
    echo "\"I found a code path that could cause this\" is inference. \"The"
    echo "logs/data show this IS what happened\" is evidence. A fix may only"
    echo "ship on the latter."
    echo ""
    echo "To fix, do ONE of:"
    echo ""
    echo "  1. Add a section to the commit message body:"
    echo ""
    echo "       ## Root cause (evidenced)"
    echo "       PROVEN: <what you observed> (cite: file:line, a backtick-"
    echo "         quoted command/output, or a command:/output:/log: line)"
    echo ""
    echo "     A section with ONLY INFERRED-tagged lines is rejected -- an"
    echo "     inferred cause must be OBSERVED before shipping the fix."
    echo ""
    echo "  2. Reference a fix-root-cause review record: get one written via"
    echo "     scripts/write-review-record.sh capture --kind fix-root-cause"
    echo "     ..., then cite its record_id (frc-YYYYMMDD-xxxxxxxx) in the"
    echo "     commit message. The record must be verdict PASS, cover a"
    echo "     staged file, and have payload.root_cause.tag PROVEN (or"
    echo "     INFERRED with blast_radius_bounded true)."
    echo ""
    echo "  3. Genuinely trivial fix (typo, formatting, no runtime symptom)?"
    echo "     Use 'fix-trivial:' instead of 'fix:'/'fix(...)' -- it never"
    echo "     triggers this gate."
    echo ""
    echo "  4. Evidence genuinely unreachable? Write a structured waiver:"
    echo "       mkdir -p .claude/state"
    echo "       {"
    echo "         echo \"Purpose: this gate exists to prevent <X>\""
    echo "         echo \"Because: <Y -- name the missing datum + how you\""
    echo "         echo \"  tried to reach it; bound the fix to fail-safe\""
    echo "         echo \"  (fail-open / shadow-first) and say so here>\""
    echo "         echo \"Files: <staged file path(s), space-separated>\""
    echo "       } > .claude/state/evidence-before-fix-waiver-\$(date +%s).txt"
    echo "     Re-run the commit (waiver is honored for 1 hour)."
    echo ""
    echo "HONESTY NOTE: this gate checks STRUCTURE (a tagged section with a"
    echo "citation-shaped token, or a record's existence/coverage), not TRUTH"
    echo "-- it cannot verify a citation is real. The record path's audit"
    echo "trail (append-only, content-addressed) is the compensating control."
    echo "================================================================"
  } >&2
}

# ============================================================================
# Main
# ============================================================================
main() {
  local INPUT
  INPUT="${CLAUDE_TOOL_INPUT:-}"
  if [[ -z "$INPUT" ]]; then
    if [[ ! -t 0 ]]; then
      INPUT=$(cat 2>/dev/null || echo "")
    fi
  fi

  local COMMAND
  COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // .command // empty' 2>/dev/null || echo "")
  [[ -z "$COMMAND" ]] && exit 0

  echo "$COMMAND" | grep -qE '(^|[[:space:];&|])git[[:space:]]+commit([[:space:]]|$)' || exit 0
  echo "$COMMAND" | grep -qE 'git[[:space:]]+commit-tree' && exit 0

  local REPO_ROOT
  REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
  [[ -z "$REPO_ROOT" ]] && exit 0

  local COMMIT_MSG
  COMMIT_MSG=$(_efg_extract_commit_message "$COMMAND")
  [[ -z "$COMMIT_MSG" ]] && exit 0   # can't classify -- fail open

  local FIRST_LINE
  FIRST_LINE=$(printf '%s\n' "$COMMIT_MSG" | head -1)

  # Skip mechanically-replayed commits.
  if _efg_in_replay_context "$REPO_ROOT" "$FIRST_LINE"; then
    echo "[evidence-before-fix-gate] merge/rebase/cherry-pick context detected -- skipping." >&2
    exit 0
  fi

  # Trigger: subject starts with fix( or fix: exactly. fix-trivial: never
  # matches either (structural FP-path, see doctrine file).
  local IS_FIX=0
  if echo "$FIRST_LINE" | grep -qE '^fix\('; then IS_FIX=1; fi
  if echo "$FIRST_LINE" | grep -qE '^fix:'; then IS_FIX=1; fi
  [[ "$IS_FIX" -eq 0 ]] && exit 0

  local STAGED
  STAGED=$(cd "$REPO_ROOT" && git diff --cached --name-only --diff-filter=ACMR 2>/dev/null || echo "")

  # Path (a): inline evidenced section.
  _efg_check_inline_section "$COMMIT_MSG"
  if [[ "$EFG_SECTION_SATISFIED" -eq 1 ]]; then
    exit 0
  fi

  # Path (b): review-record reference.
  _efg_check_record_reference "$COMMIT_MSG" "$REPO_ROOT" "$STAGED"
  if [[ "$EFG_RECORD_RESULT" == "ok" ]]; then
    exit 0
  fi

  # Path (c): structured waiver.
  if _efg_waiver_covers_staged "$REPO_ROOT" "$STAGED"; then
    echo "[evidence-before-fix-gate] structured waiver honored." >&2
    command -v ledger_emit >/dev/null 2>&1 && ledger_emit "evidence-before-fix-gate" "waiver" "$FIRST_LINE"
    exit 0
  fi

  # BLOCK -- determine the most specific reason to report.
  local reason detail
  if [[ "$EFG_SECTION_PRESENT" -eq 1 ]] && [[ "$EFG_SECTION_HAS_PROVEN_NO_CITATION" -eq 1 ]]; then
    reason="the Root cause section has a PROVEN line but no citation-shaped token"
    detail="add a file:line reference, a backtick-quoted command/output, or a command:/output:/log: line to the PROVEN line"
  elif [[ "$EFG_SECTION_PRESENT" -eq 1 ]]; then
    reason="the Root cause section contains only INFERRED-tagged lines (no PROVEN line)"
    detail="an inferred-not-observed cause cannot ship as-is -- observe it, or bound the fix to fail-safe and use the waiver"
  elif [[ -n "$EFG_RECORD_TOKEN" ]]; then
    reason="the referenced record $EFG_RECORD_TOKEN did not satisfy the gate"
    detail="$EFG_RECORD_DETAIL"
  else
    reason="no ## Root cause (evidenced) section and no fix-root-cause record referenced"
    detail=""
  fi

  command -v ledger_emit >/dev/null 2>&1 && ledger_emit "evidence-before-fix-gate" "block" "$reason"
  _efg_block "$reason" "$detail" "$REPO_ROOT"
  exit 1
}

# ============================================================================
# --self-test
# ============================================================================
run_self_test() {
  local PASSED=0 FAILED=0 TMPDIR_ST
  TMPDIR_ST=$(mktemp -d 2>/dev/null || mktemp -d -t efgself)
  trap 'rm -rf "$TMPDIR_ST"' RETURN

  local SCRIPT_PATH
  SCRIPT_PATH="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/$(basename "$0")"

  (
    cd "$TMPDIR_ST" || exit 1
    git init -q . >/dev/null 2>&1
    git config core.hooksPath ""
    git config user.email "selftest@example.test"
    git config user.name "selftest"
    mkdir -p adapters/claude-code/hooks docs/reviews/records .claude/state
    echo "v1" > adapters/claude-code/hooks/alpha.sh
    git add adapters/claude-code/hooks/alpha.sh
    git commit -q -m "init" >/dev/null 2>&1
  ) || { echo "self-test: FAIL -- repo init failed" >&2; exit 1; }

  # _run <label> <expected_rc> <commit-message> <stage-file-fn>
  # Invokes the gate via stdin JSON (jq-built, so newlines/quotes are safe).
  _run() {
    local label="$1" expected_rc="$2" msg="$3" stage_fn="$4"
    (
      cd "$TMPDIR_ST" || exit 99
      git reset -q >/dev/null 2>&1
      $stage_fn
      local cmd
      cmd=$(printf 'git commit -m "$(cat <<%s\n%s\n%s\n)"' "'EOF'" "$msg" "EOF")
      local input
      input=$(jq -n --arg cmd "$cmd" '{tool_name:"Bash", tool_input:{command:$cmd}}')
      printf '%s' "$input" | bash "$SCRIPT_PATH" >stdout.txt 2>stderr.txt
      echo $? > rc.txt
    )
    local rc; rc=$(cat "$TMPDIR_ST/rc.txt" 2>/dev/null || echo 99)
    if [[ "$rc" == "$expected_rc" ]]; then
      echo "self-test ($label): PASS" >&2
      PASSED=$((PASSED+1))
    else
      echo "self-test ($label): FAIL (rc=$rc, expected $expected_rc)" >&2
      echo "  stderr: $(cat "$TMPDIR_ST/stderr.txt" 2>/dev/null | head -5)" >&2
      FAILED=$((FAILED+1))
    fi
  }

  stage_alpha() { echo "v2" > adapters/claude-code/hooks/alpha.sh; git add adapters/claude-code/hooks/alpha.sh; }

  # S1: fix( commit with PROVEN-tagged evidenced section + citation -> ALLOW
  _run "S1-proven-with-citation-allows" 0 \
    'fix(alpha): guard against nil ptr

## Root cause (evidenced)
PROVEN: the response body at adapters/claude-code/hooks/alpha.sh:12 shows a
nil dereference (log: TypeError: Cannot read properties of undefined).' \
    stage_alpha

  # S2: fix( commit with only INFERRED tags -> BLOCK
  _run "S2-inferred-only-blocks" 1 \
    'fix(alpha): add uniqueness guard

## Root cause (evidenced)
INFERRED: a missing uniqueness constraint could allow a double-submit to
insert a duplicate row.' \
    stage_alpha

  # S3: fix( commit with no section, no record -> BLOCK
  _run "S3-no-evidence-blocks" 1 \
    'fix(alpha): tighten validation' \
    stage_alpha

  # S4: non-fix commit -> ALLOW
  _run "S4-non-fix-allows" 0 \
    'feat(alpha): add new capability' \
    stage_alpha

  # S5: merge-context -> ALLOW (skip)
  (
    cd "$TMPDIR_ST" || exit 99
    git reset -q >/dev/null 2>&1
    stage_alpha
    echo "0000000000000000000000000000000000000000" > .git/MERGE_HEAD
    local cmd input
    cmd='git commit -m "fix(alpha): merge resolution with no evidence section"'
    input=$(jq -n --arg cmd "$cmd" '{tool_name:"Bash", tool_input:{command:$cmd}}')
    printf '%s' "$input" | bash "$SCRIPT_PATH" >stdout.txt 2>stderr.txt
    echo $? > rc.txt
    rm -f .git/MERGE_HEAD
  )
  RC5=$(cat "$TMPDIR_ST/rc.txt" 2>/dev/null || echo 99)
  if [[ "$RC5" == "0" ]]; then
    echo "self-test (S5-merge-context-skips): PASS" >&2; PASSED=$((PASSED+1))
  else
    echo "self-test (S5-merge-context-skips): FAIL (rc=$RC5, expected 0)" >&2; FAILED=$((FAILED+1))
  fi

  # S6: record-reference path -- ALLOW when a matching fix-root-cause record
  # exists (created via write-review-record.sh in this fixture).
  local WRITE_RECORD="$SELF_DIR/../scripts/write-review-record.sh"
  if [[ -x "$WRITE_RECORD" ]] || [[ -f "$WRITE_RECORD" ]]; then
    (
      cd "$TMPDIR_ST" || exit 99
      git reset -q >/dev/null 2>&1
      stage_alpha
      OUT=$(bash "$WRITE_RECORD" capture --kind fix-root-cause --reviewer orchestrator \
        --verdict PASS --plan-ref "docs/plans/harness-governance-batch-2026-07-15.md#task-3" \
        --quote "PROVEN via vercel logs -- see incident trace." \
        --file "adapters/claude-code/hooks/alpha.sh" \
        --payload '{"root_cause":{"tag":"PROVEN","evidence":"vercel logs dpl_x line 412"},"blast_radius_bounded":true}' \
        --repo-root "$TMPDIR_ST" 2>&1)
      REC_ID=$(printf '%s\n' "$OUT" | tail -1)
      local cmd input
      cmd=$(printf 'git commit -m "fix(alpha): apply the reviewed fix (%s)"' "$REC_ID")
      input=$(jq -n --arg cmd "$cmd" '{tool_name:"Bash", tool_input:{command:$cmd}}')
      printf '%s' "$input" | bash "$SCRIPT_PATH" >stdout.txt 2>stderr.txt
      echo $? > rc.txt
    )
    RC6=$(cat "$TMPDIR_ST/rc.txt" 2>/dev/null || echo 99)
    if [[ "$RC6" == "0" ]]; then
      echo "self-test (S6-record-reference-allows): PASS" >&2; PASSED=$((PASSED+1))
    else
      echo "self-test (S6-record-reference-allows): FAIL (rc=$RC6, expected 0)" >&2
      echo "  stderr: $(cat "$TMPDIR_ST/stderr.txt" 2>/dev/null | head -8)" >&2
      FAILED=$((FAILED+1))
    fi

    # S7: record exists but does NOT cover any staged file -> BLOCK
    (
      cd "$TMPDIR_ST" || exit 99
      git reset -q >/dev/null 2>&1
      mkdir -p adapters/claude-code/hooks
      echo "unrelated" > adapters/claude-code/hooks/beta.sh
      git add adapters/claude-code/hooks/beta.sh
      OUT=$(bash "$WRITE_RECORD" capture --kind fix-root-cause --reviewer orchestrator \
        --verdict PASS --plan-ref "docs/plans/harness-governance-batch-2026-07-15.md#task-3" \
        --quote "PROVEN via logs." \
        --file "adapters/claude-code/hooks/alpha.sh" \
        --payload '{"root_cause":{"tag":"PROVEN"},"blast_radius_bounded":true}' \
        --repo-root "$TMPDIR_ST" 2>&1)
      REC_ID=$(printf '%s\n' "$OUT" | tail -1)
      local cmd input
      cmd=$(printf 'git commit -m "fix(beta): unrelated change citing wrong record (%s)"' "$REC_ID")
      input=$(jq -n --arg cmd "$cmd" '{tool_name:"Bash", tool_input:{command:$cmd}}')
      printf '%s' "$input" | bash "$SCRIPT_PATH" >stdout.txt 2>stderr.txt
      echo $? > rc.txt
    )
    RC7=$(cat "$TMPDIR_ST/rc.txt" 2>/dev/null || echo 99)
    if [[ "$RC7" == "1" ]]; then
      echo "self-test (S7-record-no-coverage-blocks): PASS" >&2; PASSED=$((PASSED+1))
    else
      echo "self-test (S7-record-no-coverage-blocks): FAIL (rc=$RC7, expected 1)" >&2
      FAILED=$((FAILED+1))
    fi
  else
    echo "self-test (S6/S7): SKIPPED (write-review-record.sh not found at $WRITE_RECORD)" >&2
  fi

  # S8: fix-trivial: prefix never triggers -> ALLOW
  _run "S8-fix-trivial-prefix-exempt" 0 \
    'fix-trivial: correct a typo in a comment' \
    stage_alpha

  # S9: structured waiver honored (fresh, both clauses, Files: matches staged)
  (
    cd "$TMPDIR_ST" || exit 99
    git reset -q >/dev/null 2>&1
    stage_alpha
    {
      echo "Purpose: this gate exists to prevent an inferred-not-observed cause from shipping"
      echo "Because: prod DB access is unreachable this session (Supabase 401); the fix is fail-open (feature-flagged off by default)"
      echo "Files: adapters/claude-code/hooks/alpha.sh"
    } > .claude/state/evidence-before-fix-waiver-selftest.txt
    local cmd input
    cmd='git commit -m "fix(alpha): fail-open guard, evidence unreachable"'
    input=$(jq -n --arg cmd "$cmd" '{tool_name:"Bash", tool_input:{command:$cmd}}')
    printf '%s' "$input" | bash "$SCRIPT_PATH" >stdout.txt 2>stderr.txt
    echo $? > rc.txt
    rm -f .claude/state/evidence-before-fix-waiver-selftest.txt
  )
  RC9=$(cat "$TMPDIR_ST/rc.txt" 2>/dev/null || echo 99)
  if [[ "$RC9" == "0" ]]; then
    echo "self-test (S9-waiver-honored): PASS" >&2; PASSED=$((PASSED+1))
  else
    echo "self-test (S9-waiver-honored): FAIL (rc=$RC9, expected 0)" >&2; FAILED=$((FAILED+1))
  fi

  # S10: waiver present but WITHOUT purpose-clause pair -> still BLOCK
  (
    cd "$TMPDIR_ST" || exit 99
    git reset -q >/dev/null 2>&1
    stage_alpha
    echo "Files: adapters/claude-code/hooks/alpha.sh" > .claude/state/evidence-before-fix-waiver-weak.txt
    local cmd input
    cmd='git commit -m "fix(alpha): weak waiver attempt"'
    input=$(jq -n --arg cmd "$cmd" '{tool_name:"Bash", tool_input:{command:$cmd}}')
    printf '%s' "$input" | bash "$SCRIPT_PATH" >stdout.txt 2>stderr.txt
    echo $? > rc.txt
    rm -f .claude/state/evidence-before-fix-waiver-weak.txt
  )
  RC10=$(cat "$TMPDIR_ST/rc.txt" 2>/dev/null || echo 99)
  if [[ "$RC10" == "1" ]]; then
    echo "self-test (S10-weak-waiver-blocks): PASS" >&2; PASSED=$((PASSED+1))
  else
    echo "self-test (S10-weak-waiver-blocks): FAIL (rc=$RC10, expected 1)" >&2; FAILED=$((FAILED+1))
  fi

  echo "" >&2
  echo "self-test summary: ${PASSED} passed, ${FAILED} failed (of $((PASSED+FAILED)) scenarios)" >&2
  [[ "$FAILED" -eq 0 ]]
}

case "${1:-}" in
  --self-test) run_self_test; exit $? ;;
  *) main ;;
esac
