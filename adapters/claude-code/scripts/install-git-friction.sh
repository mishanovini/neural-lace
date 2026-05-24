#!/usr/bin/env bash
# install-git-friction.sh — One-time setup script that wires the
# git-no-verify-friction wrapper into the user's shell rc files.
#
# Detects bash and zsh and appends one line to each detected shell's
# rc file. Idempotent — re-running over an existing install is safe;
# the source line is added at most once per rc file (presence-checked
# by literal grep).
#
# USAGE
#   bash adapters/claude-code/scripts/install-git-friction.sh           # install
#   bash adapters/claude-code/scripts/install-git-friction.sh --check   # report status, no changes
#   bash adapters/claude-code/scripts/install-git-friction.sh --uninstall  # remove source lines
#   bash adapters/claude-code/scripts/install-git-friction.sh --self-test  # exercise install/uninstall in a temp HOME
#
# AFTER INSTALL
#   Open a new shell, OR run: source ~/.bashrc  (or ~/.zshrc)
#   Verify: type `git commit --no-verify -m test` in a repo with
#   unstaged changes — you should see the friction prompt.

set -uo pipefail

# Source the wrapper from the canonical neural-lace path. The
# install line we append references this path verbatim. If the user
# moves their neural-lace checkout, they need to re-run the installer
# (or update the rc-file line by hand).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WRAPPER_PATH="$SCRIPT_DIR/git-no-verify-friction.sh"

# Sentinel marker — distinctive string we grep for to detect prior
# installs. Keeping it stable across runs lets the uninstaller find
# the exact lines to delete.
MARKER="# >>> neural-lace git-no-verify-friction wrapper >>>"
END_MARKER="# <<< neural-lace git-no-verify-friction wrapper <<<"

# --- Functions ---------------------------------------------------------------

rc_file_for_shell() {
  case "$1" in
    bash) echo "$HOME/.bashrc" ;;
    zsh)  echo "$HOME/.zshrc" ;;
    *)    return 1 ;;
  esac
}

is_installed_in_rc() {
  local rc="$1"
  [[ -f "$rc" ]] && grep -Fq "$MARKER" "$rc" 2>/dev/null
}

install_in_rc() {
  local rc="$1"
  local shell_name="$2"
  if is_installed_in_rc "$rc"; then
    echo "  [skip] $rc — wrapper already installed ($shell_name)"
    return 0
  fi
  # Touch the rc file if it doesn't exist (some users have one but
  # not the other).
  if [[ ! -f "$rc" ]]; then
    if [[ ! -d "$(dirname "$rc")" ]]; then
      echo "  [skip] $rc — parent directory does not exist ($shell_name)"
      return 0
    fi
    touch "$rc"
  fi
  {
    printf '\n%s\n' "$MARKER"
    printf '# Intercepts `git commit --no-verify` and similar with a\n'
    printf '# friction prompt + audit log. See:\n'
    printf '#   %s\n' "$WRAPPER_PATH"
    printf 'if [ -f "%s" ]; then\n' "$WRAPPER_PATH"
    printf '  . "%s"\n' "$WRAPPER_PATH"
    printf 'fi\n'
    printf '%s\n' "$END_MARKER"
  } >> "$rc"
  echo "  [add]  $rc — wrapper sourced ($shell_name)"
}

uninstall_from_rc() {
  local rc="$1"
  local shell_name="$2"
  if [[ ! -f "$rc" ]]; then
    echo "  [skip] $rc — file does not exist ($shell_name)"
    return 0
  fi
  if ! is_installed_in_rc "$rc"; then
    echo "  [skip] $rc — wrapper not installed ($shell_name)"
    return 0
  fi
  # Use awk to delete lines between MARKER and END_MARKER inclusive.
  local tmp
  tmp="$(mktemp)"
  awk -v start="$MARKER" -v end="$END_MARKER" '
    $0 == start { skip = 1; next }
    skip && $0 == end { skip = 0; next }
    !skip { print }
  ' "$rc" > "$tmp"
  mv "$tmp" "$rc"
  echo "  [del]  $rc — wrapper removed ($shell_name)"
}

check_rc() {
  local rc="$1"
  local shell_name="$2"
  if is_installed_in_rc "$rc"; then
    echo "  [ok]   $rc — wrapper installed ($shell_name)"
  else
    if [[ -f "$rc" ]]; then
      echo "  [miss] $rc — wrapper NOT installed ($shell_name)"
    else
      echo "  [n/a]  $rc — file does not exist ($shell_name)"
    fi
  fi
}

run_install() {
  echo "Installing git-no-verify-friction wrapper..."
  echo "Wrapper path: $WRAPPER_PATH"
  if [[ ! -f "$WRAPPER_PATH" ]]; then
    echo "ERROR: wrapper not found at $WRAPPER_PATH" >&2
    return 1
  fi
  install_in_rc "$(rc_file_for_shell bash)" bash
  install_in_rc "$(rc_file_for_shell zsh)" zsh
  echo
  echo "Done. Open a new shell OR run:"
  echo "  source ~/.bashrc      # bash"
  echo "  source ~/.zshrc       # zsh"
  echo
  echo "Then verify: `git commit --no-verify -m test` in a repo with"
  echo "unstaged changes should show the friction prompt."
}

run_uninstall() {
  echo "Uninstalling git-no-verify-friction wrapper..."
  uninstall_from_rc "$(rc_file_for_shell bash)" bash
  uninstall_from_rc "$(rc_file_for_shell zsh)" zsh
  echo
  echo "Done. Open a new shell OR run `unset -f git` to drop the wrapper."
}

run_check() {
  echo "Checking git-no-verify-friction wrapper install status..."
  echo "Wrapper path: $WRAPPER_PATH"
  if [[ ! -f "$WRAPPER_PATH" ]]; then
    echo "  [warn] wrapper file missing — install will fail until restored"
  fi
  check_rc "$(rc_file_for_shell bash)" bash
  check_rc "$(rc_file_for_shell zsh)" zsh
}

# --- Self-test ---------------------------------------------------------------

run_self_test() {
  echo "Running install-git-friction self-test..." >&2
  local fails=0
  local tmp_home
  tmp_home="$(mktemp -d)"
  local orig_home="$HOME"

  # Provide a fake wrapper file at the expected path inside the temp
  # HOME so install_in_rc's `[ -f ... ]` source check would pass at
  # rc-load time (we don't actually source it; we only verify the rc
  # file's text). The wrapper path itself is computed from SCRIPT_DIR
  # in this script's outer scope, which still points at the real
  # adapters/ path — that's fine; the test verifies rc-file text
  # mutation, not wrapper execution.

  export HOME="$tmp_home"

  # Case A: bash rc — install adds marker.
  : > "$tmp_home/.bashrc"
  install_in_rc "$tmp_home/.bashrc" bash >/dev/null
  if ! grep -Fq "$MARKER" "$tmp_home/.bashrc"; then
    echo "FAIL: install did not add marker to .bashrc" >&2
    fails=$((fails + 1))
  fi

  # Case B: idempotent — second install adds NOTHING extra.
  local before
  before=$(wc -l < "$tmp_home/.bashrc")
  install_in_rc "$tmp_home/.bashrc" bash >/dev/null
  local after
  after=$(wc -l < "$tmp_home/.bashrc")
  if [[ "$before" != "$after" ]]; then
    echo "FAIL: second install changed line count ($before -> $after)" >&2
    fails=$((fails + 1))
  fi

  # Case C: uninstall removes the marker block.
  uninstall_from_rc "$tmp_home/.bashrc" bash >/dev/null
  if grep -Fq "$MARKER" "$tmp_home/.bashrc"; then
    echo "FAIL: uninstall did not remove marker from .bashrc" >&2
    fails=$((fails + 1))
  fi

  # Case D: uninstall on never-installed rc is a no-op.
  : > "$tmp_home/.zshrc"
  local zsh_before
  zsh_before=$(wc -c < "$tmp_home/.zshrc")
  uninstall_from_rc "$tmp_home/.zshrc" zsh >/dev/null
  local zsh_after
  zsh_after=$(wc -c < "$tmp_home/.zshrc")
  if [[ "$zsh_before" != "$zsh_after" ]]; then
    echo "FAIL: uninstall on clean .zshrc changed byte count" >&2
    fails=$((fails + 1))
  fi

  # Case E: install on missing rc creates one.
  rm -f "$tmp_home/.zshrc"
  install_in_rc "$tmp_home/.zshrc" zsh >/dev/null
  if [[ ! -f "$tmp_home/.zshrc" ]]; then
    echo "FAIL: install did not create .zshrc from scratch" >&2
    fails=$((fails + 1))
  fi
  if ! grep -Fq "$MARKER" "$tmp_home/.zshrc"; then
    echo "FAIL: install on newly-created .zshrc did not add marker" >&2
    fails=$((fails + 1))
  fi

  # Case F: check reports correctly.
  uninstall_from_rc "$tmp_home/.zshrc" zsh >/dev/null
  local check_output
  check_output=$(check_rc "$tmp_home/.zshrc" zsh 2>&1)
  if [[ "$check_output" != *"NOT installed"* ]]; then
    echo "FAIL: check did not report NOT installed on clean .zshrc (got: $check_output)" >&2
    fails=$((fails + 1))
  fi

  # Restore HOME.
  export HOME="$orig_home"
  rm -rf "$tmp_home"

  if [[ $fails -eq 0 ]]; then
    echo "self-test: OK (6 cases)" >&2
    return 0
  else
    echo "self-test: FAIL ($fails of 6 cases failed)" >&2
    return 1
  fi
}

# --- Entry point -------------------------------------------------------------

case "${1:-install}" in
  install)    run_install ;;
  --check)    run_check ;;
  --uninstall) run_uninstall ;;
  --self-test) run_self_test; exit $? ;;
  *)
    echo "Usage: $0 [install|--check|--uninstall|--self-test]" >&2
    exit 2
    ;;
esac
