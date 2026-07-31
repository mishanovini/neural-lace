#!/usr/bin/env bash
# ensure-cockpit.sh — best-effort SessionStart ensure for the observability
# cockpit (Workstreams UI node server, port 7733).
#
# WHY THIS EXISTS (operator directive 2026-07-09): the cockpit should be
# running whenever the operator is in an NL Claude session — a session-tied
# lifecycle replacing the `ConversationTreeUI-AutoStart` logon scheduled
# task (operator preference: no scheduled-task sprawl). The logon task's
# retirement is a RECORDED integration step, not an implied future: it was
# unregistered (register-autostart.ps1 -Unregister; verified gone) in the
# same 2026-07-09 integration that landed this file on master, recorded in
# docs/HANDOFF.md. This script is
# invoked from the EXISTING session-start-digest.sh SessionStart hook's
# run_digest() (one line, folded in — NOT a new SessionStart hooks[] entry;
# that array is already at its 8/8 cap), mirroring the
# session-heartbeat.sh "touch" callsite convention already used there
# (best-effort, `>/dev/null 2>&1 || true`, never blocks the digest).
#
# ============================================================
# macOS SUPPORT (operator directive 2026-07-29: "I want the macOS launch
# permanent") — docs/decisions/065-macos-cockpit-launchagent.md
# ============================================================
# PLATFORM DECISION: a `launchd` LaunchAgent (~/Library/LaunchAgents/*.plist,
# RunAtLoad + KeepAlive), NOT a nohup-backgrounded spawn from this hook.
# Reasoning: the operator explicitly asked for PERMANENT. A nohup child
# spawned from a SessionStart hook is a descendant of the Claude Code
# process tree — it dies with the terminal/session and, critically, does
# NOT come back after a reboot (nothing re-spawns it at the next login
# unless some OTHER mechanism runs this hook again, which only happens
# inside an NL session). A LaunchAgent is registered with the OS once and
# is then launchd's job forever: RunAtLoad starts it at every login
# (including after a reboot, with zero NL session involved), and KeepAlive
# restarts it if it crashes. This script's job each SessionStart is only to
# install/refresh the plist idempotently and nudge it live NOW (so the
# operator does not have to log out/in the first time this code lands) —
# not to be the thing that starts the process every time.
#   KeepAlive is the DICT form `{SuccessfulExit: false}`, not the bare
# boolean `true`. Rationale: server.js has its own single-instance guard
# (EADDRINUSE -> log + `process.exit(0)`, see server.js's "Single-instance
# guard" comment) — if our launchd-managed instance ever loses the port
# race (another instance, including one the operator started by hand, got
# there first) it exits 0, and bare `KeepAlive: true` would restart-loop it
# against that other owner forever. `SuccessfulExit: false` means "restart
# only on a NON-zero (crash) exit" — so a real crash still gets an
# automatic restart, but a clean EADDRINUSE-exit is respected as a no-op,
# matching server.js's own "the port is the mutex, not a global lock"
# design intent.
#
# CONTRACT (all mandatory, both platforms):
#   1. OS guard — Windows/MSYS runs the .ps1 launcher path (unchanged);
#      Darwin runs the LaunchAgent path (below); any other OS (Linux/cloud/
#      CI): silent no-op, exit 0. Test override: ENSURE_COCKPIT_UNAME_OVERRIDE
#      (wins over `uname -s` when set — lets a self-test drive either
#      platform's branch without needing that OS).
#   2. HARNESS_SELFTEST=1 — never actually spawns powershell/node (Windows)
#      or writes a real plist / calls real launchctl (Darwin). Records the
#      invocation/install that WOULD happen (to the log) and returns 0
#      BEFORE any side effect, so a self-test proves the guard logic +
#      invocation SHAPE without ever touching a real process, a real file
#      under ~/Library/LaunchAgents, or popping a GUI.
#   3. Launcher/server path resolved MACHINE-WIDE first (review fix
#      2026-07-09): hooks/lib/nl-paths.sh's nl_repo_root() (env
#      NL_REPO_ROOT -> install-written ~/.claude/local/nl-repo-path ->
#      lib-location git -> probe list), so the ensure works from ANY
#      session cwd — matching the machine-wide coverage of the logon task
#      this replaces. The session-cwd derivation (nl_main_checkout_root())
#      is kept as a FALLBACK for machines without an install config. Every
#      git-derived candidate is normalized to the MAIN checkout — NEVER a
#      worktree, so a worktree-rooted session never spawns/points-at a
#      worktree-local server copy (worktree isolation,
#      ADR/doctrine/worktree-isolation.md).
#   4. NON-BLOCKING — Windows: the real invocation is `nohup`'d and
#      backgrounded. Darwin: `launchctl bootstrap`/`bootout`/`print` are
#      each run under `nl_run_bounded` (hooks/lib/portable-timeout.sh,
#      reused rather than re-derived) so a hung launchd call cannot hang
#      this hook, and the liveness probe is a bounded, short poll loop
#      (never a blocking wait). Either way this script's own return is
#      never gated on the managed server actually being up.
#   5. Tolerate-absent — missing launcher/powershell.exe (Windows) or
#      missing node/launchctl/server.js (Darwin) -> log and return 0.
#      NEVER errors, NEVER blocks the session (exit 0 always, on every code
#      path — `set -u` only, deliberately no `set -e`).
#   6. Operator kill-switch (guard 0, review fix 2026-07-09) — env
#      ENSURE_COCKPIT_DISABLE=1 (per-session) or flag file
#      ~/.claude/local/cockpit-disabled (durable, operator-managed) ->
#      logged no-op, on BOTH platforms. The off-switch for a recurring
#      machine behavior must never require hand-editing live harness files.
#   7. Darwin IDEMPOTENT + SINGLE-INSTANCE: the plist is only (re)written
#      when its desired content differs from what's on disk; `launchctl
#      bootstrap` is only invoked when the label is not ALREADY loaded
#      (checked via `launchctl print`, never trusted-and-skipped); a
#      content change while loaded does one `bootout` then `bootstrap`, not
#      an additive second load. Liveness is verified by POLLING THE PORT
#      (bash's `/dev/tcp` pseudo-device — no curl dependency) rather than
#      by trusting `launchctl`'s own exit code, which only proves launchd
#      accepted the job, not that the node process is actually up.
#
# Darwin test-only overrides (mirror the existing Windows
# ENSURE_COCKPIT_PS_OVERRIDE / ENSURE_COCKPIT_FORCE_NO_PS convention — each
# substitutes a harmless local stand-in so a self-test exercises the REAL
# install/idempotency/dispatch code path without ever touching the
# operator's real ~/Library/LaunchAgents or spawning real launchctl/node):
#   ENSURE_COCKPIT_LAUNCHAGENTS_DIR — override for ~/Library/LaunchAgents.
#   ENSURE_COCKPIT_PLIST_LABEL      — override the launchd Label/basename.
#   ENSURE_COCKPIT_LAUNCHCTL_OVERRIDE / ENSURE_COCKPIT_FORCE_NO_LAUNCHCTL
#   ENSURE_COCKPIT_NODE_OVERRIDE    / ENSURE_COCKPIT_FORCE_NO_NODE
#
# Self-test: --self-test (see run_self_test()). HARNESS_SELFTEST=1
# sandboxes the log path under a tmp dir, mirroring the
# session-start-digest.sh / lib/signal-ledger.sh convention.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
{ source "$SCRIPT_DIR/../hooks/lib/nl-paths.sh" 2>/dev/null; } || true
# shellcheck disable=SC1091
{ source "$SCRIPT_DIR/../hooks/lib/portable-timeout.sh" 2>/dev/null; } || true
# Defensive shim (portable-timeout.sh's own USAGE contract): a partial
# install missing the lib degrades to unbounded — visibly, not silently.
# Only the Darwin path calls nl_run_bounded (launchctl); Windows is
# unaffected either way.
if ! declare -F nl_run_bounded >/dev/null 2>&1; then
  nl_run_bounded() {
    local _secs="${1:-}"; shift 2>/dev/null || true
    printf '[ensure-cockpit] WARNING: hooks/lib/portable-timeout.sh unavailable — running "%s" unbounded\n' "$*" >&2
    "$@"
  }
fi

# ----------------------------------------------------------------------
# Log path resolution (ENSURE_COCKPIT_LOG_PATH override; HARNESS_SELFTEST
# sandbox; default ~/.claude/logs/ensure-cockpit.log). Deliberately a
# SEPARATE file from launch-gui.ps1's own conv-tree-launcher.log: this file
# answers "did the SessionStart ensure-call fire, and what did it decide",
# not the launcher's internal server-start log.
# ----------------------------------------------------------------------
_ec_log_path() {
  if [[ -n "${ENSURE_COCKPIT_LOG_PATH:-}" ]]; then
    printf '%s' "$ENSURE_COCKPIT_LOG_PATH"
    return 0
  fi
  if [[ "${HARNESS_SELFTEST:-0}" == "1" ]]; then
    printf '%s/ensure-cockpit-selftest/%s/ensure-cockpit.log' "${TMPDIR:-/tmp}" "${$}"
    return 0
  fi
  printf '%s/.claude/logs/ensure-cockpit.log' "${HOME:-$PWD}"
}

_ec_log() {
  local msg="$1" path
  path="$(_ec_log_path)"
  mkdir -p "$(dirname "$path")" 2>/dev/null || true
  # Size-cap (review fix 2026-07-09): SessionStart-frequency appends plus
  # the backgrounded launcher's stdout/stderr land here; without a cap the
  # file grows unbounded. Keep the last 200 lines once it passes ~64KB.
  # Best-effort: a concurrent writer holding an open fd makes the mv fail
  # harmlessly (caught below) and a later quiet write rotates instead.
  if [[ -f "$path" ]] && [[ "$(wc -c < "$path" 2>/dev/null || echo 0)" -gt 65536 ]]; then
    { tail -n 200 "$path" > "$path.tmp.$$" && mv -f "$path.tmp.$$" "$path"; } 2>/dev/null \
      || rm -f "$path.tmp.$$" 2>/dev/null || true
  fi
  local ts; ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo unknown)"
  printf '[%s] %s\n' "$ts" "$msg" >> "$path" 2>/dev/null || true
}

# ----------------------------------------------------------------------
# Guard 0: operator kill-switch (review fix 2026-07-09). Two mechanisms:
# ENSURE_COCKPIT_DISABLE=1 (env; per-session/test) and the flag file
# ~/.claude/local/cockpit-disabled (durable; the operator creates/deletes
# it — local/ is machine-local config, not harness-managed source, so the
# off-switch never requires hand-editing live harness files).
# ----------------------------------------------------------------------
_ec_is_disabled() {
  [[ "${ENSURE_COCKPIT_DISABLE:-0}" == "1" ]] && return 0
  [[ -n "${HOME:-}" && -f "${HOME}/.claude/local/cockpit-disabled" ]] && return 0
  return 1
}

# ----------------------------------------------------------------------
# Guard 1: OS detection. Mirrors install.sh's exact case pattern
# (MINGW*|MSYS*|CYGWIN*|Windows_NT) so the two Windows-detection sites in
# this repo never drift apart.
# ----------------------------------------------------------------------
_ec_uname() {
  if [[ -n "${ENSURE_COCKPIT_UNAME_OVERRIDE:-}" ]]; then
    printf '%s' "$ENSURE_COCKPIT_UNAME_OVERRIDE"
    return 0
  fi
  uname -s 2>/dev/null
}

_ec_is_windows() {
  case "$(_ec_uname)" in
    MINGW*|MSYS*|CYGWIN*|Windows_NT) return 0 ;;
    *) return 1 ;;
  esac
}

_ec_is_darwin() {
  case "$(_ec_uname)" in
    Darwin) return 0 ;;
    *) return 1 ;;
  esac
}

# ----------------------------------------------------------------------
# powershell.exe resolution — PATH-based (mirrors the node-resolution
# tolerate-absence convention: probe, never assume). Overrides for tests:
#   ENSURE_COCKPIT_PS_OVERRIDE   — use this exact executable instead of PATH
#                                  resolution (substitutes a harmless local
#                                  stand-in, never real powershell/node,
#                                  while still exercising the REAL
#                                  backgrounding dispatch code path).
#   ENSURE_COCKPIT_FORCE_NO_PS   — force "not found" regardless of PATH
#                                  (simulates absence without needing to
#                                  sanitize PATH, which would also break
#                                  coreutils this script itself depends on
#                                  — dirname/mkdir/date — since those live
#                                  alongside powershell.exe's directory on
#                                  a real Windows PATH).
# ----------------------------------------------------------------------
_ec_resolve_powershell() {
  if [[ "${ENSURE_COCKPIT_FORCE_NO_PS:-0}" == "1" ]]; then
    return 1
  fi
  if [[ -n "${ENSURE_COCKPIT_PS_OVERRIDE:-}" ]]; then
    printf '%s' "$ENSURE_COCKPIT_PS_OVERRIDE"
    return 0
  fi
  local found
  found="$(command -v powershell.exe 2>/dev/null || true)"
  if [[ -n "$found" ]]; then
    printf '%s' "$found"
    return 0
  fi
  found="$(command -v powershell 2>/dev/null || true)"
  if [[ -n "$found" ]]; then
    printf '%s' "$found"
    return 0
  fi
  return 1
}

# ========================================================================
# DARWIN (macOS) — LaunchAgent path. See the script header for the
# platform decision + docs/decisions/065-macos-cockpit-launchagent.md.
# ========================================================================

# node resolution — mirrors _ec_resolve_powershell's tolerate-absence +
# override conventions exactly (ENSURE_COCKPIT_NODE_OVERRIDE substitutes a
# harmless stand-in for tests; ENSURE_COCKPIT_FORCE_NO_NODE simulates
# absence without sanitizing PATH).
_ec_resolve_node() {
  if [[ "${ENSURE_COCKPIT_FORCE_NO_NODE:-0}" == "1" ]]; then
    return 1
  fi
  if [[ -n "${ENSURE_COCKPIT_NODE_OVERRIDE:-}" ]]; then
    printf '%s' "$ENSURE_COCKPIT_NODE_OVERRIDE"
    return 0
  fi
  local found
  found="$(command -v node 2>/dev/null || true)"
  if [[ -n "$found" ]]; then
    printf '%s' "$found"
    return 0
  fi
  return 1
}

# launchctl resolution — same shape as _ec_resolve_powershell/_ec_resolve_node.
_ec_resolve_launchctl() {
  if [[ "${ENSURE_COCKPIT_FORCE_NO_LAUNCHCTL:-0}" == "1" ]]; then
    return 1
  fi
  if [[ -n "${ENSURE_COCKPIT_LAUNCHCTL_OVERRIDE:-}" ]]; then
    printf '%s' "$ENSURE_COCKPIT_LAUNCHCTL_OVERRIDE"
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

_ec_darwin_launchagents_dir() {
  if [[ -n "${ENSURE_COCKPIT_LAUNCHAGENTS_DIR:-}" ]]; then
    printf '%s' "$ENSURE_COCKPIT_LAUNCHAGENTS_DIR"
  else
    printf '%s/Library/LaunchAgents' "${HOME:-$PWD}"
  fi
}

_ec_darwin_label() {
  printf '%s' "${ENSURE_COCKPIT_PLIST_LABEL:-local.neurallace.workstreams-cockpit}"
}

_ec_darwin_plist_path() {
  printf '%s/%s.plist' "$(_ec_darwin_launchagents_dir)" "$(_ec_darwin_label)"
}

# _ec_darwin_plist_content <label> <node> <server_js> <workdir> <port>
#   <out_log> <err_log> — prints the desired plist body to stdout. KeepAlive
# is the dict form (SuccessfulExit=false), not bare `true` — see header.
_ec_darwin_plist_content() {
  local label="$1" node="$2" server_js="$3" workdir="$4" port="$5" out_log="$6" err_log="$7"
  cat <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>${label}</string>
	<key>ProgramArguments</key>
	<array>
		<string>${node}</string>
		<string>${server_js}</string>
	</array>
	<key>WorkingDirectory</key>
	<string>${workdir}</string>
	<key>EnvironmentVariables</key>
	<dict>
		<key>CTREE_PORT</key>
		<string>${port}</string>
	</dict>
	<key>RunAtLoad</key>
	<true/>
	<key>KeepAlive</key>
	<dict>
		<key>SuccessfulExit</key>
		<false/>
	</dict>
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

# _ec_darwin_probe_port <host> <port> [<tries>] — liveness by POLLING THE
# PORT (contract item 7), not by trusting launchctl's exit code, which only
# proves launchd accepted the job, not that node actually bound the port.
# Uses bash's own `/dev/tcp` pseudo-device (no curl/nc dependency in the
# shipped path). If this bash was built without net-redirections the probe
# always reports "not responding" — a degraded-but-safe false negative,
# never a hang and never a false positive.
_ec_darwin_probe_port() {
  local host="$1" port="$2" tries="${3:-5}"
  local i=0
  while [ "$i" -lt "$tries" ]; do
    if (exec 3<>"/dev/tcp/$host/$port") 2>/dev/null; then
      exec 3>&- 2>/dev/null
      exec 3<&- 2>/dev/null
      return 0
    fi
    sleep 0.3 2>/dev/null || sleep 1
    i=$((i + 1))
  done
  return 1
}

# _ec_darwin_ensure — install/refresh the LaunchAgent idempotently, nudge
# it live now, verify by polling the port. Every branch is tolerate-absent
# and returns 0; HARNESS_SELFTEST=1 is checked BEFORE any real side effect
# (mkdir/plist write/launchctl call), mirroring the Windows stub contract.
_ec_darwin_ensure() {
  if ! declare -F nl_repo_root >/dev/null 2>&1; then
    _ec_log "[darwin] tolerate-absent: hooks/lib/nl-paths.sh unavailable (nl_repo_root undefined) — skipping cockpit LaunchAgent ensure"
    return 0
  fi

  # Root resolution — identical machine-wide-first / worktree-normalized
  # technique as the Windows branch (contract item 3).
  local root norm server_js workdir
  root="$(nl_repo_root 2>/dev/null || true)"
  if [[ -n "$root" ]]; then
    norm="$(cd "$root" 2>/dev/null && nl_main_checkout_root 2>/dev/null || true)"
    [[ -n "$norm" ]] && root="$norm"
  fi
  if [[ -z "$root" || ! -f "$root/neural-lace/workstreams-ui/server/server.js" ]]; then
    local main_root
    main_root="$(nl_main_checkout_root 2>/dev/null || true)"
    if [[ -n "$main_root" && -f "$main_root/neural-lace/workstreams-ui/server/server.js" ]]; then
      root="$main_root"
    fi
  fi
  if [[ -z "$root" || ! -f "$root/neural-lace/workstreams-ui/server/server.js" ]]; then
    _ec_log "[darwin] tolerate-absent: workstreams-ui server.js unresolved (machine-wide root '${root:-<none>}' and session-cwd fallback both lack it) — skipping cockpit LaunchAgent ensure"
    return 0
  fi
  server_js="$root/neural-lace/workstreams-ui/server/server.js"
  workdir="$root/neural-lace/workstreams-ui"

  local node
  if ! node="$(_ec_resolve_node)"; then
    _ec_log "[darwin] tolerate-absent: node not found on PATH — skipping cockpit LaunchAgent ensure"
    return 0
  fi

  local launchctl
  if ! launchctl="$(_ec_resolve_launchctl)"; then
    _ec_log "[darwin] tolerate-absent: launchctl not found — skipping cockpit LaunchAgent ensure"
    return 0
  fi

  local port="${CTREE_PORT:-7733}"
  local la_dir label plist_path log_dir out_log err_log
  la_dir="$(_ec_darwin_launchagents_dir)"
  label="$(_ec_darwin_label)"
  plist_path="$(_ec_darwin_plist_path)"
  log_dir="$(dirname "$(_ec_log_path)")"
  out_log="$log_dir/workstreams-cockpit.stdout.log"
  err_log="$log_dir/workstreams-cockpit.stderr.log"

  local desired
  desired="$(_ec_darwin_plist_content "$label" "$node" "$server_js" "$workdir" "$port" "$out_log" "$err_log")"

  # HARNESS_SELFTEST stub — BEFORE any mkdir/write/launchctl call (contract
  # item 2): proves the resolution + shape without ever touching a real
  # file under ~/Library/LaunchAgents or invoking real launchctl.
  if [[ "${HARNESS_SELFTEST:-0}" == "1" ]]; then
    _ec_log "[darwin self-test stub] would install/refresh plist at $plist_path (label=$label, node=$node, server=$server_js) and bootstrap via $launchctl — never written/spawned"
    return 0
  fi

  mkdir -p "$la_dir" 2>/dev/null || true

  # Idempotent write (contract item 7): only touch disk when content differs.
  local need_write=1
  if [[ -f "$plist_path" ]]; then
    local existing; existing="$(cat "$plist_path" 2>/dev/null || true)"
    [[ "$existing" == "$desired" ]] && need_write=0
  fi
  if [[ "$need_write" -eq 1 ]]; then
    local tmp_plist="${plist_path}.tmp.$$"
    if printf '%s\n' "$desired" > "$tmp_plist" 2>/dev/null && mv -f "$tmp_plist" "$plist_path" 2>/dev/null; then
      _ec_log "[darwin] plist written/refreshed: $plist_path"
    else
      _ec_log "[darwin] tolerate-absent: could not write plist at $plist_path — skipping bootstrap"
      return 0
    fi
  fi

  # Single-instance (contract item 7): only bootstrap when NOT already
  # loaded — checked via `launchctl print`, never trusted-and-skipped.
  local uid domain_target was_loaded
  uid="$(id -u 2>/dev/null || echo 0)"
  domain_target="gui/$uid/$label"
  was_loaded=1
  if nl_run_bounded 10 "$launchctl" print "$domain_target" >/dev/null 2>&1; then
    was_loaded=0
  fi

  if [[ "$need_write" -eq 1 && "$was_loaded" -eq 0 ]]; then
    # Content changed while loaded: bootout then bootstrap fresh, not an
    # additive second load.
    nl_run_bounded 10 "$launchctl" bootout "$domain_target" >/dev/null 2>&1 || true
    was_loaded=1
  fi

  if [[ "$was_loaded" -eq 1 ]]; then
    if nl_run_bounded 10 "$launchctl" bootstrap "gui/$uid" "$plist_path" >/dev/null 2>&1; then
      _ec_log "[darwin] launchctl bootstrap succeeded for $label"
    else
      _ec_log "[darwin] launchctl bootstrap returned non-zero for $label (may already be loaded, or no GUI launchd domain in this session) — continuing to liveness probe"
    fi
  else
    _ec_log "[darwin] $label already bootstrapped — no-op (idempotent)"
  fi

  # Liveness by polling the port (contract item 7), not launchctl's exit code.
  if _ec_darwin_probe_port "127.0.0.1" "$port" 5; then
    _ec_log "[darwin] cockpit responding on 127.0.0.1:$port"
  else
    _ec_log "[darwin] cockpit not yet responding on 127.0.0.1:$port after probe window (may still be starting; launchd KeepAlive retries on crash)"
  fi

  return 0
}

# ----------------------------------------------------------------------
# Main entry. Always returns 0 — every branch below is a deliberate,
# logged no-op or a fire-and-forget dispatch; there is no error branch.
# ----------------------------------------------------------------------
run_ensure() {
  if _ec_is_disabled; then
    _ec_log "no-op: cockpit ensure disabled by operator (ENSURE_COCKPIT_DISABLE=1 or ~/.claude/local/cockpit-disabled)"
    return 0
  fi

  if _ec_is_darwin; then
    _ec_darwin_ensure
    return 0
  fi

  if ! _ec_is_windows; then
    _ec_log "no-op: OS '$(_ec_uname)' is not Windows/MSYS — cockpit ensure only runs on Windows or macOS"
    return 0
  fi

  if ! declare -F nl_repo_root >/dev/null 2>&1; then
    _ec_log "tolerate-absent: hooks/lib/nl-paths.sh unavailable (nl_repo_root undefined) — skipping cockpit ensure"
    return 0
  fi

  # Launcher resolution (review fix 2026-07-09 — contract item 3):
  # MACHINE-WIDE first via nl_repo_root() so any session cwd finds the
  # cockpit (the logon task this replaces was machine-wide; the cockpit is
  # a cross-project surface); the previous session-cwd derivation
  # (nl_main_checkout_root()) stays as the fallback for machines without
  # an install config. A git-derived root can be a worktree (nl_repo_root
  # order 3 resolves the lib's own checkout), so normalize through
  # nl_main_checkout_root() run FROM that root — never spawn a
  # worktree-local server copy.
  local launcher="" root norm
  root="$(nl_repo_root 2>/dev/null || true)"
  if [[ -n "$root" ]]; then
    norm="$(cd "$root" 2>/dev/null && nl_main_checkout_root 2>/dev/null || true)"
    [[ -n "$norm" ]] && root="$norm"
    if [[ -f "$root/neural-lace/workstreams-ui/scripts/launch-gui.ps1" ]]; then
      launcher="$root/neural-lace/workstreams-ui/scripts/launch-gui.ps1"
    fi
  fi
  if [[ -z "$launcher" ]]; then
    local main_root
    main_root="$(nl_main_checkout_root 2>/dev/null || true)"
    if [[ -n "$main_root" && -f "$main_root/neural-lace/workstreams-ui/scripts/launch-gui.ps1" ]]; then
      launcher="$main_root/neural-lace/workstreams-ui/scripts/launch-gui.ps1"
    fi
  fi
  if [[ -z "$launcher" ]]; then
    _ec_log "tolerate-absent: workstreams-ui launcher unresolved (machine-wide root '${root:-<none>}' and session-cwd fallback both lack it) — skipping cockpit ensure"
    return 0
  fi

  local psexe
  if ! psexe="$(_ec_resolve_powershell)"; then
    _ec_log "tolerate-absent: powershell.exe not found on PATH — skipping cockpit ensure"
    return 0
  fi

  local -a cmd=("$psexe" -ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -File "$launcher" -NoBrowser)

  if [[ "${HARNESS_SELFTEST:-0}" == "1" ]]; then
    _ec_log "[self-test stub] would invoke (not spawned): ${cmd[*]}"
    return 0
  fi

  local log; log="$(_ec_log_path)"
  mkdir -p "$(dirname "$log")" 2>/dev/null || true
  _ec_log "invoking (backgrounded, non-blocking): ${cmd[*]}"
  # Fire-and-forget: nohup (survives SIGHUP) + background + disown (removed
  # from this shell's job table) so a cold node start (launch-gui.ps1 polls
  # Test-ServerUp for up to ~5s) can never delay this script's return.
  nohup "${cmd[@]}" >>"$log" 2>&1 < /dev/null &
  disown 2>/dev/null || true
  return 0
}

# ============================================================
# Self-test
# ============================================================
run_self_test() {
  local pass=0 fail=0 tmp
  tmp="$(mktemp -d 2>/dev/null || echo "/tmp/ensure-cockpit-st-$$")"
  mkdir -p "$tmp"
  export HARNESS_SELFTEST=1

  # Absolute self-path + absolute bash interpreter path (nl-paths.sh's own
  # self-test convention): several scenarios below `cd` into a fixture dir
  # and/or sanitize PATH before re-invoking this script, so both the
  # script path AND the `bash` command name itself must be absolute —
  # otherwise a relative BASH_SOURCE[0] or a PATH-sanitized `bash` lookup
  # fails from the new cwd/PATH (caught empirically: S2-S6 first drafts
  # failed with "No such file or directory" / "bash: command not found").
  local self_abs bash_bin
  self_abs="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
  bash_bin="${BASH:-$(command -v bash)}"

  # Machine-wide-resolution pin (review fix 2026-07-09): run_ensure now
  # tries nl_repo_root() FIRST, which on a real machine resolves via env /
  # install config / the lib's own checkout — any of which would leak the
  # REAL repo (and its real launcher) into these fixtures. Pinning
  # NL_REPO_ROOT to an existing launcher-less dir forces the machine-wide
  # candidate to fail closed, so each pinned scenario exercises exactly
  # the branch it targets. S10 exercises the machine-wide path itself
  # (fixture HOME config instead of the pin).
  local pin_root="$tmp/no-ui"
  mkdir -p "$pin_root"

  _ck_contains() {
    local label="$1" haystack="$2" needle="$3"
    if [[ "$haystack" == *"$needle"* ]]; then
      echo "PASS: $label"; pass=$((pass + 1))
    else
      echo "FAIL: $label (did not contain '$needle'); got:" >&2
      printf '%s\n' "$haystack" | sed 's/^/    /' >&2
      fail=$((fail + 1))
    fi
  }
  _ck_not_contains() {
    local label="$1" haystack="$2" needle="$3"
    if [[ "$haystack" != *"$needle"* ]]; then
      echo "PASS: $label"; pass=$((pass + 1))
    else
      echo "FAIL: $label (unexpectedly contained '$needle')" >&2
      fail=$((fail + 1))
    fi
  }
  _ck_eq() {
    local label="$1" got="$2" want="$3"
    if [[ "$got" == "$want" ]]; then
      echo "PASS: $label"; pass=$((pass + 1))
    else
      echo "FAIL: $label (got '$got', want '$want')" >&2
      fail=$((fail + 1))
    fi
  }
  # _count_lines_if_exists <file> — 0 when the file was never created (the
  # expected shape of a counter log before its first append), never a
  # redirection error to stderr from `wc -l < missing-file`.
  _count_lines_if_exists() {
    local f="$1"
    if [[ -f "$f" ]]; then
      wc -l < "$f" 2>/dev/null | tr -d ' '
    else
      printf '0'
    fi
  }

  _seed_main_repo() {
    # A minimal main-checkout fixture with the Windows launcher AND the
    # Darwin server.js present at the exact relative paths run_ensure()
    # expects on each platform (one fixture serves both branches' tests).
    local d="$1"
    mkdir -p "$d/neural-lace/workstreams-ui/scripts" "$d/neural-lace/workstreams-ui/server"
    cat > "$d/neural-lace/workstreams-ui/scripts/launch-gui.ps1" <<'EOF'
# fixture launcher — never actually executed by this self-test.
EOF
    cat > "$d/neural-lace/workstreams-ui/server/server.js" <<'EOF'
// fixture server.js — never actually executed by this self-test (Darwin
// scenarios fake launchctl so the ProgramArguments node/server.js pair is
// never really exec'd either).
EOF
    ( cd "$d" && git init --quiet && git config core.hookspath "" \
      && git config user.email t@example.com && git config user.name T \
      && git add -A && git commit --quiet -m init ) >/dev/null 2>&1
  }

  # _fake_launchctl <state_dir> — writes a stand-in launchctl to
  # "$state_dir/fake-launchctl.sh" that tracks "loaded" state on disk and
  # counts bootstrap/bootout invocations, so a test can assert exactly how
  # many times each was called (mirrors S7's ENSURE_COCKPIT_PS_OVERRIDE
  # technique: a harmless local stand-in that still exercises the REAL
  # dispatch code path in _ec_darwin_ensure, never a real launchctl call).
  _fake_launchctl() {
    local state_dir="$1"
    local script="$state_dir/fake-launchctl.sh"
    mkdir -p "$state_dir"
    cat > "$script" <<EOF
#!/usr/bin/env bash
state="$state_dir"
cmd="\$1"; shift || true
case "\$cmd" in
  print)
    [[ -f "\$state/loaded" ]] && exit 0 || exit 113
    ;;
  bootstrap)
    echo "bootstrap \$*" >> "\$state/bootstrap.log"
    : > "\$state/loaded"
    exit 0
    ;;
  bootout)
    echo "bootout \$*" >> "\$state/bootout.log"
    rm -f "\$state/loaded"
    exit 0
    ;;
  *)
    exit 1
    ;;
esac
EOF
    chmod +x "$script"
    printf '%s' "$script"
  }

  # _require_fake_launchctl <path> — hard-abort the WHOLE self-test (never
  # just fail one scenario and continue) if the fake launchctl stand-in was
  # not actually created executable. Defense-in-depth: without this, a
  # regression in _fake_launchctl silently leaves
  # ENSURE_COCKPIT_LAUNCHCTL_OVERRIDE empty, `_ec_resolve_launchctl` falls
  # through to the REAL `command -v launchctl`, and a Darwin scenario below
  # would bootstrap a REAL (if harmlessly-labeled) LaunchAgent on the
  # machine running this self-test — exactly the class of accidental
  # real-side-effect this suite must never risk. (Caught empirically: a
  # `local a=$1 b=$a`-under-`set -u` bug in an early draft of
  # _fake_launchctl did exactly this before this guard existed; cleaned up
  # by hand with `launchctl bootout` — see docs/decisions/065.)
  _require_fake_launchctl() {
    local path="$1"
    if [[ ! -x "$path" ]]; then
      echo "FATAL: fake launchctl stand-in missing/not executable at '$path' — aborting self-test rather than risk the real launchd" >&2
      rm -rf "$tmp" 2>/dev/null || true
      exit 1
    fi
  }

  # ---- S1: non-Windows override -> silent no-op, never reaches the
  # launcher/powershell resolution at all. ----
  local s1_log="$tmp/s1.log"
  ( ENSURE_COCKPIT_UNAME_OVERRIDE="Linux" ENSURE_COCKPIT_LOG_PATH="$s1_log" HARNESS_SELFTEST=1 \
      "$bash_bin" -c "source '$self_abs'; run_ensure" )
  local s1_out; s1_out="$(cat "$s1_log" 2>/dev/null || true)"
  _ck_contains "S1 non-Windows override no-ops" "$s1_out" "not Windows/MSYS"
  _ck_not_contains "S1 non-Windows override never resolves a launcher" "$s1_out" "launcher"

  # ---- S2: Windows override, no git checkout at all -> tolerate-absent
  # (nl_main_checkout_root unresolved). ----
  local s2_dir="$tmp/s2-nogit" s2_log="$tmp/s2.log"
  mkdir -p "$s2_dir"
  ( cd "$s2_dir" && NL_REPO_ROOT="$pin_root" ENSURE_COCKPIT_UNAME_OVERRIDE="MINGW64_NT" ENSURE_COCKPIT_LOG_PATH="$s2_log" HARNESS_SELFTEST=1 \
      "$bash_bin" -c "source '$self_abs'; run_ensure" )
  local s2_out; s2_out="$(cat "$s2_log" 2>/dev/null || true)"
  _ck_contains "S2 Windows + no git checkout tolerates absent root" "$s2_out" "unresolved"

  # ---- S3: Windows override, valid git checkout, launcher MISSING ->
  # tolerate-absent (launcher not found). ----
  local s3_dir="$tmp/s3-repo" s3_log="$tmp/s3.log"
  mkdir -p "$s3_dir"
  ( cd "$s3_dir" && git init --quiet && git config core.hookspath "" \
    && git config user.email t@example.com && git config user.name T \
    && echo x > f && git add f && git commit --quiet -m init ) >/dev/null 2>&1
  ( cd "$s3_dir" && NL_REPO_ROOT="$pin_root" ENSURE_COCKPIT_UNAME_OVERRIDE="MINGW64_NT" ENSURE_COCKPIT_LOG_PATH="$s3_log" HARNESS_SELFTEST=1 \
      "$bash_bin" -c "source '$self_abs'; run_ensure" )
  local s3_out; s3_out="$(cat "$s3_log" 2>/dev/null || true)"
  _ck_contains "S3 Windows + missing launcher tolerates absent" "$s3_out" "launcher unresolved"

  # ---- S4: Windows override, valid checkout + launcher present,
  # HARNESS_SELFTEST=1 -> stub-records the invocation SHAPE (-NoBrowser,
  # the launcher path) and NEVER takes the real-spawn branch. Oracle for
  # the resolved root: `git rev-parse --show-toplevel` itself (NOT the raw
  # $s4_dir mktemp path) — on this Git-for-Windows setup, git's own
  # toplevel resolution returns the C:/... drive-letter form, which
  # disagrees with bash/mktemp's POSIX-style /tmp/... spelling of the SAME
  # directory (same divergence nl-paths.sh's own T6/T7 self-test
  # documents; the non-worktree branch of nl_main_checkout_root() returns
  # this raw form verbatim, unlike the worktree branch which normalizes
  # via cd+pwd — see S6 below). ----
  local s4_dir="$tmp/s4-repo" s4_log="$tmp/s4.log"
  _seed_main_repo "$s4_dir"
  local s4_expected_root; s4_expected_root="$(cd "$s4_dir" && git rev-parse --show-toplevel)"
  ( cd "$s4_dir" && NL_REPO_ROOT="$pin_root" ENSURE_COCKPIT_UNAME_OVERRIDE="MINGW64_NT" ENSURE_COCKPIT_LOG_PATH="$s4_log" HARNESS_SELFTEST=1 \
      "$bash_bin" -c "source '$self_abs'; run_ensure" )
  local s4_out; s4_out="$(cat "$s4_log" 2>/dev/null || true)"
  _ck_contains "S4 self-test stub records the invocation" "$s4_out" "[self-test stub] would invoke"
  _ck_contains "S4 stub invocation carries -NoBrowser" "$s4_out" "-NoBrowser"
  _ck_contains "S4 stub invocation names the resolved launcher path" "$s4_out" "$s4_expected_root/neural-lace/workstreams-ui/scripts/launch-gui.ps1"
  _ck_not_contains "S4 stub never takes the real-spawn branch" "$s4_out" "invoking (backgrounded"

  # ---- S5: Windows override, valid checkout + launcher present, but
  # powershell.exe NOT resolvable -> tolerate-absent. Uses
  # ENSURE_COCKPIT_FORCE_NO_PS rather than a sanitized PATH: blanking PATH
  # would also hide the coreutils (dirname/mkdir/date) this script itself
  # depends on, since they live alongside powershell.exe's directory on a
  # real Windows PATH — caught empirically (first draft errored with
  # "dirname: command not found" instead of exercising the branch under
  # test). ----
  local s5_dir="$tmp/s5-repo" s5_log="$tmp/s5.log"
  _seed_main_repo "$s5_dir"
  ( cd "$s5_dir" && NL_REPO_ROOT="$pin_root" ENSURE_COCKPIT_UNAME_OVERRIDE="MINGW64_NT" ENSURE_COCKPIT_LOG_PATH="$s5_log" HARNESS_SELFTEST=1 \
      ENSURE_COCKPIT_FORCE_NO_PS=1 "$bash_bin" -c "source '$self_abs'; run_ensure" )
  local s5_out; s5_out="$(cat "$s5_log" 2>/dev/null || true)"
  _ck_contains "S5 missing powershell.exe tolerates absent" "$s5_out" "powershell.exe not found"

  # ---- S6: main-checkout resolution from a LINKED WORKTREE resolves the
  # launcher under the MAIN checkout, never the worktree (guard 3). Mirrors
  # nl-paths.sh's own T7 technique. ----
  local s6_main="$tmp/s6-main" s6_wt="$tmp/s6-wt" s6_log="$tmp/s6.log"
  _seed_main_repo "$s6_main"
  local s6_wt_ok=1
  ( cd "$s6_main" && git worktree add -q -b ensure-cockpit-selftest-wt6 "$s6_wt" ) >/dev/null 2>&1 || s6_wt_ok=0
  if [[ "$s6_wt_ok" -eq 1 ]]; then
    ( cd "$s6_wt" && NL_REPO_ROOT="$pin_root" ENSURE_COCKPIT_UNAME_OVERRIDE="MINGW64_NT" ENSURE_COCKPIT_LOG_PATH="$s6_log" HARNESS_SELFTEST=1 \
        "$bash_bin" -c "source '$self_abs'; run_ensure" )
    local s6_out; s6_out="$(cat "$s6_log" 2>/dev/null || true)"
    _ck_contains "S6 worktree session resolves launcher under MAIN checkout" "$s6_out" "$s6_main/neural-lace/workstreams-ui/scripts/launch-gui.ps1"
    _ck_not_contains "S6 worktree session never resolves launcher under the worktree" "$s6_out" "$s6_wt/neural-lace"
    ( cd "$s6_main" && git worktree remove --force "$s6_wt" >/dev/null 2>&1 || true )
    ( cd "$s6_main" && git branch -D ensure-cockpit-selftest-wt6 >/dev/null 2>&1 || true )
  else
    echo "  ok   S6 linked-worktree resolution: SKIP (git worktree add failed in test env)"
  fi

  # ---- S7: never blocks — the REAL (non-selftest) dispatch path, using
  # ENSURE_COCKPIT_PS_OVERRIDE to substitute a harmless local stand-in that
  # sleeps 3s (never real powershell/node), proves run_ensure() itself
  # returns near-instantly because the invocation is backgrounded. ----
  local s7_dir="$tmp/s7-repo" s7_log="$tmp/s7.log" s7_fakeps="$tmp/s7-fake-powershell.sh"
  _seed_main_repo "$s7_dir"
  cat > "$s7_fakeps" <<'EOF'
#!/usr/bin/env bash
: > "${0}.ran"
sleep 3
exit 0
EOF
  chmod +x "$s7_fakeps"
  local s7_start s7_end s7_elapsed
  s7_start=$(date +%s)
  ( cd "$s7_dir" && NL_REPO_ROOT="$pin_root" ENSURE_COCKPIT_UNAME_OVERRIDE="MINGW64_NT" ENSURE_COCKPIT_LOG_PATH="$s7_log" \
      ENSURE_COCKPIT_PS_OVERRIDE="$s7_fakeps" HARNESS_SELFTEST=0 \
      "$bash_bin" -c "source '$self_abs'; run_ensure" )
  s7_end=$(date +%s)
  s7_elapsed=$((s7_end - s7_start))
  _ck_le_local() {
    if [[ "$s7_elapsed" -le 2 ]]; then
      echo "PASS: S7 real (backgrounded) dispatch returns near-instantly despite a 3s stand-in (${s7_elapsed}s)"; pass=$((pass + 1))
    else
      echo "FAIL: S7 real dispatch took ${s7_elapsed}s (>2s) — the invocation may not be backgrounded" >&2
      fail=$((fail + 1))
    fi
  }
  _ck_le_local
  local s7_out; s7_out="$(cat "$s7_log" 2>/dev/null || true)"
  _ck_contains "S7 real dispatch logs the backgrounded invocation" "$s7_out" "invoking (backgrounded"
  # Effect assertion (review fix 2026-07-09): the stand-in writes a marker
  # BEFORE its sleep, so this proves the child actually exec'd — the
  # "invoking" log line alone is written pre-spawn and would still appear
  # if the spawn line itself regressed (test-asserts-intent-not-effect).
  local s7_ran=0 _s7i
  for _s7i in $(seq 1 20); do
    [[ -f "$s7_fakeps.ran" ]] && { s7_ran=1; break; }
    sleep 0.1 2>/dev/null || sleep 1
  done
  _ck_eq "S7 backgrounded child actually executed (marker file appeared)" "$s7_ran" "1"

  # ---- S8: nl-paths.sh unavailable (script relocated without its sibling
  # hooks/lib) -> tolerate-absent, never errors. ----
  local s8_dir="$tmp/s8-relocated" s8_log="$tmp/s8.log"
  mkdir -p "$s8_dir"
  cp "$self_abs" "$s8_dir/ensure-cockpit.sh"
  ( cd "$tmp" && ENSURE_COCKPIT_UNAME_OVERRIDE="MINGW64_NT" ENSURE_COCKPIT_LOG_PATH="$s8_log" HARNESS_SELFTEST=1 \
      bash -c "source '$s8_dir/ensure-cockpit.sh'; run_ensure" )
  local s8_out; s8_out="$(cat "$s8_log" 2>/dev/null || true)"
  _ck_contains "S8 relocated script (no sibling nl-paths.sh) tolerates absent" "$s8_out" "nl-paths.sh unavailable"

  # ---- S9: exit code is always 0 on the real invocation entry point,
  # across both a no-op branch and a tolerate-absent branch. ----
  local s9a_rc s9b_rc
  ( cd "$tmp" && ENSURE_COCKPIT_UNAME_OVERRIDE="Linux" ENSURE_COCKPIT_LOG_PATH="$tmp/s9a.log" HARNESS_SELFTEST=1 \
      "$bash_bin" "$self_abs" >/dev/null 2>&1 )
  s9a_rc=$?
  _ck_eq "S9a real entry point exits 0 on non-Windows no-op" "$s9a_rc" "0"
  ( cd "$s3_dir" && NL_REPO_ROOT="$pin_root" ENSURE_COCKPIT_UNAME_OVERRIDE="MINGW64_NT" ENSURE_COCKPIT_LOG_PATH="$tmp/s9b.log" HARNESS_SELFTEST=1 \
      "$bash_bin" "$self_abs" >/dev/null 2>&1 )
  s9b_rc=$?
  _ck_eq "S9b real entry point exits 0 on missing-launcher tolerate-absent" "$s9b_rc" "0"

  # ---- S10: machine-wide resolution (review fix 2026-07-09 — the exact
  # regression class the harness/code review caught: session-cwd-only
  # resolution silently no-ops in every non-NL project session, a coverage
  # regression vs the machine-wide logon task this replaces). S10a: from a
  # NON-NL, non-git cwd, an install-config (fixture HOME) resolves the
  # launcher machine-wide. S10b: a config pointing at a WORKTREE resolves
  # the launcher under the MAIN checkout (guard 3 survives the
  # machine-wide path). ----
  local s10_main="$tmp/s10-main" s10_home="$tmp/s10-home" s10_cwd="$tmp/s10-elsewhere" s10_log="$tmp/s10a.log"
  _seed_main_repo "$s10_main"
  mkdir -p "$s10_home/.claude/local" "$s10_cwd"
  printf '%s\n' "$s10_main" > "$s10_home/.claude/local/nl-repo-path"
  local s10_expected_root; s10_expected_root="$(cd "$s10_main" && git rev-parse --show-toplevel)"
  ( cd "$s10_cwd" && HOME="$s10_home" NL_REPO_ROOT= ENSURE_COCKPIT_UNAME_OVERRIDE="MINGW64_NT" ENSURE_COCKPIT_LOG_PATH="$s10_log" HARNESS_SELFTEST=1 \
      "$bash_bin" -c "source '$self_abs'; run_ensure" )
  local s10_out; s10_out="$(cat "$s10_log" 2>/dev/null || true)"
  _ck_contains "S10a machine-wide config resolves launcher from a non-NL cwd" "$s10_out" "$s10_expected_root/neural-lace/workstreams-ui/scripts/launch-gui.ps1"

  local s10b_wt="$tmp/s10b-wt" s10b_home="$tmp/s10b-home" s10b_log="$tmp/s10b.log"
  mkdir -p "$s10b_home/.claude/local"
  local s10b_wt_ok=1
  ( cd "$s10_main" && git worktree add -q -b ensure-cockpit-selftest-wt10 "$s10b_wt" ) >/dev/null 2>&1 || s10b_wt_ok=0
  if [[ "$s10b_wt_ok" -eq 1 ]]; then
    printf '%s\n' "$s10b_wt" > "$s10b_home/.claude/local/nl-repo-path"
    ( cd "$s10_cwd" && HOME="$s10b_home" NL_REPO_ROOT= ENSURE_COCKPIT_UNAME_OVERRIDE="MINGW64_NT" ENSURE_COCKPIT_LOG_PATH="$s10b_log" HARNESS_SELFTEST=1 \
        "$bash_bin" -c "source '$self_abs'; run_ensure" )
    local s10b_out; s10b_out="$(cat "$s10b_log" 2>/dev/null || true)"
    _ck_contains "S10b machine-wide WORKTREE config normalizes to MAIN checkout" "$s10b_out" "$s10_main/neural-lace/workstreams-ui/scripts/launch-gui.ps1"
    _ck_not_contains "S10b machine-wide worktree config never resolves under the worktree" "$s10b_out" "$s10b_wt/neural-lace"
    ( cd "$s10_main" && git worktree remove --force "$s10b_wt" >/dev/null 2>&1 || true )
    ( cd "$s10_main" && git branch -D ensure-cockpit-selftest-wt10 >/dev/null 2>&1 || true )
  else
    echo "  ok   S10b machine-wide worktree normalization: SKIP (git worktree add failed in test env)"
  fi

  # ---- S11: operator kill-switch (guard 0, review fix 2026-07-09) — env
  # knob and durable flag file each no-op before any resolution/spawn. ----
  local s11a_log="$tmp/s11a.log"
  ( cd "$s4_dir" && ENSURE_COCKPIT_DISABLE=1 ENSURE_COCKPIT_UNAME_OVERRIDE="MINGW64_NT" ENSURE_COCKPIT_LOG_PATH="$s11a_log" HARNESS_SELFTEST=1 \
      "$bash_bin" -c "source '$self_abs'; run_ensure" )
  local s11a_out; s11a_out="$(cat "$s11a_log" 2>/dev/null || true)"
  _ck_contains "S11a ENSURE_COCKPIT_DISABLE=1 no-ops" "$s11a_out" "disabled by operator"
  _ck_not_contains "S11a disabled run never resolves/invokes" "$s11a_out" "would invoke"
  local s11b_home="$tmp/s11b-home" s11b_log="$tmp/s11b.log"
  mkdir -p "$s11b_home/.claude/local"
  : > "$s11b_home/.claude/local/cockpit-disabled"
  ( cd "$s4_dir" && HOME="$s11b_home" ENSURE_COCKPIT_UNAME_OVERRIDE="MINGW64_NT" ENSURE_COCKPIT_LOG_PATH="$s11b_log" HARNESS_SELFTEST=1 \
      "$bash_bin" -c "source '$self_abs'; run_ensure" )
  local s11b_out; s11b_out="$(cat "$s11b_log" 2>/dev/null || true)"
  _ck_contains "S11b flag file ~/.claude/local/cockpit-disabled no-ops" "$s11b_out" "disabled by operator"

  # ========================================================================
  # DARWIN scenarios (macOS LaunchAgent path). D1-D3 run with
  # HARNESS_SELFTEST=0 + ENSURE_COCKPIT_LAUNCHCTL_OVERRIDE/NODE_OVERRIDE
  # pointing at harmless local stand-ins (mirrors S7's technique exactly):
  # this exercises the REAL install/idempotency/dispatch logic in
  # _ec_darwin_ensure without ever touching the operator's real
  # ~/Library/LaunchAgents or spawning a real launchctl/node.
  # ========================================================================

  # ---- D0: HARNESS_SELFTEST=1 stub — must record the intended install and
  # NEVER write a real file, even under a Darwin override, BEFORE any
  # mkdir/write/launchctl call (contract item 2). Belt-and-suspenders
  # (caught empirically while mutation-testing this exact scenario: a
  # broken stub-ordering with NO overrides at all resolves the REAL
  # default label/launchctl/node and bootstraps a REAL LaunchAgent —
  # cleaned up by hand with `launchctl bootout`, see docs/decisions/065):
  # a distinct throwaway label + fake launchctl/node stand-ins, so even a
  # future regression of the stub-ordering can only touch sandboxed
  # fixtures, never the operator's real default label. ----
  local d0_log="$tmp/d0.log" d0_la="$tmp/d0-la" d0_state="$tmp/d0-state"
  local d0_launchctl; d0_launchctl="$(_fake_launchctl "$d0_state")"
  _require_fake_launchctl "$d0_launchctl"
  local d0_node="$tmp/d0-fake-node"; : > "$d0_node"; chmod +x "$d0_node"
  ( cd "$s4_dir" && NL_REPO_ROOT="$pin_root" ENSURE_COCKPIT_UNAME_OVERRIDE="Darwin" ENSURE_COCKPIT_LOG_PATH="$d0_log" HARNESS_SELFTEST=1 \
      ENSURE_COCKPIT_LAUNCHAGENTS_DIR="$d0_la" ENSURE_COCKPIT_PLIST_LABEL="test.d0.cockpit" \
      ENSURE_COCKPIT_LAUNCHCTL_OVERRIDE="$d0_launchctl" ENSURE_COCKPIT_NODE_OVERRIDE="$d0_node" \
      "$bash_bin" -c "source '$self_abs'; run_ensure" )
  local d0_out; d0_out="$(cat "$d0_log" 2>/dev/null || true)"
  _ck_contains "D0 darwin self-test stub records the intended install" "$d0_out" "[darwin self-test stub] would install/refresh plist"
  _ck_not_contains "D0 darwin stub never claims a real write" "$d0_out" "plist written/refreshed"
  if [[ ! -e "$d0_la" ]]; then
    echo "PASS: D0 darwin stub never creates the LaunchAgents dir on disk"; pass=$((pass + 1))
  else
    echo "FAIL: D0 darwin stub unexpectedly created $d0_la" >&2; fail=$((fail + 1))
  fi

  # ---- D1: darwin-install — fresh fixture, fresh fake-launchctl state
  # (nothing loaded yet) -> plist written, bootstrap called exactly once. ----
  local d1_dir="$tmp/d1-repo" d1_log="$tmp/d1.log" d1_la="$tmp/d1-la" d1_state="$tmp/d1-state"
  _seed_main_repo "$d1_dir"
  local d1_launchctl; d1_launchctl="$(_fake_launchctl "$d1_state")"
  _require_fake_launchctl "$d1_launchctl"
  local d1_node="$tmp/d1-fake-node"; : > "$d1_node"; chmod +x "$d1_node"
  local d1_expected_root; d1_expected_root="$(cd "$d1_dir" && git rev-parse --show-toplevel)"
  local d1_port=$(( 18000 + ( $$ % 900 ) ))
  ( cd "$d1_dir" && NL_REPO_ROOT="$pin_root" ENSURE_COCKPIT_UNAME_OVERRIDE="Darwin" ENSURE_COCKPIT_LOG_PATH="$d1_log" HARNESS_SELFTEST=0 \
      ENSURE_COCKPIT_LAUNCHAGENTS_DIR="$d1_la" ENSURE_COCKPIT_PLIST_LABEL="test.d1.cockpit" \
      ENSURE_COCKPIT_LAUNCHCTL_OVERRIDE="$d1_launchctl" ENSURE_COCKPIT_NODE_OVERRIDE="$d1_node" \
      CTREE_PORT="$d1_port" \
      "$bash_bin" -c "source '$self_abs'; run_ensure" )
  local d1_out; d1_out="$(cat "$d1_log" 2>/dev/null || true)"
  local d1_plist="$d1_la/test.d1.cockpit.plist" d1_plist_content=""
  if [[ -f "$d1_plist" ]]; then
    echo "PASS: D1 darwin-install writes the plist file"; pass=$((pass + 1))
    d1_plist_content="$(cat "$d1_plist" 2>/dev/null)"
  else
    echo "FAIL: D1 darwin-install plist missing at $d1_plist" >&2; fail=$((fail + 1))
  fi
  _ck_contains "D1 plist names the resolved node override" "$d1_plist_content" "$d1_node"
  _ck_contains "D1 plist names the resolved server.js under the checkout" "$d1_plist_content" "$d1_expected_root/neural-lace/workstreams-ui/server/server.js"
  _ck_contains "D1 plist carries RunAtLoad" "$d1_plist_content" "<key>RunAtLoad</key>"
  _ck_contains "D1 plist KeepAlive uses the SuccessfulExit dict form, not bare true" "$d1_plist_content" "<key>SuccessfulExit</key>"
  local d1_boot_count; d1_boot_count="$(_count_lines_if_exists "$d1_state/bootstrap.log")"
  _ck_eq "D1 darwin-install calls launchctl bootstrap exactly once" "$d1_boot_count" "1"
  _ck_contains "D1 logs the plist write" "$d1_out" "plist written/refreshed"
  _ck_contains "D1 logs the bootstrap success" "$d1_out" "launchctl bootstrap succeeded"

  # ---- D2: darwin-idempotent-second-run — SAME fixture/state/label/port,
  # run AGAIN without resetting the fake-launchctl "loaded" state -> the
  # plist is unchanged (need_write=0) and print reports already-loaded, so
  # bootstrap must NOT be called a second time (still 1 total). ----
  local d2_log="$tmp/d2.log"
  ( cd "$d1_dir" && NL_REPO_ROOT="$pin_root" ENSURE_COCKPIT_UNAME_OVERRIDE="Darwin" ENSURE_COCKPIT_LOG_PATH="$d2_log" HARNESS_SELFTEST=0 \
      ENSURE_COCKPIT_LAUNCHAGENTS_DIR="$d1_la" ENSURE_COCKPIT_PLIST_LABEL="test.d1.cockpit" \
      ENSURE_COCKPIT_LAUNCHCTL_OVERRIDE="$d1_launchctl" ENSURE_COCKPIT_NODE_OVERRIDE="$d1_node" \
      CTREE_PORT="$d1_port" \
      "$bash_bin" -c "source '$self_abs'; run_ensure" )
  local d2_out; d2_out="$(cat "$d2_log" 2>/dev/null || true)"
  local d2_boot_count; d2_boot_count="$(_count_lines_if_exists "$d1_state/bootstrap.log")"
  _ck_eq "D2 darwin-idempotent-second-run does NOT call bootstrap again (still 1 total)" "$d2_boot_count" "1"
  _ck_contains "D2 logs already-bootstrapped no-op" "$d2_out" "already bootstrapped — no-op"
  _ck_not_contains "D2 second run never rewrites an unchanged plist" "$d2_out" "plist written/refreshed"

  # ---- D3: darwin-already-running-no-op — plist ALREADY on disk with
  # matching content, fake-launchctl ALREADY reports loaded, AND a REAL
  # listener is bound on the test port (simulating the server already up
  # from a prior login/reboot) -> bootstrap is never called AND the
  # liveness probe genuinely finds the port responding. ----
  local d3_dir="$tmp/d3-repo" d3_log="$tmp/d3.log" d3_la="$tmp/d3-la" d3_state="$tmp/d3-state"
  _seed_main_repo "$d3_dir"
  local d3_launchctl; d3_launchctl="$(_fake_launchctl "$d3_state")"
  _require_fake_launchctl "$d3_launchctl"
  local d3_node="$tmp/d3-fake-node"; : > "$d3_node"; chmod +x "$d3_node"
  local d3_expected_root; d3_expected_root="$(cd "$d3_dir" && git rev-parse --show-toplevel)"
  local d3_port=$(( 19000 + ( $$ % 900 ) ))
  mkdir -p "$d3_la"
  local d3_desired
  d3_desired="$(_ec_darwin_plist_content "test.d3.cockpit" "$d3_node" "$d3_expected_root/neural-lace/workstreams-ui/server/server.js" "$d3_expected_root/neural-lace/workstreams-ui" "$d3_port" "$tmp/workstreams-cockpit.stdout.log" "$tmp/workstreams-cockpit.stderr.log")"
  printf '%s\n' "$d3_desired" > "$d3_la/test.d3.cockpit.plist"
  : > "$d3_state/loaded"
  local d3_nc_started=0
  if command -v nc >/dev/null 2>&1; then
    ( nc -l "$d3_port" >/dev/null 2>&1 & echo $! > "$tmp/d3-nc.pid" )
    sleep 0.3
    d3_nc_started=1
  fi
  ( cd "$d3_dir" && NL_REPO_ROOT="$pin_root" ENSURE_COCKPIT_UNAME_OVERRIDE="Darwin" ENSURE_COCKPIT_LOG_PATH="$d3_log" HARNESS_SELFTEST=0 \
      ENSURE_COCKPIT_LAUNCHAGENTS_DIR="$d3_la" ENSURE_COCKPIT_PLIST_LABEL="test.d3.cockpit" \
      ENSURE_COCKPIT_LAUNCHCTL_OVERRIDE="$d3_launchctl" ENSURE_COCKPIT_NODE_OVERRIDE="$d3_node" \
      CTREE_PORT="$d3_port" \
      "$bash_bin" -c "source '$self_abs'; run_ensure" )
  local d3_out; d3_out="$(cat "$d3_log" 2>/dev/null || true)"
  if [[ -f "$tmp/d3-nc.pid" ]]; then kill "$(cat "$tmp/d3-nc.pid" 2>/dev/null)" 2>/dev/null || true; fi
  local d3_boot_count; d3_boot_count="$(_count_lines_if_exists "$d3_state/bootstrap.log")"
  _ck_eq "D3 already-running: bootstrap never called (0 total)" "$d3_boot_count" "0"
  _ck_contains "D3 already-running: logs no-op" "$d3_out" "already bootstrapped — no-op"
  if [[ "$d3_nc_started" -eq 1 ]]; then
    _ck_contains "D3 already-running: liveness probe finds it responding" "$d3_out" "cockpit responding on 127.0.0.1:$d3_port"
  else
    echo "  ok   D3 liveness probe: SKIP (nc unavailable in this test env)"
  fi

  # ---- D4: darwin missing-node tolerate-absent (parity with S5). ----
  local d4_dir="$tmp/d4-repo" d4_log="$tmp/d4.log" d4_la="$tmp/d4-la"
  _seed_main_repo "$d4_dir"
  ( cd "$d4_dir" && NL_REPO_ROOT="$pin_root" ENSURE_COCKPIT_UNAME_OVERRIDE="Darwin" ENSURE_COCKPIT_LOG_PATH="$d4_log" HARNESS_SELFTEST=0 \
      ENSURE_COCKPIT_LAUNCHAGENTS_DIR="$d4_la" ENSURE_COCKPIT_FORCE_NO_NODE=1 \
      "$bash_bin" -c "source '$self_abs'; run_ensure" )
  local d4_out; d4_out="$(cat "$d4_log" 2>/dev/null || true)"
  _ck_contains "D4 darwin missing node tolerates absent" "$d4_out" "node not found on PATH"
  if [[ ! -e "$d4_la" ]] || [[ -z "$(ls -A "$d4_la" 2>/dev/null)" ]]; then
    echo "PASS: D4 must not write a plist when node is unresolvable"; pass=$((pass + 1))
  else
    echo "FAIL: D4 unexpectedly wrote into $d4_la with node unresolvable" >&2; fail=$((fail + 1))
  fi

  # ---- D5: windows-path-unchanged / branch-isolation regression. A Windows
  # override must still take the EXACT Windows stub path (S4's assertion,
  # replayed here against the post-Darwin-branch code), and must NEVER log
  # a "[darwin" line; a Darwin override must take the Darwin stub path and
  # must NEVER log the Windows "would invoke (not spawned)" phrase. A
  # plausible authoring slip (swapping which _ec_is_* check gates which
  # branch) would cross-contaminate one of these two directions. ----
  # ENSURE_COCKPIT_PS_OVERRIDE keeps this deterministic regardless of
  # whether real powershell happens to be on THIS machine's PATH (it is
  # not, on a stock Mac) — without it this assertion would spuriously fail
  # with "powershell.exe not found" before ever reaching the stub check,
  # which is a fixture gap in the test, not a Windows-path regression.
  local d5w_log="$tmp/d5w.log" d5w_fakeps="$tmp/d5w-fake-ps"
  : > "$d5w_fakeps"; chmod +x "$d5w_fakeps"
  ( cd "$s4_dir" && NL_REPO_ROOT="$pin_root" ENSURE_COCKPIT_UNAME_OVERRIDE="MINGW64_NT" ENSURE_COCKPIT_LOG_PATH="$d5w_log" HARNESS_SELFTEST=1 \
      ENSURE_COCKPIT_PS_OVERRIDE="$d5w_fakeps" "$bash_bin" -c "source '$self_abs'; run_ensure" )
  local d5w_out; d5w_out="$(cat "$d5w_log" 2>/dev/null || true)"
  _ck_contains "D5 Windows override still takes the Windows stub path (unchanged)" "$d5w_out" "would invoke (not spawned)"
  _ck_not_contains "D5 Windows override never enters the Darwin branch" "$d5w_out" "[darwin"

  local d5d_log="$tmp/d5d.log"
  ( cd "$s4_dir" && NL_REPO_ROOT="$pin_root" ENSURE_COCKPIT_UNAME_OVERRIDE="Darwin" ENSURE_COCKPIT_LOG_PATH="$d5d_log" HARNESS_SELFTEST=1 \
      ENSURE_COCKPIT_LAUNCHAGENTS_DIR="$tmp/d5d-la" "$bash_bin" -c "source '$self_abs'; run_ensure" )
  local d5d_out; d5d_out="$(cat "$d5d_log" 2>/dev/null || true)"
  _ck_contains "D5 Darwin override takes the Darwin stub path" "$d5d_out" "[darwin self-test stub]"
  _ck_not_contains "D5 Darwin override never takes the Windows dispatch path" "$d5d_out" "would invoke (not spawned)"

  rm -rf "$tmp" 2>/dev/null || true
  echo ""
  echo "self-test summary: $pass passed, $fail failed"
  if [[ "$fail" -eq 0 ]]; then
    echo "self-test: OK $pass/$pass"
    return 0
  else
    echo "self-test: FAIL"
    return 1
  fi
}

# ============================================================
# Entry point — guarded so `source`-ing this file (self-test harness) never
# falls through to a real invocation. Mirrors the nl-paths.sh /
# session-start-digest.sh source-guard convention.
# ============================================================
if [[ "${BASH_SOURCE[0]:-$0}" == "${0}" ]]; then
  case "${1:-}" in
    --self-test)
      run_self_test
      exit $?
      ;;
    *)
      run_ensure
      # Sandbox hygiene (review fix 2026-07-09): under HARNESS_SELFTEST
      # with no explicit log path, _ec_log_path used a throwaway per-PID
      # dir (it exists only so digest self-tests never touch the real
      # log); remove our own before exiting so repeated digest self-test
      # runs don't accumulate one dir per child PID.
      if [[ "${HARNESS_SELFTEST:-0}" == "1" && -z "${ENSURE_COCKPIT_LOG_PATH:-}" ]]; then
        rm -rf "${TMPDIR:-/tmp}/ensure-cockpit-selftest/${$}" 2>/dev/null || true
      fi
      exit 0
      ;;
  esac
fi
