#!/usr/bin/env bash
# signal-ledger-flush.sh — Stop entry #5 (ADR 058 D5; specs-d §D.0.2). Non-blocking.
# Writes one terminal "flush" event so every session's ledger segment has a
# session-end boundary record for the Wave-E consumers (digest, waiver-density
# alarm, KPI script). The ledger lib is append-only JSONL; sandboxed under
# HARNESS_SELFTEST=1 by the lib itself.
set -u

HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1091
if [[ -f "$HOOKS_DIR/lib/signal-ledger.sh" ]]; then
  source "$HOOKS_DIR/lib/signal-ledger.sh"
else
  # Lib missing (partial install) — a flush marker is not worth failing a Stop for.
  exit 0
fi

if [[ "${1:-}" == "--self-test" ]]; then
  export HARNESS_SELFTEST=1
  if printf '{}' | bash "${BASH_SOURCE[0]}"; then
    echo "self-test PASS: flush exits 0 under sandbox"
    exit 0
  fi
  echo "self-test FAIL: flush exited non-zero" >&2
  exit 1
fi

ledger_emit "signal-ledger-flush" "flush" "session-end" || true
exit 0
