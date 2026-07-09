#!/usr/bin/env bash
# pr-template-inline-gate.sh
#
# DEMOTED to non-blocking warn at NL Overhaul Wave D.6 (§D.0.4 / §D.6
# item 8, 2026-07-02): every path that used to `exit 1` (block) now
# exits 0 and instead emits a hookSpecificOutput.additionalContext warn
# (the sanctioned channel that reaches model context) plus a
# signal-ledger `warn` event. Detection/parsing logic (extract_body_
# from_command, the validator invocation) is UNCHANGED — only the
# verdict emission changed from block to warn. manifest.json's
# `blocking` flag for this unit flips to false in the same wave (D.5
# template/manifest cutover). Note: the SERVER-SIDE `PR Template Check`
# CI workflow and `pre-push-pr-template.sh` (git pre-push hook, separate
# mechanism) are UNAFFECTED by this demotion — they still enforce; this
# hook's local PreToolUse early-warning just no longer blocks the tool
# call itself.
#
# Closes HARNESS-GAP-40 — local-side validation of inline PR bodies passed
# to `gh pr create` / `gh pr edit` via `--body`, `--body=`, or `--body-file`.
#
# Why this hook exists.
#   The existing `pre-push-pr-template.sh` (git pre-push hook) validates a
#   developer-authored `.pr-description.md` OR the latest commit message
#   body — never the inline `--body` argument an AI session typically uses
#   via `gh pr create --body "$(cat <<'EOF' ... EOF)"`. The first push
#   therefore reaches GitHub, the server-side `PR Template Check` workflow
#   fires, fails, emails the operator, and the AI session has to amend the
#   PR body with a second push. Misha logged ~19 such failures across ~12
#   branches in the past week — pure email spam with no signal value, and
#   a constant 2-push cycle for every AI-spawned PR.
#
# What this hook does.
#   Fires as a PreToolUse hook on `Bash`. Self-detects whether the command
#   being run is `gh pr create` or `gh pr edit` (and a body source is
#   present). Parses the inline body content from `--body`, `--body=`, or
#   `--body-file`, pipes it into `.github/scripts/validate-pr-template.sh`
#   (the canonical validator already used by the CI workflow + the local
#   pre-push hook — same regex, same canonical stderr), and blocks the
#   tool call when validation fails. Same diagnostic in all three places.
#
# Body-source recognition.
#   --body "<literal>"
#   --body '<literal>'
#   --body=<value>          (both quoted + bare-token shapes)
#   --body "$(cat <<EOF ... EOF)" and <<'EOF' / <<"EOF" / arbitrary tag
#   --body-file <path>      (relative path resolves vs repo root)
#   --body-file "$VAR/path" (unexpanded shell construct — nl-issue 59:
#                           conservative env-only expansion is attempted
#                           ($VAR/${VAR}/leading ~, from the hook's own
#                           environment; NEVER command substitution). If
#                           expansion resolves to an existing file it is
#                           validated normally; otherwise the existence
#                           test is SKIPPED (the gate cannot statically
#                           know the runtime path) — no false WARN.
#   --body-file -           (stdin — not supported; BLOCKS with hint)
#   --fill                  (gh derives body from commit messages) → PASS
#                           through (the existing pre-push hook handles
#                           commit-message validation when push happens).
#   No body source at all   → PASS through (gh's default behaviour;
#                           validation will happen at push time if at all).
#
# Decision: sibling to `vaporware-volume-gate.sh`, not an extension.
#   The vaporware-volume gate is a different concern (volume heuristic for
#   describes-vs-executes file ratio). Conflating template-content
#   validation with volume-shape validation would make both checks harder
#   to reason about, harder to self-test in isolation, and would push
#   `vaporware-volume-gate.sh` past 500 lines. Sibling preserves clean
#   separation; both wire on the same `Bash` matcher.
#
# Exit codes.
#   0 — command allowed (not a `gh pr create/edit` body call, or template
#       validation PASSED, or no body source present, or `--fill` used)
#   1 — command blocked (stderr explains the failing validation, names
#       the missing section / placeholder / answer form, and points at
#       remediation)
#   2 — internal error (validator library missing, parse failure on
#       malformed input — fails closed)
#
# Rule:  rules/planning.md "Capture-codify at PR time"
# Plan:  N/A (build-harness-infrastructure work-shape; single-purpose hook)
# Cross: vaporware-volume-gate.sh (sibling on `gh pr create`)
#        pre-push-pr-template.sh  (git-side, validates .pr-description.md
#                                  + commit messages; this hook is the
#                                  inline-body-side complement)
#        .github/scripts/validate-pr-template.sh (canonical validator;
#                                  sourced here, same as the two siblings)

set -eo pipefail

_PTIG_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
# shellcheck source=lib/signal-ledger.sh
source "$_PTIG_SELF_DIR/lib/signal-ledger.sh" 2>/dev/null || true

# ============================================================
# _demote_warn <title> <body> — emit the demoted-to-warn verdict:
# hookSpecificOutput.additionalContext JSON on stdout (reaches model
# context) + a human-readable copy on stderr + a signal-ledger warn
# event, then exit 0 (never blocks).
# ============================================================
_demote_warn() {
  local title="$1"
  local body="$2"
  printf '%s\n' "$body" >&2
  if command -v jq >/dev/null 2>&1; then
    jq -n --arg ctx "[pr-template-inline-gate] WARN (demoted from block, Wave D.6): ${title}
${body}" \
      '{hookSpecificOutput:{hookEventName:"PreToolUse", additionalContext:$ctx}}'
  fi
  command -v ledger_emit >/dev/null 2>&1 && ledger_emit "pr-template-inline-gate" "warn" "$title"
  exit 0
}

# ============================================================
# _ptig_expand_path <path> — conservative env-only expansion (nl-issue 59).
#
# Expands a leading `~` (to $HOME) and `$VAR` / `${VAR}` occurrences
# where VAR is defined in the hook's own environment. NEVER performs
# command substitution (`$(...)` or backticks → refuse immediately).
# Echoes the expanded path and returns 0 only when NO unexpanded
# construct remains; returns 1 when any construct is unresolvable
# (undefined var, `~user` form, `${VAR:-...}` operators, `$(`, backtick).
# ============================================================
_ptig_expand_path() {
  local p="$1"
  # Command substitution: never attempt (could hide arbitrary commands).
  if [[ "$p" == *'$('* ]] || [[ "$p" == *'`'* ]]; then
    return 1
  fi
  # Leading tilde: bare `~` or `~/...` → $HOME; `~user` form → unresolvable.
  if [[ "${p:0:1}" == "~" ]]; then
    if [[ "$p" == "~" ]] || [[ "${p:1:1}" == "/" ]]; then
      p="${HOME}${p:1}"
    else
      return 1
    fi
  fi
  local guard=0 m var
  while [[ "$p" == *'$'* ]]; do
    guard=$((guard + 1))
    if [[ $guard -gt 16 ]]; then
      return 1
    fi
    if [[ "$p" =~ \$\{[A-Za-z_][A-Za-z0-9_]*\} ]]; then
      m="${BASH_REMATCH[0]}"
      var="${m:2:${#m}-3}"
    elif [[ "$p" =~ \$[A-Za-z_][A-Za-z0-9_]* ]]; then
      m="${BASH_REMATCH[0]}"
      var="${m:1}"
    else
      # A `$` that is not a plain $VAR/${VAR} reference (e.g. ${VAR:-x},
      # trailing `$`) — unresolvable conservatively.
      return 1
    fi
    if [[ -z "${!var+x}" ]]; then
      # Variable not defined in the hook's environment.
      return 1
    fi
    # Replacement quoted: under bash>=5.2 patsub_replacement, an unquoted
    # replacement re-expands `&` to the matched pattern (harness-reviewer
    # finding, proven on this machine's bash 5.2.37).
    p="${p/"$m"/"${!var}"}"
  done
  printf '%s\n' "$p"
  return 0
}

# ============================================================
# extract_body_from_command — parse the inline body from the
# tokenized `gh pr create/edit` invocation.
#
# Echoes the body content to stdout. Returns 0 on successful
# extraction OR 0 with empty stdout when no body source is present.
# Returns 2 on a body-file path that does not exist or stdin (`-`).
# Returns 3 (BODY_FILE_UNEXPANDABLE sentinel) on a body-file path
# containing an unexpanded shell construct the hook cannot resolve
# from its own environment — caller skips the existence test.
#
# Implementation note: uses bash parameter expansion (not sed) because
# `sed` operates line-by-line and cannot capture multi-line `"..."`
# strings. PR bodies are virtually always multi-line.
# ============================================================
extract_body_from_command() {
  local cmd="$1"
  local repo_root="$2"
  local rest body_file body

  # --- Path 1: --body-file <path>  or  --body-file=<path>
  body_file=""
  if [[ "$cmd" == *"--body-file="* ]]; then
    # --body-file=<value>  : value runs to next whitespace or quote
    rest="${cmd#*--body-file=}"
    # Strip leading optional quote
    if [[ "${rest:0:1}" == '"' ]]; then
      rest="${rest:1}"
      body_file="${rest%%\"*}"
    elif [[ "${rest:0:1}" == "'" ]]; then
      rest="${rest:1}"
      body_file="${rest%%\'*}"
    else
      # bare token - up to first whitespace
      body_file="${rest%%[[:space:]]*}"
    fi
  elif [[ "$cmd" == *"--body-file "* ]] || [[ "$cmd" == *"--body-file"$'\t'* ]]; then
    # --body-file <value>  : space-separated
    rest="${cmd#*--body-file}"
    # Strip leading whitespace
    rest="${rest#"${rest%%[![:space:]]*}"}"
    if [[ "${rest:0:1}" == '"' ]]; then
      rest="${rest:1}"
      body_file="${rest%%\"*}"
    elif [[ "${rest:0:1}" == "'" ]]; then
      rest="${rest:1}"
      body_file="${rest%%\'*}"
    else
      body_file="${rest%%[[:space:]]*}"
    fi
  fi

  if [[ -n "$body_file" ]]; then
    if [[ "$body_file" == "-" ]]; then
      # Stdin body not supported by this gate — the Bash tool's stdin
      # is the hook-input JSON, not the user's PR body. Block with hint.
      printf 'STDIN_NOT_SUPPORTED\n'
      return 2
    fi
    # nl-issue 59: the extracted path is the UNEXPANDED command string.
    # A path containing a shell construct (`$`, backtick, leading `~`)
    # cannot be `-f`-tested as-is — doing so false-WARNed "does not
    # exist" while the actual gh call succeeded. Try conservative
    # env-only expansion; validate normally if it resolves to an
    # existing file, otherwise SKIP the existence test entirely.
    if [[ "$body_file" == *'$'* ]] || [[ "$body_file" == *'`'* ]] || [[ "${body_file:0:1}" == "~" ]]; then
      local expanded=""
      if expanded=$(_ptig_expand_path "$body_file"); then
        local eresolved="$expanded"
        if [[ "${eresolved:0:1}" != "/" ]] && [[ ! "${eresolved:1:1}" == ":" ]]; then
          eresolved="$repo_root/$eresolved"
        fi
        if [[ -f "$eresolved" ]]; then
          printf '[pr-template-inline-gate] validated after env expansion: %s -> %s\n' "$body_file" "$eresolved" >&2
          cat "$eresolved"
          return 0
        fi
      fi
      # Unresolvable (undefined var / $(...) / ~user) or the expanded
      # path is absent from the HOOK's view — the runtime shell may
      # expand differently. Never false-WARN; downstream gh + CI validate.
      printf 'BODY_FILE_UNEXPANDABLE\t%s\n' "$body_file"
      return 3
    fi
    # Resolve relative to repo root if not absolute (POSIX or Windows-style).
    local resolved="$body_file"
    if [[ "${resolved:0:1}" != "/" ]] && [[ ! "${resolved:1:1}" == ":" ]]; then
      resolved="$repo_root/$body_file"
    fi
    if [[ ! -f "$resolved" ]]; then
      printf 'BODY_FILE_MISSING\t%s\n' "$resolved"
      return 2
    fi
    cat "$resolved"
    return 0
  fi

  # --- Path 2: --body "$(cat <<TAG ... TAG)" form (heredoc).
  # Detect the heredoc tag (quoted or unquoted) and extract the body
  # between the opening `<<TAG` and the closing TAG line.
  if printf '%s' "$cmd" | grep -qE '<<[[:space:]]*['"'"'"]*[A-Za-z_][A-Za-z0-9_]*'; then
    # Extract the tag itself (strip optional quotes).
    local tag
    tag=$(printf '%s' "$cmd" | sed -nE "s/.*<<[[:space:]]*['\"]?([A-Za-z_][A-Za-z0-9_]*)['\"]?.*/\\1/p" | head -1)
    if [[ -n "$tag" ]]; then
      # The heredoc body is everything between `<<TAG\n` (or `<<'TAG'\n`)
      # and the line that is exactly `TAG`. Use awk to extract.
      printf '%s' "$cmd" | awk -v tag="$tag" '
        BEGIN { in_heredoc = 0 }
        {
          if (!in_heredoc) {
            # Look for the heredoc opener on this line.
            if (match($0, "<<[[:space:]]*[\x27\"]?" tag "[\x27\"]?")) {
              in_heredoc = 1
              # Rest of this line after the heredoc operator is not the body.
              next
            }
            next
          }
          # in_heredoc == 1
          # Closing tag line: line is exactly TAG (allow trailing whitespace)
          if ($0 ~ "^[[:space:]]*" tag "[[:space:]]*$") {
            in_heredoc = 0
            exit 0
          }
          print
        }
      '
      return 0
    fi
  fi

  # --- Path 3: --body=<value>  (equals form)
  # Forms in priority: --body="..."  -->  --body='...'  -->  --body=<bare>
  body=""
  if [[ "$cmd" == *'--body="'* ]]; then
    rest="${cmd#*--body=\"}"
    body="${rest%%\"*}"
    printf '%s' "$body"
    return 0
  fi
  if [[ "$cmd" == *"--body='"* ]]; then
    rest="${cmd#*--body=\'}"
    body="${rest%%\'*}"
    printf '%s' "$body"
    return 0
  fi
  if [[ "$cmd" == *"--body="* ]]; then
    rest="${cmd#*--body=}"
    body="${rest%%[[:space:]]*}"
    if [[ -n "$body" ]]; then
      printf '%s' "$body"
      return 0
    fi
  fi

  # --- Path 4: --body "..." (space-separated, double-quoted)
  if [[ "$cmd" == *'--body "'* ]]; then
    rest="${cmd#*--body \"}"
    body="${rest%%\"*}"
    printf '%s' "$body"
    return 0
  fi
  # --body '...' (space-separated, single-quoted)
  if [[ "$cmd" == *"--body '"* ]]; then
    rest="${cmd#*--body \'}"
    body="${rest%%\'*}"
    printf '%s' "$body"
    return 0
  fi

  # No body source recognised — return empty.
  return 0
}

# ============================================================
# --self-test
# ============================================================

if [[ "${1:-}" == "--self-test" ]]; then
  SCRIPT="${BASH_SOURCE[0]}"

  # Resolve validator library (used by all self-test cases). Mirrors the
  # runtime-path resolution below (git rev-parse --show-toplevel from cwd —
  # same idiom sibling vaporware-volume-gate.sh uses) so this works from any
  # cwd. A fixed-depth `dirname "$SCRIPT"/../../..` hop is NOT used here: it
  # silently resolves to the wrong directory when invoked from the LIVE
  # mirror (~/.claude/hooks — doctor --full does this), since the mirror has
  # no repo three levels up (it walked to $HOME's parent, e.g.
  # /c/Users/.github/... instead of the actual repo's .github/). Fall back to
  # nl-paths' self-location-based resolver (which also tries git, from the
  # SCRIPT's own directory rather than cwd, plus config-file/probe-list
  # fallbacks) when cwd isn't inside a git repo at all.
  REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
  if [[ ! -f "$REPO_ROOT/.github/scripts/validate-pr-template.sh" ]] && [[ -f "$_PTIG_SELF_DIR/lib/nl-paths.sh" ]]; then
    # shellcheck disable=SC1091
    source "$_PTIG_SELF_DIR/lib/nl-paths.sh"
    REPO_ROOT="$(nl_repo_root)"
  fi
  VALIDATOR_LIB="$REPO_ROOT/.github/scripts/validate-pr-template.sh"
  if [[ ! -f "$VALIDATOR_LIB" ]]; then
    echo "self-test: validator library missing at $VALIDATOR_LIB" >&2
    exit 2
  fi

  TMPDIR_TEST=$(mktemp -d)
  trap 'rm -rf "$TMPDIR_TEST"' EXIT

  VALID_BODY='## Summary

A valid PR body.

## What changed and why

Some changes.

## What mechanism would have caught this?

### a) Existing catalog entry

FM-006 self-reported task completion without evidence — caught by plan-edit-validator.

## Testing performed

Self-tested.'

  INVALID_BODY_NO_SUMMARY='## Some random body

No template sections at all here.'

  # Write fixture body files
  echo "$VALID_BODY" > "$TMPDIR_TEST/valid-body.md"
  echo "$INVALID_BODY_NO_SUMMARY" > "$TMPDIR_TEST/invalid-body.md"

  FAILED=0

  # Wave D.6 (§D.6 item 8): every path that used to BLOCK (exit 1) now
  # exits 0 and instead emits a WARN. `expected_warn` below therefore
  # means "1=detection should still fire (now as a WARN in stderr, exit
  # STILL 0), 0=no detection, silent allow". Every scenario now expects
  # exit_code==0 — the distinguishing signal is presence/absence of the
  # WARN marker in stderr, which proves detection logic is unchanged.
  run_scenario() {
    local name="$1"
    local command_str="$2"
    local expected_warn="$3"   # 1=expect WARN detected (stderr), 0=silent allow
    local label="$4"
    local required_marker="${5:-}"  # optional: stderr must contain this string

    local input
    input=$(jq -nc --arg cmd "$command_str" '{tool_input: {command: $cmd}}')

    local exit_code=0
    local stderr_out
    stderr_out=$(PR_TEMPLATE_INLINE_GATE_TEST_REPO_ROOT="$REPO_ROOT" \
      bash "$SCRIPT" <<<"$input" 2>&1 >/dev/null) || exit_code=$?

    local warn_present=0
    if printf '%s' "$stderr_out" | grep -q "WARN (demoted from block\|WARN, not a block\|not supported\|does not exist"; then
      warn_present=1
    fi

    if [[ $exit_code -ne 0 ]]; then
      echo "self-test ($name) [$label]: FAIL — expected exit=0 always post-demotion, got exit=$exit_code" >&2
      FAILED=1
      return
    fi

    if [[ -n "$required_marker" ]] && ! printf '%s' "$stderr_out" | grep -qF "$required_marker"; then
      echo "self-test ($name) [$label]: FAIL — stderr missing required marker '$required_marker'" >&2
      FAILED=1
      return
    fi

    if [[ "$expected_warn" == "1" ]]; then
      if [[ "$warn_present" == "1" ]]; then
        echo "self-test ($name) [$label]: ALLOW + WARN detected (expected)" >&2
      else
        echo "self-test ($name) [$label]: ALLOW but NO WARN detected (expected WARN)" >&2
        FAILED=1
      fi
    else
      if [[ "$warn_present" == "0" ]]; then
        echo "self-test ($name) [$label]: ALLOW, silent (expected)" >&2
      else
        echo "self-test ($name) [$label]: ALLOW but unexpected WARN detected" >&2
        FAILED=1
      fi
    fi
  }

  # T1: Valid inline --body with all sections → PASS, silent
  run_scenario "T1-valid-inline-body" \
    "gh pr create --title \"test\" --body \"$VALID_BODY\"" \
    0 "valid --body with all sections → ALLOW, silent"

  # T2 (Wave D.6 demotion): --body missing required sections → ALLOW +
  # WARN detected (was BLOCK exit 1 pre-demotion).
  run_scenario "T2-invalid-inline-body" \
    "gh pr create --title \"test\" --body \"$INVALID_BODY_NO_SUMMARY\"" \
    1 "--body missing mechanism section → ALLOW + WARN (demoted)"

  # T3: --body via heredoc form → parses correctly, validates valid body
  # Note: command is delivered as the literal string the shell would receive
  # PRE-execution; we test the parser against the heredoc form directly.
  HEREDOC_CMD='gh pr create --title test --body "$(cat <<EOF
'"$VALID_BODY"'
EOF
)"'
  run_scenario "T3-heredoc-valid" \
    "$HEREDOC_CMD" \
    0 "valid --body via heredoc → ALLOW"

  # T4: --body-file with valid content → PASSES
  run_scenario "T4-body-file-valid" \
    "gh pr create --title test --body-file $TMPDIR_TEST/valid-body.md" \
    0 "--body-file <valid> → ALLOW"

  # T5 (Wave D.6 demotion): --body-file with invalid content → ALLOW +
  # WARN detected (was BLOCK exit 1 pre-demotion).
  run_scenario "T5-body-file-invalid" \
    "gh pr create --title test --body-file $TMPDIR_TEST/invalid-body.md" \
    1 "--body-file <invalid> → ALLOW + WARN (demoted)"

  # T6 (Wave D.6 demotion): --body-file - (stdin) → ALLOW + WARN with
  # stdin-not-supported message (was BLOCK exit 1 pre-demotion).
  run_scenario "T6-body-file-stdin" \
    "gh pr create --title test --body-file -" \
    1 "--body-file - (stdin) → ALLOW + WARN stdin-not-supported (demoted)"

  # T7: gh pr create with NO --body/--body-file/--fill → PASS through
  run_scenario "T7-no-body-source" \
    "gh pr create --title test" \
    0 "no body source → ALLOW (pass-through)"

  # T8: gh pr create --fill → PASS through (commit messages used)
  run_scenario "T8-fill-flag" \
    "gh pr create --title test --fill" \
    0 "--fill flag → ALLOW (pass-through)"

  # T9 (Wave D.6 demotion): gh pr edit <N> --body missing sections →
  # ALLOW + WARN detected (was BLOCK exit 1 pre-demotion).
  run_scenario "T9-edit-invalid" \
    "gh pr edit 42 --body \"$INVALID_BODY_NO_SUMMARY\"" \
    1 "gh pr edit with invalid --body → ALLOW + WARN (demoted)"

  # T10: --body='inline with equals' form → parses correctly (passes)
  # Build a body that uses the equals form; use single quotes to avoid
  # shell expansion issues in the synthetic test command.
  run_scenario "T10-body-equals-form" \
    "gh pr create --title test --body='$VALID_BODY'" \
    0 "--body='<valid>' equals-form → ALLOW"

  # T11 (bonus): non-gh Bash command → PASS through silently
  run_scenario "T11-non-gh-bash" \
    "ls -la /tmp" \
    0 "non-gh Bash → ALLOW (pass-through silent)"

  # --- nl-issue 59 scenarios: unexpanded shell constructs in --body-file ---

  # T12: LITERAL nonexistent path → real "does not exist" WARN still fires
  # (unchanged behavior — the skip applies only to unexpandable paths).
  run_scenario "T12-body-file-literal-missing" \
    "gh pr create --title test --body-file $TMPDIR_TEST/definitely-absent-body.md" \
    1 "--body-file <literal nonexistent> → ALLOW + WARN does-not-exist (unchanged)"

  # T13: $VAR path where VAR is UNDEFINED in the hook env → skipped as
  # unexpandable; NO false "does not exist" WARN (RED on pre-fix code).
  unset PTIG_TEST_UNDEFINED_VAR_XYZ
  run_scenario "T13-body-file-undefined-var" \
    'gh pr create --title test --body-file "$PTIG_TEST_UNDEFINED_VAR_XYZ/pr-body.md"' \
    0 '--body-file "$UNDEFINED/..." → ALLOW, skipped-unexpandable, no false WARN' \
    "skipped: unexpandable path"

  # T14: $VAR path where VAR IS defined and file exists (valid body) →
  # env-expanded and validated normally; silent allow + expansion log line.
  export PTIG_TEST_BODY_DIR="$TMPDIR_TEST"
  run_scenario "T14-body-file-defined-var-valid" \
    'gh pr create --title test --body-file "$PTIG_TEST_BODY_DIR/valid-body.md"' \
    0 '--body-file "$DEFINED/valid" → ALLOW after env expansion' \
    "validated after env expansion"

  # T15: $VAR path, VAR defined, file exists but content INVALID → content
  # validation runs on the expanded file and the template WARN fires
  # (proves expansion feeds the real validator, not a silent skip).
  run_scenario "T15-body-file-defined-var-invalid" \
    'gh pr create --title test --body-file "$PTIG_TEST_BODY_DIR/invalid-body.md"' \
    1 '--body-file "$DEFINED/invalid" → ALLOW + template WARN after env expansion' \
    "validated after env expansion"
  unset PTIG_TEST_BODY_DIR

  # T16 (harness-reviewer Major): command-substitution path → REFUSED
  # (never executed, never expanded) → skipped-unexpandable. This is the
  # safety-critical refusal property of _ptig_expand_path.
  run_scenario "T16-body-file-command-substitution" \
    'gh pr create --title test --body-file "$(mktemp)/pr-body.md"' \
    0 '--body-file "$(cmd)/..." → ALLOW, refusal → skipped-unexpandable' \
    "skipped: unexpandable path"

  # T17 (harness-reviewer Major): ${VAR:-default} operator form → refused
  # (only plain $VAR/${VAR} are expanded) → skipped-unexpandable.
  run_scenario "T17-body-file-operator-form" \
    'gh pr create --title test --body-file "${PTIG_UNDEF:-/tmp}/pr-body.md"' \
    0 '--body-file "${VAR:-x}/..." → ALLOW, refusal → skipped-unexpandable' \
    "skipped: unexpandable path"

  if [[ $FAILED -eq 0 ]]; then
    echo "all 17 self-tests passed" >&2
    exit 0
  else
    echo "self-test failures detected" >&2
    exit 1
  fi
fi

# ============================================================
# Main hook entry
# ============================================================

INPUT="${CLAUDE_TOOL_INPUT:-}"
if [[ -z "$INPUT" ]]; then
  if [[ ! -t 0 ]]; then
    INPUT=$(cat 2>/dev/null || echo "")
  fi
fi

COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // .command // empty' 2>/dev/null || echo "")
if [[ -z "$COMMAND" ]]; then
  exit 0
fi

# Only fire on `gh pr create` or `gh pr edit`.
IS_PR_CREATE=0
IS_PR_EDIT=0
if echo "$COMMAND" | grep -qE '(^|[[:space:]])gh[[:space:]]+pr[[:space:]]+create\b'; then
  IS_PR_CREATE=1
fi
if echo "$COMMAND" | grep -qE '(^|[[:space:]])gh[[:space:]]+pr[[:space:]]+edit\b'; then
  IS_PR_EDIT=1
fi
if [[ $IS_PR_CREATE -eq 0 ]] && [[ $IS_PR_EDIT -eq 0 ]]; then
  exit 0
fi

# Check for --fill (gh derives body from commit messages). Pass through —
# the pre-push hook handles commit-message validation at push time.
if echo "$COMMAND" | grep -qE '(^|[[:space:]])--fill(\b|=)'; then
  exit 0
fi

# Resolve repo root for body-file path resolution AND validator-library
# location. Allow test-override via PR_TEMPLATE_INLINE_GATE_TEST_REPO_ROOT.
REPO_ROOT=""
if [[ -n "${PR_TEMPLATE_INLINE_GATE_TEST_REPO_ROOT:-}" ]]; then
  REPO_ROOT="$PR_TEMPLATE_INLINE_GATE_TEST_REPO_ROOT"
else
  REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
fi
if [[ -z "$REPO_ROOT" ]]; then
  # Cannot determine repo root — fail open (consistent with sibling
  # vaporware-volume-gate.sh behavior on the same condition).
  exit 0
fi

VALIDATOR_LIB="$REPO_ROOT/.github/scripts/validate-pr-template.sh"
if [[ ! -f "$VALIDATOR_LIB" ]]; then
  # Validator library not found — this is a project that hasn't opted into
  # the capture-codify PR-template convention. Pass through silently.
  exit 0
fi

# Extract the body content.
EXTRACT_RESULT=""
EXTRACT_EXIT=0
EXTRACT_RESULT=$(extract_body_from_command "$COMMAND" "$REPO_ROOT") || EXTRACT_EXIT=$?

# nl-issue 59: unexpandable --body-file path — the gate cannot statically
# know the runtime path. Skip the existence test with a one-line log
# (NOT a WARN); gh itself and the server-side PR Template Check still
# validate downstream.
if [[ $EXTRACT_EXIT -eq 3 ]]; then
  skipped_path="${EXTRACT_RESULT#BODY_FILE_UNEXPANDABLE$'\t'}"
  echo "[pr-template-inline-gate] skipped: unexpandable path '$skipped_path' — cannot statically resolve shell constructs at hook time (or the resolved file is not visible to the hook); gh + server-side PR Template Check still validate" >&2
  exit 0
fi

# Handle parser-recognized error sentinels.
if [[ $EXTRACT_EXIT -eq 2 ]]; then
  case "$EXTRACT_RESULT" in
    STDIN_NOT_SUPPORTED*)
      _demote_warn "--body-file - (stdin) not supported" "\
[pr-template-inline-gate] The \`--body-file -\` (stdin) form is not supported by the local inline-body validator. The Bash tool's stdin is the hook-input JSON, not your PR body; the gate cannot read your intended PR body content.

Remediation: write your PR body to a file first, then use \`--body-file <path>\`:

  gh pr create --title \"...\" --body-file .pr-description.md

Rule: rules/planning.md \"Capture-codify at PR time\"
Related: HARNESS-GAP-40 (inline-body validation)"
      ;;
    BODY_FILE_MISSING*)
      missing_path="${EXTRACT_RESULT#BODY_FILE_MISSING	}"
      _demote_warn "--body-file path does not exist: $missing_path" "\
[pr-template-inline-gate] The --body-file path does not exist: $missing_path

The gate cannot validate a non-existent body file. gh pr create would itself fail downstream, but we surface the failure locally so you don't waste a push.

Remediation: confirm the path is correct (relative to the repo root or use an absolute path).

Rule: rules/planning.md \"Capture-codify at PR time\""
      ;;
  esac
fi

# No recognised body source AND no --fill → gh's default body behavior.
# Pass through silently; if the resulting PR body is empty, gh itself
# will prompt or use the commit message.
if [[ -z "$EXTRACT_RESULT" ]]; then
  exit 0
fi

# Source the validator library and run validate_pr_body on the extracted body.
# shellcheck disable=SC1090
source "$VALIDATOR_LIB"

# Capture validator output (stdout + stderr) for surfacing.
VALIDATOR_STDOUT_FILE=$(mktemp)
VALIDATOR_STDERR_FILE=$(mktemp)
trap 'rm -f "$VALIDATOR_STDOUT_FILE" "$VALIDATOR_STDERR_FILE"' EXIT

VALIDATOR_EXIT=0
validate_pr_body "$EXTRACT_RESULT" >"$VALIDATOR_STDOUT_FILE" 2>"$VALIDATOR_STDERR_FILE" || VALIDATOR_EXIT=$?

if [[ $VALIDATOR_EXIT -eq 0 ]]; then
  # PASS — allow the tool call.
  exit 0
fi

# FAIL — surface the validator's own stderr verbatim, prepend a header
# naming the gate + the failing command class. Wave D.6: WARN, not block
# — the server-side `PR Template Check` CI workflow and
# pre-push-pr-template.sh still enforce.
ACTION_LABEL="gh pr create"
if [[ $IS_PR_EDIT -eq 1 ]]; then
  ACTION_LABEL="gh pr edit"
fi

WARN_BODY="[pr-template-inline-gate] template validation failed (WARN, not a block)

Inline PR body passed to \`$ACTION_LABEL\` failed the capture-codify template validator. The same validator runs server-side as \`PR Template Check\`, which still enforces — this local warning just gives you the chance to fix it before pushing.

----- validator output (stderr) -----
$(cat "$VALIDATOR_STDERR_FILE")
----- end validator output -----

Remediation:
  - Fix the PR body to address the failure above (add the missing section,
    fill the placeholder, or extend the rationale to ≥40 chars for (c)).
  - For complex bodies, author \`.pr-description.md\` locally and use
    \`gh pr create --body-file .pr-description.md\` — validate the file
    itself repeatedly (the validator is a sourceable library, not a file CLI):
      bash -c 'source .github/scripts/validate-pr-template.sh; validate_pr_body \"\$(cat .pr-description.md)\" && echo \"verdict: PASS\"'

Rule:    rules/planning.md \"Capture-codify at PR time\"
Sibling: vaporware-volume-gate.sh (PR volume-shape check on same matcher)
Sibling: pre-push-pr-template.sh  (git pre-push side; validates .pr-description.md + commit msgs; STILL ENFORCES)
Related: HARNESS-GAP-40 (inline-body validation; this gate closes it)"

_demote_warn "PR template validation failed for $ACTION_LABEL" "$WARN_BODY"
