#!/usr/bin/env bash
# ensure-coord-sync.sh — macOS scheduled runner for the cross-machine
# coordination cadence (adapters/claude-code/scripts/coord-sync.sh).
#
# WHY THIS EXISTS (operator, 2026-07-29): "The cockpit is also supposed to
# show work across multiple machines. When is that actually going to be a
# reality?" On Windows, coord-sync.sh's ~60s cadence is driven by the
# `NL-CoordSync` scheduled task (install-coord-sync-task.ps1). macOS had NO
# scheduled runner at all: ~/.claude/state/coord-sync/cycles.log had never
# been written on this machine — coord-sync.sh had literally never run
# here. This script closes that gap the SAME way decision 065 closed the
# analogous gap for the cockpit server itself
# (docs/decisions/065-macos-cockpit-launchagent.md): a launchd LaunchAgent,
# installed/refreshed idempotently, folded into the existing SessionStart
# digest hook (NOT a new hooks[] entry — that array is already at its cap).
#
# ============================================================
# WHY StartInterval, NOT RunAtLoad+KeepAlive (contrast w/ ensure-cockpit.sh)
# ============================================================
# ensure-cockpit.sh's LaunchAgent runs a PERSISTENT node server: RunAtLoad
# starts it once, KeepAlive({SuccessfulExit:false}) restarts it if it
# crashes, and it is expected to still be running an hour later.
# coord-sync.sh is the OPPOSITE shape: a short-lived cadence script that
# EXITS after each debounced fire (Task 7's marker-check/event/floor logic)
# and is meant to be re-invoked ~60s later — exactly launchd's
# `StartInterval` contract, not `KeepAlive`. Setting KeepAlive on a
# StartInterval job fights launchd's own semantics (KeepAlive expects a
# long-running daemon; StartInterval expects short runs that exit cleanly),
# so this plist carries StartInterval only — no KeepAlive key at all.
# RunAtLoad is ALSO set (fire once immediately at install/login, mirroring
# "start now" so the operator does not wait up to the interval for the
# first cycle), but nothing here restarts a still-running instance —
# coord-sync.sh's own mkdir lock (STATE_DIR/coord-sync.lock, 900s stale
# reclaim) is what prevents overlap if a slow cycle is still running when
# the next interval fires, exactly as the Windows scheduled task's own
# `-MultipleInstances IgnoreNew` does there.
#
# ============================================================
# CREDENTIAL FIX: same-person, different-GitHub-account-per-machine
# ============================================================
# coord-push.sh/coord-pull.sh are git-over-<whatever COORD_REPO_URL is>;
# the documented design (coord-push.sh's own header) is git-over-SSH
# specifically to avoid "gh-account-blindness" (the gh Contents API
# silently uses whichever gh account is *active*). The SAME class of bug
# exists for a plain HTTPS remote once `gh auth setup-git` has installed
# its own global `credential.https://github.com.helper` — that helper ALSO
# resolves to whichever gh account is *active*, not to whichever account
# actually owns/collaborates on the coord repo. On a machine whose only
# SSH key authenticates as a DIFFERENT GitHub account than the one that
# owns the private coord repo (this Mac: the machine's SSH identity is
# account A, the coord repo is privately owned by account B, and A is not
# a collaborator on it), neither SSH nor gh's own default HTTPS helper can
# reach it — `git ls-remote` fails "Repository not found" (GitHub's
# generic response for both "doesn't exist" and "exists, no access").
#
# Fix (`_ecs_ensure_repo_credential`, idempotent, runs every ensure):
# resolve COORD_REPO_URL the IDENTICAL way coord-push.sh's own
# `_resolve_repo_url` does (env > ~/.claude/local/coord-repo-url.txt >
# existing clone's origin > none); if it is an
# `https://github.com/<owner>/<repo>` URL AND this machine already has a
# gh-authenticated token for <owner> (`gh auth token -u <owner>`, checked
# WITHOUT switching the active account — this NEVER touches `gh auth
# switch`, so it has zero effect on any other repo's gh-CLI usage on this
# machine), install a URL-SCOPED (not host-scoped) *global* git
# credential-helper override for that EXACT url that always resolves to
# <owner>'s token, fetched fresh via `gh auth token` on every git
# operation (never written to disk in plaintext). Being URL-scoped means
# it can NEVER affect any other github.com clone/push/fetch on this
# machine — it coexists with `gh auth setup-git`'s own host-level helper
# (git tries helpers in config order and stops at the first one that
# supplies both username+password; the reset-then-set pattern used here
# — an empty `credential.<url>.helper` entry followed by the real one —
# is the SAME idempotent-reset trick `gh auth setup-git` itself uses,
# scoped to one URL instead of the whole host, so it wins for THIS repo
# without disturbing the host-wide default for every other repo).
# If <owner> has no gh token on this machine at all, this is a genuine
# operator-provisioning gap — tolerate-absent + log, never blocks.
# If COORD_REPO_URL is SSH-form or a non-github.com host, this fix does
# not apply (out of scope for this class); see docs/runbooks/coord-sync.md
# "Second-account (second person's) coord-repo access" for the SSH path.
#
# CONTRACT (mirrors ensure-cockpit.sh's Darwin contract):
#   1. Darwin only; any other OS is a silent no-op (Windows keeps its own
#      install-coord-sync-task.ps1, operator/orchestrator-applied per
#      docs/runbooks/coord-sync.md — registering a scheduled task is
#      intentionally NOT something an agent session does unattended).
#   2. HARNESS_SELFTEST=1 — never writes a real plist / calls real
#      launchctl / touches the real global gitconfig; logs the intended
#      action and returns 0 BEFORE any side effect.
#   3. Script path resolved via the SAME stable, cross-platform convention
#      install-coord-sync-task.ps1 already documents for Windows:
#      `$HOME/.claude/scripts/coord-sync.sh` (the live, kept-in-sync
#      mirror — a symlink into this checkout on a dev machine, an
#      install.sh-managed copy elsewhere; NEVER a worktree-local copy,
#      because worktrees are never what `~/.claude/scripts` points at).
#      Falls back to nl_repo_root()-based resolution (mirrors
#      ensure-cockpit.sh) if that mirror is somehow absent.
#   4. NON-BLOCKING — launchctl calls run under `nl_run_bounded`
#      (hooks/lib/portable-timeout.sh); this script's own return is never
#      gated on a real coord-sync cycle having actually completed.
#   5. Tolerate-absent — missing coord-sync.sh / bash / launchctl -> log
#      and return 0. NEVER errors (set -u only, no set -e).
#   6. Operator kill-switch — ENSURE_COORD_SYNC_DISABLE=1 (env) or
#      ~/.claude/local/coord-sync-disabled (durable flag file) -> no-op,
#      logged, on the LaunchAgent step (the credential-ensure step is
#      separately harmless/idempotent and also skipped under this switch).
#   7. Darwin IDEMPOTENT + SINGLE-INSTANCE, identical discipline to
#      ensure-cockpit.sh: plist rewritten only when content differs;
#      `launchctl bootstrap` only when not already loaded (checked via
#      `launchctl print`); a content change while loaded does bootout
#      then bootstrap, never an additive second load.
#
# NO liveness probe (contrast with ensure-cockpit.sh's port poll): a
# periodic cadence script has no listening socket to probe. "Did it
# actually run" is answered by ~/.claude/state/coord-sync/cycles.log's own
# freshness — this script logs that it SCHEDULED the job, not that a cycle
# completed; hand-verifying a real cycle is a separate, explicit step
# (`bash ~/.claude/scripts/coord-sync.sh --force`), same as the runbook's
# own "Verify after applying" section for the Windows task.
#
# Darwin test-only overrides (mirror ensure-cockpit.sh's naming):
#   ENSURE_COORD_SYNC_LAUNCHAGENTS_DIR / ENSURE_COORD_SYNC_PLIST_LABEL
#   ENSURE_COORD_SYNC_LAUNCHCTL_OVERRIDE / ENSURE_COORD_SYNC_FORCE_NO_LAUNCHCTL
#   ENSURE_COORD_SYNC_BASH_OVERRIDE / ENSURE_COORD_SYNC_FORCE_NO_BASH
#   ENSURE_COORD_SYNC_SCRIPT_OVERRIDE (point at a fixture coord-sync.sh)
#   ENSURE_COORD_SYNC_UNAME_OVERRIDE (OS override for tests)
#   ENSURE_COORD_SYNC_GH_TOKEN_CMD (override for the reachability CHECK's
#     own `gh auth token -u <owner>` call — never affects the INSTALLED
#     helper, which always shells out to the real `gh` at request time)
#   ENSURE_COORD_SYNC_INTERVAL_SECONDS (default 60, matches the Windows
#     task's -IntervalSeconds default)
#
# Self-test: --self-test (see run_self_test()).

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
{ source "$SCRIPT_DIR/../hooks/lib/nl-paths.sh" 2>/dev/null; } || true
# shellcheck disable=SC1091
{ source "$SCRIPT_DIR/../hooks/lib/portable-timeout.sh" 2>/dev/null; } || true
# Defensive shim (portable-timeout.sh's own USAGE contract): a partial
# install missing the lib degrades to unbounded — visibly, not silently.
if ! declare -F nl_run_bounded >/dev/null 2>&1; then
  nl_run_bounded() {
    local _secs="${1:-}"; shift 2>/dev/null || true
    printf '[ensure-coord-sync] WARNING: hooks/lib/portable-timeout.sh unavailable — running "%s" unbounded\n' "$*" >&2
    "$@"
  }
fi

# ----------------------------------------------------------------------
# Log path resolution (mirrors ensure-cockpit.sh's _ec_log_path exactly).
# ----------------------------------------------------------------------
_ecs_log_path() {
  if [[ -n "${ENSURE_COORD_SYNC_LOG_PATH:-}" ]]; then
    printf '%s' "$ENSURE_COORD_SYNC_LOG_PATH"
    return 0
  fi
  if [[ "${HARNESS_SELFTEST:-0}" == "1" ]]; then
    printf '%s/ensure-coord-sync-selftest/%s/ensure-coord-sync.log' "${TMPDIR:-/tmp}" "${$}"
    return 0
  fi
  printf '%s/.claude/logs/ensure-coord-sync.log' "${HOME:-$PWD}"
}

_ecs_log() {
  local msg="$1" path
  path="$(_ecs_log_path)"
  mkdir -p "$(dirname "$path")" 2>/dev/null || true
  if [[ -f "$path" ]] && [[ "$(wc -c < "$path" 2>/dev/null || echo 0)" -gt 65536 ]]; then
    { tail -n 200 "$path" > "$path.tmp.$$" && mv -f "$path.tmp.$$" "$path"; } 2>/dev/null \
      || rm -f "$path.tmp.$$" 2>/dev/null || true
  fi
  local ts; ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo unknown)"
  printf '[%s] %s\n' "$ts" "$msg" >> "$path" 2>/dev/null || true
}

# ----------------------------------------------------------------------
# Guard 0: operator kill-switch.
# ----------------------------------------------------------------------
_ecs_is_disabled() {
  [[ "${ENSURE_COORD_SYNC_DISABLE:-0}" == "1" ]] && return 0
  [[ -n "${HOME:-}" && -f "${HOME}/.claude/local/coord-sync-disabled" ]] && return 0
  return 1
}

# ----------------------------------------------------------------------
# Guard 1: OS detection (mirrors ensure-cockpit.sh's _ec_uname/_ec_is_darwin).
# ----------------------------------------------------------------------
_ecs_uname() {
  if [[ -n "${ENSURE_COORD_SYNC_UNAME_OVERRIDE:-}" ]]; then
    printf '%s' "$ENSURE_COORD_SYNC_UNAME_OVERRIDE"
    return 0
  fi
  uname -s 2>/dev/null
}

_ecs_is_darwin() {
  case "$(_ecs_uname)" in
    Darwin) return 0 ;;
    *) return 1 ;;
  esac
}

# ----------------------------------------------------------------------
# bash / launchctl resolution — tolerate-absence + override convention
# (mirrors ensure-cockpit.sh's _ec_resolve_node / _ec_resolve_launchctl).
# ----------------------------------------------------------------------
_ecs_resolve_bash() {
  if [[ "${ENSURE_COORD_SYNC_FORCE_NO_BASH:-0}" == "1" ]]; then
    return 1
  fi
  if [[ -n "${ENSURE_COORD_SYNC_BASH_OVERRIDE:-}" ]]; then
    printf '%s' "$ENSURE_COORD_SYNC_BASH_OVERRIDE"
    return 0
  fi
  local found
  found="$(command -v bash 2>/dev/null || true)"
  if [[ -n "$found" ]]; then
    printf '%s' "$found"
    return 0
  fi
  return 1
}

_ecs_resolve_launchctl() {
  if [[ "${ENSURE_COORD_SYNC_FORCE_NO_LAUNCHCTL:-0}" == "1" ]]; then
    return 1
  fi
  if [[ -n "${ENSURE_COORD_SYNC_LAUNCHCTL_OVERRIDE:-}" ]]; then
    printf '%s' "$ENSURE_COORD_SYNC_LAUNCHCTL_OVERRIDE"
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

# ----------------------------------------------------------------------
# coord-sync.sh script resolution (contract item 3): the stable live
# mirror first, nl_repo_root()-derived path as fallback.
# ----------------------------------------------------------------------
_ecs_resolve_script() {
  if [[ -n "${ENSURE_COORD_SYNC_SCRIPT_OVERRIDE:-}" ]]; then
    printf '%s' "$ENSURE_COORD_SYNC_SCRIPT_OVERRIDE"
    return 0
  fi
  local mirror="${HOME:-}/.claude/scripts/coord-sync.sh"
  if [[ -n "${HOME:-}" && -f "$mirror" ]]; then
    printf '%s' "$mirror"
    return 0
  fi
  if declare -F nl_repo_root >/dev/null 2>&1; then
    local root norm cand
    root="$(nl_repo_root 2>/dev/null || true)"
    if [[ -n "$root" ]]; then
      norm="$(cd "$root" 2>/dev/null && nl_main_checkout_root 2>/dev/null || true)"
      [[ -n "$norm" ]] && root="$norm"
      cand="$root/adapters/claude-code/scripts/coord-sync.sh"
      if [[ -f "$cand" ]]; then
        printf '%s' "$cand"
        return 0
      fi
    fi
  fi
  return 1
}

# ========================================================================
# CREDENTIAL ENSURE (see header). Runs independently of the LaunchAgent
# install/kill-switch — it is a harmless, idempotent, URL-scoped fix that
# only ever touches config for the ONE resolved coord-repo URL.
# ========================================================================

# _ecs_resolve_repo_url — IDENTICAL 3-tier resolution to coord-push.sh's
# own _resolve_repo_url: env > local config file > existing clone's
# origin > empty.
_ecs_resolve_repo_url() {
  if [[ -n "${COORD_REPO_URL:-}" ]]; then
    printf '%s' "$COORD_REPO_URL"
    return 0
  fi
  local f="${HOME:-}/.claude/local/coord-repo-url.txt"
  if [[ -n "${HOME:-}" && -f "$f" ]]; then
    local u; u="$(head -n1 "$f" 2>/dev/null | tr -d '[:space:]')"
    if [[ -n "$u" ]]; then
      printf '%s' "$u"
      return 0
    fi
  fi
  local dir="${COORD_CLONE_DIR:-${HOME:-}/claude-projects/workstreams-coordination}"
  if [[ -d "$dir/.git" ]]; then
    local u2; u2="$(git -C "$dir" remote get-url origin 2>/dev/null || true)"
    if [[ -n "$u2" ]]; then
      printf '%s' "$u2"
      return 0
    fi
  fi
  return 1
}

# _ecs_parse_github_https <url> — prints "<owner> <repo>" on stdout for a
# `https://github.com/<owner>/<repo>[.git]` URL; returns 1 (prints
# nothing) for any other shape (SSH, other host, malformed).
_ecs_parse_github_https() {
  local url="$1" rest owner repo
  case "$url" in
    https://github.com/*) rest="${url#https://github.com/}" ;;
    *) return 1 ;;
  esac
  case "$rest" in
    */*) : ;;
    *) return 1 ;;
  esac
  owner="${rest%%/*}"
  repo="${rest#*/}"
  repo="${repo%.git}"
  repo="${repo%/}"
  [[ -n "$owner" && -n "$repo" ]] || return 1
  printf '%s %s\n' "$owner" "$repo"
  return 0
}

# _ecs_gh_token_for <owner> — the reachability CHECK's own token lookup
# (test-overridable via ENSURE_COORD_SYNC_GH_TOKEN_CMD). The credential
# helper actually INSTALLED into gitconfig never uses this override — it
# always shells out to the real `gh` at request time (see header).
_ecs_gh_token_for() {
  local owner="$1"
  if [[ -n "${ENSURE_COORD_SYNC_GH_TOKEN_CMD:-}" ]]; then
    bash -c "$ENSURE_COORD_SYNC_GH_TOKEN_CMD" "$owner" 2>/dev/null
    return $?
  fi
  command -v gh >/dev/null 2>&1 || return 1
  gh auth token -u "$owner" 2>/dev/null
}

_ecs_ensure_repo_credential() {
  local url parsed owner repo
  url="$(_ecs_resolve_repo_url)" || {
    _ecs_log "no coord repo URL configured yet (~/.claude/local/coord-repo-url.txt absent, COORD_REPO_URL unset, no existing clone) — skipping credential ensure"
    return 0
  }
  parsed="$(_ecs_parse_github_https "$url" 2>/dev/null)" || {
    _ecs_log "coord repo URL '$url' is not an https://github.com/<owner>/<repo> URL — credential auto-fix only covers that class (SSH/non-github transports: see docs/runbooks/coord-sync.md 'Second-account access')"
    return 0
  }
  owner="${parsed%% *}"
  repo="${parsed#* }"

  if [[ "${HARNESS_SELFTEST:-0}" == "1" ]]; then
    _ecs_log "[credential self-test stub] would ensure a URL-scoped git credential helper for https://github.com/$owner/$repo.git (owner=$owner) — never touches the real gitconfig"
    return 0
  fi

  local token
  token="$(_ecs_gh_token_for "$owner")"
  if [[ -z "$token" ]]; then
    _ecs_log "tolerate-absent: no gh-authenticated token for '$owner' on this machine — operator must 'gh auth login' that account, or grant this machine's already-authenticated account collaborator access to $owner/$repo, before coord-sync can reach the coord repo over HTTPS"
    return 0
  fi

  local scoped_url="https://github.com/$owner/$repo.git"
  local desired_helper
  desired_helper="!f() { printf 'username=%s\n' '$owner'; printf 'password=%s\n' \"\$(gh auth token -u $owner 2>/dev/null)\"; }; f"

  git config --global --unset-all credential."$scoped_url".helper 2>/dev/null || true
  git config --global --add credential."$scoped_url".helper "" 2>/dev/null || true
  if git config --global --add credential."$scoped_url".helper "$desired_helper" 2>/dev/null; then
    _ecs_log "ensured a URL-scoped git credential helper for $scoped_url (owner=$owner) — resolves via 'gh auth token -u $owner' at request time, independent of gh's globally-active account"
  else
    _ecs_log "tolerate-absent: could not write the global git credential config for $scoped_url"
  fi
  return 0
}

# ========================================================================
# LaunchAgent plist content + darwin ensure.
# ========================================================================

_ecs_launchagents_dir() {
  if [[ -n "${ENSURE_COORD_SYNC_LAUNCHAGENTS_DIR:-}" ]]; then
    printf '%s' "$ENSURE_COORD_SYNC_LAUNCHAGENTS_DIR"
  else
    printf '%s/Library/LaunchAgents' "${HOME:-$PWD}"
  fi
}

_ecs_label() {
  printf '%s' "${ENSURE_COORD_SYNC_PLIST_LABEL:-local.neurallace.coord-sync}"
}

_ecs_plist_path() {
  printf '%s/%s.plist' "$(_ecs_launchagents_dir)" "$(_ecs_label)"
}

# _ecs_plist_content <label> <bash> <script> <workdir> <path_env>
#   <interval> <out_log> <err_log> — StartInterval + RunAtLoad, NO
#   KeepAlive (see header rationale).
_ecs_plist_content() {
  local label="$1" bash_bin="$2" script="$3" workdir="$4" path_env="$5" \
        interval="$6" out_log="$7" err_log="$8"
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
	</array>
	<key>WorkingDirectory</key>
	<string>${workdir}</string>
	<key>EnvironmentVariables</key>
	<dict>
		<key>PATH</key>
		<string>${path_env}</string>
	</dict>
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

# _ecs_path_env — launchd jobs run with a minimal environment; coord-sync.sh
# shells out to plain `git`/`node`/`gh` (no absolute paths), so PATH must
# name wherever THIS session resolved each of them, plus the standard
# system dirs. De-duplication is unnecessary (PATH search just tries each
# entry) so this simply concatenates.
_ecs_path_env() {
  local dirs="" bin
  for bin in "$(command -v git 2>/dev/null || true)" \
             "$(command -v node 2>/dev/null || true)" \
             "$(command -v gh 2>/dev/null || true)" \
             "$(_ecs_resolve_bash 2>/dev/null || true)"; do
    [[ -n "$bin" ]] || continue
    dirs="${dirs}$(dirname "$bin"):"
  done
  printf '%s/usr/bin:/bin:/usr/sbin:/sbin' "$dirs"
}

# _ecs_darwin_ensure — install/refresh the LaunchAgent idempotently.
# HARNESS_SELFTEST=1 is checked BEFORE any real side effect. Every branch
# is tolerate-absent and returns 0.
_ecs_darwin_ensure() {
  local script
  if ! script="$(_ecs_resolve_script)"; then
    _ecs_log "tolerate-absent: coord-sync.sh unresolved (\$HOME/.claude/scripts/coord-sync.sh absent and nl_repo_root() fallback also came up empty) — skipping coord-sync LaunchAgent ensure"
    return 0
  fi

  local bash_bin
  if ! bash_bin="$(_ecs_resolve_bash)"; then
    _ecs_log "tolerate-absent: bash not found on PATH — skipping coord-sync LaunchAgent ensure"
    return 0
  fi

  local launchctl
  if ! launchctl="$(_ecs_resolve_launchctl)"; then
    _ecs_log "tolerate-absent: launchctl not found — skipping coord-sync LaunchAgent ensure"
    return 0
  fi

  local interval="${ENSURE_COORD_SYNC_INTERVAL_SECONDS:-60}"
  local workdir; workdir="$(dirname "$script")"
  local la_dir label plist_path log_dir out_log err_log
  la_dir="$(_ecs_launchagents_dir)"
  label="$(_ecs_label)"
  plist_path="$(_ecs_plist_path)"
  log_dir="$(dirname "$(_ecs_log_path)")"
  out_log="$log_dir/coord-sync.stdout.log"
  err_log="$log_dir/coord-sync.stderr.log"

  local path_env; path_env="$(_ecs_path_env)"
  local desired
  desired="$(_ecs_plist_content "$label" "$bash_bin" "$script" "$workdir" "$path_env" "$interval" "$out_log" "$err_log")"

  if [[ "${HARNESS_SELFTEST:-0}" == "1" ]]; then
    _ecs_log "[darwin self-test stub] would install/refresh plist at $plist_path (label=$label, bash=$bash_bin, script=$script, interval=${interval}s) and bootstrap via $launchctl — never written/spawned"
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
      _ecs_log "plist written/refreshed: $plist_path"
    else
      _ecs_log "tolerate-absent: could not write plist at $plist_path — skipping bootstrap"
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
      _ecs_log "launchctl bootstrap succeeded for $label (StartInterval=${interval}s)"
    else
      _ecs_log "launchctl bootstrap returned non-zero for $label (may already be loaded, or no GUI launchd domain in this session) — continuing"
    fi
  else
    _ecs_log "$label already bootstrapped — no-op (idempotent)"
  fi

  return 0
}

# ----------------------------------------------------------------------
# Main entry. Always returns 0.
# ----------------------------------------------------------------------
run_ensure() {
  # The credential ensure is independent of the kill-switch and of the
  # Darwin guard below: it is a harmless, URL-scoped, idempotent config
  # fix that any platform's coord-push.sh/coord-pull.sh benefit from, and
  # skipping it under the kill-switch would leave a stale/broken
  # credential in place for no reason. It still fully respects
  # HARNESS_SELFTEST (see _ecs_ensure_repo_credential).
  _ecs_ensure_repo_credential

  if _ecs_is_disabled; then
    _ecs_log "no-op: coord-sync LaunchAgent ensure disabled by operator (ENSURE_COORD_SYNC_DISABLE=1 or ~/.claude/local/coord-sync-disabled)"
    return 0
  fi

  if ! _ecs_is_darwin; then
    _ecs_log "no-op: OS '$(_ecs_uname)' is not Darwin — coord-sync LaunchAgent ensure only runs on macOS (Windows uses install-coord-sync-task.ps1, operator-applied)"
    return 0
  fi

  _ecs_darwin_ensure
  return 0
}

# ============================================================
# Self-test
# ============================================================
run_self_test() {
  local pass=0 fail=0 tmp
  tmp="$(mktemp -d 2>/dev/null || echo "/tmp/ensure-coord-sync-st-$$")"
  mkdir -p "$tmp"
  export HARNESS_SELFTEST=1

  local self_abs bash_bin
  self_abs="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
  bash_bin="${BASH:-$(command -v bash)}"

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
  _count_lines_if_exists() {
    local f="$1"
    if [[ -f "$f" ]]; then
      wc -l < "$f" 2>/dev/null | tr -d ' '
    else
      printf '0'
    fi
  }

  # _fake_launchctl <state_dir> — same technique as ensure-cockpit.sh's own
  # self-test: a stand-in that tracks "loaded" state on disk and counts
  # bootstrap/bootout invocations, so a test can assert exactly how many
  # times each was called without ever touching real launchd.
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

  # _require_fake_launchctl <path> — hard-abort rather than risk the real
  # launchd if the stand-in was not actually created executable (same
  # defense-in-depth as ensure-cockpit.sh's own self-test, which caught a
  # real accidental-real-bootstrap this exact way once — see decisions/065).
  _require_fake_launchctl() {
    local path="$1"
    if [[ ! -x "$path" ]]; then
      echo "FATAL: fake launchctl stand-in missing/not executable at '$path' — aborting self-test rather than risk the real launchd" >&2
      rm -rf "$tmp" 2>/dev/null || true
      exit 1
    fi
  }

  local fake_script="$tmp/fixture-coord-sync.sh"
  cat > "$fake_script" <<'EOF'
#!/usr/bin/env bash
echo "fixture coord-sync.sh ran"
EOF
  chmod +x "$fake_script"

  # ---- S1: non-Darwin override -> silent no-op, never resolves anything. ----
  local s1_log="$tmp/s1.log"
  ( ENSURE_COORD_SYNC_UNAME_OVERRIDE="Linux" ENSURE_COORD_SYNC_LOG_PATH="$s1_log" HARNESS_SELFTEST=1 \
      ENSURE_COORD_SYNC_SCRIPT_OVERRIDE="$fake_script" \
      "$bash_bin" -c "source '$self_abs'; run_ensure" )
  local s1_out; s1_out="$(cat "$s1_log" 2>/dev/null || true)"
  _ck_contains "S1 non-Darwin override no-ops the LaunchAgent step" "$s1_out" "not Darwin"
  _ck_not_contains "S1 non-Darwin override never reaches darwin stub" "$s1_out" "[darwin self-test stub]"

  # ---- S2: Darwin, coord-sync.sh script missing -> tolerate-absent.
  # NL_REPO_ROOT must be an EXISTING directory (nl_repo_root()'s order-1
  # check is a plain `-d` test) that does NOT contain
  # adapters/claude-code/scripts/coord-sync.sh, or its order-3 git-derived
  # fallback would resolve THIS repo's own real checkout (since this
  # self-test itself runs from inside it) and the scenario would never
  # reach the tolerate-absent branch it means to test — same pin_root
  # technique ensure-cockpit.sh's own self-test uses. ----
  local s2_log="$tmp/s2.log" s2_home="$tmp/s2-home" s2_pin_root="$tmp/s2-no-coord-sync"
  mkdir -p "$s2_home" "$s2_pin_root"
  ( HOME="$s2_home" ENSURE_COORD_SYNC_UNAME_OVERRIDE="Darwin" ENSURE_COORD_SYNC_LOG_PATH="$s2_log" HARNESS_SELFTEST=1 \
      NL_REPO_ROOT="$s2_pin_root" \
      "$bash_bin" -c "source '$self_abs'; run_ensure" )
  local s2_out; s2_out="$(cat "$s2_log" 2>/dev/null || true)"
  _ck_contains "S2 missing coord-sync.sh tolerates absent" "$s2_out" "coord-sync.sh unresolved"

  # ---- S3: kill-switch env. ----
  local s3_log="$tmp/s3.log"
  ( ENSURE_COORD_SYNC_DISABLE=1 ENSURE_COORD_SYNC_UNAME_OVERRIDE="Darwin" ENSURE_COORD_SYNC_LOG_PATH="$s3_log" HARNESS_SELFTEST=1 \
      ENSURE_COORD_SYNC_SCRIPT_OVERRIDE="$fake_script" \
      "$bash_bin" -c "source '$self_abs'; run_ensure" )
  local s3_out; s3_out="$(cat "$s3_log" 2>/dev/null || true)"
  _ck_contains "S3 ENSURE_COORD_SYNC_DISABLE=1 no-ops the LaunchAgent step" "$s3_out" "disabled by operator"
  _ck_not_contains "S3 disabled run never reaches darwin stub" "$s3_out" "[darwin self-test stub]"

  # ---- S4: kill-switch flag file. ----
  local s4_home="$tmp/s4-home" s4_log="$tmp/s4.log"
  mkdir -p "$s4_home/.claude/local"
  : > "$s4_home/.claude/local/coord-sync-disabled"
  ( HOME="$s4_home" ENSURE_COORD_SYNC_UNAME_OVERRIDE="Darwin" ENSURE_COORD_SYNC_LOG_PATH="$s4_log" HARNESS_SELFTEST=1 \
      ENSURE_COORD_SYNC_SCRIPT_OVERRIDE="$fake_script" \
      "$bash_bin" -c "source '$self_abs'; run_ensure" )
  local s4_out; s4_out="$(cat "$s4_log" 2>/dev/null || true)"
  _ck_contains "S4 flag file ~/.claude/local/coord-sync-disabled no-ops" "$s4_out" "disabled by operator"

  # ---- D0: HARNESS_SELFTEST=1 stub -> records intended install, never
  # writes a real file, even under a Darwin override (belt-and-suspenders,
  # same discipline as ensure-cockpit.sh's own D0). ----
  local d0_log="$tmp/d0.log" d0_la="$tmp/d0-la" d0_state="$tmp/d0-state"
  local d0_launchctl; d0_launchctl="$(_fake_launchctl "$d0_state")"
  _require_fake_launchctl "$d0_launchctl"
  ( ENSURE_COORD_SYNC_UNAME_OVERRIDE="Darwin" ENSURE_COORD_SYNC_LOG_PATH="$d0_log" HARNESS_SELFTEST=1 \
      ENSURE_COORD_SYNC_SCRIPT_OVERRIDE="$fake_script" \
      ENSURE_COORD_SYNC_LAUNCHAGENTS_DIR="$d0_la" ENSURE_COORD_SYNC_PLIST_LABEL="test.d0.coord-sync" \
      ENSURE_COORD_SYNC_LAUNCHCTL_OVERRIDE="$d0_launchctl" \
      "$bash_bin" -c "source '$self_abs'; run_ensure" )
  local d0_out; d0_out="$(cat "$d0_log" 2>/dev/null || true)"
  _ck_contains "D0 darwin self-test stub records the intended install" "$d0_out" "[darwin self-test stub] would install/refresh plist"
  _ck_not_contains "D0 darwin stub never claims a real write" "$d0_out" "plist written/refreshed"
  if [[ ! -e "$d0_la" ]]; then
    echo "PASS: D0 darwin stub never creates the LaunchAgents dir on disk"; pass=$((pass + 1))
  else
    echo "FAIL: D0 darwin stub unexpectedly created $d0_la" >&2; fail=$((fail + 1))
  fi

  # ---- D1: fresh install -> plist written w/ StartInterval + NO KeepAlive
  # + RunAtLoad + resolved script/bash/PATH; bootstrap called exactly once. ----
  local d1_log="$tmp/d1.log" d1_la="$tmp/d1-la" d1_state="$tmp/d1-state"
  local d1_launchctl; d1_launchctl="$(_fake_launchctl "$d1_state")"
  _require_fake_launchctl "$d1_launchctl"
  ( ENSURE_COORD_SYNC_UNAME_OVERRIDE="Darwin" ENSURE_COORD_SYNC_LOG_PATH="$d1_log" HARNESS_SELFTEST=0 \
      ENSURE_COORD_SYNC_SCRIPT_OVERRIDE="$fake_script" \
      ENSURE_COORD_SYNC_LAUNCHAGENTS_DIR="$d1_la" ENSURE_COORD_SYNC_PLIST_LABEL="test.d1.coord-sync" \
      ENSURE_COORD_SYNC_LAUNCHCTL_OVERRIDE="$d1_launchctl" ENSURE_COORD_SYNC_INTERVAL_SECONDS=45 \
      "$bash_bin" -c "source '$self_abs'; run_ensure" )
  local d1_out; d1_out="$(cat "$d1_log" 2>/dev/null || true)"
  local d1_plist="$d1_la/test.d1.coord-sync.plist" d1_plist_content=""
  if [[ -f "$d1_plist" ]]; then
    echo "PASS: D1 fresh install writes the plist file"; pass=$((pass + 1))
    d1_plist_content="$(cat "$d1_plist" 2>/dev/null)"
  else
    echo "FAIL: D1 fresh install plist missing at $d1_plist" >&2; fail=$((fail + 1))
  fi
  _ck_contains "D1 plist names the resolved fixture script" "$d1_plist_content" "$fake_script"
  _ck_contains "D1 plist carries StartInterval 45" "$d1_plist_content" "<integer>45</integer>"
  _ck_contains "D1 plist carries RunAtLoad" "$d1_plist_content" "<key>RunAtLoad</key>"
  _ck_not_contains "D1 plist carries NO KeepAlive key (StartInterval job, not a daemon)" "$d1_plist_content" "KeepAlive"
  _ck_contains "D1 plist carries a PATH env var" "$d1_plist_content" "<key>PATH</key>"
  local d1_boot_count; d1_boot_count="$(_count_lines_if_exists "$d1_state/bootstrap.log")"
  _ck_eq "D1 fresh install calls launchctl bootstrap exactly once" "$d1_boot_count" "1"
  _ck_contains "D1 logs the plist write" "$d1_out" "plist written/refreshed"
  _ck_contains "D1 logs the bootstrap success" "$d1_out" "launchctl bootstrap succeeded"

  # ---- D2: idempotent second run — SAME fixture/state/label, run again
  # without resetting fake-launchctl's "loaded" state -> plist unchanged,
  # bootstrap NOT called again (still 1 total). ----
  local d2_log="$tmp/d2.log"
  ( ENSURE_COORD_SYNC_UNAME_OVERRIDE="Darwin" ENSURE_COORD_SYNC_LOG_PATH="$d2_log" HARNESS_SELFTEST=0 \
      ENSURE_COORD_SYNC_SCRIPT_OVERRIDE="$fake_script" \
      ENSURE_COORD_SYNC_LAUNCHAGENTS_DIR="$d1_la" ENSURE_COORD_SYNC_PLIST_LABEL="test.d1.coord-sync" \
      ENSURE_COORD_SYNC_LAUNCHCTL_OVERRIDE="$d1_launchctl" ENSURE_COORD_SYNC_INTERVAL_SECONDS=45 \
      "$bash_bin" -c "source '$self_abs'; run_ensure" )
  local d2_out; d2_out="$(cat "$d2_log" 2>/dev/null || true)"
  local d2_boot_count; d2_boot_count="$(_count_lines_if_exists "$d1_state/bootstrap.log")"
  _ck_eq "D2 idempotent second run does NOT call bootstrap again (still 1 total)" "$d2_boot_count" "1"
  _ck_contains "D2 logs already-bootstrapped no-op" "$d2_out" "already bootstrapped — no-op"
  _ck_not_contains "D2 second run never rewrites an unchanged plist" "$d2_out" "plist written/refreshed"

  # ---- D3: content change (interval 45 -> 90) while loaded -> bootout
  # THEN bootstrap (2 total bootstraps, 1 bootout), never an additive
  # second load. ----
  local d3_log="$tmp/d3.log"
  ( ENSURE_COORD_SYNC_UNAME_OVERRIDE="Darwin" ENSURE_COORD_SYNC_LOG_PATH="$d3_log" HARNESS_SELFTEST=0 \
      ENSURE_COORD_SYNC_SCRIPT_OVERRIDE="$fake_script" \
      ENSURE_COORD_SYNC_LAUNCHAGENTS_DIR="$d1_la" ENSURE_COORD_SYNC_PLIST_LABEL="test.d1.coord-sync" \
      ENSURE_COORD_SYNC_LAUNCHCTL_OVERRIDE="$d1_launchctl" ENSURE_COORD_SYNC_INTERVAL_SECONDS=90 \
      "$bash_bin" -c "source '$self_abs'; run_ensure" )
  local d3_out; d3_out="$(cat "$d3_log" 2>/dev/null || true)"
  local d3_boot_count d3_bootout_count
  d3_boot_count="$(_count_lines_if_exists "$d1_state/bootstrap.log")"
  d3_bootout_count="$(_count_lines_if_exists "$d1_state/bootout.log")"
  _ck_eq "D3 content change (StartInterval 45->90) triggers exactly ONE bootout" "$d3_bootout_count" "1"
  _ck_eq "D3 content change triggers a SECOND bootstrap (2 total)" "$d3_boot_count" "2"
  _ck_contains "D3 refreshed plist now carries the new interval" "$(cat "$d1_plist" 2>/dev/null)" "<integer>90</integer>"

  # ---- D4: missing bash -> tolerate-absent, no plist written. ----
  local d4_log="$tmp/d4.log" d4_la="$tmp/d4-la"
  ( ENSURE_COORD_SYNC_UNAME_OVERRIDE="Darwin" ENSURE_COORD_SYNC_LOG_PATH="$d4_log" HARNESS_SELFTEST=0 \
      ENSURE_COORD_SYNC_SCRIPT_OVERRIDE="$fake_script" ENSURE_COORD_SYNC_FORCE_NO_BASH=1 \
      ENSURE_COORD_SYNC_LAUNCHAGENTS_DIR="$d4_la" \
      "$bash_bin" -c "source '$self_abs'; run_ensure" )
  local d4_out; d4_out="$(cat "$d4_log" 2>/dev/null || true)"
  _ck_contains "D4 missing bash tolerates absent" "$d4_out" "bash not found on PATH"
  if [[ ! -e "$d4_la" ]] || [[ -z "$(ls -A "$d4_la" 2>/dev/null)" ]]; then
    echo "PASS: D4 must not write a plist when bash is unresolvable"; pass=$((pass + 1))
  else
    echo "FAIL: D4 unexpectedly wrote into $d4_la with bash unresolvable" >&2; fail=$((fail + 1))
  fi

  # ========================================================================
  # CREDENTIAL scenarios — GIT_CONFIG_GLOBAL sandboxes ALL git --global
  # reads/writes to a fixture file (git >= 2.32); the REAL ~/.gitconfig is
  # never touched by any of these.
  # ========================================================================
  local c_home="$tmp/c-home"; mkdir -p "$c_home/.claude/local"

  # ---- C1: github https URL configured + a token IS resolvable -> the
  # URL-scoped reset+helper pair is installed. ----
  local c1_gitconfig="$tmp/c1-gitconfig"
  printf '%s\n' "https://github.com/exampleowner/examplerepo.git" > "$c_home/.claude/local/coord-repo-url.txt"
  ( HOME="$c_home" GIT_CONFIG_GLOBAL="$c1_gitconfig" ENSURE_COORD_SYNC_UNAME_OVERRIDE="Linux" HARNESS_SELFTEST=0 \
      ENSURE_COORD_SYNC_GH_TOKEN_CMD='echo fake-token-value' \
      "$bash_bin" -c "source '$self_abs'; _ecs_ensure_repo_credential" >/dev/null 2>&1 )
  local c1_cfg; c1_cfg="$(cat "$c1_gitconfig" 2>/dev/null || true)"
  _ck_contains "C1 installs a credential section for the resolved URL" "$c1_cfg" 'credential "https://github.com/exampleowner/examplerepo.git"'
  _ck_contains "C1 helper resolves via gh auth token -u <owner>" "$c1_cfg" "gh auth token -u exampleowner"
  _ck_contains "C1 helper prints a username= line" "$c1_cfg" "username=%s"
  _ck_contains "C1 helper echoes the parsed owner as the username value" "$c1_cfg" "'exampleowner'"

  # ---- C2: same URL, but no gh token resolvable for that owner ->
  # tolerate-absent, gitconfig fixture stays untouched. ----
  local c2_gitconfig="$tmp/c2-gitconfig"
  ( HOME="$c_home" GIT_CONFIG_GLOBAL="$c2_gitconfig" ENSURE_COORD_SYNC_UNAME_OVERRIDE="Linux" HARNESS_SELFTEST=0 \
      ENSURE_COORD_SYNC_GH_TOKEN_CMD='true' \
      "$bash_bin" -c "source '$self_abs'; _ecs_ensure_repo_credential" >/dev/null 2>&1 )
  if [[ ! -f "$c2_gitconfig" ]]; then
    echo "PASS: C2 no-token-for-owner -> gitconfig fixture never created"; pass=$((pass + 1))
  else
    echo "FAIL: C2 unexpectedly wrote $c2_gitconfig with no token resolvable" >&2; fail=$((fail + 1))
  fi

  # ---- C3: SSH-form URL -> skipped, gitconfig fixture untouched. ----
  local c3_home="$tmp/c3-home" c3_gitconfig="$tmp/c3-gitconfig"
  mkdir -p "$c3_home/.claude/local"
  printf '%s\n' "git@github.com:exampleowner/examplerepo.git" > "$c3_home/.claude/local/coord-repo-url.txt"
  ( HOME="$c3_home" GIT_CONFIG_GLOBAL="$c3_gitconfig" ENSURE_COORD_SYNC_UNAME_OVERRIDE="Linux" HARNESS_SELFTEST=0 \
      ENSURE_COORD_SYNC_GH_TOKEN_CMD='echo fake-token-value' \
      "$bash_bin" -c "source '$self_abs'; _ecs_ensure_repo_credential" >/dev/null 2>&1 )
  if [[ ! -f "$c3_gitconfig" ]]; then
    echo "PASS: C3 SSH-form URL -> gitconfig fixture never created"; pass=$((pass + 1))
  else
    echo "FAIL: C3 unexpectedly wrote $c3_gitconfig for an SSH-form URL" >&2; fail=$((fail + 1))
  fi

  # ---- C4: no coord repo URL configured at all -> skipped gracefully. ----
  local c4_home="$tmp/c4-home" c4_gitconfig="$tmp/c4-gitconfig"
  mkdir -p "$c4_home/.claude/local"
  ( HOME="$c4_home" GIT_CONFIG_GLOBAL="$c4_gitconfig" ENSURE_COORD_SYNC_UNAME_OVERRIDE="Linux" HARNESS_SELFTEST=0 \
      unset COORD_REPO_URL COORD_CLONE_DIR 2>/dev/null;
      "$bash_bin" -c "source '$self_abs'; _ecs_ensure_repo_credential" >/dev/null 2>&1 )
  local c4_rc=$?
  _ck_eq "C4 no coord repo URL configured -> exits 0" "$c4_rc" "0"
  if [[ ! -f "$c4_gitconfig" ]]; then
    echo "PASS: C4 nothing configured -> gitconfig fixture never created"; pass=$((pass + 1))
  else
    echo "FAIL: C4 unexpectedly wrote $c4_gitconfig with nothing configured" >&2; fail=$((fail + 1))
  fi

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
# Entry point — guarded so `source`-ing this file (self-test harness /
# scenario helpers calling _ecs_ensure_repo_credential directly) never
# falls through to a real invocation.
# ============================================================
if [[ "${BASH_SOURCE[0]:-$0}" == "${0}" ]]; then
  case "${1:-}" in
    --self-test)
      run_self_test
      exit $?
      ;;
    --help|-h)
      sed -n '2,140p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      run_ensure
      if [[ "${HARNESS_SELFTEST:-0}" == "1" && -z "${ENSURE_COORD_SYNC_LOG_PATH:-}" ]]; then
        rm -rf "${TMPDIR:-/tmp}/ensure-coord-sync-selftest/${$}" 2>/dev/null || true
      fi
      exit 0
      ;;
  esac
fi
