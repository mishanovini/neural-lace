#!/bin/bash
# register-surfacer.sh — SessionStart hook
#
# Surfaces the top open items from the INCOMPLETE-WORK REGISTER at the
# start of every session, so the register (the durable cross-session
# memory of "everything still to build") is in front of every agent turn
# and cannot be lost between sessions.
#
# Originating context: 2026-06-13. For a week, incomplete work accumulated
# invisibly across 40+ branches/worktrees because the harness's "memory"
# (the Workstreams tracker + handoff doc) tracked decisions-awaiting-Misha
# and the orchestrator's own dispatches — never a full cross-session census
# of incomplete work. The register
# (workstreams-coordination/INCOMPLETE-WORK-REGISTER-*.md) is that census;
# this hook makes it structurally unmissable. It is the SessionStart half
# of the register-driven-session enforcement; the Stop half is
# register-progress-gate.sh (which blocks a working session that ends
# without advancing a register item or naming a specific blocker).
#
# Design notes:
# - Reads JSON on stdin per the SessionStart contract; payload unused.
# - The register lives in the cross-machine coordination repo, NOT the cwd
#   repo. Resolution order: $REGISTER_PATH env > newest
#   <coordination-root>/INCOMPLETE-WORK-REGISTER-*.md, where
#   <coordination-root> is resolved from
#   ~/.claude/config/register-path (one line: the coordination repo dir)
#   then a small set of conventional locations. Missing register => exit 0
#   silently (informational; never block session start).
# - Surfaces the items under "## LIST 1 — STILL NEEDS TO BE BUILT" up to
#   the next "## " heading, capped at REGISTER_SURFACE_MAX (default 12)
#   leading numbered/bulleted lines, plus the count of remaining items.
#
# Self-test: invoke with --self-test to exercise the resolution + extract.

set -u

REGISTER_SURFACE_MAX="${REGISTER_SURFACE_MAX:-12}"

# -------- resolve the register file --------
resolve_register() {
  # 1) explicit env override
  if [ -n "${REGISTER_PATH:-}" ] && [ -f "${REGISTER_PATH}" ]; then
    printf '%s\n' "$REGISTER_PATH"; return 0
  fi
  # 2) coordination-root pointer file
  local root=""
  local ptr="$HOME/.claude/config/register-path"
  if [ -f "$ptr" ]; then
    root="$(head -n1 "$ptr" 2>/dev/null | tr -d '\r')"
  fi
  # 3) conventional fallbacks for the coordination repo
  local candidates=()
  [ -n "$root" ] && candidates+=("$root")
  candidates+=(
    "$HOME/claude-projects/workstreams-coordination"
    "$(pwd)/../workstreams-coordination"
    "$(pwd)/workstreams-coordination"
  )
  local d f
  for d in "${candidates[@]}"; do
    [ -d "$d" ] || continue
    # newest INCOMPLETE-WORK-REGISTER-*.md in that dir
    f="$(ls -t "$d"/INCOMPLETE-WORK-REGISTER-*.md 2>/dev/null | head -n1)"
    if [ -n "$f" ] && [ -f "$f" ]; then printf '%s\n' "$f"; return 0; fi
  done
  return 1
}

# -------- extract the open-items section --------
# Prints up to REGISTER_SURFACE_MAX leading list lines (numbered or '- ')
# from the "STILL NEEDS TO BE BUILT" section, plus a remaining-count line.
emit_register() {
  local file="$1"
  awk -v max="$REGISTER_SURFACE_MAX" '
    BEGIN { insec=0; shown=0; total=0 }
    /^##[[:space:]]+LIST 1/ { insec=1; next }
    insec && /^##[[:space:]]/ { insec=0 }
    insec {
      # count + collect top-level list items (numbered "N." or "- ")
      if ($0 ~ /^[0-9]+\.[[:space:]]/ || $0 ~ /^-[[:space:]]/) {
        total++
        if (shown < max) { print "  " $0; shown++ }
      } else if ($0 ~ /^###[[:space:]]/) {
        # priority sub-headers (P0 / P1) — show them as context
        if (shown < max) { print $0 }
      }
    }
    END {
      if (total > shown) printf "  … (+%d more items in the register)\n", total - shown
    }
  ' "$file"
}

run() {
  local reg
  reg="$(resolve_register)" || { exit 0; }
  # Only surface if there is a STILL-NEEDS section
  grep -qE '^##[[:space:]]+LIST 1' "$reg" 2>/dev/null || exit 0
  echo "[register] INCOMPLETE-WORK REGISTER — top open items (drive these; do not babysit):"
  echo "  source: $reg"
  emit_register "$reg"
  echo "  Full register + safe-to-clean + do-not-clean lists in that file."
  echo "  Per register-progress-gate: a working session must advance a register"
  echo "  item (commit/PR) or name a specific blocker before it can end."
  exit 0
}

# ============================ SELF-TEST ============================
self_test() {
  local tmp pass=0 fail=0
  tmp="$(mktemp -d)"
  local reg="$tmp/INCOMPLETE-WORK-REGISTER-2026-06-13.md"
  cat > "$reg" <<'EOF'
# INCOMPLETE-WORK REGISTER
intro line
## LIST 1 — STILL NEEDS TO BE BUILT
### P0 — top priority
1. First high-priority item to build
2. Second high-priority item
3. Third high-priority item
### P1 — secondary
7. Fourth item — PR #100
8. Fifth item — PR #200
## LIST 2 — SAFE TO CLEAN
- worker-task-1
EOF
  # T1: resolves via REGISTER_PATH + emits the section, not LIST 2
  local out
  out="$(REGISTER_PATH="$reg" REGISTER_SURFACE_MAX=12 bash "$0" 2>/dev/null </dev/null)"
  if echo "$out" | grep -q "First high-priority item to build" \
     && echo "$out" | grep -q "P0 — top priority" \
     && ! echo "$out" | grep -q "worker-task-1"; then
    echo "T1 surface-list1-not-list2: PASS"; pass=$((pass+1))
  else echo "T1 surface-list1-not-list2: FAIL"; fail=$((fail+1)); fi
  # T2: cap honored + remaining-count line
  out="$(REGISTER_PATH="$reg" REGISTER_SURFACE_MAX=2 bash "$0" 2>/dev/null </dev/null)"
  if echo "$out" | grep -qE "\+[0-9]+ more items"; then
    echo "T2 cap-and-remaining-count: PASS"; pass=$((pass+1))
  else echo "T2 cap-and-remaining-count: FAIL"; fail=$((fail+1)); fi
  # T3: unresolvable register (env points nowhere AND fallbacks neutralized
  # by isolating HOME + cwd to an empty dir) => silent exit 0, no output
  out="$(cd "$tmp" && HOME="$tmp" REGISTER_PATH="$tmp/nonexistent.md" bash "$0" 2>/dev/null </dev/null)"
  if [ -z "$out" ]; then echo "T3 unresolvable-register-silent: PASS"; pass=$((pass+1));
  else echo "T3 unresolvable-register-silent: FAIL"; fail=$((fail+1)); fi
  # T4: register without LIST 1 => silent
  local reg2="$tmp/INCOMPLETE-WORK-REGISTER-empty.md"; printf '# x\nno section\n' > "$reg2"
  out="$(REGISTER_PATH="$reg2" bash "$0" 2>/dev/null </dev/null)"
  if [ -z "$out" ]; then echo "T4 no-list1-silent: PASS"; pass=$((pass+1));
  else echo "T4 no-list1-silent: FAIL"; fail=$((fail+1)); fi
  rm -rf "$tmp"
  echo "self-test: $pass passed, $fail failed"
  [ "$fail" -eq 0 ]
}

if [ "${1:-}" = "--self-test" ]; then self_test; exit $?; fi
run
