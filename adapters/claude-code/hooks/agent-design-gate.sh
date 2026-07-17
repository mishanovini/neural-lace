#!/bin/bash
# agent-design-gate.sh — GATE 2 of the artifact-evidence-bar
# (doctrine/artifact-evidence-bar.md, constitution §10 generalized).
#
# PreToolUse hook. Blocks the WRITE of a brand-new agent file under
# adapters/claude-code/agents/*.md unless it carries a `## GOLDEN CASE`
# section plus mechanical evidence of the seven world-class-agent
# properties (doctrine/artifact-evidence-bar.md). "No golden case, no
# agent" — the same bar constitution §10 sets for gates: an artifact
# with no evidence it beats a naive/generic version is a claim, not a
# control.
#
# GRANDFATHER CLAUSE (explicit, per the build task): the ~25 agents that
# predate this bar are NEVER retroactively blocked. The gate distinguishes
# "new" from "existing" the only way a single PreToolUse call safely can —
# by checking whether the target file already exists ON DISK at the
# moment this hook fires (PreToolUse runs BEFORE the tool executes, so
# disk state here IS the pre-edit state):
#
#   - File does NOT exist yet (a `Write` creating a brand-new agent)
#     -> NEW agent -> the bar is enforced against the content being
#        written; missing GOLDEN CASE or missing property-evidence BLOCKS.
#   - File already exists (any `Edit`/`MultiEdit`/overwriting `Write` of
#     a pre-existing agent file) -> GRANDFATHERED -> always allowed,
#     advisory note only. This deliberately does NOT re-check the
#     resulting content, so it cannot regress-detect an edit that STRIPS
#     an existing GOLDEN CASE section back out — a known, accepted gap
#     (see doctrine/artifact-evidence-bar-full.md); catching that would
#     require diffing tool_input against the pre-edit file for Edit and
#     replaying tool_input.edits for MultiEdit, out of scope for this
#     build.
#
# `Edit|Write|MultiEdit` matcher (NOT `Edit|Write` alone): a MultiEdit-
# shaped hole has bitten this harness before (a gate wired only to
# Edit|Write silently let MultiEdit calls through). MultiEdit only ever
# targets an EXISTING file (Claude Code requires the file to pre-exist),
# so it can only ever hit the grandfathered branch above — included here
# for completeness / defense-in-depth, not because it can trigger a block.
#
# Self-test: bash agent-design-gate.sh --self-test
#
# Exit codes:
#   0 — tool may proceed (not an agent file / grandfathered / bar met)
#   2 — tool is blocked; stderr explains why; stdout has JSON block decision

set -u

# ============================================================
# Self-test entry point (handled BEFORE any input parsing)
# ============================================================
if [[ "${1:-}" == "--self-test" ]]; then
  SELF_TEST=1
fi

SELF_PATH="${BASH_SOURCE[0]}"
case "$SELF_PATH" in
  /*) ;;
  *) SELF_PATH="$PWD/$SELF_PATH" ;;
esac

# ============================================================
# Helpers
# ============================================================

# Read stdin JSON or CLAUDE_TOOL_INPUT env var (same convention as
# local-edit-gate.sh).
load_input() {
  local input="${CLAUDE_TOOL_INPUT:-}"
  if [[ -z "$input" ]]; then
    if [[ ! -t 0 ]]; then
      input=$(cat 2>/dev/null || echo "")
    fi
  fi
  printf '%s' "$input"
}

extract_field() {
  local input="$1" field="$2"
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$input" | jq -r ".$field // \"\"" 2>/dev/null
  else
    printf '%s' "$input" | grep -oE "\"$field\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | sed -E "s/\"$field\"[[:space:]]*:[[:space:]]*\"([^\"]*)\"/\1/" | head -1
  fi
}

extract_content() {
  local input="$1"
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$input" | jq -r '.tool_input.content // ""' 2>/dev/null
  else
    # Best-effort fallback without jq: not reliable for multi-line content
    # with embedded quotes/newlines, so we degrade to empty (fail toward
    # "cannot verify -> block with an explanatory reason" rather than a
    # corrupt partial extraction being treated as the real content).
    echo ""
  fi
}

# Path match: does this path refer to a file under
# adapters/claude-code/agents/ with a .md extension? Substring-based
# (not repo-root-relative) so it works regardless of absolute/relative
# form, Windows drive letters, or which worktree/checkout this is.
is_agent_file() {
  local path="$1"
  local normalized
  normalized=$(printf '%s' "$path" | tr '\\' '/')
  case "$normalized" in
    */adapters/claude-code/agents/*.md|adapters/claude-code/agents/*.md) return 0 ;;
    *) return 1 ;;
  esac
}

emit_block() {
  local reason="$1"
  # Observe-first rollout (harness-review 2026-07-17, block-mode-before-FP-calibrated):
  # default records the would-block verdict and ALLOWS; set AGENT_DESIGN_GATE_ENFORCE=1
  # to actually block. Flip criterion (manifest): N real fires observed with zero
  # false positives on the would-block log.
  if [ "${AGENT_DESIGN_GATE_ENFORCE:-0}" = "1" ]; then
    printf '{"decision":"block","reason":"%s"}\n' "$reason"
  else
    ( mkdir -p "${HOME}/.claude/state" 2>/dev/null && \
      printf '{"ts":"%s","would_block":true,"reason":"%s"}\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$reason" \
        >> "${HOME}/.claude/state/agent-design-gate-probe.jsonl" 2>/dev/null ) || true
  fi
}

# Check content for the GOLDEN CASE heading + substantive body. Returns
# 0 (pass) if present and >= 30 non-whitespace chars in the section body.
has_golden_case() {
  local content="$1"
  local body
  body=$(printf '%s\n' "$content" | awk '
    BEGIN { in_gc = 0 }
    /^##[[:space:]]+GOLDEN[[:space:]]+CASE/ { in_gc = 1; next }
    in_gc && /^## / { exit }
    in_gc { print }
  ')
  local non_ws
  non_ws=$(printf '%s' "$body" | tr -d '[:space:]' | wc -c | tr -cd '[:digit:]')
  non_ws=${non_ws:-0}
  [[ "$non_ws" -ge 30 ]]
}

# Pragmatic, section/phrase-presence checks for the seven properties
# (doctrine/artifact-evidence-bar.md). "Be pragmatic: check for the
# load-bearing sections, not prose quality" — each is a broad OR-list of
# vocabulary already standard across this harness's own agent corpus
# (verified against architecture-reviewer.md, the reference "world-class"
# agent this bar was built to codify), so a genuinely well-designed new
# agent using ordinary review vocabulary should clear all seven; the one
# hard, unambiguous requirement is the GOLDEN CASE heading itself, which
# is checked separately above.
declare -a PROPERTY_LABELS=(
  "named failure modes"
  "structural protocol"
  "named canon"
  "system hazard priors"
  "output contract"
  "anti-rubber-stamp mechanism"
)
declare -a PROPERTY_PATTERNS=(
  'failure[[:space:]]+mode|anti-pattern|how this (job|agent) fails'
  'phase[[:space:]]+[0-9]|protocol|ordered (phase|step)'
  'canon|framework|methodology'
  'hazard[[:space:]]+prior|this codebase|this system|landmine|this-system'
  'output contract|PROVEN|HYPOTHESIZED|severity'
  'rubber.stamp|steelman'
)

# Populates the global MISSING_PROPERTIES array (bash 3.2-safe: no
# nameref/mapfile dependency) with the human labels of any property whose
# pattern is absent from content. Empty array == all seven present.
check_properties() {
  local content="$1"
  MISSING_PROPERTIES=()
  local i
  for i in "${!PROPERTY_PATTERNS[@]}"; do
    if ! printf '%s' "$content" | grep -qiE "${PROPERTY_PATTERNS[$i]}"; then
      MISSING_PROPERTIES+=("${PROPERTY_LABELS[$i]}")
    fi
  done
}

# ============================================================
# Main gate logic
# ============================================================

run_gate() {
  local input
  input=$(load_input)

  local tool_name
  tool_name=$(extract_field "$input" "tool_name")

  case "$tool_name" in
    Edit|Write|MultiEdit) ;;
    *) return 0 ;;
  esac

  local file_path
  if command -v jq >/dev/null 2>&1; then
    file_path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // ""' 2>/dev/null)
  else
    file_path=$(printf '%s' "$input" | grep -oE '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | sed -E 's/"file_path"[[:space:]]*:[[:space:]]*"([^"]*)"/\1/' | head -1)
  fi

  # No file_path -> cannot determine scope. Fail OPEN (this gate's remit
  # is narrow: only new agents/*.md files; a malformed-input edge case on
  # an unrelated tool call should never block unrelated work).
  if [[ -z "$file_path" ]]; then
    return 0
  fi

  if ! is_agent_file "$file_path"; then
    return 0
  fi

  # Grandfather check: does the file already exist on disk (pre-edit
  # state, since PreToolUse fires before the tool runs)?
  if [[ -f "$file_path" ]]; then
    echo "[agent-design-gate] ALLOW (grandfathered): $(basename "$file_path") predates the artifact-evidence-bar; existing agents are never retroactively blocked. See doctrine/artifact-evidence-bar.md." >&2
    return 0
  fi

  # New agent file. Only a Write call can plausibly carry the full
  # resulting content (Edit/MultiEdit require a pre-existing file, so
  # reaching this branch on those tool names is an edge case we don't
  # try to validate content for — allow with an advisory).
  if [[ "$tool_name" != "Write" ]]; then
    echo "[agent-design-gate] ALLOW (advisory): $tool_name on a non-existent agent file path — cannot evaluate resulting content for the bar; only 'Write' of a brand-new agent is validated." >&2
    return 0
  fi

  local content
  content=$(extract_content "$input")

  if [[ -z "$content" ]]; then
    emit_block "agent-design-gate: could not read tool_input.content for new agent file $(basename "$file_path") (jq unavailable or empty content) — cannot verify the GOLDEN CASE + seven-properties bar. See doctrine/artifact-evidence-bar.md."
    echo "[agent-design-gate] $([ "${AGENT_DESIGN_GATE_ENFORCE:-0}" = "1" ] && echo BLOCK || echo WOULD-BLOCK): could not extract content for $(basename "$file_path")" >&2
    [ "${AGENT_DESIGN_GATE_ENFORCE:-0}" = "1" ] && return 2 || return 0
  fi

  local reasons=""
  if ! has_golden_case "$content"; then
    reasons+="missing (or < 30 non-whitespace chars) '## GOLDEN CASE' section; "
  fi

  local MISSING_PROPERTIES
  check_properties "$content"
  if [[ ${#MISSING_PROPERTIES[@]} -gt 0 ]]; then
    local joined
    joined=$(printf '%s, ' "${MISSING_PROPERTIES[@]}")
    joined="${joined%, }"
    reasons+="no evidence of: ${joined}; "
  fi

  if [[ -n "$reasons" ]]; then
    emit_block "agent-design-gate: new agent $(basename "$file_path") does not meet the artifact-evidence-bar (constitution §10 generalized) — ${reasons}Add a '## GOLDEN CASE' section (a real historical defect this agent catches that a generic agent misses) and evidence of all seven properties. See doctrine/artifact-evidence-bar.md and doctrine/artifact-evidence-bar-full.md."
    echo "[agent-design-gate] $([ "${AGENT_DESIGN_GATE_ENFORCE:-0}" = "1" ] && echo BLOCK || echo WOULD-BLOCK): $(basename "$file_path") — ${reasons}" >&2
    [ "${AGENT_DESIGN_GATE_ENFORCE:-0}" = "1" ] && return 2 || return 0
  fi

  echo "[agent-design-gate] ALLOW: $(basename "$file_path") — GOLDEN CASE + all seven properties detected." >&2
  return 0
}

# ============================================================
# Self-test
# ============================================================

cmd_self_test() {
  local PASSED=0 FAILED=0
  # NOT local: the EXIT trap fires after this function's scope is gone
  # (same fix as local-edit-gate.sh / manifest-check.sh self-tests).
  TMPROOT=$(mktemp -d 2>/dev/null || mktemp -d -t agent-design-gate)
  trap 'rm -rf "$TMPROOT"' EXIT

  build_input_write() {
    local path="$1" content="$2"
    # jq -Rs slurps the raw content into a JSON-safe string; avoids
    # hand-rolled escaping bugs for multi-line fixture text.
    if command -v jq >/dev/null 2>&1; then
      printf '%s' "$content" | jq -Rs --arg path "$path" '{tool_name:"Write", tool_input:{file_path:$path, content:.}}'
    else
      # jq is required for the self-test's content-bearing scenarios;
      # scenarios that don't need jq (non-agent path, grandfathered,
      # wrong tool) still run without it.
      printf '{"tool_name":"Write","tool_input":{"file_path":"%s","content":""}}' "$path"
    fi
  }

  build_input_simple() {
    local tool="$1" path="$2"
    printf '{"tool_name":"%s","tool_input":{"file_path":"%s"}}' "$tool" "$path"
  }

  run_with() {
    # scenarios assert BLOCK semantics -> run in enforce mode (the shipped
    # default is observe-first; S8 below covers that posture explicitly)
    local input="$1"
    CLAUDE_TOOL_INPUT="$input" AGENT_DESIGN_GATE_ENFORCE=1 run_gate >/dev/null 2>&1
    echo $?
  }

  run_with_observe() {
    local input="$1"
    CLAUDE_TOOL_INPUT="$input" AGENT_DESIGN_GATE_ENFORCE=0 HOME="$TMPROOT/home" run_gate >/dev/null 2>&1
    echo $?
  }

  # ---- S1: tool != Edit/Write/MultiEdit -> allow silently
  local rc
  rc=$(run_with "$(build_input_simple "Read" "$TMPROOT/adapters/claude-code/agents/foo.md")")
  if [[ "$rc" == "0" ]]; then
    echo "self-test (S1) non-edit-tool-allow: PASS" >&2; PASSED=$((PASSED+1))
  else
    echo "self-test (S1) non-edit-tool-allow: FAIL (rc=$rc)" >&2; FAILED=$((FAILED+1))
  fi

  # ---- S2: target outside agents/ -> allow silently
  rc=$(run_with "$(build_input_simple "Write" "$TMPROOT/src/components/Foo.tsx")")
  if [[ "$rc" == "0" ]]; then
    echo "self-test (S2) non-agent-path-allow: PASS" >&2; PASSED=$((PASSED+1))
  else
    echo "self-test (S2) non-agent-path-allow: FAIL (rc=$rc)" >&2; FAILED=$((FAILED+1))
  fi

  # ---- S3: EXISTING agent file (grandfathered) edited without the bar -> allow
  mkdir -p "$TMPROOT/adapters/claude-code/agents"
  echo "# Some legacy agent with no golden case section at all" > "$TMPROOT/adapters/claude-code/agents/legacy-reviewer.md"
  rc=$(run_with "$(build_input_simple "Edit" "$TMPROOT/adapters/claude-code/agents/legacy-reviewer.md")")
  if [[ "$rc" == "0" ]]; then
    echo "self-test (S3) grandfathered-existing-agent-allow: PASS" >&2; PASSED=$((PASSED+1))
  else
    echo "self-test (S3) grandfathered-existing-agent-allow: FAIL (rc=$rc)" >&2; FAILED=$((FAILED+1))
  fi

  # ---- S4 (golden bad case): NEW agent Write with polished prose but no
  # GOLDEN CASE / no named failure modes / no canon — the exact shape this
  # bar exists to catch (doctrine/artifact-evidence-bar-full.md: "Not one
  # [reviewer] attacked the SHAPE of the design"). Must BLOCK.
  if command -v jq >/dev/null 2>&1; then
    NAIVE_CONTENT='---
name: shape-reviewer
description: Reviews the shape of a design carefully and thoroughly.
---

You are a careful, thorough reviewer. Read the proposal. Think about whether
it seems reasonable. If it seems reasonable, approve it. Be nice and
constructive in your feedback. Consider the pros and cons.'
    rc=$(run_with "$(build_input_write "$TMPROOT/adapters/claude-code/agents/shape-reviewer.md" "$NAIVE_CONTENT")")
    if [[ "$rc" == "2" ]]; then
      echo "self-test (S4) golden-bad-case-naive-agent-blocks: PASS" >&2; PASSED=$((PASSED+1))
    else
      echo "self-test (S4) golden-bad-case-naive-agent-blocks: FAIL (rc=$rc, expected 2)" >&2; FAILED=$((FAILED+1))
    fi
  else
    echo "self-test (S4) golden-bad-case-naive-agent-blocks: SKIP (no jq)" >&2
  fi

  # ---- S5 (golden good case): NEW agent Write with all seven properties
  # present, modeled on architecture-reviewer.md's real shape -> ALLOW.
  if command -v jq >/dev/null 2>&1; then
    GOOD_CONTENT='---
name: fixture-reviewer
description: World-class fixture reviewer for the self-test.
---

## Named failure modes
This job fails via anchoring, speculation-instead-of-measurement, and
rubber-stamping — each traced to a real past incident here.

## Structural protocol
Phase 0: derive your own answer BEFORE reading the proposal.
Phase 1: measure, do not speculate.

## Named canon
Applies Parnas, Brooks, Chesterton, and connascence by name — a real
framework, not a vibe.

## System hazard priors
This codebase has known landmines: process spawns are slow on this
system, hooks are blind to git operations.

## Output contract
Severity is blast-radius x likelihood. Confidence is PROVEN or
HYPOTHESIZED with a named refuter.

## Anti-rubber-stamp mechanism
You may not return SOUND without first writing a steelman of the
opposing design.

## GOLDEN CASE
A real historical defect: session X shipped a reviewer that agreed with
every proposal it saw because it never independently re-derived the
problem. A naive reviewer concludes "looks fine." This agent must
conclude NEEDS-RESHAPING because Phase 0 forces an independent baseline
that contradicts the proposal'"'"'s framing.'
    rc=$(run_with "$(build_input_write "$TMPROOT/adapters/claude-code/agents/fixture-reviewer.md" "$GOOD_CONTENT")")
    if [[ "$rc" == "0" ]]; then
      echo "self-test (S5) golden-good-case-compliant-agent-allows: PASS" >&2; PASSED=$((PASSED+1))
    else
      echo "self-test (S5) golden-good-case-compliant-agent-allows: FAIL (rc=$rc, expected 0)" >&2; FAILED=$((FAILED+1))
    fi
  else
    echo "self-test (S5) golden-good-case-compliant-agent-allows: SKIP (no jq)" >&2
  fi

  # ---- S6: MultiEdit fires the same gate (defense-in-depth for the
  # matcher hole) — targets an EXISTING (grandfathered) file since
  # MultiEdit cannot target a non-existent file.
  rc=$(run_with "$(build_input_simple "MultiEdit" "$TMPROOT/adapters/claude-code/agents/legacy-reviewer.md")")
  if [[ "$rc" == "0" ]]; then
    echo "self-test (S6) multiedit-matcher-covered: PASS" >&2; PASSED=$((PASSED+1))
  else
    echo "self-test (S6) multiedit-matcher-covered: FAIL (rc=$rc)" >&2; FAILED=$((FAILED+1))
  fi

  # ---- S7: NEW agent Write with GOLDEN CASE present but 30-char body
  # threshold not met (placeholder-shaped) -> BLOCK.
  if command -v jq >/dev/null 2>&1; then
    THIN_CONTENT='## GOLDEN CASE
TBD

## Named failure modes
failure mode placeholder
## Structural protocol
phase 0 placeholder
## Named canon
canon placeholder
## System hazard priors
this codebase placeholder
## Output contract
PROVEN placeholder
## Anti-rubber-stamp mechanism
steelman placeholder'
    rc=$(run_with "$(build_input_write "$TMPROOT/adapters/claude-code/agents/thin-reviewer.md" "$THIN_CONTENT")")
    if [[ "$rc" == "2" ]]; then
      echo "self-test (S7) thin-golden-case-body-blocks: PASS" >&2; PASSED=$((PASSED+1))
    else
      echo "self-test (S7) thin-golden-case-body-blocks: FAIL (rc=$rc, expected 2)" >&2; FAILED=$((FAILED+1))
    fi
  else
    echo "self-test (S7) thin-golden-case-body-blocks: SKIP (no jq)" >&2
  fi

  echo "" >&2
  # ---- S8: OBSERVE posture (the shipped default) — a golden-case-less new
  # agent is ALLOWED (rc 0) and the would-block verdict lands in the probe log.
  if command -v jq >/dev/null 2>&1; then
    mkdir -p "$TMPROOT/home/.claude/state"
    rc=$(run_with_observe "$(build_input_write "$TMPROOT/adapters/claude-code/agents/observe-case.md" "---
name: observe-case
description: naive agent with no golden case
---
# observe-case
just vibes")")
    if [[ "$rc" == "0" ]] && grep -q '"would_block":true' "$TMPROOT/home/.claude/state/agent-design-gate-probe.jsonl" 2>/dev/null; then
      echo "self-test (S8) observe-default-allows-and-records: PASS" >&2; PASSED=$((PASSED+1))
    else
      echo "self-test (S8) observe-default-allows-and-records: FAIL (rc=$rc)" >&2; FAILED=$((FAILED+1))
    fi
  else
    echo "self-test (S8) observe-default-allows-and-records: SKIP (no jq)" >&2
  fi

  echo "self-test summary: ${PASSED} passed, ${FAILED} failed (of $((PASSED + FAILED)) scenarios)" >&2
  if [[ "$FAILED" -gt 0 ]]; then return 1; fi
  return 0
}

# ============================================================
# Entry
# ============================================================

if [[ "${SELF_TEST:-0}" == "1" ]]; then
  cmd_self_test
  exit $?
fi

run_gate
exit $?
