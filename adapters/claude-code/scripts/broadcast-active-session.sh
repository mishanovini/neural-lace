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
#                ALSO writes a local same-machine per-branch claim (v2).
#   check      — list other-hostname recent broadcasts and surface them,
#                PLUS same-machine other worktrees + fresh other-session
#                claims (v2 — the lesson-2026-07-11 same-machine hole).
#   claim      — [<branch>] [<plan-slug>]: write a local per-branch claim
#                file to $STATE_DIR/claims/ so the concurrent-ownership
#                gate can see same-machine ownership. Defaults: current
#                branch, no plan slug.
#   unclaim    — [<branch>]: remove this session's claim file.
#   clear      — best-effort: PUT an empty state to mark this hostname
#                no-longer-active (call from end-of-session manually).
#   --self-test
#
# v2 EXTENSION (2026-07-12, concurrent-ownership-gate plan; lesson
# 2026-07-11-bulk-shared-state-mutation-without-ownership-check):
# v1 was per-hostname and other-machines-only — structurally blind to a
# same-machine concurrent worktree, the exact collision the lesson records.
# v2 adds (a) a `worktrees` array in state.json (ADDITIVE — the only
# state.json consumers are this script's own `check` sed-extraction and the
# SessionStart template invocation, both tolerant of new fields) and
# (b) local per-branch claim files under $STATE_DIR/claims/, freshness by
# file mtime, consumed by hooks/concurrent-ownership-gate.sh.
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
# STATE_DIR is env-overridable (BROADCAST_STATE_DIR) and sandboxed under
# HARNESS_SELFTEST=1 so self-tests never touch the operator's real state.
if [ "${HARNESS_SELFTEST:-0}" = "1" ]; then
  STATE_DIR="${BROADCAST_STATE_DIR:-${TMPDIR:-/tmp}/broadcast-selftest-$$}"
else
  STATE_DIR="${BROADCAST_STATE_DIR:-${HOME}/.claude/state/active-session-broadcast}"
fi
LOCAL_THROTTLE_FILE="$STATE_DIR/last-broadcast"
# Same-machine per-branch claims (v2). Shared with
# hooks/concurrent-ownership-gate.sh (its COG_CLAIMS_DIR default).
CLAIMS_DIR="${BROADCAST_CLAIMS_DIR:-$STATE_DIR/claims}"
CLAIM_FRESH_SECONDS="${BROADCAST_CLAIM_FRESH_SECONDS:-7200}"

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

# JSON string escaping — escape backslashes and quotes in string values.
_json_str() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

# Same-machine worktrees of the current repo as a JSON array (v2):
#   [{"path":"...","branch":"..."}, ...]
# Detached-HEAD entries (no branch line) are skipped. Emits [] outside a
# git repo or on any parse failure — additive field, never load-bearing
# for v1 consumers.
_worktrees_json() {
  local out="" cur_path="" line first=1
  while IFS= read -r line; do
    case "$line" in
      "worktree "*) cur_path="${line#worktree }" ;;
      "branch refs/heads/"*)
        local br="${line#branch refs/heads/}"
        if [ -n "$cur_path" ]; then
          [ "$first" -eq 1 ] && first=0 || out+=","
          out+="{\"path\":\"$(_json_str "$cur_path")\",\"branch\":\"$(_json_str "$br")\"}"
        fi
        ;;
      "") cur_path="" ;;
    esac
  done < <(git worktree list --porcelain 2>/dev/null)
  printf '[%s]' "$out"
}

# List OTHER worktrees of the current repo (excluding the current one) as
# tab-separated "path<TAB>branch" lines. Used by the check subcommand.
_other_worktrees() {
  local cur_root cur_path="" line
  cur_root=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
  [ -n "$cur_root" ] || return 0
  while IFS= read -r line; do
    case "$line" in
      "worktree "*) cur_path="${line#worktree }" ;;
      "branch refs/heads/"*)
        local br="${line#branch refs/heads/}"
        if [ -n "$cur_path" ] && [ "$cur_path" != "$cur_root" ]; then
          printf '%s\t%s\n' "$cur_path" "$br"
        fi
        ;;
      "") cur_path="" ;;
    esac
  done < <(git worktree list --porcelain 2>/dev/null)
}

# Build the state JSON for the current session.
_build_state_json() {
  local hostname iso_ts cwd current_branch dirty origin_url worktrees
  hostname="$(_hostname)"
  iso_ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  cwd="$(pwd)"
  current_branch="$(_current_branch)"
  dirty="$(_has_uncommitted)"
  origin_url="$(git remote get-url --push origin 2>/dev/null || echo '')"
  worktrees="$(_worktrees_json)"

  cat <<JSON
{
  "hostname": "$(_json_str "$hostname")",
  "iso_timestamp": "$iso_ts",
  "working_directory": "$(_json_str "$cwd")",
  "current_branch": "$(_json_str "$current_branch")",
  "git_remote_url": "$(_json_str "$origin_url")",
  "uncommitted_changes": $dirty,
  "worktrees": $worktrees
}
JSON
}

# Sanitize a branch name into a claim filename segment.
_claim_key() {
  printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '-'
}

# Write a local per-branch claim file (v2). $1 = branch (default: current),
# $2 = plan slug (optional). Never fails the caller.
_cmd_claim() {
  local branch="${1:-}" plan="${2:-}" wt key
  [ -n "$branch" ] || branch="$(_current_branch)"
  [ -n "$branch" ] || return 0
  [ "$branch" = "(detached)" ] && return 0
  wt=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
  key="$(_claim_key "$branch")"
  mkdir -p "$CLAIMS_DIR" 2>/dev/null || return 0
  cat > "$CLAIMS_DIR/${key}.json" 2>/dev/null <<JSON
{
  "branch": "$(_json_str "$branch")",
  "plan": "$(_json_str "$plan")",
  "worktree": "$(_json_str "$wt")",
  "hostname": "$(_json_str "$(_hostname)")",
  "pid": "$$",
  "iso_timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
JSON
  _log "claim written: ${branch} -> $CLAIMS_DIR/${key}.json"
}

# Remove a claim file. $1 = branch (default: current).
_cmd_unclaim() {
  local branch="${1:-}" key
  [ -n "$branch" ] || branch="$(_current_branch)"
  [ -n "$branch" ] || return 0
  key="$(_claim_key "$branch")"
  rm -f "$CLAIMS_DIR/${key}.json" 2>/dev/null
  _log "claim removed: ${branch}"
}

# Surface same-machine coordination state (v2): other worktrees of this
# repo + fresh other-session claims. Informational, never blocks.
_check_local() {
  local cur_root cur_branch out="" count=0 line p b
  cur_root=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
  cur_branch="$(_current_branch)"

  while IFS=$'\t' read -r p b; do
    [ -z "$p" ] && continue
    count=$((count + 1))
    out+="  • worktree ${p} — branch '${b}'"$'\n'
  done < <(_other_worktrees)

  # Fresh claims from other sessions (worktree != ours, branch != ours).
  if [ -d "$CLAIMS_DIR" ]; then
    local cutoff f br wt ts
    cutoff=$(date -d "-${CLAIM_FRESH_SECONDS} seconds" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "")
    if [ -n "$cutoff" ]; then
      while IFS= read -r f; do
        [ -f "$f" ] || continue
        br=$(sed -nE 's/.*"branch"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' "$f" | head -1)
        wt=$(sed -nE 's/.*"worktree"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' "$f" | head -1)
        ts=$(sed -nE 's/.*"iso_timestamp"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' "$f" | head -1)
        [ -z "$br" ] && continue
        [ "$br" = "$cur_branch" ] && continue
        [ -n "$cur_root" ] && [ "$wt" = "$cur_root" ] && continue
        count=$((count + 1))
        out+="  • claim: branch '${br}' by session in '${wt}' (since ${ts})"$'\n'
      done < <(find "$CLAIMS_DIR" -maxdepth 1 -type f -name '*.json' -newermt "$cutoff" 2>/dev/null)
    fi
  fi

  if [ "$count" -gt 0 ]; then
    echo ""
    echo "[active-session-broadcast] same-machine ownership signals (${count}):"
    printf '%s' "$out"
    echo "  Do not mutate these branches/plans without coordinating — the"
    echo "  concurrent-ownership gate will block Status flips / branch deletes"
    echo "  targeting them."
    echo ""
  fi
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
  # Local same-machine claim first (v2) — cheap, filesystem-only, NOT
  # throttled (the throttle protects the GitHub API, not local writes).
  _cmd_claim || true

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
  # Same-machine signals first (v2) — these work even with no origin remote.
  _check_local

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

  # S7 — claim writes a schema-valid per-branch claim file (v2, sandboxed).
  (
    tmp=$(mktemp -d)
    CLAIMS_DIR="$tmp/claims"
    cd "$tmp"
    git init --quiet
    git config user.email "t@example.com" && git config user.name "T"
    git commit --allow-empty -q -m init
    git checkout -q -b feat/selftest-claim
    _cmd_claim "" "selftest-plan" >/dev/null 2>&1
    f="$CLAIMS_DIR/feat-selftest-claim.json"
    if [ -f "$f" ] \
       && grep -q '"branch": "feat/selftest-claim"' "$f" \
       && grep -q '"plan": "selftest-plan"' "$f" \
       && grep -q '"worktree"' "$f" \
       && grep -q '"iso_timestamp"' "$f"; then
      echo "  S7 claim file schema: PASS"
    else
      echo "  S7 claim file schema: FAIL"; exit 1
    fi
  ) && pass=$((pass+1)) || fail=$((fail+1))

  # S8 — state.json carries the same-machine worktrees array (v2, additive).
  (
    tmp=$(mktemp -d)
    cd "$tmp"
    mkdir main && cd main
    git init --quiet
    git config user.email "t@example.com" && git config user.name "T"
    git commit --allow-empty -q -m init
    git worktree add ../wt2 -b feat/selftest-wt >/dev/null 2>&1
    json="$(_build_state_json)"
    if echo "$json" | grep -q '"worktrees":' \
       && echo "$json" | grep -q 'feat/selftest-wt'; then
      echo "  S8 worktrees array in state.json: PASS"
    else
      echo "  S8 worktrees array in state.json: FAIL (got: $json)"; exit 1
    fi
  ) && pass=$((pass+1)) || fail=$((fail+1))

  # S9 — unclaim removes this session's claim file (v2).
  (
    tmp=$(mktemp -d)
    CLAIMS_DIR="$tmp/claims"
    cd "$tmp"
    git init --quiet
    git config user.email "t@example.com" && git config user.name "T"
    git commit --allow-empty -q -m init
    git checkout -q -b feat/selftest-unclaim
    _cmd_claim >/dev/null 2>&1
    f="$CLAIMS_DIR/feat-selftest-unclaim.json"
    [ -f "$f" ] || { echo "  S9 unclaim: FAIL (claim not written)"; exit 1; }
    _cmd_unclaim >/dev/null 2>&1
    if [ ! -f "$f" ]; then
      echo "  S9 unclaim removes claim: PASS"
    else
      echo "  S9 unclaim removes claim: FAIL (file survived)"; exit 1
    fi
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
  claim)        _cmd_claim "${2:-}" "${3:-}" ;;
  unclaim)      _cmd_unclaim "${2:-}" ;;
  clear)        _cmd_clear ;;
  --self-test)  _self_test; exit $? ;;
  -h|--help|"")
    cat <<'BROADCAST_USAGE_END' >&2
broadcast-active-session.sh — cross-computer active-session coordination.

USAGE
  broadcast-active-session.sh write       # push current state to reserved branch (+ local claim)
  broadcast-active-session.sh check       # surface other-hostname broadcasts + same-machine worktrees/claims
  broadcast-active-session.sh claim [<branch>] [<plan-slug>]   # write local per-branch claim
  broadcast-active-session.sh unclaim [<branch>]               # remove this session's claim
  broadcast-active-session.sh clear       # mark this hostname no-longer-active
  broadcast-active-session.sh --self-test

ENV
  BROADCAST_THROTTLE_SECONDS    Throttle window for write (default 300 = 5 min)
  BROADCAST_FRESH_HOURS         Freshness window for remote check (default 2h)
  BROADCAST_STATE_DIR           Local state dir override (sandboxed under HARNESS_SELFTEST=1)
  BROADCAST_CLAIMS_DIR          Claims dir override (default $STATE_DIR/claims)
  BROADCAST_CLAIM_FRESH_SECONDS Claim freshness for check (default 7200, by mtime)

Storage: a single state.json file on branch
'harness/active-sessions/<hostname>' on the canonical remote (origin),
written via the GitHub Contents API. Stale broadcasts (older than the
freshness window) are filtered out by check; no explicit cleanup needed.
Same-machine (v2): per-branch claim files under $STATE_DIR/claims/ (mtime
freshness, no cleanup needed) + a 'worktrees' array in state.json; consumed
by hooks/concurrent-ownership-gate.sh for ownership checks.
BROADCAST_USAGE_END
    exit 2
    ;;
  *)
    echo "broadcast-active-session.sh: unknown subcommand '$1'" >&2
    exit 2
    ;;
esac
