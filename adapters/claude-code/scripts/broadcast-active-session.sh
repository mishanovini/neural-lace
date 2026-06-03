#!/usr/bin/env bash
# broadcast-active-session.sh — cross-computer active-session coordination.
#
# Item 7 of the git-best-practices 9-item initiative.
#
# WHAT IT DOES
# Each NL-context session writes a small JSON broadcast to a reserved
# branch on the canonical remote (`harness/active-sessions/<hostname>`)
# at session start. Other computers' SessionStart sees recent
# broadcasts from OTHER hostnames and surfaces them — so a session on
# laptop knows desktop_pc has an open session on the same repo, before
# both diverge.
#
# Subcommands:
#   write      — push current state to the reserved branch (idempotent;
#                throttled — skipped silently if last broadcast was
#                less than $BROADCAST_THROTTLE_SECONDS ago, default 300).
#   check      — list other-hostname recent broadcasts and surface them.
#   clear      — best-effort: PUT an empty state to mark this hostname
#                no-longer-active (call from end-of-session manually).
#   --self-test
#
# DESIGN DECISIONS (v1, 2026-05-29)
# - Push target: origin only. Cross-remote (PT + personal) visibility
#   would need cross-account gh auth switching per remote. v2 work.
# - Storage: a single `state.json` blob on branch
#   `harness/active-sessions/<hostname>`, written via GitHub Contents
#   API (no local working-tree switch needed). Branch is created on
#   first write if absent.
# - Staleness: broadcasts whose iso_timestamp is older than
#   $BROADCAST_FRESH_HOURS (default 2h) are considered stale by the
#   check subcommand. No explicit cleanup needed; staleness expires
#   naturally.
# - There is no Claude Code SessionEnd hook today. The original spec
#   assumed one for explicit cleanup. v1 uses timestamp staleness
#   instead; `clear` is provided for manual / future-SessionEnd use.
#
# AUTHENTICATION
# - gh CLI handles auth via the currently-active gh account for the
#   remote's owner. A clone whose origin points at one org needs the
#   gh account authenticated to push to THAT org to be active. A
#   mismatched account returns 403 -> the script logs a WARN and
#   returns 0 (non-blocking — broadcast is informational, never the
#   load-bearing primary path).

set -u

# ============================================================
# Constants
# ============================================================

BROADCAST_THROTTLE_SECONDS="${BROADCAST_THROTTLE_SECONDS:-300}"
BROADCAST_FRESH_HOURS="${BROADCAST_FRESH_HOURS:-2}"
BROADCAST_BRANCH_PREFIX="harness/active-sessions"
BROADCAST_STATE_FILE="state.json"
STATE_DIR="${HOME}/.claude/state/active-session-broadcast"
LOCAL_THROTTLE_FILE="$STATE_DIR/last-broadcast"

# ============================================================
# Helpers
# ============================================================

_log() { printf '[broadcast-active-session] %s\n' "$*" >&2; }
_die() { _log "ERROR: $*"; exit 1; }

# Discover the canonical remote (origin) and parse owner/name.
_origin_owner_name() {
  local url
  url=$(git remote get-url --push origin 2>/dev/null || echo "")
  case "$url" in
    https://github.com/*) url="${url#https://github.com/}"; url="${url%.git}"; printf '%s' "$url" ;;
    git@github.com:*)     url="${url#git@github.com:}"; url="${url%.git}"; printf '%s' "$url" ;;
    # SSH host-alias remotes (e.g. `git@<alias>:Owner/Repo.git` from a
    # ~/.ssh/config `Host <alias>` entry that selects a per-account key).
    # gh api uses the active gh account, not SSH, so only owner/name matters.
    git@*:*/*)            url="${url#git@*:}"; url="${url%.git}"; printf '%s' "$url" ;;
    # Non-github HTTPS hosts (GHE / custom). Strips scheme+host, keeps owner/name.
    https://*/*/*)        url="${url#https://*/}"; url="${url%.git}"; printf '%s' "$url" ;;
    *) printf '' ;;
  esac
}

# Get current hostname (best-effort).
_hostname() {
  local h
  h=$(hostname 2>/dev/null || echo "")
  [ -n "$h" ] || h="${HOSTNAME:-unknown-host}"
  # Replace non-alphanum-or-dash with dash so it's a valid git ref segment.
  printf '%s' "$h" | tr -c 'A-Za-z0-9._-' '-'
}

# Current branch (or "(detached)").
_current_branch() {
  git symbolic-ref --short -q HEAD 2>/dev/null || echo "(detached)"
}

# Has tracked uncommitted changes (true/false).
_has_uncommitted() {
  if git diff --quiet 2>/dev/null && git diff --cached --quiet 2>/dev/null; then
    echo "false"
  else
    echo "true"
  fi
}

# Build the state JSON for the current session.
_build_state_json() {
  local hostname iso_ts cwd current_branch dirty origin_url
  hostname="$(_hostname)"
  iso_ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  cwd="$(pwd)"
  current_branch="$(_current_branch)"
  dirty="$(_has_uncommitted)"
  origin_url="$(git remote get-url --push origin 2>/dev/null || echo '')"

  # JSON via printf — escape backslashes and quotes in string values.
  _json_str() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

  cat <<JSON
{
  "hostname": "$(_json_str "$hostname")",
  "iso_timestamp": "$iso_ts",
  "working_directory": "$(_json_str "$cwd")",
  "current_branch": "$(_json_str "$current_branch")",
  "git_remote_url": "$(_json_str "$origin_url")",
  "uncommitted_changes": $dirty
}
JSON
}

# Convert ISO 8601 timestamp to epoch seconds (best-effort across
# GNU date + macOS date).
_iso_to_epoch() {
  local iso="$1"
  date -u -d "$iso" +%s 2>/dev/null \
    || date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$iso" +%s 2>/dev/null \
    || echo 0
}

# Throttle check: returns 0 if a write is allowed (last write older
# than $BROADCAST_THROTTLE_SECONDS), non-zero if throttled.
_throttle_allows_write() {
  [ -f "$LOCAL_THROTTLE_FILE" ] || return 0
  local last_epoch now diff
  last_epoch=$(cat "$LOCAL_THROTTLE_FILE" 2>/dev/null || echo 0)
  now=$(date +%s)
  diff=$((now - last_epoch))
  [ "$diff" -ge "$BROADCAST_THROTTLE_SECONDS" ]
}

# Record a successful write to the throttle file.
_record_write() {
  mkdir -p "$STATE_DIR" 2>/dev/null || return 0
  date +%s > "$LOCAL_THROTTLE_FILE" 2>/dev/null || true
}

# Get the default branch's HEAD commit SHA from the canonical remote.
_default_branch_sha() {
  local owner_name="$1"
  gh api "repos/${owner_name}/branches/master" --jq '.commit.sha' 2>/dev/null || \
  gh api "repos/${owner_name}/branches/main" --jq '.commit.sha' 2>/dev/null || \
  echo ""
}

# ============================================================
# Subcommands
# ============================================================

_cmd_write() {
  local owner_name hostname branch_name state_json existing_sha default_sha b64
  owner_name="$(_origin_owner_name)"
  [ -n "$owner_name" ] || _die "could not parse origin URL"

  if ! _throttle_allows_write; then
    return 0  # Silent throttle skip.
  fi

  hostname="$(_hostname)"
  branch_name="${BROADCAST_BRANCH_PREFIX}/${hostname}"
  state_json="$(_build_state_json)"

  # Ensure the branch exists (create from default branch HEAD if absent).
  # Note: gh api with --jq emits error JSON to stdout on 404; check exit code.
  if gh api "repos/${owner_name}/branches/${branch_name}" --jq '.commit.sha' >/dev/null 2>&1; then
    existing_sha=$(gh api "repos/${owner_name}/branches/${branch_name}" --jq '.commit.sha' 2>/dev/null)
  else
    existing_sha=""
  fi
  if [ -z "$existing_sha" ]; then
    default_sha="$(_default_branch_sha "$owner_name")"
    if [ -z "$default_sha" ]; then
      _log "WARN: cannot resolve default branch SHA for ${owner_name}; skipping broadcast"
      return 0
    fi
    if ! gh api "repos/${owner_name}/git/refs" -X POST -f ref="refs/heads/${branch_name}" -f sha="$default_sha" >/dev/null 2>&1; then
      _log "WARN: cannot create branch ${branch_name} on ${owner_name}; skipping broadcast"
      return 0
    fi
  fi

  # PUT state.json to the branch via Contents API.
  b64=$(printf '%s' "$state_json" | base64 | tr -d '\n')
  if gh api "repos/${owner_name}/contents/${BROADCAST_STATE_FILE}?ref=${branch_name}" --jq '.sha' >/dev/null 2>&1; then
    existing_file_sha=$(gh api "repos/${owner_name}/contents/${BROADCAST_STATE_FILE}?ref=${branch_name}" --jq '.sha' 2>/dev/null)
  else
    existing_file_sha=""
  fi
  local msg="broadcast active-session: ${hostname} $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  if [ -n "$existing_file_sha" ]; then
    if gh api "repos/${owner_name}/contents/${BROADCAST_STATE_FILE}" -X PUT \
        -f message="$msg" -f content="$b64" -f branch="$branch_name" -f sha="$existing_file_sha" >/dev/null 2>&1; then
      _record_write
      _log "broadcast written to ${owner_name}@${branch_name}"
    else
      _log "WARN: PUT failed for existing state.json on ${branch_name}"
    fi
  else
    if gh api "repos/${owner_name}/contents/${BROADCAST_STATE_FILE}" -X PUT \
        -f message="$msg" -f content="$b64" -f branch="$branch_name" >/dev/null 2>&1; then
      _record_write
      _log "broadcast written to ${owner_name}@${branch_name} (first push)"
    else
      _log "WARN: PUT failed for new state.json on ${branch_name}"
    fi
  fi
}

_cmd_check() {
  local owner_name my_hostname now_epoch fresh_seconds
  owner_name="$(_origin_owner_name)"
  [ -n "$owner_name" ] || return 0  # Not a github repo or no origin → silent.

  my_hostname="$(_hostname)"
  now_epoch=$(date +%s)
  fresh_seconds=$((BROADCAST_FRESH_HOURS * 3600))

  # List branches matching our reserved namespace.
  local branches_json
  branches_json=$(gh api "repos/${owner_name}/branches" --paginate --jq '.[].name' 2>/dev/null \
    | grep -F "${BROADCAST_BRANCH_PREFIX}/" || true)
  [ -z "$branches_json" ] && return 0

  local out=""
  local count=0
  local branch_name remote_hostname state_json iso_ts cwd br dirty ts_epoch age
  while IFS= read -r branch_name; do
    [ -z "$branch_name" ] && continue
    remote_hostname="${branch_name#${BROADCAST_BRANCH_PREFIX}/}"
    # Skip our own broadcast.
    [ "$remote_hostname" = "$my_hostname" ] && continue

    # Fetch state.json from the branch. Check exit code, not output content
    # (gh api emits error JSON to stdout on 404; we'd misparse it otherwise).
    if ! gh api "repos/${owner_name}/contents/${BROADCAST_STATE_FILE}?ref=${branch_name}" --jq '.content' >/dev/null 2>&1; then
      continue
    fi
    state_json=$(gh api "repos/${owner_name}/contents/${BROADCAST_STATE_FILE}?ref=${branch_name}" --jq '.content' 2>/dev/null | tr -d '\n' | base64 -d 2>/dev/null || true)
    [ -z "$state_json" ] && continue

    iso_ts=$(printf '%s' "$state_json" | sed -nE 's/.*"iso_timestamp"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' | head -1)
    cwd=$(printf '%s' "$state_json" | sed -nE 's/.*"working_directory"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' | head -1)
    br=$(printf '%s' "$state_json" | sed -nE 's/.*"current_branch"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' | head -1)
    dirty=$(printf '%s' "$state_json" | sed -nE 's/.*"uncommitted_changes"[[:space:]]*:[[:space:]]*(true|false).*/\1/p' | head -1)

    [ -z "$iso_ts" ] && continue
    ts_epoch=$(_iso_to_epoch "$iso_ts")
    [ "$ts_epoch" = "0" ] && continue
    age=$((now_epoch - ts_epoch))

    # Only surface FRESH broadcasts (<= fresh_seconds old).
    if [ "$age" -le "$fresh_seconds" ]; then
      count=$((count + 1))
      local minutes=$((age / 60))
      out+="  • ${remote_hostname} — branch '${br}' in '${cwd}'; uncommitted=${dirty}; broadcast ${minutes}m ago"$'\n'
    fi
  done <<< "$branches_json"

  if [ "$count" -gt 0 ]; then
    echo ""
    echo "[active-session-broadcast] ${count} other computer(s) currently active on ${owner_name}:"
    printf '%s' "$out"
    echo "  Coordinate before making competing changes (pull --rebase, communicate)."
    echo ""
  fi
}

_cmd_clear() {
  local owner_name hostname branch_name empty_json b64 existing_file_sha
  owner_name="$(_origin_owner_name)"
  [ -n "$owner_name" ] || return 0

  hostname="$(_hostname)"
  branch_name="${BROADCAST_BRANCH_PREFIX}/${hostname}"

  # Empty state: signal "no active session here."
  empty_json='{"hostname":"'"$hostname"'","iso_timestamp":"1970-01-01T00:00:00Z","cleared":true}'
  b64=$(printf '%s' "$empty_json" | base64 | tr -d '\n')
  if gh api "repos/${owner_name}/contents/${BROADCAST_STATE_FILE}?ref=${branch_name}" --jq '.sha' >/dev/null 2>&1; then
    existing_file_sha=$(gh api "repos/${owner_name}/contents/${BROADCAST_STATE_FILE}?ref=${branch_name}" --jq '.sha' 2>/dev/null)
  else
    existing_file_sha=""
  fi
  if [ -n "$existing_file_sha" ]; then
    gh api "repos/${owner_name}/contents/${BROADCAST_STATE_FILE}" -X PUT \
      -f message="clear active-session broadcast: ${hostname}" -f content="$b64" \
      -f branch="$branch_name" -f sha="$existing_file_sha" >/dev/null 2>&1 \
      && _log "broadcast cleared for ${hostname}" \
      || _log "WARN: clear failed for ${branch_name}"
  fi
}

# ============================================================
# Self-test
# ============================================================

_self_test() {
  local pass=0 fail=0

  # S1 — _build_state_json produces valid JSON with required fields.
  (
    cd "$(mktemp -d)"
    git init --quiet
    git config user.email "t@example.com" && git config user.name "T"
    json="$(_build_state_json)"
    if echo "$json" | grep -q '"hostname"' && \
       echo "$json" | grep -q '"iso_timestamp"' && \
       echo "$json" | grep -q '"working_directory"' && \
       echo "$json" | grep -q '"current_branch"' && \
       echo "$json" | grep -q '"uncommitted_changes"'; then
      echo "  S1 build_state_json schema: PASS"
    else
      echo "  S1 build_state_json schema: FAIL"; return 1
    fi
  ) && pass=$((pass+1)) || fail=$((fail+1))

  # S2 — sanitization-via-tr (the actual logic in _hostname's tail).
  raw="my host & spaces"
  cleaned="$(printf '%s' "$raw" | tr -c 'A-Za-z0-9._-' '-')"
  if [ "$cleaned" = "my-host---spaces" ]; then
    echo "  S2 hostname sanitization clean: PASS"; pass=$((pass+1))
  else
    echo "  S2 hostname sanitization clean: FAIL (got '$cleaned')"; fail=$((fail+1))
  fi

  # S3 — _origin_owner_name parses HTTPS / SSH URLs.
  (
    tmp=$(mktemp -d)
    cd "$tmp"
    git init --quiet
    git remote add origin "https://github.com/example-org/example-repo.git"
    got="$(_origin_owner_name)"
    [ "$got" = "example-org/example-repo" ] || { echo "  S3 origin-owner HTTPS: FAIL ($got)"; exit 1; }
    git remote remove origin
    git remote add origin "git@github.com:other-user/other-repo.git"
    got="$(_origin_owner_name)"
    [ "$got" = "other-user/other-repo" ] || { echo "  S3 origin-owner SSH: FAIL ($got)"; exit 1; }
    # SSH host-alias remote (e.g. a ~/.ssh/config Host alias selecting a per-account key):
    # git@<alias>:owner/repo.git — gh api uses the active account, so only owner/name matters.
    git remote remove origin
    git remote add origin "git@gh-alias:example-org/example-repo.git"
    got="$(_origin_owner_name)"
    [ "$got" = "example-org/example-repo" ] || { echo "  S3 origin-owner SSH-alias: FAIL ($got)"; exit 1; }
    # Non-github HTTPS host (GHE / custom)
    git remote remove origin
    git remote add origin "https://ghe.example.com/grp/proj.git"
    got="$(_origin_owner_name)"
    [ "$got" = "grp/proj" ] || { echo "  S3 origin-owner HTTPS-custom: FAIL ($got)"; exit 1; }
    echo "  S3 origin-owner parsing: PASS"
  ) && pass=$((pass+1)) || fail=$((fail+1))

  # S4 — throttle returns true on first call (no state file), false within window.
  (
    export STATE_DIR="$(mktemp -d)"
    LOCAL_THROTTLE_FILE="$STATE_DIR/last-broadcast"
    _throttle_allows_write && true || { echo "  S4 throttle first-call: FAIL"; exit 1; }
    _record_write
    if _throttle_allows_write; then
      echo "  S4 throttle blocks within window: FAIL"; exit 1
    fi
    echo "  S4 throttle: PASS"
  ) && pass=$((pass+1)) || fail=$((fail+1))

  # S5 — _iso_to_epoch round-trips: convert now to ISO, then ISO back to epoch, within 1s.
  now_epoch=$(date -u +%s)
  iso_now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  got_epoch="$(_iso_to_epoch "$iso_now")"
  diff=$(( got_epoch > now_epoch ? got_epoch - now_epoch : now_epoch - got_epoch ))
  if [ "$diff" -le 1 ]; then
    echo "  S5 iso-to-epoch round-trip: PASS"; pass=$((pass+1))
  else
    echo "  S5 iso-to-epoch round-trip: FAIL (got '$got_epoch', expected ~'$now_epoch', diff=$diff)"; fail=$((fail+1))
  fi

  # S6 — check subcommand is silent in a repo with no origin remote (or no broadcasts).
  (
    tmp=$(mktemp -d)
    cd "$tmp"
    git init --quiet
    out="$(_cmd_check 2>&1)"
    if [ -z "$out" ]; then echo "  S6 check no-origin silent: PASS"
    else echo "  S6 check no-origin silent: FAIL (got: $out)"; return 1; fi
  ) && pass=$((pass+1)) || fail=$((fail+1))

  echo ""
  echo "[self-test] $pass passed, $fail failed"
  return $fail
}

# ============================================================
# Entry point
# ============================================================

case "${1:-}" in
  write)        _cmd_write ;;
  check)        _cmd_check ;;
  clear)        _cmd_clear ;;
  --self-test)  _self_test; exit $? ;;
  -h|--help|"")
    cat <<'BROADCAST_USAGE_END' >&2
broadcast-active-session.sh — cross-computer active-session coordination.

USAGE
  broadcast-active-session.sh write       # push current state to reserved branch
  broadcast-active-session.sh check       # surface other-hostname recent broadcasts
  broadcast-active-session.sh clear       # mark this hostname no-longer-active
  broadcast-active-session.sh --self-test

ENV
  BROADCAST_THROTTLE_SECONDS  Throttle window for write (default 300 = 5 min)
  BROADCAST_FRESH_HOURS       Freshness window for check (default 2h)

Storage: a single state.json file on branch
'harness/active-sessions/<hostname>' on the canonical remote (origin),
written via the GitHub Contents API. Stale broadcasts (older than the
freshness window) are filtered out by check; no explicit cleanup needed.
BROADCAST_USAGE_END
    exit 2
    ;;
  *)
    echo "broadcast-active-session.sh: unknown subcommand '$1'" >&2
    exit 2
    ;;
esac
