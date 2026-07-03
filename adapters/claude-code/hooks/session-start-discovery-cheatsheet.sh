#!/bin/bash
# session-start-discovery-cheatsheet.sh
#
# SessionStart hook that emits a short "where to find harness info" map at
# every session boundary. The map lists the canonical locations for the
# content kinds that are most-commonly orphaned-or-asked-for-redundantly:
# operating principles, credential reference, the rules INDEX, plans,
# discoveries, ADRs, and the information-architecture routing rule.
#
# This is the discoverability half of the harness-hygiene-2 initiative.
# Companion: doctrine/harness-dev.md (the routing rule itself).
# Sibling Mechanism: claude-md-hygiene-gate.sh (PR 3 — bloat detection).
#
# Why this exists:
#   Even with INDEX.md and the principles `@`-reference, sessions repeatedly
#   ask for content that already exists at a known path (the canonical
#   instance: asking the operator for credentials despite
#   ~/.claude/local/credentials-reference.md being the documented
#   convention). The cheatsheet surfaces the map BEFORE any orphan-content
#   failure mode can fire, in the session's loaded context.
#
# Design notes:
#   - Reads JSON on stdin per Claude Code SessionStart contract; payload
#     ignored — the hook emits the same content every session.
#   - Output is plain stdout text (same convention as discovery-surfacer.sh,
#     external-monitor-alert-surfacer.sh, etc.).
#   - Silent when ~/.claude/doctrine/INDEX.md is missing AND no INDEX is in the
#     project's adapters/ subtree — i.e. the harness is not installed.
#     Otherwise always emits the cheatsheet (no harm in surfacing it).
#   - Map content is hand-maintained here, not auto-derived. The 9 entries
#     are stable; auto-derivation from INDEX.md would emit 50+ lines and
#     defeat the purpose (a SHORT cheatsheet the agent skims).
#
# Self-test: --self-test exercises three scenarios.

set -u

# -------- Resolve INDEX.md path (prefer live mirror, fall back to repo) --------
resolve_index_path() {
  local cwd="${1:-$PWD}"
  if [ -f "$HOME/.claude/doctrine/INDEX.md" ]; then
    printf '%s\n' "$HOME/.claude/doctrine/INDEX.md"
    return 0
  fi
  if [ -f "$cwd/adapters/claude-code/doctrine/INDEX.md" ]; then
    printf '%s\n' "$cwd/adapters/claude-code/doctrine/INDEX.md"
    return 0
  fi
  return 1
}

# -------- Core surfacing logic --------
# Args: $1 = working directory (defaults to $PWD)
# Writes the cheatsheet to stdout. Exits 0 always.
emit_cheatsheet() {
  local cwd="${1:-$PWD}"
  local index_path
  if ! index_path=$(resolve_index_path "$cwd"); then
    # No INDEX anywhere => harness not installed in this context => silent.
    return 0
  fi

  cat <<'EOF'
[discovery-cheatsheet] Where to find harness info (per ~/.claude/doctrine/harness-dev.md):

  Operating principles           → ~/.claude/rules/constitution.md (full: ~/.claude/doctrine/principles-full.md)
  Credentials / auth conventions → ~/.claude/local/credentials-reference.md
  All operating rules (index)    → ~/.claude/doctrine/INDEX.md
  Per-surface rules              → ~/.claude/doctrine/<rule-name>.md
  Information architecture rule  → ~/.claude/doctrine/harness-dev.md
  Architectural decisions (ADRs) → docs/decisions/NNN-<slug>.md  (index: docs/DECISIONS.md)
  Active implementation plans    → docs/plans/<slug>.md          (archived: docs/plans/archive/)
  Pending discoveries            → docs/discoveries/YYYY-MM-DD-<slug>.md
  Audit / review passes          → docs/reviews/YYYY-MM-DD-<slug>.md
  Class-aware findings           → docs/findings.md
  Failure-mode catalog           → docs/failure-modes.md
  Backlog (open work)            → docs/backlog.md
  Ephemeral session state        → SCRATCHPAD.md (gitignored)
  Machine-local config           → ~/.claude/local/*.{json,md} (gitignored)

  Before asking the operator for credentials, conventions, or persona/audience
  context: consult the canonical files above. They likely already document it.
EOF
}

# -------- Self-test --------
run_self_test() {
  local tmp failures=0
  tmp=$(mktemp -d 2>/dev/null || mktemp -d -t schccsh)
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" EXIT

  # Scenario 1: INDEX in live mirror present => emit cheatsheet
  # We can't easily mock $HOME, so we test the resolve helper directly and
  # assume the live mirror exists (which it does on any installed machine).
  if [ -f "$HOME/.claude/doctrine/INDEX.md" ]; then
    local out1
    out1=$(emit_cheatsheet "$tmp" 2>/dev/null)
    if echo "$out1" | grep -qF "Where to find harness info"; then
      echo "PASS: [live-mirror-present] emits cheatsheet"
    else
      echo "FAIL: [live-mirror-present] expected cheatsheet header" >&2
      failures=$((failures + 1))
    fi
    if echo "$out1" | grep -qF "credentials-reference.md"; then
      echo "PASS: [credentials-line-present]"
    else
      echo "FAIL: [credentials-line-present] cheatsheet missing credentials line" >&2
      failures=$((failures + 1))
    fi
    if echo "$out1" | grep -qF "harness-dev.md"; then
      echo "PASS: [info-arch-line-present]"
    else
      echo "FAIL: [info-arch-line-present] cheatsheet missing info-arch line" >&2
      failures=$((failures + 1))
    fi
  else
    echo "SKIP: [live-mirror-present] no live mirror at \$HOME/.claude/doctrine/INDEX.md"
  fi

  # Scenario 2: INDEX in repo subtree present (no live mirror) => emit cheatsheet
  local s2="$tmp/repo-subtree"
  mkdir -p "$s2/adapters/claude-code/doctrine"
  echo "# Rules INDEX" > "$s2/adapters/claude-code/doctrine/INDEX.md"
  # We can't unset HOME safely; test resolve_index_path directly with a fake
  # path. Force the helper to fail on $HOME by setting HOME to /nonexistent.
  local saved_home="$HOME"
  HOME="/nonexistent-for-test-$$"
  export HOME
  local out2
  out2=$(emit_cheatsheet "$s2" 2>/dev/null)
  HOME="$saved_home"
  export HOME
  if echo "$out2" | grep -qF "Where to find harness info"; then
    echo "PASS: [repo-subtree-fallback] emits cheatsheet from repo INDEX"
  else
    echo "FAIL: [repo-subtree-fallback] expected cheatsheet from repo INDEX" >&2
    failures=$((failures + 1))
  fi

  # Scenario 3: no INDEX anywhere => silent
  local s3="$tmp/no-index"
  mkdir -p "$s3"
  local saved_home2="$HOME"
  HOME="/nonexistent-for-test2-$$"
  export HOME
  local out3
  out3=$(emit_cheatsheet "$s3" 2>/dev/null)
  HOME="$saved_home2"
  export HOME
  if [ -z "$out3" ]; then
    echo "PASS: [no-index-anywhere] silent"
  else
    echo "FAIL: [no-index-anywhere] expected silence, got: $(echo "$out3" | head -1)" >&2
    failures=$((failures + 1))
  fi

  if [ "$failures" -eq 0 ]; then
    echo ""
    echo "SELF-TEST: all scenarios passed"
    return 0
  else
    echo ""
    echo "SELF-TEST: $failures scenario(s) failed" >&2
    return 1
  fi
}

# -------- Entry point --------
if [ "${1:-}" = "--self-test" ]; then
  run_self_test
  exit $?
fi

# Normal invocation: consume any stdin JSON (Claude Code hook contract) and
# emit the cheatsheet. Always exits 0.
if [ ! -t 0 ]; then
  cat >/dev/null 2>&1 || true
fi

emit_cheatsheet "$PWD"
exit 0
