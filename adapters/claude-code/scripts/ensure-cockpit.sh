#!/usr/bin/env bash
# ensure-cockpit.sh — best-effort SessionStart ensure for the observability
# cockpit (Workstreams UI node server, port 7733).
#
# WHY THIS EXISTS (operator directive 2026-07-09): the cockpit should be
# running whenever the operator is in an NL Claude session — a session-tied
# lifecycle replacing the `ConversationTreeUI-AutoStart` logon scheduled
# task (operator preference: no scheduled-task sprawl). The logon task's
# retirement is a RECORDED integration step, not an implied future: it was
# unregistered (register-autostart.ps1 -Unregister) in the same integration
# that merged this file to master (2026-07-09; the merge commit records
# it). This script is
# invoked from the EXISTING session-start-digest.sh SessionStart hook's
# run_digest() (one line, folded in — NOT a new SessionStart hooks[] entry;
# that array is already at its 8/8 cap), mirroring the
# session-heartbeat.sh "touch" callsite convention already used there
# (best-effort, `>/dev/null 2>&1 || true`, never blocks the digest).
#
# CONTRACT (all mandatory):
#   1. OS guard — only Windows/MSYS (the launcher is a .ps1). Any other OS
#      (Linux/cloud/CI): silent no-op, exit 0. Test override:
#      ENSURE_COCKPIT_UNAME_OVERRIDE (wins over `uname -s` when set — lets
#      a self-test simulate a non-Windows host without needing one).
#   2. HARNESS_SELFTEST=1 — never actually spawns powershell/node. Records
#      the invocation that WOULD run (to the log) and returns 0, so a
#      self-test proves the guard logic + invocation SHAPE without ever
#      touching a real process or popping a GUI.
#   3. Launcher path resolved MACHINE-WIDE first (review fix 2026-07-09):
#      hooks/lib/nl-paths.sh's nl_repo_root() (env NL_REPO_ROOT ->
#      install-written ~/.claude/local/nl-repo-path -> lib-location git ->
#      probe list), so the ensure works from ANY session cwd — matching
#      the machine-wide coverage of the logon task this replaces. The
#      session-cwd derivation (nl_main_checkout_root()) is kept as a
#      FALLBACK for machines without an install config. Every git-derived
#      candidate is normalized to the MAIN checkout — NEVER a worktree,
#      so a worktree-rooted session never spawns a worktree-local server
#      copy (worktree isolation, ADR/doctrine/worktree-isolation.md).
#   4. NON-BLOCKING — the real invocation is `nohup`'d and backgrounded;
#      this script's own return is never gated on the child.
#      launch-gui.ps1 polls Test-ServerUp for up to ~5s on a cold node
#      start — that must never delay this script, which must never delay
#      session-start-digest.sh, which must never delay session start.
#   5. Tolerate-absent — missing launcher / powershell.exe -> log and
#      return 0. NEVER errors, NEVER blocks the session (exit 0 always,
#      on every code path — `set -u` only, deliberately no `set -e`).
#   6. Operator kill-switch (guard 0, review fix 2026-07-09) — env
#      ENSURE_COCKPIT_DISABLE=1 (per-session) or flag file
#      ~/.claude/local/cockpit-disabled (durable, operator-managed) ->
#      logged no-op. The off-switch for a recurring machine behavior must
#      never require hand-editing live harness files.
#
# Self-test: --self-test (see run_self_test()). HARNESS_SELFTEST=1
# sandboxes the log path under a tmp dir, mirroring the
# session-start-digest.sh / lib/signal-ledger.sh convention.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
{ source "$SCRIPT_DIR/../hooks/lib/nl-paths.sh" 2>/dev/null; } || true

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

# ----------------------------------------------------------------------
# Main entry. Always returns 0 — every branch below is a deliberate,
# logged no-op or a fire-and-forget dispatch; there is no error branch.
# ----------------------------------------------------------------------
run_ensure() {
  if _ec_is_disabled; then
    _ec_log "no-op: cockpit ensure disabled by operator (ENSURE_COCKPIT_DISABLE=1 or ~/.claude/local/cockpit-disabled)"
    return 0
  fi

  if ! _ec_is_windows; then
    _ec_log "no-op: OS '$(_ec_uname)' is not Windows/MSYS — cockpit ensure only runs on Windows"
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

  _seed_main_repo() {
    # A minimal main-checkout fixture with the launcher present at the
    # exact relative path run_ensure() expects.
    local d="$1"
    mkdir -p "$d/neural-lace/workstreams-ui/scripts"
    cat > "$d/neural-lace/workstreams-ui/scripts/launch-gui.ps1" <<'EOF'
# fixture launcher — never actually executed by this self-test.
EOF
    ( cd "$d" && git init --quiet && git config core.hookspath "" \
      && git config user.email t@example.com && git config user.name T \
      && git add -A && git commit --quiet -m init ) >/dev/null 2>&1
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
