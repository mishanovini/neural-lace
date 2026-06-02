#!/usr/bin/env bash
# NEURAL-LACE-HOOK
# cross-repo-drift-postpush-gate.sh — PostToolUse hook: after a `git push`, verify
# the configured NL repo pair is NOT left at a post-push CONTENT divergence.
#
# WHY THIS EXISTS (Misha, 2026-06-02): "NL ALWAYS syncs to both remotes. There
# must never be a state where one NL master has something the other doesn't.
# If a commit landed on one remote without landing on the other, that's a
# fail-state — surface as a critical warning." This is the structural fix to the
# sync-deferral pattern that created repeated PT↔personal divergence: the moment
# you push and leave the remotes diverged, you hear about it — not at the next
# session start, not "in follow-on cleanup."
#
# RELATION TO THE SIBLING SessionStart WARNER: `cross-repo-drift-warn.sh` runs
# the SAME poller (`check-cross-repo-drift.sh`, tree-hash compare via the GitHub
# API) at session start. This hook is the POST-PUSH timing-delta: it fires
# immediately after a push so a freshly-created divergence is surfaced at the
# moment it is created, when it is cheapest to reconcile.
#
# WHY ADVISORY (never blocks): the push has already happened by PostToolUse —
# blocking is pointless. And the GitHub API can lag a second behind a push, so a
# hard block would risk a transient false-positive. The signal is a loud CRITICAL
# warning, surfaced on stdout (some Claude Code clients don't show stderr).
#
# POSTURE NOTE: under the divergent-history-identical-content posture (one repo
# canonical, the mirror synced via cherry-pick + non-force push), DIFFERENT
# commit SHAs are expected and fine. Only TREE-HASH (content) divergence is a
# real fail-state. The poller compares tree hashes precisely for this reason.
#
# Behavior:
#   - Reads the tool command from the PostToolUse JSON payload on stdin.
#   - No-op (silent, exit 0) unless the command is a `git push`.
#   - No-op if no drift-pair config exists on this machine (operator not opted in).
#   - Otherwise runs the poller in --quiet mode; on rc=1 (drift) emits a CRITICAL
#     post-push warning. rc=0 (in sync) / rc=2 (unverifiable) → silent.
#   - ALWAYS exits 0 (advisory; never blocks).
#
# Hook event: PostToolUse, matcher "Bash".
# Self-test: invoke with --self-test (uses POLLER_OVERRIDE + CMD_OVERRIDE stubs).

set -u

# ============================================================
# Resolve the poller (prefer runtime mirror, fall back to repo source)
# ============================================================
_resolve_poller() {
  if [ -n "${POLLER_OVERRIDE:-}" ]; then
    printf '%s\n' "$POLLER_OVERRIDE"; return 0
  fi
  local cand
  for cand in \
      "$HOME/.claude/scripts/check-cross-repo-drift.sh" \
      "$HOME/claude-projects/neural-lace/adapters/claude-code/scripts/check-cross-repo-drift.sh" \
      "$(dirname "$0")/../scripts/check-cross-repo-drift.sh"; do
    if [ -f "$cand" ]; then printf '%s\n' "$cand"; return 0; fi
  done
  printf '%s\n' ""
}

# Extract the tool command. CMD_OVERRIDE wins (self-test); else parse stdin JSON.
_read_command() {
  if [ -n "${CMD_OVERRIDE:-}" ]; then
    printf '%s' "$CMD_OVERRIDE"; return 0
  fi
  local payload
  payload="$(cat 2>/dev/null || true)"
  if command -v jq >/dev/null 2>&1 && [ -n "$payload" ]; then
    printf '%s' "$payload" | jq -r '.tool_input.command // .command // ""' 2>/dev/null || true
  else
    # Fallback: the raw payload (best-effort substring match still works).
    printf '%s' "$payload"
  fi
}

_is_git_push() {
  printf '%s' "$1" | grep -qE '(^|[[:space:];&|])git[[:space:]]+([^|;&]*[[:space:]])?push([[:space:]]|$)'
}

_config_file() {
  printf '%s' "${CROSS_REPO_DRIFT_PAIRS:-$HOME/.claude/local/cross-repo-drift-pairs.txt}"
}

# ============================================================
# Core
# ============================================================
run_postpush_check() {
  local cmd poller cfg poller_out poller_rc
  cmd="$(_read_command)"

  # Only act on git push.
  _is_git_push "$cmd" || return 0

  cfg="$(_config_file)"
  [ -f "$cfg" ] || return 0   # operator hasn't opted into drift pairs

  poller="$(_resolve_poller)"
  [ -n "$poller" ] || return 0  # can't do the job; never break the session

  poller_out="$(CONFIG_FILE="$cfg" bash "$poller" --quiet 2>&1)"
  poller_rc=$?

  if [ "$poller_rc" -eq 1 ]; then
    {
      echo ""
      echo "================================================================"
      echo "[cross-repo-drift POST-PUSH] CRITICAL — REMOTES DIVERGED AFTER PUSH"
      echo "================================================================"
      echo "$poller_out"
      echo ""
      echo "A push just left two configured Neural Lace remotes at DIFFERENT"
      echo "master TREE HASHES — one remote now has content the other does not."
      echo "Per the both-remotes-always-in-sync rule, this is a FAIL-STATE:"
      echo "sync is NOT deferrable to 'follow-on cleanup' — that pattern is what"
      echo "creates multi-commit divergence."
      echo ""
      echo "Reconcile NOW (never force-push):"
      echo "  - Simple case (one remote strictly ahead): cherry-pick the missing"
      echo "    commit(s) onto the other remote's master + non-force push, OR run"
      echo "    scripts/sync-pt-to-personal.sh <commit> (tree-verifies before+after)."
      echo "  - Bidirectional divergence: reconcile both sides into a union first"
      echo "    (do NOT one-directional-overwrite — that destroys the other side's"
      echo "    work). Verify both remotes report identical tree hashes when done."
      echo "================================================================"
      echo ""
    } 2>&1   # surface on stdout too (clients that hide stderr still see it)
  fi
  # rc=0 (in sync) or rc=2 (unverifiable) → silent. Always advisory.
  return 0
}

# ============================================================
# Self-test
# ============================================================
run_self_test() {
  local tmp pass=0 fail=0
  tmp=$(mktemp -d 2>/dev/null || mktemp -d -t xrepo) || { echo "cannot mktemp" >&2; return 1; }
  trap "rm -rf '$tmp'" EXIT

  # Stub pollers returning controlled exit codes.
  printf '%s\n' '#!/usr/bin/env bash' 'echo "stub: drift"' 'exit 1' > "$tmp/poller-drift.sh"
  printf '%s\n' '#!/usr/bin/env bash' 'echo "stub: in-sync"' 'exit 0' > "$tmp/poller-sync.sh"
  printf '%s\n' '#!/usr/bin/env bash' 'echo "stub: unverifiable"' 'exit 2' > "$tmp/poller-unverif.sh"
  chmod +x "$tmp"/poller-*.sh
  local cfg="$tmp/pairs.txt"
  printf '%s\n' "owner-a/repo owner-b/repo label" > "$cfg"

  local out

  # S1: non-push command → silent no-op (even with drift poller).
  out=$( CMD_OVERRIDE="git status" POLLER_OVERRIDE="$tmp/poller-drift.sh" CROSS_REPO_DRIFT_PAIRS="$cfg" \
         bash "$SELF_PATH" 2>&1 )
  if [ -z "$out" ]; then echo "PASS: non-push-command-noop"; pass=$((pass+1))
  else echo "FAIL: non-push-command-noop (got: $out)"; fail=$((fail+1)); fi

  # S2: git push + drift → CRITICAL warning.
  out=$( CMD_OVERRIDE="git push origin master" POLLER_OVERRIDE="$tmp/poller-drift.sh" CROSS_REPO_DRIFT_PAIRS="$cfg" \
         bash "$SELF_PATH" 2>&1 )
  if echo "$out" | grep -q "CRITICAL — REMOTES DIVERGED"; then echo "PASS: push-with-drift-warns"; pass=$((pass+1))
  else echo "FAIL: push-with-drift-warns (got: $out)"; fail=$((fail+1)); fi

  # S3: git push + in-sync → silent.
  out=$( CMD_OVERRIDE="git push origin master" POLLER_OVERRIDE="$tmp/poller-sync.sh" CROSS_REPO_DRIFT_PAIRS="$cfg" \
         bash "$SELF_PATH" 2>&1 )
  if [ -z "$out" ]; then echo "PASS: push-in-sync-silent"; pass=$((pass+1))
  else echo "FAIL: push-in-sync-silent (got: $out)"; fail=$((fail+1)); fi

  # S4: git push + unverifiable (rc=2) → silent (no false alarm).
  out=$( CMD_OVERRIDE="git push origin master" POLLER_OVERRIDE="$tmp/poller-unverif.sh" CROSS_REPO_DRIFT_PAIRS="$cfg" \
         bash "$SELF_PATH" 2>&1 )
  if [ -z "$out" ]; then echo "PASS: push-unverifiable-silent"; pass=$((pass+1))
  else echo "FAIL: push-unverifiable-silent (got: $out)"; fail=$((fail+1)); fi

  # S5: no config file → silent no-op even on push+drift.
  out=$( CMD_OVERRIDE="git push origin master" POLLER_OVERRIDE="$tmp/poller-drift.sh" CROSS_REPO_DRIFT_PAIRS="$tmp/nonexistent.txt" \
         bash "$SELF_PATH" 2>&1 )
  if [ -z "$out" ]; then echo "PASS: no-config-noop"; pass=$((pass+1))
  else echo "FAIL: no-config-noop (got: $out)"; fail=$((fail+1)); fi

  # S6: git push -f variant still detected as a push.
  out=$( CMD_OVERRIDE="git push --force-with-lease origin feat/x" POLLER_OVERRIDE="$tmp/poller-drift.sh" CROSS_REPO_DRIFT_PAIRS="$cfg" \
         bash "$SELF_PATH" 2>&1 )
  if echo "$out" | grep -q "CRITICAL"; then echo "PASS: push-variant-detected"; pass=$((pass+1))
  else echo "FAIL: push-variant-detected (got: $out)"; fail=$((fail+1)); fi

  # S7: command that merely mentions 'push' in a non-git context → no-op.
  out=$( CMD_OVERRIDE="echo do not push to prod" POLLER_OVERRIDE="$tmp/poller-drift.sh" CROSS_REPO_DRIFT_PAIRS="$cfg" \
         bash "$SELF_PATH" 2>&1 )
  if [ -z "$out" ]; then echo "PASS: non-git-push-mention-noop"; pass=$((pass+1))
  else echo "FAIL: non-git-push-mention-noop (got: $out)"; fail=$((fail+1)); fi

  echo ""
  echo "[self-test] $pass passed, $fail failed"
  return "$fail"
}

# ============================================================
# Entry point
# ============================================================
SELF_PATH="${BASH_SOURCE[0]}"
case "$SELF_PATH" in
  /*) : ;;
  *) SELF_PATH="$(cd "$(dirname "$SELF_PATH")" && pwd)/$(basename "$SELF_PATH")" ;;
esac

case "${1:-}" in
  --self-test) run_self_test; exit $? ;;
  *) run_postpush_check; exit 0 ;;
esac
