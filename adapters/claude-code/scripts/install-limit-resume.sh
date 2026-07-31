#!/usr/bin/env bash
# install-limit-resume.sh — macOS launchd LaunchAgent installer for the
# limit-resume watchdog (scripts/limit-resume.sh).
#
# Mirrors ensure-cockpit.sh's Darwin LaunchAgent conventions (docs/
# decisions/065-macos-cockpit-launchagent.md) almost exactly — idempotent
# plist write, `launchctl print`-checked single-instance bootstrap, every
# launchctl call bounded via hooks/lib/portable-timeout.sh's
# nl_run_bounded, HARNESS_SELFTEST stub BEFORE any real side effect,
# operator kill-switch, tolerate-absent on every branch. The one
# structural difference: this LaunchAgent runs a PERIODIC TICK
# (StartInterval, RunAtLoad=false, no KeepAlive) rather than a persistent
# server (RunAtLoad+KeepAlive) — there is no "port" to probe for
# liveness, so this script instead verifies via `launchctl print` that
# the label is loaded and its StartInterval is what we expect.
#
# CONTRACT (mirrors ensure-cockpit.sh's numbered contract):
#   1. Darwin only. Any other OS (Linux/CI/cloud): silent no-op, exit 0.
#      (Windows gets its own scheduled-task installer, install-limit-
#      resume-task.ps1 — untested on this machine, see that file's own
#      header.)
#   2. HARNESS_SELFTEST=1 — never writes a real plist or calls real
#      launchctl. Logs the invocation shape and returns 0 BEFORE any
#      side effect.
#   3. Script path resolved via hooks/lib/nl-paths.sh's nl_repo_root ->
#      nl_main_checkout_root (never a worktree — a worktree-rooted
#      builder session must never register a LaunchAgent pointing at
#      its own throwaway checkout).
#   4. NON-BLOCKING — every launchctl call runs under nl_run_bounded so a
#      hung launchd call can never hang a caller (e.g. the SessionStart
#      splice that calls `ensure`).
#   5. Tolerate-absent — missing bash/launchctl -> log and return 0.
#      NEVER errors (set -u only, no set -e).
#   6. Operator kill-switch: env LIMIT_RESUME_DISABLE=1 or flag file
#      ~/.claude/local/limit-resume-disabled -> logged no-op.
#   7. Idempotent + single-instance: plist only (re)written when its
#      content differs; `launchctl bootstrap` only when NOT already
#      loaded (checked via `launchctl print`, never trusted-and-skipped);
#      a content change while loaded does one bootout then bootstrap.
#
# Test-only overrides (same convention as ensure-cockpit.sh):
#   LIMIT_RESUME_LAUNCHAGENTS_DIR, LIMIT_RESUME_PLIST_LABEL,
#   LIMIT_RESUME_LAUNCHCTL_OVERRIDE / LIMIT_RESUME_FORCE_NO_LAUNCHCTL,
#   LIMIT_RESUME_BASH_OVERRIDE / LIMIT_RESUME_FORCE_NO_BASH
#
# Subcommands:
#   ensure       Install/refresh + bootstrap-if-needed. Idempotent. This
#                is what the SessionStart splice calls every session.
#   install      Same as ensure (explicit operator-facing alias).
#   uninstall    launchctl bootout + rm the plist.
#   status       Print whether the LaunchAgent is loaded + the plist path.
#   --self-test  Sandboxed scenarios (see run_self_test()).

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
{ source "$SCRIPT_DIR/../hooks/lib/nl-paths.sh" 2>/dev/null; } || true
# shellcheck disable=SC1091
{ source "$SCRIPT_DIR/../hooks/lib/portable-timeout.sh" 2>/dev/null; } || true
if ! declare -F nl_run_bounded >/dev/null 2>&1; then
  nl_run_bounded() { local _secs="$1"; shift; "$@"; }
fi

_lir_log_path() {
  printf '%s/.claude/logs/limit-resume-install.log' "${HOME:-$PWD}"
}

_lir_log() {
  local p; p="$(_lir_log_path)"
  mkdir -p "$(dirname "$p")" 2>/dev/null || true
  printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >> "$p" 2>/dev/null || true
}

_lir_is_disabled() {
  [[ "${LIMIT_RESUME_DISABLE:-0}" == "1" ]] && return 0
  [[ -f "${HOME:-$PWD}/.claude/local/limit-resume-disabled" ]] && return 0
  return 1
}

_lir_uname() {
  printf '%s' "${LIMIT_RESUME_UNAME_OVERRIDE:-$(uname -s 2>/dev/null || echo unknown)}"
}

_lir_is_darwin() {
  [[ "$(_lir_uname)" == "Darwin" ]]
}

_lir_resolve_bash() {
  if [[ "${LIMIT_RESUME_FORCE_NO_BASH:-0}" == "1" ]]; then
    return 1
  fi
  if [[ -n "${LIMIT_RESUME_BASH_OVERRIDE:-}" ]]; then
    printf '%s' "$LIMIT_RESUME_BASH_OVERRIDE"
    return 0
  fi
  local found
  found="$(command -v bash 2>/dev/null || true)"
  if [[ -n "$found" ]]; then
    printf '%s' "$found"
    return 0
  fi
  [[ -x /bin/bash ]] && { printf '/bin/bash'; return 0; }
  return 1
}

_lir_resolve_launchctl() {
  if [[ "${LIMIT_RESUME_FORCE_NO_LAUNCHCTL:-0}" == "1" ]]; then
    return 1
  fi
  if [[ -n "${LIMIT_RESUME_LAUNCHCTL_OVERRIDE:-}" ]]; then
    printf '%s' "$LIMIT_RESUME_LAUNCHCTL_OVERRIDE"
    return 0
  fi
  local found
  found="$(command -v launchctl 2>/dev/null || true)"
  if [[ -n "$found" ]]; then
    printf '%s' "$found"
    return 0
  fi
  return 1
}

_lir_launchagents_dir() {
  if [[ -n "${LIMIT_RESUME_LAUNCHAGENTS_DIR:-}" ]]; then
    printf '%s' "$LIMIT_RESUME_LAUNCHAGENTS_DIR"
  else
    printf '%s/Library/LaunchAgents' "${HOME:-$PWD}"
  fi
}

_lir_label() {
  printf '%s' "${LIMIT_RESUME_PLIST_LABEL:-local.neurallace.limit-resume}"
}

_lir_plist_path() {
  printf '%s/%s.plist' "$(_lir_launchagents_dir)" "$(_lir_label)"
}

# _lir_plist_content <label> <bash_bin> <script_path> <out_log> <err_log>
# StartInterval 900s (15 min — matches the historical hand-made
# predecessor and limit-resume.sh's own default backoff base). RunAtLoad
# false: a tick is a no-op unless armed, so there is no value in firing
# one at login before the operator has even started a session.
_lir_plist_content() {
  local label="$1" bash_bin="$2" script_path="$3" out_log="$4" err_log="$5"
  cat <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>${label}</string>
	<key>ProgramArguments</key>
	<array>
		<string>${bash_bin}</string>
		<string>${script_path}</string>
		<string>tick</string>
	</array>
	<key>StartInterval</key>
	<integer>900</integer>
	<key>RunAtLoad</key>
	<false/>
	<key>StandardOutPath</key>
	<string>${out_log}</string>
	<key>StandardErrorPath</key>
	<string>${err_log}</string>
	<key>ProcessType</key>
	<string>Background</string>
</dict>
</plist>
PLIST
}

# 0 (true) when $1 is NOT a linked worktree (git-dir == git-common-dir),
# or is not a git repo at all. Mirrors limit-resume.sh's own
# _lr_is_main_checkout, duplicated (not sourced) since this file must
# tolerate limit-resume.sh being entirely absent.
_lir_is_worktree_path() {
  local dir="$1" gd cgd
  gd="$(cd "$dir" 2>/dev/null && git rev-parse --git-dir 2>/dev/null)" || return 1
  cgd="$(cd "$dir" 2>/dev/null && git rev-parse --git-common-dir 2>/dev/null)" || return 1
  gd="$(cd "$dir" 2>/dev/null && cd "$gd" 2>/dev/null && pwd)"
  cgd="$(cd "$dir" 2>/dev/null && cd "$cgd" 2>/dev/null && pwd)"
  [[ -n "$gd" && -n "$cgd" && "$gd" != "$cgd" ]]
}

# Resolve the absolute path to limit-resume.sh in the MAIN checkout
# (never a worktree). Prints empty on total failure.
#
# harness-reviewer REJECT finding F2 (2026-07-30, PROVEN live on this
# machine): the ORIGINAL version of this function fell back to
# "$SCRIPT_DIR/limit-resume.sh" whenever the main-checkout candidate
# file did not exist yet (true on EVERY pre-merge run, since a worktree
# build's new files exist only in that worktree) — silently registering
# a PERMANENT LaunchAgent pointing at a THROWAWAY worktree, which then
# ticks forever against a missing script the moment that worktree is
# pruned (a verbatim reintroduction of DEFECT 1). Fixed: the
# $SCRIPT_DIR fallback is now used ONLY when $SCRIPT_DIR itself is
# NOT inside a linked worktree (fail CLOSED — log + return 1 — when it
# is, per this file's own contract item 3, rather than silently
# defeating that contract).
_lir_resolve_script_path() {
  local root norm candidate
  if declare -F nl_repo_root >/dev/null 2>&1; then
    root="$(nl_repo_root 2>/dev/null || true)"
    if [[ -n "$root" ]] && declare -F nl_main_checkout_root >/dev/null 2>&1; then
      norm="$(cd "$root" 2>/dev/null && nl_main_checkout_root 2>/dev/null || true)"
      [[ -n "$norm" ]] && root="$norm"
    fi
  fi
  if [[ -n "${root:-}" ]]; then
    candidate="$root/adapters/claude-code/scripts/limit-resume.sh"
    [[ -f "$candidate" ]] && { printf '%s' "$candidate"; return 0; }
  fi
  # Fallback: this script's own sibling — ONLY when SCRIPT_DIR is not
  # itself a linked worktree (works even without nl-paths.sh, e.g. a
  # stripped-down fixture tree — same tolerate-absent spirit as
  # ensure-cockpit.sh's session-cwd fallback, minus the worktree hazard).
  if _lir_is_worktree_path "$SCRIPT_DIR"; then
    _lir_log "refusing to fall back to '$SCRIPT_DIR/limit-resume.sh' — that path is inside a linked worktree (git-dir != git-common-dir); registering a permanent LaunchAgent against a throwaway worktree would break the moment it is pruned (F2). Re-run ensure from the main checkout, or after this worktree's work has merged there."
    printf ''
    return 1
  fi
  candidate="$SCRIPT_DIR/limit-resume.sh"
  [[ -f "$candidate" ]] && { printf '%s' "$candidate"; return 0; }
  printf ''
  return 1
}

_lir_darwin_ensure() {
  local script_path bash_bin launchctl
  if ! script_path="$(_lir_resolve_script_path)"; then
    _lir_log "tolerate-absent: limit-resume.sh not resolved — skipping LaunchAgent ensure"
    return 0
  fi
  if ! bash_bin="$(_lir_resolve_bash)"; then
    _lir_log "tolerate-absent: bash not found on PATH — skipping LaunchAgent ensure"
    return 0
  fi
  if ! launchctl="$(_lir_resolve_launchctl)"; then
    _lir_log "tolerate-absent: launchctl not found — skipping LaunchAgent ensure"
    return 0
  fi

  local la_dir label plist_path log_dir out_log err_log
  la_dir="$(_lir_launchagents_dir)"
  label="$(_lir_label)"
  plist_path="$(_lir_plist_path)"
  log_dir="$(dirname "$(_lir_log_path)")"
  out_log="$log_dir/limit-resume.stdout.log"
  err_log="$log_dir/limit-resume.stderr.log"

  local desired
  desired="$(_lir_plist_content "$label" "$bash_bin" "$script_path" "$out_log" "$err_log")"

  if [[ "${HARNESS_SELFTEST:-0}" == "1" ]]; then
    _lir_log "[self-test stub] would install/refresh plist at $plist_path (label=$label, bash=$bash_bin, script=$script_path) and bootstrap via $launchctl — never written/spawned"
    return 0
  fi

  mkdir -p "$la_dir" 2>/dev/null || true

  local need_write=1
  if [[ -f "$plist_path" ]]; then
    local existing; existing="$(cat "$plist_path" 2>/dev/null || true)"
    [[ "$existing" == "$desired" ]] && need_write=0
  fi
  if [[ "$need_write" -eq 1 ]]; then
    local tmp_plist="${plist_path}.tmp.$$"
    if printf '%s\n' "$desired" > "$tmp_plist" 2>/dev/null && mv -f "$tmp_plist" "$plist_path" 2>/dev/null; then
      _lir_log "plist written/refreshed: $plist_path"
    else
      _lir_log "tolerate-absent: could not write plist at $plist_path — skipping bootstrap"
      return 0
    fi
  fi

  local uid domain_target was_loaded
  uid="$(id -u 2>/dev/null || echo 0)"
  domain_target="gui/$uid/$label"
  was_loaded=1
  if nl_run_bounded 10 "$launchctl" print "$domain_target" >/dev/null 2>&1; then
    was_loaded=0
  fi

  if [[ "$need_write" -eq 1 && "$was_loaded" -eq 0 ]]; then
    nl_run_bounded 10 "$launchctl" bootout "$domain_target" >/dev/null 2>&1 || true
    was_loaded=1
  fi

  if [[ "$was_loaded" -eq 1 ]]; then
    if nl_run_bounded 10 "$launchctl" bootstrap "gui/$uid" "$plist_path" >/dev/null 2>&1; then
      _lir_log "launchctl bootstrap succeeded for $label"
    else
      _lir_log "launchctl bootstrap returned non-zero for $label (may already be loaded, or no GUI launchd domain in this session)"
    fi
  else
    _lir_log "$label already bootstrapped — no-op (idempotent)"
  fi

  return 0
}

_lir_darwin_uninstall() {
  local launchctl plist_path label uid
  plist_path="$(_lir_plist_path)"
  label="$(_lir_label)"
  if [[ "${HARNESS_SELFTEST:-0}" == "1" ]]; then
    _lir_log "[self-test stub] would uninstall $plist_path — never touched"
    return 0
  fi
  if launchctl="$(_lir_resolve_launchctl)"; then
    uid="$(id -u 2>/dev/null || echo 0)"
    nl_run_bounded 10 "$launchctl" bootout "gui/$uid/$label" >/dev/null 2>&1 || true
  fi
  rm -f "$plist_path" 2>/dev/null || true
  _lir_log "uninstalled (bootout + rm $plist_path)"
}

_lir_darwin_status() {
  local launchctl plist_path label uid loaded="not loaded"
  plist_path="$(_lir_plist_path)"
  label="$(_lir_label)"
  echo "plist: $plist_path ($( [[ -f "$plist_path" ]] && echo present || echo absent ))"
  if launchctl="$(_lir_resolve_launchctl)"; then
    uid="$(id -u 2>/dev/null || echo 0)"
    if nl_run_bounded 10 "$launchctl" print "gui/$uid/$label" >/dev/null 2>&1; then
      loaded="loaded"
    fi
  fi
  echo "launchd: $loaded (label=$label)"
}

cmd_ensure() {
  if _lir_is_disabled; then
    _lir_log "kill-switch active (LIMIT_RESUME_DISABLE or ~/.claude/local/limit-resume-disabled) — skipping"
    return 0
  fi
  if ! _lir_is_darwin; then
    return 0
  fi
  _lir_darwin_ensure
}

cmd_uninstall() {
  if ! _lir_is_darwin; then
    echo "install-limit-resume.sh: not Darwin — nothing to uninstall" >&2
    return 0
  fi
  _lir_darwin_uninstall
}

cmd_status() {
  if ! _lir_is_darwin; then
    echo "not Darwin"
    return 0
  fi
  _lir_darwin_status
}

# ============================================================
# --self-test
# ============================================================
_self_test() {
  local pass=0 fail=0 tmp

  # S1 -- HARNESS_SELFTEST stub never writes a real plist or spawns launchctl.
  (
    tmp=$(mktemp -d)
    export HARNESS_SELFTEST=1
    export LIMIT_RESUME_LAUNCHAGENTS_DIR="$tmp/LaunchAgents"
    export LIMIT_RESUME_UNAME_OVERRIDE=Darwin
    "$SCRIPT_DIR/install-limit-resume.sh" ensure >/dev/null 2>&1
    if [ ! -d "$tmp/LaunchAgents" ]; then
      echo "  S1 self-test stub never touches disk: PASS"
    else
      echo "  S1 self-test stub never touches disk: FAIL"; exit 1
    fi
  ) && pass=$((pass+1)) || fail=$((fail+1))

  # S2 -- non-Darwin is a silent no-op (no plist dir created even without
  # HARNESS_SELFTEST).
  (
    tmp=$(mktemp -d)
    export LIMIT_RESUME_LAUNCHAGENTS_DIR="$tmp/LaunchAgents"
    export LIMIT_RESUME_UNAME_OVERRIDE=Linux
    "$SCRIPT_DIR/install-limit-resume.sh" ensure >/dev/null 2>&1
    if [ ! -d "$tmp/LaunchAgents" ]; then
      echo "  S2 non-Darwin no-op: PASS"
    else
      echo "  S2 non-Darwin no-op: FAIL"; exit 1
    fi
  ) && pass=$((pass+1)) || fail=$((fail+1))

  # S3 -- kill-switch (env) prevents even the self-test stub log line's
  # underlying ensure call from reaching the Darwin branch.
  (
    tmp=$(mktemp -d)
    export LIMIT_RESUME_LAUNCHAGENTS_DIR="$tmp/LaunchAgents"
    export LIMIT_RESUME_UNAME_OVERRIDE=Darwin
    export LIMIT_RESUME_DISABLE=1
    export LIMIT_RESUME_FORCE_NO_LAUNCHCTL=1
    "$SCRIPT_DIR/install-limit-resume.sh" ensure >/dev/null 2>&1
    if [ ! -d "$tmp/LaunchAgents" ]; then
      echo "  S3 kill-switch (env) no-op: PASS"
    else
      echo "  S3 kill-switch (env) no-op: FAIL"; exit 1
    fi
  ) && pass=$((pass+1)) || fail=$((fail+1))

  # Builds a PLAIN (non-worktree) fake repo containing a copy of
  # limit-resume.sh at the expected relative path, so S4-S6 exercise the
  # normal "root resolves and the file exists there" path regardless of
  # whether THIS install-limit-resume.sh happens to be running from a
  # linked worktree itself (it usually is, mid-build — see F2 fix above).
  # $1 = target dir to create.
  _fake_repo_with_watchdog() {
    local dir="$1"
    mkdir -p "$dir/adapters/claude-code/scripts"
    cp "$SCRIPT_DIR/limit-resume.sh" "$dir/adapters/claude-code/scripts/limit-resume.sh"
    ( cd "$dir" && git init --quiet && git config user.email t@example.com && git config user.name T \
      && git add -A && git commit --quiet -m init ) >/dev/null 2>&1
  }

  # S4 -- real (non-self-test) install under FAKE launchctl/bash overrides:
  # proves the actual plist-writing + idempotent-bootstrap code path
  # without ever invoking the real launchd or a real script.
  (
    tmp=$(mktemp -d)
    export LIMIT_RESUME_LAUNCHAGENTS_DIR="$tmp/LaunchAgents"
    export LIMIT_RESUME_UNAME_OVERRIDE=Darwin
    export LIMIT_RESUME_BASH_OVERRIDE="/bin/bash"
    _fake_repo_with_watchdog "$tmp/fakerepo"
    fake_lc="$tmp/fake-launchctl"
    cat > "$fake_lc" <<'EOF'
#!/bin/bash
# fake launchctl: `print` always "not loaded" (exit 1) so bootstrap runs;
# `bootstrap`/`bootout` succeed (exit 0).
case "$1" in
  print) exit 1 ;;
  *) exit 0 ;;
esac
EOF
    chmod +x "$fake_lc"
    export LIMIT_RESUME_LAUNCHCTL_OVERRIDE="$fake_lc"
    NL_REPO_ROOT="$tmp/fakerepo" "$SCRIPT_DIR/install-limit-resume.sh" ensure >/dev/null 2>&1
    label="local.neurallace.limit-resume"
    plist="$tmp/LaunchAgents/${label}.plist"
    if [ -f "$plist" ] && grep -q "<string>tick</string>" "$plist" && grep -q "StartInterval" "$plist" \
       && grep -q "$tmp/fakerepo/adapters/claude-code/scripts/limit-resume.sh" "$plist"; then
      echo "  S4 real (faked-launchctl) install writes plist with the resolved (non-worktree) path: PASS"
    else
      echo "  S4 real (faked-launchctl) install writes plist: FAIL"; exit 1
    fi
  ) && pass=$((pass+1)) || fail=$((fail+1))

  # S5 -- idempotent: a second ensure with identical content does not
  # rewrite the plist (mtime unchanged).
  (
    tmp=$(mktemp -d)
    export LIMIT_RESUME_LAUNCHAGENTS_DIR="$tmp/LaunchAgents"
    export LIMIT_RESUME_UNAME_OVERRIDE=Darwin
    export LIMIT_RESUME_BASH_OVERRIDE="/bin/bash"
    _fake_repo_with_watchdog "$tmp/fakerepo"
    fake_lc="$tmp/fake-launchctl"
    cat > "$fake_lc" <<'EOF'
#!/bin/bash
case "$1" in
  print) exit 0 ;;   # already loaded
  *) exit 0 ;;
esac
EOF
    chmod +x "$fake_lc"
    export LIMIT_RESUME_LAUNCHCTL_OVERRIDE="$fake_lc"
    NL_REPO_ROOT="$tmp/fakerepo" "$SCRIPT_DIR/install-limit-resume.sh" ensure >/dev/null 2>&1
    label="local.neurallace.limit-resume"
    plist="$tmp/LaunchAgents/${label}.plist"
    m1=$(stat -f "%m" "$plist" 2>/dev/null || stat -c "%Y" "$plist" 2>/dev/null)
    sleep 1
    NL_REPO_ROOT="$tmp/fakerepo" "$SCRIPT_DIR/install-limit-resume.sh" ensure >/dev/null 2>&1
    m2=$(stat -f "%m" "$plist" 2>/dev/null || stat -c "%Y" "$plist" 2>/dev/null)
    if [ "$m1" = "$m2" ]; then
      echo "  S5 idempotent second ensure (no rewrite): PASS"
    else
      echo "  S5 idempotent second ensure (no rewrite): FAIL (mtime $m1 -> $m2)"; exit 1
    fi
  ) && pass=$((pass+1)) || fail=$((fail+1))

  # S6 -- uninstall removes the plist.
  (
    tmp=$(mktemp -d)
    export LIMIT_RESUME_LAUNCHAGENTS_DIR="$tmp/LaunchAgents"
    export LIMIT_RESUME_UNAME_OVERRIDE=Darwin
    export LIMIT_RESUME_BASH_OVERRIDE="/bin/bash"
    _fake_repo_with_watchdog "$tmp/fakerepo"
    fake_lc="$tmp/fake-launchctl"; printf '#!/bin/bash\nexit 0\n' > "$fake_lc"; chmod +x "$fake_lc"
    export LIMIT_RESUME_LAUNCHCTL_OVERRIDE="$fake_lc"
    NL_REPO_ROOT="$tmp/fakerepo" "$SCRIPT_DIR/install-limit-resume.sh" ensure >/dev/null 2>&1
    plist="$tmp/LaunchAgents/local.neurallace.limit-resume.plist"
    [ -f "$plist" ] || { echo "  S6 uninstall: FAIL (setup did not create plist)"; exit 1; }
    "$SCRIPT_DIR/install-limit-resume.sh" uninstall >/dev/null 2>&1
    if [ ! -f "$plist" ]; then
      echo "  S6 uninstall removes plist: PASS"
    else
      echo "  S6 uninstall removes plist: FAIL"; exit 1
    fi
  ) && pass=$((pass+1)) || fail=$((fail+1))

  # S7 (F2 fix, PROVEN-live-on-this-machine regression test) -- when the
  # ONLY resolvable candidate is inside a linked worktree (main-checkout
  # resolution unavailable/absent), ensure must FAIL CLOSED: log a
  # refusal and write NO plist, rather than the original behavior of
  # silently registering a LaunchAgent against a throwaway worktree path.
  (
    tmp=$(mktemp -d)
    export LIMIT_RESUME_LAUNCHAGENTS_DIR="$tmp/LaunchAgents"
    export LIMIT_RESUME_UNAME_OVERRIDE=Darwin
    export LIMIT_RESUME_BASH_OVERRIDE="/bin/bash"
    mkdir -p "$tmp/main/adapters/claude-code/scripts"
    ( cd "$tmp/main" && git init --quiet && git config user.email t@example.com && git config user.name T \
      && git commit --allow-empty --quiet -m init \
      && git worktree add --quiet -b feat/s7-wt "$tmp/wt" >/dev/null 2>&1 )
    [ -d "$tmp/wt" ] || { echo "  S7 fail-closed from a linked worktree: FAIL (worktree setup itself failed)"; exit 1; }
    mkdir -p "$tmp/wt/adapters/claude-code/scripts"
    cp "$SCRIPT_DIR/install-limit-resume.sh" "$tmp/wt/adapters/claude-code/scripts/install-limit-resume.sh"
    cp "$SCRIPT_DIR/limit-resume.sh" "$tmp/wt/adapters/claude-code/scripts/limit-resume.sh"
    fake_lc="$tmp/fake-launchctl"; printf '#!/bin/bash\nexit 1\n' > "$fake_lc"; chmod +x "$fake_lc"
    export LIMIT_RESUME_LAUNCHCTL_OVERRIDE="$fake_lc"
    # No NL_REPO_ROOT / nl-repo-path config -> nl_repo_root falls back to
    # git-toplevel of the SOURCING script's own location, which here IS
    # the worktree -- exactly the pre-fix hazard.
    ( unset NL_REPO_ROOT; bash "$tmp/wt/adapters/claude-code/scripts/install-limit-resume.sh" ensure >/dev/null 2>&1 )
    plist="$tmp/LaunchAgents/local.neurallace.limit-resume.plist"
    if [ ! -f "$plist" ]; then
      echo "  S7 fail-closed from a linked worktree (no plist written): PASS"
    else
      echo "  S7 fail-closed from a linked worktree (no plist written): FAIL (plist was written against a worktree path: $(grep -o '/tmp[^<]*limit-resume.sh' "$plist" 2>/dev/null))"; exit 1
    fi
  ) && pass=$((pass+1)) || fail=$((fail+1))

  echo ""
  echo "[self-test] $pass passed, $fail failed"
  return $fail
}

case "${1:-}" in
  ensure|install) cmd_ensure ;;
  uninstall)      cmd_uninstall ;;
  status)         cmd_status ;;
  --self-test)    _self_test; exit $? ;;
  -h|--help|"")
    cat <<'USAGE_END' >&2
install-limit-resume.sh -- macOS LaunchAgent installer for limit-resume.sh

Usage:
  install-limit-resume.sh ensure       # install/refresh + bootstrap (idempotent)
  install-limit-resume.sh install      # alias for ensure
  install-limit-resume.sh uninstall    # bootout + remove plist
  install-limit-resume.sh status       # print loaded/plist state
  install-limit-resume.sh --self-test
USAGE_END
    exit 2
    ;;
  *)
    echo "install-limit-resume.sh: unknown subcommand '$1'" >&2
    exit 2
    ;;
esac
