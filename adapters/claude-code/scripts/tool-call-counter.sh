#!/bin/bash
# tool-call-counter.sh — successor to tool-call-budget.sh's attestation loop
# (NL Overhaul Wave D, task D.6 / §D.0.4).
#
# tool-call-budget.sh is retired to attic at D.5 (0 attestations observed in
# 10,959 calls — the block-and-attest loop was pure friction). This script
# reads the SAME per-session counter file tool-call-budget.sh maintained
# ($STATE_DIR/tool-call-count.<effective_id>) and, at the same thresholds
# (30 = soft, 90 = hard-ceiling equivalent), emits a non-blocking
# signal-ledger `soft-counter` event instead of blocking + demanding a
# plan-evidence-reviewer attestation. No blocking, no attestation, no state
# mutation of its own — read-only w.r.t. the counter file.
#
# Usage: bash tool-call-counter.sh [<effective_id>]
#   <effective_id> defaults to CLAUDE_SESSION_ID (solo mode key used by
#   tool-call-budget.sh when no agent-team config matches).
STATE_DIR="${STATE_DIR_OVERRIDE:-$HOME/.claude/state}"
EFFECTIVE_ID="${1:-${CLAUDE_SESSION_ID:-${PPID:-$$}}}"
COUNTER_FILE="$STATE_DIR/tool-call-count.$EFFECTIVE_ID"

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../hooks/lib/signal-ledger.sh
source "$SELF_DIR/../hooks/lib/signal-ledger.sh" 2>/dev/null || true

COUNT=$(cat "$COUNTER_FILE" 2>/dev/null || echo 0)
[[ "$COUNT" =~ ^[0-9]+$ ]] || COUNT=0

if [ "$COUNT" -ge 90 ]; then
  command -v ledger_emit >/dev/null 2>&1 && ledger_emit "tool-call-counter" "soft-counter" "hard-threshold:$COUNT:$EFFECTIVE_ID"
elif [ "$COUNT" -ge 30 ]; then
  command -v ledger_emit >/dev/null 2>&1 && ledger_emit "tool-call-counter" "soft-counter" "soft-threshold:$COUNT:$EFFECTIVE_ID"
fi

exit 0
