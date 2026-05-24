#!/usr/bin/env bash
# git-no-verify-friction.sh — Local `git` shell-function wrapper that
# intercepts `--no-verify` / `-n` on commits, requires an explicit
# confirmation string, and logs every attempt.
#
# Classification: Pattern (local convenience friction). The actual
# defense against bypass is the server-side enforcement workflow
# (`.github/workflows/server-side-enforcement.yml`); this wrapper is
# the "make the right thing easier than the wrong thing" complement
# that lives in the local shell.
#
# WHAT IT DOES
#   When you type `git commit --no-verify <args>` (or `git commit -n
#   <args>`) in a shell that has sourced this file, the wrapper:
#     1. Logs the attempt to `~/.claude/logs/no-verify-attempts.log`
#        with timestamp + cwd + the verbatim argv.
#     2. Prints a clear warning explaining what just got bypassed.
#     3. Prompts for a literal confirmation string. If the user does
#        not type the exact string, the commit is aborted.
#     4. On confirmation, delegates to the real git via `command git`.
#
# WHAT IT DOES NOT DO
#   - Block a determined bypass. A user who really wants to bypass can
#     run `command git commit --no-verify ...`, or unalias / unfunction
#     the wrapper, or invoke `/usr/bin/git` directly. The intent is
#     friction, not a hard block.
#   - Run inside CI. The CI runner does not source the user's shell
#     rc files, so the wrapper does not fire there — which is correct,
#     because CI runs the server-side enforcement workflow instead.
#   - Apply to non-commit subcommands. `git push --no-verify`,
#     `git rebase --no-verify`, etc. are NOT intercepted by this
#     wrapper. Pre-push bypass is handled by the global pre-push hook
#     (`pre-push-scan.sh`); rebase --no-verify is rare and intentional
#     when it does happen.
#
# THE THREE-LAYER STORY
#   Layer 1: AI sessions in Claude Code already block `--no-verify` via
#            the PreToolUse Bash hook chain. AI cannot bypass.
#   Layer 2: Human shells (with this wrapper installed) see friction +
#            log. Bypass is possible but visible and effortful.
#   Layer 3: Server-side enforcement workflow runs on every PR. Even if
#            Layers 1 and 2 are both bypassed, the PR cannot merge once
#            branch-protection is configured.
#
# INSTALL
#   Source this file from your `~/.bashrc` or `~/.zshrc`:
#       . ~/claude-projects/neural-lace/adapters/claude-code/scripts/git-no-verify-friction.sh
#   Or use the installer:
#       bash ~/claude-projects/neural-lace/adapters/claude-code/scripts/install-git-friction.sh
#
# UNINSTALL
#   Remove the source line from your rc file, then `unset -f git`
#   (or open a new shell).
#
# SELF-TEST
#   bash adapters/claude-code/scripts/git-no-verify-friction.sh --self-test
#   Exercises the argument-detection logic in a subshell (does not
#   require an interactive prompt to PASS the test).

# Self-test runs when the file is INVOKED directly with --self-test.
# When the file is SOURCED into a shell, only the function definition
# runs (the self-test block is gated by direct-invocation detection).

# --- The wrapper function ----------------------------------------------------

git() {
  local _gnv_has_no_verify=0
  local _gnv_found_commit=0
  local _gnv_arg

  for _gnv_arg in "$@"; do
    case "$_gnv_arg" in
      commit)
        _gnv_found_commit=1
        ;;
      --no-verify)
        _gnv_has_no_verify=1
        ;;
      -n)
        # `-n` is the short form of `--no-verify` for `git commit` but
        # is also a valid short flag for OTHER subcommands (none on the
        # commit path that conflict, but be defensive). Only treat `-n`
        # as a bypass when a commit subcommand is also present.
        _gnv_has_no_verify=1
        ;;
    esac
  done

  if [[ $_gnv_found_commit -eq 1 && $_gnv_has_no_verify -eq 1 ]]; then
    local _gnv_log_dir="$HOME/.claude/logs"
    local _gnv_log_file="$_gnv_log_dir/no-verify-attempts.log"
    mkdir -p "$_gnv_log_dir" 2>/dev/null

    # Log the attempt FIRST so even an interrupt (Ctrl-C at the prompt)
    # leaves an audit trail.
    {
      printf '\n--- no-verify attempt %s ---\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
      printf 'cwd: %s\n' "$PWD"
      printf 'argv: git'
      for _gnv_arg in "$@"; do
        printf ' %q' "$_gnv_arg"
      done
      printf '\n'
    } >> "$_gnv_log_file" 2>/dev/null

    # Friction prompt.
    cat >&2 <<'EOF'

  >> --no-verify bypass detected <<

  You are about to commit with pre-commit hooks DISABLED. The local
  hook chain (credential scan, harness-hygiene, plan-edit-validator,
  no-test-skip, scope-enforcement, etc.) will NOT run on this commit.

  This is a defensive backstop, not a hard block. The server-side
  enforcement workflow still runs on push and branch-protection prevents
  the PR from merging if it fails -- so the local bypass is recoverable.

  To proceed, type the literal string below (case-sensitive, no quotes):

      I-AM-BYPASSING-SAFETY-DELIBERATELY

  Notes:
    - This attempt is logged to ~/.claude/logs/no-verify-attempts.log
    - To bypass this wrapper entirely: `command git commit --no-verify ...`
      (also discoverable via shell history; not recommended)
    - See docs/no-verify-friction.md for the three-layer defense story

EOF

    local _gnv_confirmation=""
    # Use printf + read so the prompt works under both bash and zsh.
    printf '  Type confirmation > ' >&2
    if ! read -r _gnv_confirmation; then
      echo "  XX  read failed (input closed). Commit aborted." >&2
      return 1
    fi

    if [[ "$_gnv_confirmation" != "I-AM-BYPASSING-SAFETY-DELIBERATELY" ]]; then
      echo "  XX  Confirmation mismatch. Commit aborted." >&2
      # Log the outcome too so the audit trail shows abort-vs-proceed.
      printf 'outcome: aborted (confirmation mismatch)\n' >> "$_gnv_log_file" 2>/dev/null
      return 1
    fi

    echo "  OK  Confirmation accepted. Proceeding with --no-verify commit." >&2
    printf 'outcome: proceeded (confirmation matched)\n' >> "$_gnv_log_file" 2>/dev/null
  fi

  # Delegate to the real git. `command git` bypasses functions/aliases.
  command git "$@"
}

# --- Detection helpers exposed for the self-test -----------------------------
# These are namespaced with _gnv_ to avoid colliding with anything else the
# user may have defined in their shell.

_gnv_detect_bypass() {
  # _gnv_detect_bypass <argv...>
  # Echoes "yes" if the argv looks like a `git commit --no-verify`
  # (or `git commit -n`) invocation, "no" otherwise. Used by the
  # self-test to avoid needing an interactive prompt.
  local _gnv_has_no_verify=0
  local _gnv_found_commit=0
  local _gnv_arg
  for _gnv_arg in "$@"; do
    case "$_gnv_arg" in
      commit)     _gnv_found_commit=1 ;;
      --no-verify) _gnv_has_no_verify=1 ;;
      -n)         _gnv_has_no_verify=1 ;;
    esac
  done
  if [[ $_gnv_found_commit -eq 1 && $_gnv_has_no_verify -eq 1 ]]; then
    echo "yes"
  else
    echo "no"
  fi
}

# --- Self-test ---------------------------------------------------------------
# Fires only when this file is invoked directly (not sourced).
if [[ "${BASH_SOURCE[0]:-$0}" == "${0}" ]] && [[ "${1:-}" == "--self-test" ]]; then
  echo "Running git-no-verify-friction self-test..." >&2
  fails=0

  # Helper for self-test cases. Calls _gnv_detect_bypass and compares
  # the echoed verdict against the expected value.
  expect_detect() {
    local label="$1"
    local expected="$2"
    shift 2
    local actual
    actual=$(_gnv_detect_bypass "$@")
    if [[ "$actual" != "$expected" ]]; then
      echo "FAIL: $label — expected '$expected', got '$actual' (argv: $*)" >&2
      fails=$((fails + 1))
    else
      echo "PASS: $label" >&2
    fi
  }

  # Case 1: plain `git commit -m msg` (no bypass) → no
  expect_detect "plain commit, no bypass" "no" commit -m "feat: thing"
  # Case 2: `git commit --no-verify -m msg` → yes
  expect_detect "commit --no-verify long form" "yes" commit --no-verify -m "feat: thing"
  # Case 3: `git commit -n -m msg` → yes
  expect_detect "commit -n short form" "yes" commit -n -m "feat: thing"
  # Case 4: `git status` (no commit subcommand) → no
  expect_detect "no commit subcommand" "no" status
  # Case 5: `git push --no-verify` (different subcommand) → no
  expect_detect "push --no-verify (not commit)" "no" push --no-verify
  # Case 6: `git commit --amend -m msg` (no bypass flag) → no
  expect_detect "amend without bypass" "no" commit --amend -m "fix"
  # Case 7: `git commit --amend --no-verify` → yes
  expect_detect "amend + --no-verify" "yes" commit --amend --no-verify
  # Case 8: `git rebase --no-verify` (rebase is not intercepted here) → no
  expect_detect "rebase --no-verify (intentionally not intercepted)" "no" rebase --no-verify main
  # Case 9: empty argv → no
  expect_detect "empty argv" "no"
  # Case 10: --no-verify before commit (rare but legal) → yes
  expect_detect "--no-verify before commit" "yes" --no-verify commit -m "x"

  if [[ $fails -eq 0 ]]; then
    echo "self-test: OK (10 cases)" >&2
    exit 0
  else
    echo "self-test: FAIL ($fails of 10 cases failed)" >&2
    exit 1
  fi
fi
