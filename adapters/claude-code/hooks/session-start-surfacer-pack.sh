#!/usr/bin/env bash
# session-start-surfacer-pack.sh — TRANSITIONAL SessionStart consolidation (Wave D.5,
# specs-d §D.0.3 entry 8). One SessionStart entry chaining the surviving surfacers so
# the live chain meets the ADR 058 D5 budget (SessionStart ≤ 8) BEFORE Wave E.1's
# digest exists. E.1's digest REPLACES this pack — retire it there.
#
# Members run in prior-template order; each receives the SessionStart stdin JSON;
# member stdout passes through (SessionStart stdout is operator-visible context);
# a member failure never breaks session start — surfacers observe, they do not gate.
#
# NOT pack members (retired at D.5): settings-divergence-detector + cross-repo-drift-warn
# (harness-doctor's remit, ADR 058 D4), decision-context-replay (fence retired, D.4).
set -u

INPUT="$(cat 2>/dev/null || true)"
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

MEMBERS=(
  "effort-policy-warn.sh"
  "session-start-discovery-cheatsheet.sh"
  "discovery-surfacer.sh"
  "register-surfacer.sh"
  "stalled-work-surfacer.sh"
  "decision-context-pending-surfacer.sh"
  "spawned-task-result-surfacer.sh"
  "external-monitor-alert-surfacer.sh"
  "session-start-git-freshness.sh"
  "session-start-worktree-advisor.sh"
  "workstreams-task-binding.sh"
  "plan-status-archival-sweep.sh"
  "stale-active-plan-surfacer.sh"
)

if [[ "${1:-}" == "--self-test" ]]; then
  fails=0
  for m in "${MEMBERS[@]}"; do
    if [[ ! -f "$HOOKS_DIR/$m" ]]; then
      echo "self-test FAIL: missing pack member $m" >&2
      fails=1
    fi
  done
  # Syntax-check only — never live-run members in self-test (plan-status-archival-sweep
  # mutates; surfacers read live state). E.2's temp-HOME sweep covers execution.
  if ! bash -n "${BASH_SOURCE[0]}"; then
    echo "self-test FAIL: pack fails bash -n" >&2
    fails=1
  fi
  [[ $fails -eq 0 ]] && echo "self-test PASS: ${#MEMBERS[@]} members present; pack syntax OK"
  exit $fails
fi

run_member() {
  printf '%s' "$INPUT" | bash "$@" 2>/dev/null || true
}

# Inline pipeline hint (was its own template entry pre-D.5)
if [ -f pipeline/evidence.md ] || [ -f orchestrate.sh ]; then
  echo 'Pipeline: active. Use Option B (build → evidence → gates → verifier → commit) for all changes.'
elif [ -f "$HOME/.claude/pipeline-templates/orchestrate.sh" ]; then
  echo 'Pipeline: available but not set up for this project. Run /setup-pipeline to initialize.'
fi

for m in "${MEMBERS[@]}"; do
  if [[ "$m" == "workstreams-task-binding.sh" ]]; then
    run_member "$HOOKS_DIR/$m" --on-session-start
  else
    run_member "$HOOKS_DIR/$m"
  fi
done

exit 0
