#!/usr/bin/env bash
# install-maintenance-task-darwin.sh — launchd adapter for nl-maintenance.sh
# (harness-execution-redesign-2026-08, Task 3 / Stage 1, R3.2: darwin
# support is the portability REQUIREMENT of Stage 1 itself, not a later
# stage). Follows ensure-cockpit.sh's darwin LaunchAgent pattern exactly
# (docs/decisions/065-macos-cockpit-launchagent.md is the precedent this
# mirrors): a `launchd` LaunchAgent (~/Library/LaunchAgents/*.plist,
# RunAtLoad + StartInterval), idempotent write (only touches disk when the
# plist content actually differs), single-instance (bootstrap only when
# NOT already loaded, checked via `launchctl print`, never trusted-and-
# skipped), tolerate-absent everywhere (missing node/bash/launchctl/script
# -> log + return 0, never errors, never blocks).
#
# WHAT IT REGISTERS: exactly ONE recurring launchd job,
# `local.neurallace.nl-maintenance-watchdog`, running
# `nl-maintenance.sh --watchdog` on StartInterval (default 300s) — the
# SAME "one remaining recurring OS task" contract install-maintenance-
# task.ps1 gives Windows (R3.2: identical mechanism, platform-appropriate
# scheduler). `--watchdog` relaunches the `--daemon` loop (which hosts the
# six maintenance mechanisms as completion-anchored internal jobs) only
# when its heartbeat looks stale.
#
# CONTRACT (mirrors ensure-cockpit.sh's darwin contract, all mandatory):
#   1. HARNESS_SELFTEST=1 — never actually writes a real plist / calls real
#      launchctl. Records the invocation/install that WOULD happen and
#      returns 0 BEFORE any side effect.
#   2. Idempotent + single-instance: plist rewritten only on content
#      change; bootstrap only when not already loaded; a content change
#      while loaded does one bootout then bootstrap, never an additive
#      second load.
#   3. Tolerate-absent: missing bash/launchctl/nl-maintenance.sh -> log and
#      return 0, never errors.
#   4. Operator kill-switch: MAINT_TASK_DISABLE=1 (env) or the flag file
#      ~/.claude/local/nl-maintenance-disabled (durable) -> logged no-op.
#   5. -Uninstall / --uninstall: bootout + remove the plist.
#
# Darwin test-only overrides (same names/shape as ensure-cockpit.sh's,
# minus the ENSURE_ prefix -> MAINT_TASK_ prefix):
#   MAINT_TASK_UNAME_OVERRIDE, MAINT_TASK_LAUNCHAGENTS_DIR,
#   MAINT_TASK_PLIST_LABEL, MAINT_TASK_LAUNCHCTL_OVERRIDE,
#   MAINT_TASK_FORCE_NO_LAUNCHCTL, MAINT_TASK_BASH_OVERRIDE,
#   MAINT_TASK_FORCE_NO_BASH, MAINT_TASK_SCRIPT_OVERRIDE
#
# Self-test: --self-test (see run_self_test()). Runs on ANY platform
# (uname is overridable), so this darwin adapter's logic is proven from
# Windows CI too, same as ensure-cockpit.sh's own self-test does today.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
# shellcheck disable=SC1091
{ source "$SCRIPT_DIR/../hooks/lib/nl-paths.sh" 2>/dev/null; } || true
# shellcheck disable=SC1091
{ source "$SCRIPT_DIR/../hooks/lib/portable-timeout.sh" 2>/dev/null; } || true
if ! declare -F nl_run_bounded >/dev/null 2>&1; then
  nl_run_bounded() { local s="${1:-}"; shift 2>/dev/null || true; "$@"; }
fi

_mt_log_path() {
  if [[ -n "${MAINT_TASK_LOG_PATH:-}" ]]; then
    printf '%s' "$MAINT_TASK_LOG_PATH"; return 0
  fi
  if [[ "${HARNESS_SELFTEST:-0}" == "1" ]]; then
    printf '%s/nl-maintenance-darwin-selftest/%s/install.log' "${TMPDIR:-/tmp}" "$$"; return 0
  fi
  printf '%s/.claude/logs/nl-maintenance-darwin.log' "${HOME:-$PWD}"
}

_mt_log() {
  local msg="$1" path; path="$(_mt_log_path)"
  mkdir -p "$(dirname "$path")" 2>/dev/null || true
  local ts; ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo unknown)"
  printf '[%s] %s\n' "$ts" "$msg" >> "$path" 2>/dev/null || true
}

_mt_is_disabled() {
  [[ "${MAINT_TASK_DISABLE:-0}" == "1" ]] && return 0
  [[ -n "${HOME:-}" && -f "${HOME}/.claude/local/nl-maintenance-disabled" ]] && return 0
  return 1
}

_mt_uname() {
  if [[ -n "${MAINT_TASK_UNAME_OVERRIDE:-}" ]]; then
    printf '%s' "$MAINT_TASK_UNAME_OVERRIDE"; return 0
  fi
  uname -s 2>/dev/null
}
_mt_is_darwin() { case "$(_mt_uname)" in Darwin) return 0 ;; *) return 1 ;; esac; }

_mt_resolve_bash() {
  if [[ "${MAINT_TASK_FORCE_NO_BASH:-0}" == "1" ]]; then return 1; fi
  if [[ -n "${MAINT_TASK_BASH_OVERRIDE:-}" ]]; then printf '%s' "$MAINT_TASK_BASH_OVERRIDE"; return 0; fi
  local found; found="$(command -v bash 2>/dev/null || true)"
  [[ -n "$found" ]] && { printf '%s' "$found"; return 0; }
  return 1
}

_mt_resolve_launchctl() {
  if [[ "${MAINT_TASK_FORCE_NO_LAUNCHCTL:-0}" == "1" ]]; then return 1; fi
  if [[ -n "${MAINT_TASK_LAUNCHCTL_OVERRIDE:-}" ]]; then printf '%s' "$MAINT_TASK_LAUNCHCTL_OVERRIDE"; return 0; fi
  local found; found="$(command -v launchctl 2>/dev/null || true)"
  [[ -n "$found" ]] && { printf '%s' "$found"; return 0; }
  return 1
}

_mt_launchagents_dir() {
  if [[ -n "${MAINT_TASK_LAUNCHAGENTS_DIR:-}" ]]; then printf '%s' "$MAINT_TASK_LAUNCHAGENTS_DIR"; return 0; fi
  printf '%s/Library/LaunchAgents' "${HOME:-$PWD}"
}
_mt_label() { printf '%s' "${MAINT_TASK_PLIST_LABEL:-local.neurallace.nl-maintenance-watchdog}"; }
_mt_plist_path() { printf '%s/%s.plist' "$(_mt_launchagents_dir)" "$(_mt_label)"; }

# _mt_resolve_script — the SAME machine-wide-first / worktree-normalized
# resolution ensure-cockpit.sh uses (contract item 3 there): nl_repo_root()
# then nl_main_checkout_root() from that root, falling back to the
# session-cwd derivation. Prints nl-maintenance.sh's absolute path, or
# empty.
_mt_resolve_script() {
  if [[ -n "${MAINT_TASK_SCRIPT_OVERRIDE:-}" ]]; then
    printf '%s' "$MAINT_TASK_SCRIPT_OVERRIDE"; return 0
  fi
  if ! declare -F nl_repo_root >/dev/null 2>&1; then
    printf ''; return 0
  fi
  local root norm cand
  root="$(nl_repo_root 2>/dev/null || true)"
  if [[ -n "$root" ]]; then
    norm="$(cd "$root" 2>/dev/null && nl_main_checkout_root 2>/dev/null || true)"
    [[ -n "$norm" ]] && root="$norm"
    cand="$root/adapters/claude-code/scripts/nl-maintenance.sh"
    [[ -f "$cand" ]] && { printf '%s' "$cand"; return 0; }
  fi
  local main_root
  main_root="$(nl_main_checkout_root 2>/dev/null || true)"
  if [[ -n "$main_root" ]]; then
    cand="$main_root/adapters/claude-code/scripts/nl-maintenance.sh"
    [[ -f "$cand" ]] && { printf '%s' "$cand"; return 0; }
  fi
  printf ''
}

_mt_plist_content() {
  local label="$1" bash_bin="$2" script="$3" workdir="$4" interval="$5" out_log="$6" err_log="$7"
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
		<string>${script}</string>
		<string>--watchdog</string>
	</array>
	<key>WorkingDirectory</key>
	<string>${workdir}</string>
	<key>StartInterval</key>
	<integer>${interval}</integer>
	<key>RunAtLoad</key>
	<true/>
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

# _mt_ensure — install/refresh the LaunchAgent idempotently. Every branch
# tolerate-absent returns 0; HARNESS_SELFTEST=1 is checked BEFORE any real
# side effect, mirroring ensure-cockpit.sh's contract exactly.
_mt_ensure() {
  local script; script="$(_mt_resolve_script)"
  if [[ -z "$script" ]]; then
    _mt_log "tolerate-absent: nl-maintenance.sh unresolved -- skipping LaunchAgent ensure"
    return 0
  fi
  local bash_bin
  if ! bash_bin="$(_mt_resolve_bash)"; then
    _mt_log "tolerate-absent: bash not found on PATH -- skipping LaunchAgent ensure"
    return 0
  fi
  local launchctl
  if ! launchctl="$(_mt_resolve_launchctl)"; then
    _mt_log "tolerate-absent: launchctl not found -- skipping LaunchAgent ensure"
    return 0
  fi

  local interval="${MAINT_TASK_WATCHDOG_INTERVAL_SECONDS:-300}"
  local workdir; workdir="$(dirname "$script")"
  local la_dir label plist_path log_dir out_log err_log
  la_dir="$(_mt_launchagents_dir)"
  label="$(_mt_label)"
  plist_path="$(_mt_plist_path)"
  log_dir="$(dirname "$(_mt_log_path)")"
  out_log="$log_dir/nl-maintenance-watchdog.stdout.log"
  err_log="$log_dir/nl-maintenance-watchdog.stderr.log"

  local desired
  desired="$(_mt_plist_content "$label" "$bash_bin" "$script" "$workdir" "$interval" "$out_log" "$err_log")"

  if [[ "${HARNESS_SELFTEST:-0}" == "1" ]]; then
    _mt_log "[self-test stub] would install/refresh plist at $plist_path (label=$label, bash=$bash_bin, script=$script, interval=${interval}s) and bootstrap via $launchctl -- never written/spawned"
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
      _mt_log "plist written/refreshed: $plist_path"
    else
      _mt_log "tolerate-absent: could not write plist at $plist_path -- skipping bootstrap"
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
      _mt_log "launchctl bootstrap succeeded for $label"
    else
      _mt_log "launchctl bootstrap returned non-zero for $label (may already be loaded, or no GUI launchd domain in this session)"
    fi
  else
    _mt_log "$label already bootstrapped -- no-op (idempotent)"
  fi
  return 0
}

_mt_uninstall() {
  local launchctl
  if ! launchctl="$(_mt_resolve_launchctl)"; then
    _mt_log "tolerate-absent: launchctl not found -- cannot uninstall"
    return 0
  fi
  local label plist_path uid domain_target
  label="$(_mt_label)"
  plist_path="$(_mt_plist_path)"
  uid="$(id -u 2>/dev/null || echo 0)"
  domain_target="gui/$uid/$label"

  if [[ "${HARNESS_SELFTEST:-0}" == "1" ]]; then
    _mt_log "[self-test stub] would bootout $domain_target and remove $plist_path -- never touched"
    return 0
  fi

  nl_run_bounded 10 "$launchctl" bootout "$domain_target" >/dev/null 2>&1 || true
  rm -f "$plist_path" 2>/dev/null || true
  _mt_log "uninstalled: bootout $domain_target, removed $plist_path"
  return 0
}

run_ensure() {
  if _mt_is_disabled; then
    _mt_log "no-op: disabled by operator (MAINT_TASK_DISABLE=1 or ~/.claude/local/nl-maintenance-disabled)"
    return 0
  fi
  if ! _mt_is_darwin; then
    _mt_log "no-op: OS '$(_mt_uname)' is not Darwin -- this adapter only runs on macOS (Windows uses install-maintenance-task.ps1)"
    return 0
  fi
  _mt_ensure
}

run_uninstall() {
  if ! _mt_is_darwin; then
    _mt_log "no-op: OS '$(_mt_uname)' is not Darwin"
    return 0
  fi
  _mt_uninstall
}

# ============================================================
# Self-test
# ============================================================
run_self_test() {
  local pass=0 fail=0 tmp
  tmp="$(mktemp -d 2>/dev/null || echo "/tmp/mt-darwin-st-$$")"
  mkdir -p "$tmp"
  export HARNESS_SELFTEST=1
  local self_abs bash_bin
  self_abs="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
  bash_bin="${BASH:-$(command -v bash)}"

  _ck() { if [[ "$1" == *"$2"* ]]; then echo "PASS: $3"; pass=$((pass+1)); else echo "FAIL: $3 (did not contain '$2'; got: $1)" >&2; fail=$((fail+1)); fi; }
  _ck_not() { if [[ "$1" != *"$2"* ]]; then echo "PASS: $3"; pass=$((pass+1)); else echo "FAIL: $3 (unexpectedly contained '$2')" >&2; fail=$((fail+1)); fi; }
  _ck_eq() { if [[ "$1" == "$2" ]]; then echo "PASS: $3"; pass=$((pass+1)); else echo "FAIL: $3 (got '$1' want '$2')" >&2; fail=$((fail+1)); fi; }

  _fake_launchctl() {
    local state_dir="$1"
    local script="$state_dir/fake-launchctl.sh"
    mkdir -p "$state_dir"
    cat > "$script" <<EOF
#!/usr/bin/env bash
state="$state_dir"
cmd="\$1"; shift || true
case "\$cmd" in
  print) [[ -f "\$state/loaded" ]] && exit 0 || exit 113 ;;
  bootstrap) echo "bootstrap \$*" >> "\$state/bootstrap.log"; : > "\$state/loaded"; exit 0 ;;
  bootout) echo "bootout \$*" >> "\$state/bootout.log"; rm -f "\$state/loaded"; exit 0 ;;
  *) exit 1 ;;
esac
EOF
    chmod +x "$script"
    printf '%s' "$script"
  }
  _require_fake_launchctl() {
    if [[ ! -x "$1" ]]; then
      echo "FATAL: fake launchctl missing/not executable -- aborting rather than risk a real launchctl call" >&2
      rm -rf "$tmp" 2>/dev/null || true
      exit 1
    fi
  }

  echo "Scenario 1: non-Darwin -> silent no-op, never resolves the script"
  local s1_log="$tmp/s1.log"
  MAINT_TASK_UNAME_OVERRIDE="Linux" MAINT_TASK_LOG_PATH="$s1_log" HARNESS_SELFTEST=1 \
    "$bash_bin" -c "source '$self_abs'; run_ensure"
  local s1_out; s1_out="$(cat "$s1_log" 2>/dev/null)"
  _ck "$s1_out" "not Darwin" "S1 non-Darwin no-ops"

  echo "Scenario 2: operator kill-switch (env) -> no-op even on Darwin"
  local s2_log="$tmp/s2.log"
  MAINT_TASK_UNAME_OVERRIDE="Darwin" MAINT_TASK_DISABLE=1 MAINT_TASK_LOG_PATH="$s2_log" HARNESS_SELFTEST=1 \
    "$bash_bin" -c "source '$self_abs'; run_ensure"
  _ck "$(cat "$s2_log" 2>/dev/null)" "disabled by operator" "S2 kill-switch honored"

  echo "Scenario 3: Darwin + script unresolved (no repo) -> tolerate-absent"
  local s3_log="$tmp/s3.log"
  MAINT_TASK_UNAME_OVERRIDE="Darwin" MAINT_TASK_LOG_PATH="$s3_log" MAINT_TASK_SCRIPT_OVERRIDE="" HARNESS_SELFTEST=1 \
    "$bash_bin" -c "source '$self_abs'; NL_REPO_ROOT='$tmp/no-such-repo' run_ensure"
  _ck "$(cat "$s3_log" 2>/dev/null)" "unresolved" "S3 missing script tolerates absent"

  echo "Scenario 4: Darwin + script present + HARNESS_SELFTEST=1 -> stub records shape, never writes a real plist"
  local s4_script="$tmp/fixture-nl-maintenance.sh" s4_dir="$tmp/s4-la" s4_log="$tmp/s4.log"
  printf '#!/usr/bin/env bash\n' > "$s4_script"
  local s4_lc; s4_lc="$(_fake_launchctl "$tmp/s4-lc")"; _require_fake_launchctl "$s4_lc"
  MAINT_TASK_UNAME_OVERRIDE="Darwin" MAINT_TASK_SCRIPT_OVERRIDE="$s4_script" \
    MAINT_TASK_LAUNCHAGENTS_DIR="$s4_dir" MAINT_TASK_LAUNCHCTL_OVERRIDE="$s4_lc" \
    MAINT_TASK_LOG_PATH="$s4_log" HARNESS_SELFTEST=1 \
    "$bash_bin" -c "source '$self_abs'; run_ensure"
  _ck "$(cat "$s4_log" 2>/dev/null)" "[self-test stub] would install/refresh plist" "S4 stub records the would-be install"
  if [[ ! -f "$s4_dir/local.neurallace.nl-maintenance-watchdog.plist" ]]; then
    echo "PASS: S4 stub never wrote a real plist"; pass=$((pass+1))
  else
    echo "FAIL: S4 stub should NOT have written a real plist" >&2; fail=$((fail+1))
  fi

  echo "Scenario 5: REAL (non-selftest) install -- plist written, bootstrap invoked via the fake launchctl (proves the real dispatch code path without a real launchd)"
  local s5_script="$tmp/fixture2-nl-maintenance.sh" s5_dir="$tmp/s5-la" s5_log="$tmp/s5.log" s5_lcstate="$tmp/s5-lc"
  printf '#!/usr/bin/env bash\n' > "$s5_script"
  local s5_lc; s5_lc="$(_fake_launchctl "$s5_lcstate")"; _require_fake_launchctl "$s5_lc"
  MAINT_TASK_UNAME_OVERRIDE="Darwin" MAINT_TASK_SCRIPT_OVERRIDE="$s5_script" \
    MAINT_TASK_LAUNCHAGENTS_DIR="$s5_dir" MAINT_TASK_LAUNCHCTL_OVERRIDE="$s5_lc" \
    MAINT_TASK_LOG_PATH="$s5_log" HARNESS_SELFTEST=0 \
    "$bash_bin" -c "source '$self_abs'; run_ensure"
  if [[ -f "$s5_dir/local.neurallace.nl-maintenance-watchdog.plist" ]]; then
    echo "PASS: S5 real install wrote the plist"; pass=$((pass+1))
  else
    echo "FAIL: S5 expected a real plist at $s5_dir/local.neurallace.nl-maintenance-watchdog.plist" >&2; fail=$((fail+1))
  fi
  _ck "$(cat "$s5_dir/local.neurallace.nl-maintenance-watchdog.plist" 2>/dev/null)" "--watchdog" "S5 plist's ProgramArguments include --watchdog"
  _ck "$(cat "$s5_lcstate/bootstrap.log" 2>/dev/null)" "bootstrap" "S5 fake launchctl bootstrap was actually invoked"

  echo "Scenario 6: idempotent re-install (same content, already loaded) -> no second bootstrap, no bootout"
  MAINT_TASK_UNAME_OVERRIDE="Darwin" MAINT_TASK_SCRIPT_OVERRIDE="$s5_script" \
    MAINT_TASK_LAUNCHAGENTS_DIR="$s5_dir" MAINT_TASK_LAUNCHCTL_OVERRIDE="$s5_lc" \
    MAINT_TASK_LOG_PATH="$s5_log" HARNESS_SELFTEST=0 \
    "$bash_bin" -c "source '$self_abs'; run_ensure"
  local s6_bootstrap_count; s6_bootstrap_count="$(grep -c '^bootstrap' "$s5_lcstate/bootstrap.log" 2>/dev/null || echo 0)"
  _ck_eq "$s6_bootstrap_count" "1" "S6 unchanged content + already-loaded -> still exactly ONE bootstrap total (idempotent, no re-bootstrap)"
  if [[ ! -f "$s5_lcstate/bootout.log" ]]; then
    echo "PASS: S6 no bootout fired on an unchanged, already-loaded install"; pass=$((pass+1))
  else
    echo "FAIL: S6 unexpected bootout on unchanged content" >&2; fail=$((fail+1))
  fi

  echo "Scenario 7: content change while loaded -> bootout then bootstrap fresh (not an additive second load)"
  MAINT_TASK_UNAME_OVERRIDE="Darwin" MAINT_TASK_SCRIPT_OVERRIDE="$s5_script" \
    MAINT_TASK_LAUNCHAGENTS_DIR="$s5_dir" MAINT_TASK_LAUNCHCTL_OVERRIDE="$s5_lc" \
    MAINT_TASK_LOG_PATH="$s5_log" MAINT_TASK_WATCHDOG_INTERVAL_SECONDS=600 HARNESS_SELFTEST=0 \
    "$bash_bin" -c "source '$self_abs'; run_ensure"
  _ck "$(cat "$s5_dir/local.neurallace.nl-maintenance-watchdog.plist" 2>/dev/null)" "<integer>600</integer>" "S7 plist content actually changed (new interval)"
  if [[ -f "$s5_lcstate/bootout.log" ]]; then
    echo "PASS: S7 content change triggered a bootout"; pass=$((pass+1))
  else
    echo "FAIL: S7 expected a bootout on content change" >&2; fail=$((fail+1))
  fi
  local s7_bootstrap_count; s7_bootstrap_count="$(grep -c '^bootstrap' "$s5_lcstate/bootstrap.log" 2>/dev/null || echo 0)"
  _ck_eq "$s7_bootstrap_count" "2" "S7 content change -> a SECOND bootstrap fired (total 2, not an additive third load)"

  echo "Scenario 8: missing launchctl -> tolerate-absent"
  local s8_log="$tmp/s8.log"
  MAINT_TASK_UNAME_OVERRIDE="Darwin" MAINT_TASK_SCRIPT_OVERRIDE="$s4_script" \
    MAINT_TASK_LOG_PATH="$s8_log" MAINT_TASK_FORCE_NO_LAUNCHCTL=1 HARNESS_SELFTEST=0 \
    "$bash_bin" -c "source '$self_abs'; run_ensure"
  _ck "$(cat "$s8_log" 2>/dev/null)" "launchctl not found" "S8 missing launchctl tolerates absent"

  echo "Scenario 9: --uninstall bootout + removes the plist"
  local s9_log="$tmp/s9.log"
  MAINT_TASK_UNAME_OVERRIDE="Darwin" MAINT_TASK_LAUNCHAGENTS_DIR="$s5_dir" \
    MAINT_TASK_LAUNCHCTL_OVERRIDE="$s5_lc" MAINT_TASK_LOG_PATH="$s9_log" HARNESS_SELFTEST=0 \
    "$bash_bin" -c "source '$self_abs'; run_uninstall"
  if [[ ! -f "$s5_dir/local.neurallace.nl-maintenance-watchdog.plist" ]]; then
    echo "PASS: S9 uninstall removed the plist"; pass=$((pass+1))
  else
    echo "FAIL: S9 plist should have been removed" >&2; fail=$((fail+1))
  fi

  echo "Scenario 10: exit code is always 0, across a no-op and a tolerate-absent branch"
  local s10a_rc s10b_rc
  MAINT_TASK_UNAME_OVERRIDE="Linux" MAINT_TASK_LOG_PATH="$tmp/s10a.log" HARNESS_SELFTEST=1 \
    "$bash_bin" "$self_abs" >/dev/null 2>&1
  s10a_rc=$?
  _ck_eq "$s10a_rc" "0" "S10a non-Darwin real entry point exits 0"
  MAINT_TASK_UNAME_OVERRIDE="Darwin" MAINT_TASK_SCRIPT_OVERRIDE="" MAINT_TASK_LOG_PATH="$tmp/s10b.log" HARNESS_SELFTEST=1 \
    "$bash_bin" -c "source '$self_abs'; NL_REPO_ROOT='$tmp/no-such-repo-2' run_ensure"
  s10b_rc=$?
  _ck_eq "$s10b_rc" "0" "S10b tolerate-absent branch exits 0"

  echo ""
  echo "self-test interpreter: ${BASH_VERSION:-unknown}"
  echo "self-test summary: ${pass} passed, ${fail} failed"
  rm -rf "$tmp" 2>/dev/null || true
  [[ "$fail" -eq 0 ]] && exit 0 || exit 1
}

# ============================================================
# Entry point
# ============================================================
if [[ "${BASH_SOURCE[0]:-$0}" == "${0}" ]]; then
  case "${1:-}" in
    --self-test) run_self_test ;;
    --uninstall) run_uninstall ;;
    *) run_ensure ;;
  esac
fi
