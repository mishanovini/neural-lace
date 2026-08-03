#!/usr/bin/env bash
# install-estate-janitor-task-darwin.sh — launchd adapter for the Accountable
# Estate janitor (docs/plans/accountable-estate-program-2026-07.md, T6
# prerequisite (c): "occupancy real on the collecting machine — needs a darwin
# janitor schedule; the installer is Windows-only today").
#
# ============================================================================
# UNVERIFIED ON DARWIN — READ THIS FIRST
# ============================================================================
# This file was WRITTEN AND SELF-TESTED ON WINDOWS. Its self-test drives every
# branch through a FAKE launchctl and an overridable uname, so the LOGIC is
# proven on any platform — but no line of it has ever run against a real
# macOS `launchctl`, a real `~/Library/LaunchAgents`, or a real launchd
# domain. Do not claim this schedules anything on the Mac mini until someone
# runs the verification block at the bottom of this header ON that machine
# and reports the output. The honest status is: reviewable, self-tested,
# UNVERIFIED-ON-DARWIN.
#
# ============================================================================
# WHY THIS EXISTS
# ============================================================================
# admission-lib.sh derives estate occupancy (`adm_live_sessions`) from the
# janitor's snapshot.json. If no janitor runs, the snapshot is absent or
# stale and occupancy reads -1 (unknown) forever — which admits everything.
# That is tolerable in T3's observe mode and NOT tolerable at T6, when
# admission starts enforcing: an enforcing governor with a dead occupancy
# input is a governor that cannot see load. The Windows machine has
# NL-EstateJanitor (install-estate-janitor-task.ps1); the darwin collector
# had no scheduler at all. This is that missing half.
#
# ============================================================================
# WHAT IT REGISTERS
# ============================================================================
# Exactly ONE launchd LaunchAgent, `local.neurallace.estate-janitor`, running
# a GENERATED WRAPPER SCRIPT on StartInterval (default 300s) — the same
# cadence and the same two-step tick the Windows task performs:
#
#     estate-janitor.sh run  &&  estate-brief.sh --write
#
# appending stdout+stderr to ~/.claude/state/estate/cron-YYYY-MM-DD.log.
# Running the brief writer in the SAME tick is deliberate (mirrors the
# Windows wrapper's own note): brief.txt is always a read of the snapshot
# this same tick just wrote, never a stale one.
#
# WHY A GENERATED WRAPPER AND NOT AN INLINE `bash -c "..."` IN THE PLIST:
# launchd's ProgramArguments runs ONE program, so chaining two scripts with
# a date-stamped log redirect would otherwise mean embedding a shell string
# inside XML — two nested quoting contexts over paths this repo KNOWS contain
# a space (the canonical checkout is `.../Pocket Technician/neural-lace`).
# That is precisely the untested-quoting class this task was told not to
# ship. Instead the installer writes a small wrapper script with every path
# shell-quoted by `_ej_shq` (single-quote wrapping with embedded-quote
# escaping), and the plist's ProgramArguments is the fixed 2-element array
# [bash, wrapper] with no shell metacharacters in it at all. This mirrors the
# Windows installer, which writes an `estate-janitor-tick.cmd` wrapper for
# the same reason. Self-test Scenarios 11 and 12 pin this against a path
# containing BOTH a space and a single quote.
#
# ============================================================================
# CONTRACT (mirrors install-maintenance-task-darwin.sh, the sibling adapter)
# ============================================================================
#   1. HARNESS_SELFTEST=1 — never writes a real plist / wrapper, never calls
#      a real launchctl. Records what WOULD happen, returns 0 BEFORE any side
#      effect.
#   2. Idempotent + single-instance: plist AND wrapper rewritten only on
#      content change; bootstrap only when not already loaded; a content
#      change while loaded does one bootout then one bootstrap, never an
#      additive second load.
#   3. Tolerate-absent: missing bash / launchctl / estate-janitor.sh /
#      estate-brief.sh -> log and return 0, never errors, never blocks.
#   4. Operator kill-switch: EJD_DISABLE=1 (env) or the durable flag file
#      ~/.claude/local/estate-janitor-disabled -> logged no-op.
#   5. --uninstall: bootout + remove the plist and the wrapper.
#
# Test-only overrides (same shape as the sibling adapter's MAINT_TASK_*):
#   EJD_UNAME_OVERRIDE, EJD_LAUNCHAGENTS_DIR, EJD_PLIST_LABEL,
#   EJD_LAUNCHCTL_OVERRIDE, EJD_FORCE_NO_LAUNCHCTL, EJD_BASH_OVERRIDE,
#   EJD_FORCE_NO_BASH, EJD_JANITOR_OVERRIDE, EJD_BRIEF_OVERRIDE,
#   EJD_WRAPPER_DIR, EJD_LOG_PATH, EJD_STATE_DIR, EJD_INTERVAL_SECONDS
#
# ============================================================================
# VERIFICATION ON THE REAL MAC (operator- or Mac-mini-run; NOT agent-run)
# ============================================================================
#   # 1. logic check, no side effects, safe anywhere:
#   bash adapters/claude-code/scripts/install-estate-janitor-task-darwin.sh --self-test
#
#   # 2. dry run on the Mac — prints the exact plist + wrapper, writes nothing:
#   HARNESS_SELFTEST=1 bash adapters/claude-code/scripts/install-estate-janitor-task-darwin.sh --print
#
#   # 3. real install on the Mac:
#   bash adapters/claude-code/scripts/install-estate-janitor-task-darwin.sh
#
#   # 4. confirm launchd actually took it:
#   launchctl print "gui/$(id -u)/local.neurallace.estate-janitor" | head -20
#
#   # 5. confirm the tick actually produces occupancy (the thing T6 needs).
#   #    Wait one interval, then:
#   ls -la ~/.claude/state/estate/snapshot.json
#   cat ~/.claude/state/estate/cron-$(date +%Y-%m-%d).log
#
#   # 6. the real acceptance for T6-(c) — occupancy must stop reading -1:
#   bash -c 'source adapters/claude-code/hooks/lib/admission-lib.sh; \
#            echo "live_sessions=$(adm_live_sessions)"'
#   #    -1 means the snapshot is still absent/stale/unparseable -> (c) NOT met.
#   #    A non-negative integer means occupancy is real on that machine.
#
#   # uninstall:
#   bash adapters/claude-code/scripts/install-estate-janitor-task-darwin.sh --uninstall

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
# shellcheck disable=SC1091
{ source "$SCRIPT_DIR/../hooks/lib/nl-paths.sh" 2>/dev/null; } || true
# shellcheck disable=SC1091
{ source "$SCRIPT_DIR/../hooks/lib/portable-timeout.sh" 2>/dev/null; } || true
if ! declare -F nl_run_bounded >/dev/null 2>&1; then
  nl_run_bounded() { local s="${1:-}"; shift 2>/dev/null || true; "$@"; }
fi

# ---------------------------------------------------------------------------
# logging
# ---------------------------------------------------------------------------
_ej_log_path() {
  if [[ -n "${EJD_LOG_PATH:-}" ]]; then printf '%s' "$EJD_LOG_PATH"; return 0; fi
  if [[ "${HARNESS_SELFTEST:-0}" == "1" ]]; then
    printf '%s/estate-janitor-darwin-selftest/%s/install.log' "${TMPDIR:-/tmp}" "$$"; return 0
  fi
  printf '%s/.claude/logs/estate-janitor-darwin.log' "${HOME:-$PWD}"
}

_ej_log() {
  local msg="$1" path; path="$(_ej_log_path)"
  mkdir -p "$(dirname "$path")" 2>/dev/null || true
  local ts; ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo unknown)"
  printf '[%s] %s\n' "$ts" "$msg" >> "$path" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# quoting helpers — the load-bearing correctness surface of this file
# ---------------------------------------------------------------------------
# _ej_shq — POSIX single-quote shell quoting. Wraps in '...' and turns each
# embedded single quote into '\'' . Safe for ANY byte sequence including
# spaces, quotes, $, backticks, newlines. Every path interpolated into the
# generated wrapper goes through this.
_ej_shq() {
  local s="$1"
  printf "'%s'" "${s//\'/\'\\\'\'}"
}

# _ej_xmlq — XML text escaping for plist string values. & must be first.
_ej_xmlq() {
  local s="$1"
  s="${s//&/&amp;}"
  s="${s//</&lt;}"
  s="${s//>/&gt;}"
  s="${s//\"/&quot;}"
  printf '%s' "$s"
}

# ---------------------------------------------------------------------------
# environment probes
# ---------------------------------------------------------------------------
_ej_is_disabled() {
  [[ "${EJD_DISABLE:-0}" == "1" ]] && return 0
  [[ -n "${HOME:-}" && -f "${HOME}/.claude/local/estate-janitor-disabled" ]] && return 0
  return 1
}

_ej_uname() {
  if [[ -n "${EJD_UNAME_OVERRIDE:-}" ]]; then printf '%s' "$EJD_UNAME_OVERRIDE"; return 0; fi
  uname -s 2>/dev/null
}
_ej_is_darwin() { case "$(_ej_uname)" in Darwin) return 0 ;; *) return 1 ;; esac; }

_ej_resolve_bash() {
  if [[ "${EJD_FORCE_NO_BASH:-0}" == "1" ]]; then return 1; fi
  if [[ -n "${EJD_BASH_OVERRIDE:-}" ]]; then printf '%s' "$EJD_BASH_OVERRIDE"; return 0; fi
  local found; found="$(command -v bash 2>/dev/null || true)"
  [[ -n "$found" ]] && { printf '%s' "$found"; return 0; }
  return 1
}

_ej_resolve_launchctl() {
  if [[ "${EJD_FORCE_NO_LAUNCHCTL:-0}" == "1" ]]; then return 1; fi
  if [[ -n "${EJD_LAUNCHCTL_OVERRIDE:-}" ]]; then printf '%s' "$EJD_LAUNCHCTL_OVERRIDE"; return 0; fi
  local found; found="$(command -v launchctl 2>/dev/null || true)"
  [[ -n "$found" ]] && { printf '%s' "$found"; return 0; }
  return 1
}

_ej_launchagents_dir() {
  if [[ -n "${EJD_LAUNCHAGENTS_DIR:-}" ]]; then printf '%s' "$EJD_LAUNCHAGENTS_DIR"; return 0; fi
  printf '%s/Library/LaunchAgents' "${HOME:-$PWD}"
}
_ej_label() { printf '%s' "${EJD_PLIST_LABEL:-local.neurallace.estate-janitor}"; }
_ej_plist_path() { printf '%s/%s.plist' "$(_ej_launchagents_dir)" "$(_ej_label)"; }

# Wrapper lives in machine STATE, never ~/.claude/scripts — install.sh
# re-syncs that tree and would wipe it (same rationale as the Windows
# installer's task-wrappers dir).
_ej_wrapper_dir() {
  if [[ -n "${EJD_WRAPPER_DIR:-}" ]]; then printf '%s' "$EJD_WRAPPER_DIR"; return 0; fi
  printf '%s/.claude/state/task-wrappers' "${HOME:-$PWD}"
}
_ej_wrapper_path() { printf '%s/estate-janitor-tick.sh' "$(_ej_wrapper_dir)"; }

_ej_state_dir() {
  if [[ -n "${EJD_STATE_DIR:-}" ]]; then printf '%s' "$EJD_STATE_DIR"; return 0; fi
  printf '%s/.claude/state/estate' "${HOME:-$PWD}"
}

# _ej_resolve_script <basename> <override-var-value> — live mirror first,
# then the repo checkout (same precedence as the Windows installer: a live
# ~/.claude/scripts copy wins, repo is the fallback).
_ej_resolve_script() {
  local base="$1" override="${2:-}"
  if [[ -n "$override" ]]; then printf '%s' "$override"; return 0; fi
  local live="${HOME:-$PWD}/.claude/scripts/$base"
  [[ -f "$live" ]] && { printf '%s' "$live"; return 0; }
  local cand=""
  if declare -F nl_repo_root >/dev/null 2>&1; then
    local root norm
    root="$(nl_repo_root 2>/dev/null || true)"
    if [[ -n "$root" ]]; then
      norm="$(cd "$root" 2>/dev/null && nl_main_checkout_root 2>/dev/null || true)"
      [[ -n "$norm" ]] && root="$norm"
      cand="$root/adapters/claude-code/scripts/$base"
      [[ -f "$cand" ]] && { printf '%s' "$cand"; return 0; }
    fi
  fi
  # last resort: this script's own sibling
  cand="$SCRIPT_DIR/$base"
  [[ -f "$cand" ]] && { printf '%s' "$cand"; return 0; }
  printf ''
}

# ---------------------------------------------------------------------------
# generated artifacts
# ---------------------------------------------------------------------------
# _ej_wrapper_content — every interpolated path is _ej_shq-quoted, so the
# generated script is correct for paths containing spaces, quotes, $, etc.
_ej_wrapper_content() {
  local bash_bin="$1" janitor="$2" brief="$3" state_dir="$4"
  local q_janitor q_brief q_state
  q_janitor="$(_ej_shq "$janitor")"
  q_brief="$(_ej_shq "$brief")"
  q_state="$(_ej_shq "$state_dir")"
  cat <<WRAPPER
#!/usr/bin/env bash
# GENERATED by install-estate-janitor-task-darwin.sh — do not hand-edit.
# Re-running that installer rewrites this file.
#
# One estate-janitor tick: snapshot then brief, both appended to a
# date-stamped log. Mirrors the Windows estate-janitor-tick.cmd wrapper.
set -u
state_dir=${q_state}
mkdir -p "\$state_dir" 2>/dev/null || true
log="\$state_dir/cron-\$(date +%Y-%m-%d).log"
{
  ${bash_bin} ${q_janitor} run && ${bash_bin} ${q_brief} --write
} >> "\$log" 2>&1
exit 0
WRAPPER
}

_ej_plist_content() {
  local label="$1" bash_bin="$2" wrapper="$3" workdir="$4" interval="$5" out_log="$6" err_log="$7"
  cat <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>$(_ej_xmlq "$label")</string>
	<key>ProgramArguments</key>
	<array>
		<string>$(_ej_xmlq "$bash_bin")</string>
		<string>$(_ej_xmlq "$wrapper")</string>
	</array>
	<key>WorkingDirectory</key>
	<string>$(_ej_xmlq "$workdir")</string>
	<key>StartInterval</key>
	<integer>${interval}</integer>
	<key>RunAtLoad</key>
	<true/>
	<key>StandardOutPath</key>
	<string>$(_ej_xmlq "$out_log")</string>
	<key>StandardErrorPath</key>
	<string>$(_ej_xmlq "$err_log")</string>
	<key>ProcessType</key>
	<string>Background</string>
</dict>
</plist>
PLIST
}

# _ej_write_if_changed <path> <content> <mode> -> echoes "changed"|"same"|""
_ej_write_if_changed() {
  local path="$1" content="$2" mode="${3:-0644}"
  if [[ -f "$path" ]]; then
    local existing; existing="$(cat "$path" 2>/dev/null || true)"
    if [[ "$existing" == "$content" ]]; then printf 'same'; return 0; fi
  fi
  local tmp="${path}.tmp.$$"
  if printf '%s\n' "$content" > "$tmp" 2>/dev/null && mv -f "$tmp" "$path" 2>/dev/null; then
    chmod "$mode" "$path" 2>/dev/null || true
    printf 'changed'; return 0
  fi
  rm -f "$tmp" 2>/dev/null || true
  printf ''
  return 0
}

# ---------------------------------------------------------------------------
# resolve everything once; used by both --print and the real ensure
# ---------------------------------------------------------------------------
# Sets: EJ_R_BASH EJ_R_JANITOR EJ_R_BRIEF EJ_R_WRAPPER EJ_R_PLIST EJ_R_LABEL
#       EJ_R_INTERVAL EJ_R_STATE EJ_R_OUTLOG EJ_R_ERRLOG EJ_R_WRAPPER_CONTENT
#       EJ_R_PLIST_CONTENT
# Returns 1 (with a logged tolerate-absent reason) if anything is missing.
_ej_resolve_all() {
  EJ_R_JANITOR="$(_ej_resolve_script estate-janitor.sh "${EJD_JANITOR_OVERRIDE:-}")"
  if [[ -z "$EJ_R_JANITOR" ]]; then
    _ej_log "tolerate-absent: estate-janitor.sh unresolved -- skipping LaunchAgent ensure"
    return 1
  fi
  EJ_R_BRIEF="$(_ej_resolve_script estate-brief.sh "${EJD_BRIEF_OVERRIDE:-}")"
  if [[ -z "$EJ_R_BRIEF" ]]; then
    _ej_log "tolerate-absent: estate-brief.sh unresolved -- skipping LaunchAgent ensure"
    return 1
  fi
  if ! EJ_R_BASH="$(_ej_resolve_bash)"; then
    _ej_log "tolerate-absent: bash not found on PATH -- skipping LaunchAgent ensure"
    return 1
  fi
  EJ_R_INTERVAL="${EJD_INTERVAL_SECONDS:-300}"
  if [[ ! "$EJ_R_INTERVAL" =~ ^[0-9]+$ || "$EJ_R_INTERVAL" -le 0 ]]; then
    _ej_log "invalid EJD_INTERVAL_SECONDS='$EJ_R_INTERVAL' -- falling back to 300"
    EJ_R_INTERVAL=300
  fi
  EJ_R_LABEL="$(_ej_label)"
  EJ_R_PLIST="$(_ej_plist_path)"
  EJ_R_WRAPPER="$(_ej_wrapper_path)"
  EJ_R_STATE="$(_ej_state_dir)"
  local log_dir; log_dir="$(dirname "$(_ej_log_path)")"
  EJ_R_OUTLOG="$log_dir/estate-janitor.stdout.log"
  EJ_R_ERRLOG="$log_dir/estate-janitor.stderr.log"
  EJ_R_WRAPPER_CONTENT="$(_ej_wrapper_content "$EJ_R_BASH" "$EJ_R_JANITOR" "$EJ_R_BRIEF" "$EJ_R_STATE")"
  EJ_R_PLIST_CONTENT="$(_ej_plist_content "$EJ_R_LABEL" "$EJ_R_BASH" "$EJ_R_WRAPPER" \
    "$(dirname "$EJ_R_JANITOR")" "$EJ_R_INTERVAL" "$EJ_R_OUTLOG" "$EJ_R_ERRLOG")"
  return 0
}

_ej_ensure() {
  _ej_resolve_all || return 0
  local launchctl
  if ! launchctl="$(_ej_resolve_launchctl)"; then
    _ej_log "tolerate-absent: launchctl not found -- skipping LaunchAgent ensure"
    return 0
  fi

  if [[ "${HARNESS_SELFTEST:-0}" == "1" ]]; then
    _ej_log "[self-test stub] would write wrapper at $EJ_R_WRAPPER and plist at $EJ_R_PLIST (label=$EJ_R_LABEL, bash=$EJ_R_BASH, janitor=$EJ_R_JANITOR, brief=$EJ_R_BRIEF, interval=${EJ_R_INTERVAL}s) and bootstrap via $launchctl -- never written/spawned"
    return 0
  fi

  mkdir -p "$(_ej_launchagents_dir)" 2>/dev/null || true
  mkdir -p "$(_ej_wrapper_dir)" 2>/dev/null || true

  local w_res p_res
  w_res="$(_ej_write_if_changed "$EJ_R_WRAPPER" "$EJ_R_WRAPPER_CONTENT" 0755)"
  if [[ -z "$w_res" ]]; then
    _ej_log "tolerate-absent: could not write wrapper at $EJ_R_WRAPPER -- skipping bootstrap"
    return 0
  fi
  p_res="$(_ej_write_if_changed "$EJ_R_PLIST" "$EJ_R_PLIST_CONTENT" 0644)"
  if [[ -z "$p_res" ]]; then
    _ej_log "tolerate-absent: could not write plist at $EJ_R_PLIST -- skipping bootstrap"
    return 0
  fi
  [[ "$w_res" == "changed" ]] && _ej_log "wrapper written/refreshed: $EJ_R_WRAPPER"
  [[ "$p_res" == "changed" ]] && _ej_log "plist written/refreshed: $EJ_R_PLIST"

  local need_reload=0
  [[ "$w_res" == "changed" || "$p_res" == "changed" ]] && need_reload=1

  local uid domain_target was_loaded
  uid="$(id -u 2>/dev/null || echo 0)"
  domain_target="gui/$uid/$EJ_R_LABEL"
  was_loaded=1
  if nl_run_bounded 10 "$launchctl" print "$domain_target" >/dev/null 2>&1; then
    was_loaded=0
  fi

  if [[ "$need_reload" -eq 1 && "$was_loaded" -eq 0 ]]; then
    nl_run_bounded 10 "$launchctl" bootout "$domain_target" >/dev/null 2>&1 || true
    was_loaded=1
  fi

  if [[ "$was_loaded" -eq 1 ]]; then
    if nl_run_bounded 10 "$launchctl" bootstrap "gui/$uid" "$EJ_R_PLIST" >/dev/null 2>&1; then
      _ej_log "launchctl bootstrap succeeded for $EJ_R_LABEL"
    else
      _ej_log "launchctl bootstrap returned non-zero for $EJ_R_LABEL (may already be loaded, or no GUI launchd domain in this session)"
    fi
  else
    _ej_log "$EJ_R_LABEL already bootstrapped -- no-op (idempotent)"
  fi
  return 0
}

_ej_uninstall() {
  local launchctl
  if ! launchctl="$(_ej_resolve_launchctl)"; then
    _ej_log "tolerate-absent: launchctl not found -- cannot uninstall"
    return 0
  fi
  local label plist_path wrapper uid domain_target
  label="$(_ej_label)"; plist_path="$(_ej_plist_path)"; wrapper="$(_ej_wrapper_path)"
  uid="$(id -u 2>/dev/null || echo 0)"
  domain_target="gui/$uid/$label"

  if [[ "${HARNESS_SELFTEST:-0}" == "1" ]]; then
    _ej_log "[self-test stub] would bootout $domain_target and remove $plist_path + $wrapper -- never touched"
    return 0
  fi
  nl_run_bounded 10 "$launchctl" bootout "$domain_target" >/dev/null 2>&1 || true
  rm -f "$plist_path" 2>/dev/null || true
  rm -f "$wrapper" 2>/dev/null || true
  _ej_log "uninstalled: bootout $domain_target, removed $plist_path and $wrapper"
  return 0
}

# --print — dump the exact artifacts without writing anything. The review
# surface for a machine that cannot run launchd.
_ej_print() {
  if ! _ej_resolve_all; then
    echo "(unresolved — see $(_ej_log_path))"
    return 0
  fi
  echo "=== plist: $EJ_R_PLIST ==="
  printf '%s\n' "$EJ_R_PLIST_CONTENT"
  echo
  echo "=== wrapper: $EJ_R_WRAPPER ==="
  printf '%s\n' "$EJ_R_WRAPPER_CONTENT"
  return 0
}

run_ensure() {
  if _ej_is_disabled; then
    _ej_log "no-op: disabled by operator (EJD_DISABLE=1 or ~/.claude/local/estate-janitor-disabled)"
    return 0
  fi
  if ! _ej_is_darwin; then
    _ej_log "no-op: OS '$(_ej_uname)' is not Darwin -- this adapter only runs on macOS (Windows uses install-estate-janitor-task.ps1)"
    return 0
  fi
  _ej_ensure
}

run_uninstall() {
  if ! _ej_is_darwin; then
    _ej_log "no-op: OS '$(_ej_uname)' is not Darwin"
    return 0
  fi
  _ej_uninstall
}

# ============================================================
# Self-test — runs on ANY platform (uname + launchctl are overridable)
# ============================================================
run_self_test() {
  local pass=0 fail=0 tmp
  tmp="$(mktemp -d 2>/dev/null || echo "/tmp/ejd-st-$$")"
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

  # shared fixtures
  local fx_janitor="$tmp/estate-janitor.sh" fx_brief="$tmp/estate-brief.sh"
  printf '#!/usr/bin/env bash\necho janitor-ran\n' > "$fx_janitor"; chmod +x "$fx_janitor"
  printf '#!/usr/bin/env bash\necho brief-ran\n' > "$fx_brief"; chmod +x "$fx_brief"

  echo "Scenario 1: non-Darwin -> silent no-op"
  local s1_log="$tmp/s1.log"
  EJD_UNAME_OVERRIDE="Linux" EJD_LOG_PATH="$s1_log" HARNESS_SELFTEST=1 \
    "$bash_bin" -c "source '$self_abs'; run_ensure"
  _ck "$(cat "$s1_log" 2>/dev/null)" "not Darwin" "S1 non-Darwin no-ops"

  echo "Scenario 2: operator kill-switch (env) -> no-op even on Darwin"
  local s2_log="$tmp/s2.log"
  EJD_UNAME_OVERRIDE="Darwin" EJD_DISABLE=1 EJD_LOG_PATH="$s2_log" HARNESS_SELFTEST=1 \
    "$bash_bin" -c "source '$self_abs'; run_ensure"
  _ck "$(cat "$s2_log" 2>/dev/null)" "disabled by operator" "S2 kill-switch honored"

  echo "Scenario 3: Darwin + janitor unresolved -> tolerate-absent"
  local s3_log="$tmp/s3.log"
  EJD_UNAME_OVERRIDE="Darwin" EJD_LOG_PATH="$s3_log" EJD_JANITOR_OVERRIDE="$tmp/nope.sh" \
    HOME="$tmp/nohome" HARNESS_SELFTEST=1 \
    "$bash_bin" -c "source '$self_abs'; EJD_JANITOR_OVERRIDE='' run_ensure"
  _ck "$(cat "$s3_log" 2>/dev/null)" "unresolved" "S3 missing janitor tolerates absent"

  echo "Scenario 4: Darwin + HARNESS_SELFTEST=1 -> stub records shape, writes NOTHING"
  local s4_la="$tmp/s4-la" s4_wr="$tmp/s4-wr" s4_log="$tmp/s4.log"
  local s4_lc; s4_lc="$(_fake_launchctl "$tmp/s4-lc")"; _require_fake_launchctl "$s4_lc"
  EJD_UNAME_OVERRIDE="Darwin" EJD_JANITOR_OVERRIDE="$fx_janitor" EJD_BRIEF_OVERRIDE="$fx_brief" \
    EJD_LAUNCHAGENTS_DIR="$s4_la" EJD_WRAPPER_DIR="$s4_wr" EJD_LAUNCHCTL_OVERRIDE="$s4_lc" \
    EJD_LOG_PATH="$s4_log" HARNESS_SELFTEST=1 \
    "$bash_bin" -c "source '$self_abs'; run_ensure"
  _ck "$(cat "$s4_log" 2>/dev/null)" "[self-test stub] would write wrapper" "S4 stub records the would-be install"
  if [[ ! -f "$s4_la/local.neurallace.estate-janitor.plist" && ! -f "$s4_wr/estate-janitor-tick.sh" ]]; then
    echo "PASS: S4 stub wrote neither plist nor wrapper"; pass=$((pass+1))
  else
    echo "FAIL: S4 stub should NOT have written anything" >&2; fail=$((fail+1))
  fi

  echo "Scenario 5: REAL install -> plist + wrapper written, bootstrap invoked"
  local s5_la="$tmp/s5-la" s5_wr="$tmp/s5-wr" s5_log="$tmp/s5.log" s5_lcstate="$tmp/s5-lc"
  local s5_lc; s5_lc="$(_fake_launchctl "$s5_lcstate")"; _require_fake_launchctl "$s5_lc"
  EJD_UNAME_OVERRIDE="Darwin" EJD_JANITOR_OVERRIDE="$fx_janitor" EJD_BRIEF_OVERRIDE="$fx_brief" \
    EJD_LAUNCHAGENTS_DIR="$s5_la" EJD_WRAPPER_DIR="$s5_wr" EJD_LAUNCHCTL_OVERRIDE="$s5_lc" \
    EJD_LOG_PATH="$s5_log" EJD_STATE_DIR="$tmp/s5-state" HARNESS_SELFTEST=0 \
    "$bash_bin" -c "source '$self_abs'; run_ensure"
  if [[ -f "$s5_la/local.neurallace.estate-janitor.plist" ]]; then
    echo "PASS: S5 real install wrote the plist"; pass=$((pass+1))
  else
    echo "FAIL: S5 expected a plist at $s5_la/local.neurallace.estate-janitor.plist" >&2; fail=$((fail+1))
  fi
  if [[ -x "$s5_wr/estate-janitor-tick.sh" ]]; then
    echo "PASS: S5 wrapper written AND executable"; pass=$((pass+1))
  else
    echo "FAIL: S5 wrapper missing or not executable" >&2; fail=$((fail+1))
  fi
  _ck "$(cat "$s5_lcstate/bootstrap.log" 2>/dev/null)" "bootstrap" "S5 fake launchctl bootstrap actually invoked"

  echo "Scenario 6: plist ProgramArguments is [bash, wrapper] — no shell string in the plist"
  local s6_plist; s6_plist="$(cat "$s5_la/local.neurallace.estate-janitor.plist" 2>/dev/null)"
  _ck "$s6_plist" "estate-janitor-tick.sh" "S6 plist points at the wrapper"
  _ck_not "$s6_plist" "&&" "S6 plist contains NO shell chaining operator (the quoting hazard this design avoids)"
  _ck_not "$s6_plist" "-c" "S6 plist ProgramArguments has no 'bash -c' shell string"
  _ck "$s6_plist" "<integer>300</integer>" "S6 default StartInterval is 300s (matches the Windows task cadence)"
  _ck "$s6_plist" "<key>RunAtLoad</key>" "S6 RunAtLoad set so occupancy appears without waiting a full interval"

  echo "Scenario 7: idempotent re-install -> exactly ONE bootstrap, no bootout"
  EJD_UNAME_OVERRIDE="Darwin" EJD_JANITOR_OVERRIDE="$fx_janitor" EJD_BRIEF_OVERRIDE="$fx_brief" \
    EJD_LAUNCHAGENTS_DIR="$s5_la" EJD_WRAPPER_DIR="$s5_wr" EJD_LAUNCHCTL_OVERRIDE="$s5_lc" \
    EJD_LOG_PATH="$s5_log" EJD_STATE_DIR="$tmp/s5-state" HARNESS_SELFTEST=0 \
    "$bash_bin" -c "source '$self_abs'; run_ensure"
  local s7_bs; s7_bs="$(grep -c '^bootstrap' "$s5_lcstate/bootstrap.log" 2>/dev/null || echo 0)"
  _ck_eq "$s7_bs" "1" "S7 unchanged content + already-loaded -> still exactly ONE bootstrap"
  if [[ ! -f "$s5_lcstate/bootout.log" ]]; then
    echo "PASS: S7 no bootout on an unchanged, already-loaded install"; pass=$((pass+1))
  else
    echo "FAIL: S7 unexpected bootout on unchanged content" >&2; fail=$((fail+1))
  fi

  echo "Scenario 8: content change while loaded -> bootout then a SECOND bootstrap"
  EJD_UNAME_OVERRIDE="Darwin" EJD_JANITOR_OVERRIDE="$fx_janitor" EJD_BRIEF_OVERRIDE="$fx_brief" \
    EJD_LAUNCHAGENTS_DIR="$s5_la" EJD_WRAPPER_DIR="$s5_wr" EJD_LAUNCHCTL_OVERRIDE="$s5_lc" \
    EJD_LOG_PATH="$s5_log" EJD_STATE_DIR="$tmp/s5-state" EJD_INTERVAL_SECONDS=600 HARNESS_SELFTEST=0 \
    "$bash_bin" -c "source '$self_abs'; run_ensure"
  _ck "$(cat "$s5_la/local.neurallace.estate-janitor.plist" 2>/dev/null)" "<integer>600</integer>" "S8 plist content actually changed"
  if [[ -f "$s5_lcstate/bootout.log" ]]; then
    echo "PASS: S8 content change triggered a bootout"; pass=$((pass+1))
  else
    echo "FAIL: S8 expected a bootout on content change" >&2; fail=$((fail+1))
  fi
  local s8_bs; s8_bs="$(grep -c '^bootstrap' "$s5_lcstate/bootstrap.log" 2>/dev/null || echo 0)"
  _ck_eq "$s8_bs" "2" "S8 content change -> exactly TWO bootstraps total"

  echo "Scenario 9: missing launchctl -> tolerate-absent"
  local s9_log="$tmp/s9.log"
  EJD_UNAME_OVERRIDE="Darwin" EJD_JANITOR_OVERRIDE="$fx_janitor" EJD_BRIEF_OVERRIDE="$fx_brief" \
    EJD_LOG_PATH="$s9_log" EJD_FORCE_NO_LAUNCHCTL=1 HARNESS_SELFTEST=0 \
    "$bash_bin" -c "source '$self_abs'; run_ensure"
  _ck "$(cat "$s9_log" 2>/dev/null)" "launchctl not found" "S9 missing launchctl tolerates absent"

  echo "Scenario 10: --uninstall removes BOTH plist and wrapper"
  local s10_log="$tmp/s10.log"
  EJD_UNAME_OVERRIDE="Darwin" EJD_LAUNCHAGENTS_DIR="$s5_la" EJD_WRAPPER_DIR="$s5_wr" \
    EJD_LAUNCHCTL_OVERRIDE="$s5_lc" EJD_LOG_PATH="$s10_log" HARNESS_SELFTEST=0 \
    "$bash_bin" -c "source '$self_abs'; run_uninstall"
  if [[ ! -f "$s5_la/local.neurallace.estate-janitor.plist" && ! -f "$s5_wr/estate-janitor-tick.sh" ]]; then
    echo "PASS: S10 uninstall removed both artifacts"; pass=$((pass+1))
  else
    echo "FAIL: S10 uninstall left an artifact behind" >&2; fail=$((fail+1))
  fi

  # ---- the quoting proofs: this is why the wrapper indirection exists ----
  echo "Scenario 11: paths containing a SPACE survive into a RUNNABLE wrapper"
  local sp_dir="$tmp/Pocket Technician/neural lace"
  mkdir -p "$sp_dir"
  local sp_j="$sp_dir/estate-janitor.sh" sp_b="$sp_dir/estate-brief.sh"
  printf '#!/usr/bin/env bash\necho "janitor-ok arg=$1"\n' > "$sp_j"; chmod +x "$sp_j"
  printf '#!/usr/bin/env bash\necho "brief-ok arg=$1"\n' > "$sp_b"; chmod +x "$sp_b"
  local s11_la="$tmp/s11-la" s11_wr="$tmp/s11-wr" s11_state="$tmp/s11 state dir" s11_log="$tmp/s11.log"
  local s11_lc; s11_lc="$(_fake_launchctl "$tmp/s11-lc")"; _require_fake_launchctl "$s11_lc"
  EJD_UNAME_OVERRIDE="Darwin" EJD_JANITOR_OVERRIDE="$sp_j" EJD_BRIEF_OVERRIDE="$sp_b" \
    EJD_LAUNCHAGENTS_DIR="$s11_la" EJD_WRAPPER_DIR="$s11_wr" EJD_LAUNCHCTL_OVERRIDE="$s11_lc" \
    EJD_LOG_PATH="$s11_log" EJD_STATE_DIR="$s11_state" HARNESS_SELFTEST=0 \
    "$bash_bin" -c "source '$self_abs'; run_ensure"
  # BEHAVIOR, not source text: actually EXECUTE the generated wrapper and
  # assert both fixture scripts ran with the right args and the log landed.
  "$bash_bin" "$s11_wr/estate-janitor-tick.sh" >/dev/null 2>&1
  local s11_logfile; s11_logfile="$s11_state/cron-$(date +%Y-%m-%d).log"
  _ck "$(cat "$s11_logfile" 2>/dev/null)" "janitor-ok arg=run" "S11 generated wrapper RAN the janitor with 'run' through a space-containing path"
  _ck "$(cat "$s11_logfile" 2>/dev/null)" "brief-ok arg=--write" "S11 generated wrapper RAN the brief with '--write' through a space-containing path"

  echo "Scenario 12: a path containing a SINGLE QUOTE survives shell quoting"
  local q_dir="$tmp/misha's repo"
  mkdir -p "$q_dir"
  local q_j="$q_dir/estate-janitor.sh" q_b="$q_dir/estate-brief.sh"
  printf '#!/usr/bin/env bash\necho "quoted-janitor-ok"\n' > "$q_j"; chmod +x "$q_j"
  printf '#!/usr/bin/env bash\necho "quoted-brief-ok"\n' > "$q_b"; chmod +x "$q_b"
  local s12_la="$tmp/s12-la" s12_wr="$tmp/s12-wr" s12_state="$tmp/s12-state" s12_log="$tmp/s12.log"
  local s12_lc; s12_lc="$(_fake_launchctl "$tmp/s12-lc")"; _require_fake_launchctl "$s12_lc"
  EJD_UNAME_OVERRIDE="Darwin" EJD_JANITOR_OVERRIDE="$q_j" EJD_BRIEF_OVERRIDE="$q_b" \
    EJD_LAUNCHAGENTS_DIR="$s12_la" EJD_WRAPPER_DIR="$s12_wr" EJD_LAUNCHCTL_OVERRIDE="$s12_lc" \
    EJD_LOG_PATH="$s12_log" EJD_STATE_DIR="$s12_state" HARNESS_SELFTEST=0 \
    "$bash_bin" -c "source '$self_abs'; run_ensure"
  "$bash_bin" "$s12_wr/estate-janitor-tick.sh" >/dev/null 2>&1
  _ck "$(cat "$s12_state/cron-$(date +%Y-%m-%d).log" 2>/dev/null)" "quoted-janitor-ok" "S12 single-quote path survived _ej_shq into a running wrapper"

  echo "Scenario 13: brief runs ONLY if the janitor succeeded (&& semantics preserved)"
  local f_dir="$tmp/failcase"; mkdir -p "$f_dir"
  local f_j="$f_dir/estate-janitor.sh" f_b="$f_dir/estate-brief.sh"
  printf '#!/usr/bin/env bash\necho "janitor-failed"; exit 3\n' > "$f_j"; chmod +x "$f_j"
  printf '#!/usr/bin/env bash\necho "brief-SHOULD-NOT-RUN"\n' > "$f_b"; chmod +x "$f_b"
  local s13_wr="$tmp/s13-wr" s13_state="$tmp/s13-state"
  local s13_lc; s13_lc="$(_fake_launchctl "$tmp/s13-lc")"; _require_fake_launchctl "$s13_lc"
  EJD_UNAME_OVERRIDE="Darwin" EJD_JANITOR_OVERRIDE="$f_j" EJD_BRIEF_OVERRIDE="$f_b" \
    EJD_LAUNCHAGENTS_DIR="$tmp/s13-la" EJD_WRAPPER_DIR="$s13_wr" EJD_LAUNCHCTL_OVERRIDE="$s13_lc" \
    EJD_LOG_PATH="$tmp/s13.log" EJD_STATE_DIR="$s13_state" HARNESS_SELFTEST=0 \
    "$bash_bin" -c "source '$self_abs'; run_ensure"
  "$bash_bin" "$s13_wr/estate-janitor-tick.sh" >/dev/null 2>&1
  local s13_out; s13_out="$(cat "$s13_state/cron-$(date +%Y-%m-%d).log" 2>/dev/null)"
  _ck "$s13_out" "janitor-failed" "S13 janitor failure is logged"
  _ck_not "$s13_out" "brief-SHOULD-NOT-RUN" "S13 brief did NOT run after a janitor failure"

  echo "Scenario 14: wrapper always exits 0 (a failing tick must never mark the LaunchAgent bad)"
  "$bash_bin" "$s13_wr/estate-janitor-tick.sh" >/dev/null 2>&1
  _ck_eq "$?" "0" "S14 wrapper exits 0 even when the janitor exits 3"

  echo "Scenario 15: invalid interval falls back to 300, never emits a malformed plist"
  local s15_la="$tmp/s15-la" s15_wr="$tmp/s15-wr"
  local s15_lc; s15_lc="$(_fake_launchctl "$tmp/s15-lc")"; _require_fake_launchctl "$s15_lc"
  EJD_UNAME_OVERRIDE="Darwin" EJD_JANITOR_OVERRIDE="$fx_janitor" EJD_BRIEF_OVERRIDE="$fx_brief" \
    EJD_LAUNCHAGENTS_DIR="$s15_la" EJD_WRAPPER_DIR="$s15_wr" EJD_LAUNCHCTL_OVERRIDE="$s15_lc" \
    EJD_LOG_PATH="$tmp/s15.log" EJD_STATE_DIR="$tmp/s15-state" EJD_INTERVAL_SECONDS="; rm -rf /" \
    HARNESS_SELFTEST=0 \
    "$bash_bin" -c "source '$self_abs'; run_ensure"
  local s15_plist; s15_plist="$(cat "$s15_la/local.neurallace.estate-janitor.plist" 2>/dev/null)"
  _ck "$s15_plist" "<integer>300</integer>" "S15 non-numeric interval fell back to 300"
  _ck_not "$s15_plist" "rm -rf" "S15 injected interval never reached the plist"

  echo "Scenario 16: exit code is always 0 across no-op and tolerate-absent branches"
  EJD_UNAME_OVERRIDE="Linux" EJD_LOG_PATH="$tmp/s16a.log" HARNESS_SELFTEST=1 \
    "$bash_bin" "$self_abs" >/dev/null 2>&1
  _ck_eq "$?" "0" "S16a non-Darwin real entry point exits 0"
  EJD_UNAME_OVERRIDE="Darwin" EJD_LOG_PATH="$tmp/s16b.log" EJD_FORCE_NO_BASH=1 \
    EJD_JANITOR_OVERRIDE="$fx_janitor" EJD_BRIEF_OVERRIDE="$fx_brief" HARNESS_SELFTEST=1 \
    "$bash_bin" -c "source '$self_abs'; run_ensure"
  _ck_eq "$?" "0" "S16b tolerate-absent (no bash) branch exits 0"

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
    --print)     _ej_print ;;
    *)           run_ensure ;;
  esac
fi
