#!/usr/bin/env bash
# workstreams-stop-writer.sh — ONE consolidated Stop entry for the workstreams writer
# family (ADR 058 D5 target chain #4; specs-d §D.0.2). Collapses six prior Stop
# entries: workstreams-stop-gate, workstreams-emit --on-stop, workstreams-task-binding
# --on-stop (warn mode per D.6 — its Stop BLOCK retired per specs-d §D.0.5),
# workstreams-extract-pending, workstreams-emit-reconciler, workstreams-orchestrator-queue.
#
# WRITER SEMANTICS — THIS HOOK NEVER BLOCKS. Member stdout is swallowed (that is where
# a legacy {"decision":"block"} would live); member side effects (GUI data layer,
# queues, pending files) still happen. Any member that emits output is recorded as a
# signal-ledger WARN — the uniform demotion mechanism: complaints become ledger
# events, not session blocks.
set -u

INPUT="$(cat 2>/dev/null || true)"
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1091
[[ -f "$HOOKS_DIR/lib/signal-ledger.sh" ]] && source "$HOOKS_DIR/lib/signal-ledger.sh"

MEMBERS=(
  "workstreams-stop-gate.sh"
  "workstreams-emit.sh --on-stop"
  "workstreams-task-binding.sh --on-stop"
  "workstreams-extract-pending.sh"
  "workstreams-emit-reconciler.sh"
  "workstreams-orchestrator-queue.sh"
)

if [[ "${1:-}" == "--self-test" ]]; then
  fails=0
  for spec in "${MEMBERS[@]}"; do
    f="${spec%% *}"
    if [[ ! -f "$HOOKS_DIR/$f" ]]; then
      echo "self-test FAIL: missing member $f" >&2
      fails=1
    fi
  done
  # Syntax-check only — never live-run members in self-test (writers mutate the GUI
  # data layer / queues). E.2's temp-HOME sweep covers execution.
  if ! bash -n "${BASH_SOURCE[0]}"; then
    echo "self-test FAIL: writer fails bash -n" >&2
    fails=1
  fi
  [[ $fails -eq 0 ]] && echo "self-test PASS: ${#MEMBERS[@]} members present; writer syntax OK"
  exit $fails
fi

for spec in "${MEMBERS[@]}"; do
  f="${spec%% *}"
  args="${spec#"$f"}"
  # shellcheck disable=SC2086
  out=$(printf '%s' "$INPUT" | bash "$HOOKS_DIR/$f" $args 2>&1 || true)
  if [[ -n "$out" ]] && command -v ledger_emit >/dev/null 2>&1; then
    ledger_emit "${f%.sh}" "warn" "stop-writer: ${out:0:200}"
  fi
done

exit 0
