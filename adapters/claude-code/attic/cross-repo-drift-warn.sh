#!/usr/bin/env bash
# cross-repo-drift-warn.sh — SessionStart hook that surfaces cross-repo NL master
# CONTENT drift at session start. Drift detection component (c).
#
# WHY THIS EXISTS: per 2026-05-28 pivot (ADR-044 Reverted), the cross-repo mirror
# Action was dropped. This hook is the operator-facing surface: when a session
# starts in any working directory, check the configured NL repo pairs and warn
# (NEVER block) if their master TREE HASHES disagree (i.e. content has
# diverged). Pairs to a sibling poller (`scripts/check-cross-repo-drift.sh`,
# component b) for the periodic backstop.
#
# Under the 2026-05-29 divergent-history-identical-content posture, the two
# repos are expected to have DIFFERENT commit SHAs forever (each cherry-pick
# creates a distinct commit object) but IDENTICAL tree hashes (same content);
# this hook surfaces content divergence, not history divergence.
#
# Behavior:
#   - Reads pair config from ~/.claude/local/cross-repo-drift-pairs.txt
#     (same file the scheduled-task poller uses).
#   - If config missing OR no pairs: silent no-op.
#   - If config present + at least one pair: invoke the poller in --quiet mode.
#     On drift (rc=1), emit a warning to stderr (visible in SessionStart output).
#     On verify failure (rc=2), silent — don't false-alarm on transient auth/network.
#   - NEVER exits non-zero. Hooks that error block SessionStart; this is a warn
#     not a block. Always exit 0.
#
# Configuration: see `scripts/check-cross-repo-drift.sh --help`. Same config file.
#
# Hook event: SessionStart (matcher: "" — fires on every session start).
# Wired in `settings.json.template` PostToolUse section is wrong — this is
# SessionStart. See the template wiring.

set -u
exec 2>&1  # surface warnings on stdout too so SessionStart UIs that don't show
           # stderr (some Claude Code clients) still see them

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
{ source "$SELF_DIR/lib/nl-paths.sh" 2>/dev/null; } || true

# Resolve sibling poller script. Prefer the runtime-mirror copy in ~/.claude/
# (where `install.sh` places harness files); fall back to the repo source path
# (useful when the hook is invoked from a fresh clone before install).
_NL_ROOT_FOR_POLLER=""
command -v nl_repo_root >/dev/null 2>&1 && _NL_ROOT_FOR_POLLER="$(nl_repo_root 2>/dev/null)"
POLLER=""
for cand in \
    "$HOME/.claude/scripts/check-cross-repo-drift.sh" \
    "${_NL_ROOT_FOR_POLLER:+$_NL_ROOT_FOR_POLLER/adapters/claude-code/scripts/check-cross-repo-drift.sh}" \
    "$(dirname "$0")/../scripts/check-cross-repo-drift.sh"; do
  [ -z "$cand" ] && continue
  if [ -f "$cand" ]; then POLLER="$cand"; break; fi
done

if [ -z "$POLLER" ]; then
  # Hook can't do its job, but must not break SessionStart. Silent.
  exit 0
fi

CONFIG_FILE="${CROSS_REPO_DRIFT_PAIRS:-$HOME/.claude/local/cross-repo-drift-pairs.txt}"
if [ ! -f "$CONFIG_FILE" ]; then
  # No pairs configured on this machine. Operator hasn't opted in. Silent.
  exit 0
fi

# Invoke the poller in --quiet mode. Capture rc; warn on drift only.
poller_out="$(bash "$POLLER" --quiet 2>&1)"
poller_rc=$?

if [ "$poller_rc" -eq 1 ]; then
  echo ""
  echo "================================================================"
  echo "[cross-repo-drift-warn] DRIFT WARNING"
  echo "================================================================"
  echo "$poller_out"
  echo ""
  echo "One or more configured Neural Lace repo pairs are at DIFFERENT master"
  echo "TREE HASHES — i.e. their CONTENT has diverged (not just commit history)."
  echo "The next push via 'sync.sh' will surface the same drift in its post-push"
  echo "verification. Note: under the divergent-history-identical-content"
  echo "posture (PT canonical; personal synced via cherry-pick + non-force"
  echo "direct push), DIFFERENT COMMIT SHAs are expected and OK — only tree"
  echo "(content) divergence is a real signal. To reconcile content:"
  echo "  1. Decide which side is canonical for the divergent content."
  echo "  2. Cherry-pick (DO NOT force-push) the missing commits onto the other side."
  echo "  3. Verify both repos now report identical tree hashes."
  echo "================================================================"
  echo ""
fi

# rc=0 (convergent) or rc=2 (unverifiable): silent. Always exit 0 — never block.
exit 0
