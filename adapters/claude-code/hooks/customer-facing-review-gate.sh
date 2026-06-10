#!/bin/bash
# customer-facing-review-gate.sh — Stop hook (UX + customer-advocate review gate)
#
# Misha's directive (2026-06-02): a session that SPAWNS customer-facing build
# work must also involve BOTH the UX agent AND the customer-advocate agent
# (end-user-advocate) before it is allowed to wrap. HARD REQUIREMENT — the gate
# blocks session wrap (block-mode, the default) when a customer-facing spawn was
# made but one or both review agents were never invoked in the session.
#
# WHY THIS EXISTS  (the failure that motivated it — read it, don't rationalize it away)
# =====================================================================================
# On 2026-06-02 the Dispatch orchestrator spawned FOUR customer-facing sessions —
# Nav IA, Smart Import v2, doc-reviewer, support-backfill — with ZERO UX-agent and
# ZERO customer-advocate-agent involvement. The harness was SUPPOSED to require that
# review on customer-facing work but had no mechanism enforcing it: the requirement
# lived only as a social convention (rules in planning.md / testing.md), and a
# task-loaded orchestrator silently routed around it four times in one day.
#
# The cost of routing around UX/CX review on customer-facing work is exactly the
# cost the harness was built to prevent: shipping UI a contractor can't use, support
# docs written in the wrong voice, dead-end navigation, features that compile but
# confuse the target persona. "Tests pass" never catches this; only an adversarial
# user-perspective pass does. This gate moves the requirement from SOCIAL to
# MECHANICAL — the orchestrator CAN'T silently skip review even when it forgets.
#
# DESIGN (mirrors pr-health-snapshot-gate.sh + principles-compliance-gate.sh)
# ===========================================================================
# 1. Read JSON from stdin. Resolve transcript_path + session_id.
# 2. Defensive no-ops (exit 0): UX_REVIEW_GATE_DISABLE=1 (audit-logged),
#    no transcript, no jq, empty transcript.
# 3. Scan the WHOLE transcript for tool_use records (the agent cannot edit the
#    transcript). For each: tool name, subagent_type, and a text blob of the
#    spawn's prompt/title/tldr/description/cwd.
# 4. Classify each spawn surface:
#      - Spawn tools (mcp__ccd_session__spawn_task / mcp__ccd_session_mgmt__start_code_task)
#        and `Agent` dispatches to a BUILDER subagent_type are candidate
#        "build-spawns": classify their blob as customer-facing or not.
#      - `Agent` dispatches whose subagent_type is in the UX family or the CX
#        family are SATISFIERS, not build-spawns.
# 5. Track: did the session make >=1 customer-facing build-spawn? Did it invoke a
#    UX-family agent? A CX-family agent?
# 6. Verdict:
#      - No customer-facing build-spawn            -> exit 0 (gate not applicable).
#      - Customer-facing + UX-seen + CX-seen        -> exit 0 (allow).
#      - Customer-facing + (UX or CX missing):
#          - `[skip-ux-review: <reason>]` present   -> exit 0 (audit-logged).
#          - block-mode                              -> block via retry-guard
#                                                        (exit 2 + JSON decision),
#                                                        naming the missing family.
#          - warn-mode                               -> exit 0 + stderr warning.
#
# CLASSIFIER (customer-facing vs not)
# ===================================
#   STRONG signals (contractor-facing; OVERRIDE the platform/backend exclusion):
#     contractor | user-facing | support page | navigation | nav ia |
#     src/app/(dashboard) | (dashboard) | /dashboard | src/components/ | docs/support
#   WEAK signals (customer-facing ONLY if no exclusion signal is also present):
#     \bpage\b | \bUI\b | /admin
#   EXCLUSION signals (platform/backend; suppress WEAK, never STRONG):
#     (platform) | src/app/(platform) | platform-admin | src/lib/ | src/trigger/ |
#     migrations/ | tests-only
#   A spawn is customer-facing iff: STRONG matches, OR (WEAK matches AND no EXCLUSION).
#
# AGENT FAMILIES (subagent_type strings — the agent registry `name:` values)
# ==========================================================================
#   UX family : ux-designer | UX End-User Tester | Domain Expert Tester
#   CX family : end-user-advocate
#   (Audience Content Reviewer also counts toward the UX family — it is a
#    user-facing-content review. Extend UX_FAMILY / CX_FAMILY below if the
#    agent registry grows.)
#
# ESCAPE HATCHES (both audit-logged with a mandatory reason)
# ==========================================================
#   [skip-ux-review: <reason>]   footer in any assistant message (reason mandatory)
#   UX_REVIEW_GATE_DISABLE=1      env var (for harness-dev sessions editing this gate)
#   Audit log: ${UX_REVIEW_AUDIT_LOG:-$HOME/.claude/state/ux-review-gate-overrides.log}
#
# MODE
# ====
# Resolution order: UX_REVIEW_GATE_MODE env > ~/.claude/local/ux-review-gate-mode file > "block".
# Per the hard-requirement directive the default is `block`. Flip to warn per-machine
# by writing "warn" to the local file or exporting UX_REVIEW_GATE_MODE=warn.

set -u

# ============================================================
# Agent family definitions (subagent_type strings). Case-insensitive match.
# ============================================================
UX_FAMILY=("ux-designer" "UX End-User Tester" "Domain Expert Tester" "Audience Content Reviewer")
CX_FAMILY=("end-user-advocate")

# Spawn tool names that are always candidate build-spawns (no subagent_type).
SPAWN_TOOLS_RE='^(mcp__ccd_session__spawn_task|mcp__ccd_session_mgmt__start_code_task)$'

# Classifier regexes (LC_ALL=C grep -iE).
STRONG_RE='contractor|user-facing|user facing|support page|navigation|nav ia|src/app/\(dashboard\)|\(dashboard\)|/dashboard|src/components/|docs/support'
WEAK_RE='\bpage\b|\bUI\b|/admin'
EXCLUSION_RE='\(platform\)|src/app/\(platform\)|platform-admin|platform admin|\bsrc/lib/|\bsrc/trigger/|migrations/|tests-only|test-only|tests only'

# ------------------------------------------------------------
# in_family <subtype> <family-array-name> — 0 if subtype matches a family member
# (case-insensitive, exact string).
# ------------------------------------------------------------
in_family() {
  local subtype="$1"; shift
  local member lc_sub lc_mem
  lc_sub=$(printf '%s' "$subtype" | tr '[:upper:]' '[:lower:]')
  for member in "$@"; do
    lc_mem=$(printf '%s' "$member" | tr '[:upper:]' '[:lower:]')
    [[ "$lc_sub" == "$lc_mem" ]] && return 0
  done
  return 1
}

# ------------------------------------------------------------
# is_customer_facing <blob> — 0 if the spawn blob classifies customer-facing.
# ------------------------------------------------------------
is_customer_facing() {
  local blob="$1"
  if printf '%s' "$blob" | LC_ALL=C grep -iEq "$STRONG_RE" 2>/dev/null; then
    return 0
  fi
  if printf '%s' "$blob" | LC_ALL=C grep -iEq "$WEAK_RE" 2>/dev/null; then
    if printf '%s' "$blob" | LC_ALL=C grep -iEq "$EXCLUSION_RE" 2>/dev/null; then
      return 1   # weak signal but platform/backend exclusion present -> not customer-facing
    fi
    return 0
  fi
  return 1
}

# ------------------------------------------------------------
# audit_log <event> <session> <reason> — append an override line.
# ------------------------------------------------------------
audit_log() {
  local event="$1" sid="$2" reason="$3"
  local logf="${UX_REVIEW_AUDIT_LOG:-$HOME/.claude/state/ux-review-gate-overrides.log}"
  mkdir -p "$(dirname "$logf")" 2>/dev/null || return 0
  printf '%s\t%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown-time)" "$event" "${sid:-no-sid}" "$reason" >> "$logf" 2>/dev/null || true
}

# ============================================================
# --self-test (no Dispatch / no Agent runtime; fixture transcripts inline)
# ============================================================
if [[ "${1:-}" == "--self-test" ]]; then
  PASS=0
  FAIL=0

  # Build a JSONL transcript from a sequence of (kind, arg1, arg2) tool/text triples.
  # We assemble assistant messages each carrying a content array of tool_use / text.
  # Helpers emit one jq-built assistant line per call for simplicity.
  emit_spawn() {
    # $1 = path ; $2 = spawn tool name ; $3 = prompt blob
    jq -n --arg name "$2" --arg prompt "$3" \
      '{role:"assistant",message:{role:"assistant",content:[{type:"tool_use",name:$name,input:{prompt:$prompt}}]}}' >> "$1"
  }
  emit_agent() {
    # $1 = path ; $2 = subagent_type ; $3 = prompt blob
    jq -n --arg st "$2" --arg prompt "$3" \
      '{role:"assistant",message:{role:"assistant",content:[{type:"tool_use",name:"Agent",input:{subagent_type:$st,prompt:$prompt}}]}}' >> "$1"
  }
  emit_text() {
    # $1 = path ; $2 = assistant text
    jq -n --arg t "$2" \
      '{role:"assistant",message:{role:"assistant",content:[{type:"text",text:$t}]}}' >> "$1"
  }

  run_case() {
    # $1 = name ; $2 = expected_exit ; $3 = builder fn (populates $TFILE) ; $4 = mode
    local name="$1" expected_exit="$2" builder="$3" mode="${4:-block}"
    local tdir tfile actual
    tdir=$(mktemp -d 2>/dev/null || mktemp -d -t cfrg)
    tfile="$tdir/transcript.jsonl"
    : > "$tfile"
    TFILE="$tfile" "$builder"
    CFR_TRANSCRIPT="$tfile" \
    CFR_SESSION_ID="st-$name" \
    UX_REVIEW_GATE_MODE="$mode" \
    UX_REVIEW_AUDIT_LOG="$tdir/audit.log" \
    RETRY_GUARD_STATE_DIR="$tdir/state" \
      bash "${BASH_SOURCE[0]}" < /dev/null > "$tdir/out.txt" 2> "$tdir/err.txt"
    actual=$?
    CFR_LAST_ERR="$tdir/err.txt"   # exported path for assertion in caller
    cp "$tdir/err.txt" "$tdir/../last_err_$name.txt" 2>/dev/null || true
    LAST_ERR_CONTENT=$(cat "$tdir/err.txt" 2>/dev/null || echo "")
    rm -rf "$tdir"
    if [[ "$actual" -eq "$expected_exit" ]]; then
      echo "PASS  $name (exit $actual)"
      PASS=$((PASS+1))
      return 0
    else
      echo "FAIL  $name (expected exit $expected_exit, got $actual)"
      FAIL=$((FAIL+1))
      return 1
    fi
  }

  CF_PROMPT="Build the contractor-facing navigation IA for the support page under src/app/(dashboard)/."
  BACKEND_PROMPT="Refactor the billing reconciliation logic in src/lib/billing.ts and src/trigger/sync.ts; add a supabase migration. Tests-only changes elsewhere."
  PLATFORM_PROMPT="Update the internal platform-admin metrics page in src/app/(platform)/admin and its UI panel."

  # builders for each scenario
  b_cf_ux_cx()   { emit_spawn "$TFILE" "mcp__ccd_session_mgmt__start_code_task" "$CF_PROMPT"; emit_agent "$TFILE" "ux-designer" "review the nav IA plan"; emit_agent "$TFILE" "end-user-advocate" "author acceptance scenarios"; emit_text "$TFILE" "Done. DONE: shipped."; }
  b_cf_no_ux()   { emit_spawn "$TFILE" "mcp__ccd_session_mgmt__start_code_task" "$CF_PROMPT"; emit_agent "$TFILE" "end-user-advocate" "author acceptance scenarios"; emit_text "$TFILE" "Done. DONE: shipped."; }
  b_cf_no_cx()   { emit_spawn "$TFILE" "mcp__ccd_session_mgmt__start_code_task" "$CF_PROMPT"; emit_agent "$TFILE" "ux-designer" "review the nav IA plan"; emit_text "$TFILE" "Done. DONE: shipped."; }
  b_cf_skip()    { emit_spawn "$TFILE" "mcp__ccd_session_mgmt__start_code_task" "$CF_PROMPT"; emit_text "$TFILE" "Wrapping. [skip-ux-review: nav IA is a copy-only string change with no layout impact] DONE: shipped."; }
  b_backend()    { emit_spawn "$TFILE" "mcp__ccd_session_mgmt__start_code_task" "$BACKEND_PROMPT"; emit_text "$TFILE" "Done. DONE: shipped."; }
  b_platform()   { emit_spawn "$TFILE" "mcp__ccd_session_mgmt__start_code_task" "$PLATFORM_PROMPT"; emit_text "$TFILE" "Done. DONE: shipped."; }
  b_neither()    { emit_spawn "$TFILE" "mcp__ccd_session_mgmt__start_code_task" "$CF_PROMPT"; emit_text "$TFILE" "Done. DONE: shipped."; }

  # ST1 — customer-facing + UX + CX -> allow
  run_case "customer-facing-with-ux-and-cx-passes" 0 b_cf_ux_cx  block
  # ST2 — customer-facing, CX present but UX missing -> block
  run_case "customer-facing-no-ux-blocks"          2 b_cf_no_ux  block
  # ST3 — customer-facing, UX present but CX missing -> block
  run_case "customer-facing-no-cx-blocks"          2 b_cf_no_cx  block
  # ST4 — customer-facing + skip-flag -> allow
  run_case "customer-facing-with-skip-flag-passes" 0 b_cf_skip   block
  # ST5 — backend-only spawn -> allow without UX
  run_case "backend-only-passes-without-ux"        0 b_backend   block
  # ST6 — platform-only spawn -> allow without UX
  run_case "platform-only-passes-without-ux"       0 b_platform  block

  # ST7 — malformed input (no transcript file) -> graceful no-op (exit 0)
  TDIR7=$(mktemp -d 2>/dev/null || mktemp -d -t cfrg7)
  CFR_TRANSCRIPT="/nonexistent/path/never.jsonl" CFR_SESSION_ID="st-malformed" \
  UX_REVIEW_GATE_MODE="block" UX_REVIEW_AUDIT_LOG="$TDIR7/audit.log" RETRY_GUARD_STATE_DIR="$TDIR7/state" \
    bash "${BASH_SOURCE[0]}" < /dev/null > /dev/null 2>&1
  if [[ $? -eq 0 ]]; then echo "PASS  malformed-input-fails-gracefully (exit 0)"; PASS=$((PASS+1)); else echo "FAIL  malformed-input-fails-gracefully"; FAIL=$((FAIL+1)); fi
  rm -rf "$TDIR7"

  # ST8 — both agents missing -> block AND the message clearly flags BOTH families.
  TDIR8=$(mktemp -d 2>/dev/null || mktemp -d -t cfrg8)
  TF8="$TDIR8/t.jsonl"; : > "$TF8"
  TFILE="$TF8" b_neither
  CFR_TRANSCRIPT="$TF8" CFR_SESSION_ID="st-flags-clearly" \
  UX_REVIEW_GATE_MODE="block" UX_REVIEW_AUDIT_LOG="$TDIR8/audit.log" RETRY_GUARD_STATE_DIR="$TDIR8/state" \
    bash "${BASH_SOURCE[0]}" < /dev/null > /dev/null 2> "$TDIR8/err.txt"
  ST8_EXIT=$?
  ST8_ERR=$(cat "$TDIR8/err.txt" 2>/dev/null || echo "")
  rm -rf "$TDIR8"
  if [[ "$ST8_EXIT" -eq 2 ]] \
     && printf '%s' "$ST8_ERR" | LC_ALL=C grep -iq "UX" \
     && printf '%s' "$ST8_ERR" | LC_ALL=C grep -iq "advocate"; then
    echo "PASS  missing-agents-defined-flags-clearly (exit 2 + names both families)"
    PASS=$((PASS+1))
  else
    echo "FAIL  missing-agents-defined-flags-clearly (exit $ST8_EXIT; err did not name both families)"
    FAIL=$((FAIL+1))
  fi

  # Bonus — disable env short-circuits even on a blocking case (defense check).
  TDIR9=$(mktemp -d 2>/dev/null || mktemp -d -t cfrg9)
  TF9="$TDIR9/t.jsonl"; : > "$TF9"
  TFILE="$TF9" b_neither
  CFR_TRANSCRIPT="$TF9" CFR_SESSION_ID="st-disable" UX_REVIEW_GATE_DISABLE=1 \
  UX_REVIEW_AUDIT_LOG="$TDIR9/audit.log" RETRY_GUARD_STATE_DIR="$TDIR9/state" \
    bash "${BASH_SOURCE[0]}" < /dev/null > /dev/null 2>&1
  if [[ $? -eq 0 ]]; then echo "PASS  disable-env-allows (exit 0, bonus)"; PASS=$((PASS+1)); else echo "FAIL  disable-env-allows (bonus)"; FAIL=$((FAIL+1)); fi
  rm -rf "$TDIR9"

  echo ""
  echo "self-test: $PASS pass, $FAIL fail"
  if [[ "$FAIL" -gt 0 ]]; then echo "self-test: FAIL"; exit 1; fi
  echo "self-test: OK $PASS/$PASS"
  exit 0
fi

# ============================================================
# Normal path
# ============================================================

# Shared retry-guard library (3-retry downgrade-to-warn loop-break).
# shellcheck disable=SC1091
source "${BASH_SOURCE[0]%/*}/lib/stop-hook-retry-guard.sh"

INPUT=""
if [[ ! -t 0 ]]; then
  INPUT=$(cat 2>/dev/null || echo "")
fi

TRANSCRIPT_PATH=""
SESSION_ID=""
if [[ -n "$INPUT" ]]; then
  TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // .session.transcript_path // empty' 2>/dev/null || echo "")
  SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // .session.id // empty' 2>/dev/null || echo "")
fi

# Self-test / direct overrides.
[[ -n "${CFR_TRANSCRIPT:-}" ]] && TRANSCRIPT_PATH="$CFR_TRANSCRIPT"
[[ -n "${CFR_SESSION_ID:-}" ]] && SESSION_ID="$CFR_SESSION_ID"

# Defensive no-ops.
if [[ "${UX_REVIEW_GATE_DISABLE:-0}" = "1" ]]; then
  audit_log "disable-env" "$SESSION_ID" "UX_REVIEW_GATE_DISABLE=1"
  exit 0
fi
if [[ -z "$TRANSCRIPT_PATH" ]] || [[ ! -f "$TRANSCRIPT_PATH" ]]; then exit 0; fi
if ! command -v jq >/dev/null 2>&1; then exit 0; fi

# Mode resolution: env > local file > "block" (hard-requirement default).
MODE="${UX_REVIEW_GATE_MODE:-}"
if [[ -z "$MODE" ]] && [[ -f "$HOME/.claude/local/ux-review-gate-mode" ]]; then
  MODE=$(tr -d '[:space:]' < "$HOME/.claude/local/ux-review-gate-mode" 2>/dev/null || echo "")
fi
[[ -z "$MODE" ]] && MODE="block"
[[ "$MODE" != "warn" ]] && MODE="block"

# ------------------------------------------------------------
# Extract every tool_use record as: name <US> subagent_type <US> blob
# where <US> is ASCII Unit Separator (\x1f). A non-whitespace separator is
# REQUIRED: IFS=$'\t' collapses consecutive tabs (tab is IFS-whitespace), so an
# empty subagent_type field would vanish and shift the blob into the wrong slot.
# The blob has its own newlines/tabs squashed to spaces inside jq so each record
# is exactly one physical line; `tr -d '\r'` strips the CRLF jq emits on Windows.
# ------------------------------------------------------------
TOOL_RECORDS=$(jq -r '
  select(type=="object")
  | (.message.content // .content // empty)
  | if type=="array" then .[] else empty end
  | select(type=="object" and (.type//"")=="tool_use")
  | (.name // "") as $n
  | (.input.subagent_type // "") as $s
  | ([ (.input.prompt//""), (.input.title//""), (.input.tldr//""),
       (.input.description//""), (.input.cwd//"") ] | join(" ") | gsub("[\\r\\n\\t]"; " ")) as $b
  | [$n, $s, $b] | join("")
' "$TRANSCRIPT_PATH" 2>/dev/null | tr -d '\r')

# No tool calls at all — nothing to gate. Defer to other hooks.
if [[ -z "$TOOL_RECORDS" ]]; then exit 0; fi

CUSTOMER_FACING_SPAWN=0
UX_SEEN=0
CX_SEEN=0

while IFS=$'\x1f' read -r tname tsubtype tblob; do
  [[ -z "$tname" ]] && continue

  # Satisfiers: Agent dispatches to a UX-family / CX-family subagent_type.
  if [[ "$tname" == "Agent" ]] && [[ -n "$tsubtype" ]]; then
    if in_family "$tsubtype" "${UX_FAMILY[@]}"; then UX_SEEN=1; continue; fi
    if in_family "$tsubtype" "${CX_FAMILY[@]}"; then CX_SEEN=1; continue; fi
  fi

  # Build-spawn candidates: Dispatch spawn tools, or Agent dispatches to a
  # non-review subagent_type (builders: plan-phase-builder, general-purpose,
  # claude, Explore, etc.).
  is_build_spawn=0
  if printf '%s' "$tname" | LC_ALL=C grep -Eq "$SPAWN_TOOLS_RE" 2>/dev/null; then
    is_build_spawn=1
  elif [[ "$tname" == "Agent" ]]; then
    # An Agent dispatch that is not a UX/CX satisfier counts as a build-spawn.
    is_build_spawn=1
  fi

  if [[ "$is_build_spawn" -eq 1 ]]; then
    if is_customer_facing "$tblob"; then
      CUSTOMER_FACING_SPAWN=1
    fi
  fi
done <<< "$TOOL_RECORDS"

# Gate not applicable: no customer-facing build-spawn this session.
if [[ "$CUSTOMER_FACING_SPAWN" -eq 0 ]]; then exit 0; fi

# Both review families present -> allow.
if [[ "$UX_SEEN" -eq 1 ]] && [[ "$CX_SEEN" -eq 1 ]]; then exit 0; fi

# ------------------------------------------------------------
# Escape hatch: [skip-ux-review: <reason>] in any assistant message.
# ------------------------------------------------------------
ASSIST_TEXT=$(jq -r '
  select(type=="object")
  | select((.role // .message.role // "") == "assistant")
  | (.content // .text // .message.content // empty)
  | if type=="string" then .
    elif type=="array" then ([.[] | select(type=="object" and (.type//"")=="text") | (.text//"")] | join("\n"))
    else empty end
  | select(. != "")
' "$TRANSCRIPT_PATH" 2>/dev/null | tr '\n' ' ')

SKIP_REASON=$(printf '%s' "$ASSIST_TEXT" | LC_ALL=C grep -oiE '\[skip-ux-review:[[:space:]]*[^]]+\]' 2>/dev/null | head -n 1)
if [[ -n "$SKIP_REASON" ]]; then
  # Extract the reason text between ':' and ']' and require it be non-empty.
  REASON_BODY=$(printf '%s' "$SKIP_REASON" | sed -E 's/^\[skip-ux-review:[[:space:]]*//I; s/\][[:space:]]*$//')
  if [[ -n "${REASON_BODY// /}" ]]; then
    audit_log "skip-flag" "$SESSION_ID" "$REASON_BODY"
    echo "[customer-facing-review-gate] skip-ux-review honored — reason: ${REASON_BODY} (audit-logged)" >&2
    exit 0
  fi
fi

# ------------------------------------------------------------
# Build the missing-family list (drives the "flags clearly" requirement).
# ------------------------------------------------------------
MISSING=""
[[ "$UX_SEEN" -eq 0 ]] && MISSING="UX agent (one of: ${UX_FAMILY[*]})"
if [[ "$CX_SEEN" -eq 0 ]]; then
  if [[ -n "$MISSING" ]]; then MISSING="${MISSING} AND customer-advocate agent (${CX_FAMILY[*]})";
  else MISSING="customer-advocate agent (${CX_FAMILY[*]})"; fi
fi

BLOCKER_MSG="CUSTOMER-FACING REVIEW MISSING. This session spawned customer-facing build work but never invoked the required review agent(s): ${MISSING}. Customer-facing work (contractor UI, dashboard pages, navigation, support docs) MUST be reviewed by BOTH the UX agent AND the customer-advocate agent (end-user-advocate) before the session wraps — this is a hard requirement (rules/customer-facing-review.md). On 2026-06-02 the orchestrator silently routed around this review on four customer-facing sessions in one day; this gate exists so that can't recur. To clear: invoke the missing agent(s) via the Agent tool and incorporate their findings, OR — if review is genuinely not warranted — add a [skip-ux-review: <reason>] footer to your final message (reason mandatory, audit-logged), then re-attempt Stop."

# warn-mode -> allow + warn.
if [[ "$MODE" = "warn" ]]; then
  echo "" >&2
  echo "[customer-facing-review-gate] WARNING (warn-mode): ${BLOCKER_MSG}" >&2
  echo "" >&2
  exit 0
fi

# block-mode -> route through the retry-guard (3-retry downgrade-to-warn).
echo "" >&2
echo "================================================================" >&2
echo "CUSTOMER-FACING REVIEW GATE: SESSION BLOCKED" >&2
echo "================================================================" >&2
echo "$BLOCKER_MSG" >&2
echo "" >&2

RG_SESSION_ID=$(retry_guard_session_id "$INPUT")
[[ -z "$RG_SESSION_ID" ]] && RG_SESSION_ID="${SESSION_ID:-cfr-nosid}"
retry_guard_block_or_exit \
  "customer-facing-review-gate" \
  "$RG_SESSION_ID" \
  "cfr-missing:ux=${UX_SEEN}:cx=${CX_SEEN}" \
  "$BLOCKER_MSG" \
  "{\"decision\": \"block\", \"reason\": \"Customer-facing work spawned without required UX + customer-advocate review. Missing: ${MISSING}. Invoke the agent(s) or add a [skip-ux-review: <reason>] footer.\"}" \
  2
