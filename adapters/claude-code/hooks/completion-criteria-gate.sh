#!/bin/bash
# completion-criteria-gate.sh — Stop hook (feature-completion-criteria gate)
#
# Misha's directive (2026-06-01): "intended but not finished" is a binary
# failure, not gradual drift. Today the only enforced bar for "a feature is
# shipped" is criterion #1 — code merged to master. Every other completion
# criterion (tests, dev docs, user docs, migration-applied, deploy-verified,
# acceptance-criteria-verified, stakeholder-notified) lives in human attention
# and is therefore systematically missed: F4 Platform Console, C-47 transfer
# flow, ODS Twilio, Smart Import, the What's-New redesign — all merged +
# deployed, none with user-facing support docs. This gate moves the completion
# definition from SOCIAL to MECHANICAL, which is the only way it holds across
# many parallel sessions.
#
# WHY THIS EXISTS
# ===============
# "Code merged" is the easiest exit signal for an LLM session — the commit
# landed, the PR is green, so the session declares the feature shipped and
# stops. The other seven criteria are invisible to that signal. A memory rule
# ("remember to add docs") drifts under exactly the context pressure where it
# matters most. So this is a HARD REQUIREMENT (block-mode default, mirroring
# pr-health-snapshot-gate.sh): when a session's final message DECLARES a
# feature shipped, the gate requires the message to also account for ALL EIGHT
# completion criteria — each either checked-off-with-evidence (a commit SHA,
# PR#, route, .mdx path, test/artifact reference) or explicitly N/A with a
# justification. Anything less blocks the session wrap.
#
# This gate is the fast IN-SESSION backstop. The thorough POST-FACT net is
# feature-completion-audit.sh, which walks shipped features against real
# production state and catches what the gate's phrase-trigger misses. Two
# layers, by design: the gate favors false-negatives (a real shipment with
# unusual phrasing slips the gate) precisely because the periodic audit is the
# catch-all. A gate that fired on EVERY session would be noise; a gate scoped
# to feature-shipment phrasing + an audit backstop is signal.
#
# THE EIGHT CRITERIA (keys are the COMPLETION_GATE_SKIP tokens)
# ============================================================
#   1. code        — Code merged to master
#   2. tests       — Tests added (unit / integration / E2E as appropriate)
#   3. dev_docs    — Dev docs updated (ADR / architecture / runbook)
#   4. user_docs   — User docs updated (docs/support/*.mdx for contractor-facing)
#   5. migration   — Migration applied (schema live on prod, not just in repo)
#   6. deploy      — Vercel master deploy succeeded for the merged commit
#   7. acceptance  — Acceptance criteria explicitly verified (test/smoke/screenshot)
#   8. stakeholder — Stakeholder / team notified if relevant
#
# DESIGN (mirrors pr-health-snapshot-gate.sh + goal-coverage-on-stop.sh)
# =====================================================================
# 1. Read JSON from stdin. Resolve transcript_path + session_id.
# 2. Defensive no-ops (exit 0): no transcript, no jq, empty transcript,
#    COMPLETION_GATE_DISABLE=1.
# 3. Extract the LAST assistant message text from $TRANSCRIPT_PATH.
# 4. TRIGGER check: does the message DECLARE a feature shipped?
#    (feature shipped|complete|live ; shipped/deployed to master/production ;
#     Status: COMPLETED ; live in production ; + COMPLETION_GATE_EXTRA_TRIGGER).
#    No trigger -> exit 0 (this is NOT a feature-shipment session; the bare
#    session-end DONE: marker is handled by session-end-protocol, not here).
# 5. Triggered: require a `## Completion Criteria` section accounting for all 8.
#    Per criterion: PASS (check-mark + evidence token) OR N/A (+ justification).
#    Criteria in COMPLETION_GATE_SKIP are treated satisfied (audit-logged).
# 6. Verdict:
#      - All 8 satisfied                      -> exit 0 (allow).
#      - Section MISSING entirely             -> block (retry-guard).
#      - Section present, >=1 criterion unmet -> block naming the unmet ones.
#    block-mode is the default (hard requirement). warn-mode -> exit 0 + stderr.
#
# ESCAPE HATCHES
# ==============
# COMPLETION_GATE_DISABLE=1        — suppress all enforcement (harness-dev
#                                    sessions editing this gate; non-feature work).
# COMPLETION_GATE_SKIP=a,b,c       — per-criterion skip (e.g. user_docs,migration
#                                    for a dev-only feature). Each skip is
#                                    appended to .claude/state/completion-gate-skips.log
#                                    with the session id + timestamp (audit trail).
# COMPLETION_GATE_EXTRA_TRIGGER=re — add an ERE alternative to the trigger set.
#
# MODE
# ====
# Resolution order: COMPLETION_GATE_MODE env  >  ~/.claude/local/completion-gate-mode file  >  "block".
# Per the hard-requirement directive the default is `block` (like
# pr-health-snapshot-gate, unlike doc-gate's warn-default). Flip per-machine by
# writing "warn" to the local file or exporting COMPLETION_GATE_MODE=warn.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

REQUIRED_HEADING='## Completion Criteria'

# ------------------------------------------------------------
# Canonical criteria. Each row: key|Display name|keyword-ERE (matched
# case-insensitively against a section line to locate that criterion's line).
# Order is the canonical 1..8 ordering.
# ------------------------------------------------------------
CRIT_KEYS=(code tests dev_docs user_docs migration deploy acceptance stakeholder)
crit_display() {
  case "$1" in
    code)        echo "Code merged to master" ;;
    tests)       echo "Tests added" ;;
    dev_docs)    echo "Dev docs updated (ADR/architecture/runbook)" ;;
    user_docs)   echo "User docs updated (docs/support/*.mdx)" ;;
    migration)   echo "Migration applied to production" ;;
    deploy)      echo "Vercel master deploy succeeded" ;;
    acceptance)  echo "Acceptance criteria verified" ;;
    stakeholder) echo "Stakeholder / team notified" ;;
    *)           echo "$1" ;;
  esac
}
# Keyword ERE per criterion (case-insensitive). A section line matching this
# is taken to be that criterion's check-off line.
crit_keyword_re() {
  case "$1" in
    code)        echo 'code merged|merged to master|code merge|code:[[:space:]]' ;;
    tests)       echo 'test' ;;
    dev_docs)    echo 'dev doc|dev-doc|developer doc|adr|architecture|runbook' ;;
    user_docs)   echo 'user doc|user-doc|support doc|support page|\.mdx|docs/support' ;;
    migration)   echo 'migration|schema' ;;
    deploy)      echo 'deploy|vercel' ;;
    acceptance)  echo 'acceptance' ;;
    stakeholder) echo 'stakeholder|notif|notified|support team|team alert' ;;
    *)           echo "$1" ;;
  esac
}

# Evidence token ERE: a PASS check-off must carry at least one of these.
# SHA | #PR-or-channel | @handle | URL | file-with-ext | /route | artifact keyword.
# (#support is legitimate stakeholder-notification evidence — a Slack channel —
#  so #-handles are accepted, not only numeric #PR refs.)
EVIDENCE_RE='[0-9a-f]{7,40}|#[A-Za-z0-9][A-Za-z0-9_-]*|@[A-Za-z][A-Za-z0-9_-]*|https?://|[A-Za-z0-9_./-]+\.(mdx|md|tsx?|jsx?|sql|sh|ya?ml|json|png|jpe?g|csv)|/[a-z][A-Za-z0-9_/-]+|screenshot|smoke[- ]?test|playwright|curl |migration [0-9]+|deploy[a-z]* (green|success|succeeded|verified)'

# Check-mark ERE (ASCII [x] plus common unicode ticks). Fixtures use ASCII.
CHECK_RE='\[[xX]\]|✓|✅|✔|☑'

# ------------------------------------------------------------
# classify_criterion <key> <section-text>
# Echoes one of: SATISFIED | NA | NOEVIDENCE | NOVERDICT | MISSING
#   SATISFIED  — a line matches the keyword + has check-mark + evidence token
#   NA         — a line matches the keyword + "N/A" + a justification clause
#   NOEVIDENCE — a line matches keyword + check-mark but NO evidence token
#   NOVERDICT  — a line matches keyword but neither a valid PASS nor a valid N/A
#   MISSING    — no line matches the keyword at all
# ------------------------------------------------------------
classify_criterion() {
  local key="$1" section="$2"
  local kw; kw="$(crit_keyword_re "$key")"
  # All section lines mentioning this criterion's keyword.
  local lines
  lines="$(printf '%s\n' "$section" | grep -iE "$kw" 2>/dev/null || true)"
  if [[ -z "$lines" ]]; then
    echo "MISSING"; return 0
  fi
  local saw_na=0 saw_check=0 saw_check_noevidence=0 line
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    # N/A with a justification clause (separator + >=4 letters of reason).
    if printf '%s' "$line" | grep -iqE 'n/?a\b|not applicable' 2>/dev/null; then
      if printf '%s' "$line" | grep -iqE '(n/?a\b|not applicable).*[-—:].*[A-Za-z]{4}' 2>/dev/null; then
        echo "NA"; return 0
      else
        saw_na=1
      fi
      continue
    fi
    # PASS = check-mark AND evidence token.
    if printf '%s' "$line" | grep -qE "$CHECK_RE" 2>/dev/null; then
      if printf '%s' "$line" | grep -qiE "$EVIDENCE_RE" 2>/dev/null; then
        echo "SATISFIED"; return 0
      else
        saw_check_noevidence=1
      fi
    fi
  done <<< "$lines"
  if [[ "$saw_check_noevidence" -eq 1 ]]; then echo "NOEVIDENCE"; return 0; fi
  if [[ "$saw_na" -eq 1 ]]; then echo "NOVERDICT"; return 0; fi
  echo "NOVERDICT"
}

# ============================================================
# --self-test (gh-free, jq-only; fixture transcripts generated inline)
# ============================================================
if [[ "${1:-}" == "--self-test" ]]; then
  PASS=0
  FAIL=0

  make_transcript() {
    local path="$1" body="$2"
    {
      printf '{"role":"user","content":"ship the feature"}\n'
      jq -n --arg t "$body" '{role:"assistant",content:[{type:"text",text:$t}]}'
    } > "$path"
  }

  run_case() {
    local name="$1" expected_exit="$2" body="$3" mode="${4:-block}" skip="${5:-}"
    local tdir tfile actual
    tdir=$(mktemp -d 2>/dev/null || mktemp -d -t ccg)
    tfile="$tdir/transcript.jsonl"
    make_transcript "$tfile" "$body"
    COMPLETION_GATE_TRANSCRIPT="$tfile" \
    COMPLETION_GATE_SESSION_ID="st-$name" \
    COMPLETION_GATE_MODE="$mode" \
    COMPLETION_GATE_SKIP="$skip" \
    RETRY_GUARD_STATE_DIR="$tdir/state" \
    COMPLETION_GATE_SKIPLOG="$tdir/skips.log" \
      bash "${BASH_SOURCE[0]}" < /dev/null > /dev/null 2>&1
    actual=$?
    rm -rf "$tdir"
    if [[ "$actual" -eq "$expected_exit" ]]; then
      echo "PASS  $name (exit $actual)"
      PASS=$((PASS+1))
    else
      echo "FAIL  $name (expected exit $expected_exit, got $actual)"
      FAIL=$((FAIL+1))
    fi
  }

  # A trigger phrase + a complete, fully-evidenced Completion Criteria section.
  FULL_BODY=$'Feature shipped to production.\n\n## Completion Criteria\n\n- [x] Code merged to master — PR #412, commit ab12cd3\n- [x] Tests added — e2e/transfer.spec.ts, unit coverage in src/lib/transfer.test.ts\n- [x] Dev docs updated — docs/decisions/047-transfer.md (ADR)\n- [x] User docs updated — docs/support/transfer.mdx\n- [x] Migration applied to production — migration 152 pushed, verified applied\n- [x] Vercel master deploy succeeded — deploy green for ab12cd3\n- [x] Acceptance criteria verified — smoke test against /contacts, screenshot captured\n- [x] Stakeholder notified — support team alerted in #support\n\nDONE: feature shipped.'

  # All eight N/A with justifications (legitimately dev-only feature).
  ALLNA_BODY=$'Feature complete (internal tooling, dev-only).\n\n## Completion Criteria\n\n- Code merged to master: N/A - internal spike, not merged to product master\n- Tests: N/A - throwaway prototype, no tests warranted\n- Dev docs: N/A - documented inline in the spike notes\n- User docs: N/A - dev-only tool, no contractor surface\n- Migration: N/A - no schema change in this change\n- Deploy: N/A - never deployed, local-only spike\n- Acceptance criteria: N/A - exploratory, no acceptance bar\n- Stakeholder: N/A - solo exploration, nobody to notify\n\nDONE.'

  # Trigger present, NO completion-criteria section at all.
  MISSING_BODY=$'Feature shipped to production. All good.\n\nDONE: feature shipped.'

  # One criterion missing (user_docs absent), rest present+evidenced.
  ONEMISSING_BODY=$'Feature shipped to master.\n\n## Completion Criteria\n\n- [x] Code merged to master — PR #412\n- [x] Tests added — e2e/transfer.spec.ts\n- [x] Dev docs updated — docs/decisions/047-x.md\n- [x] Migration applied to production — migration 152 verified\n- [x] Vercel master deploy succeeded — deploy green abc1234\n- [x] Acceptance criteria verified — smoke test /contacts\n- [x] Stakeholder notified — #support\n\n(user docs intentionally omitted)\n\nDONE.'

  # Only the code criterion present (code-only).
  CODEONLY_BODY=$'Feature shipped to production.\n\n## Completion Criteria\n\n- [x] Code merged to master — PR #412, commit ab12cd3\n\nDONE.'

  # Only the user_docs/dev_docs present (docs-only — no code/tests/etc.).
  DOCSONLY_BODY=$'Feature complete and live in production.\n\n## Completion Criteria\n\n- [x] User docs updated — docs/support/transfer.mdx\n- [x] Dev docs updated — docs/decisions/047-x.md\n\nDONE.'

  # Malformed: trigger present, heading present, body is unparseable garbage.
  MALFORMED_BODY=$'Feature shipped to production.\n\n## Completion Criteria\n\nlgtm shipped it all good no notes here\n\nDONE.'

  # Evidence-without-link: every criterion checked but NO evidence tokens.
  NOEVIDENCE_BODY=$'Feature shipped to production.\n\n## Completion Criteria\n\n- [x] Code merged to master\n- [x] Tests added\n- [x] Dev docs updated\n- [x] User docs updated\n- [x] Migration applied to production\n- [x] Vercel master deploy succeeded\n- [x] Acceptance criteria verified\n- [x] Stakeholder notified\n\nDONE.'

  # ===== The 8 named scenarios from the build spec =====
  run_case "full-evidence-passes"        0 "$FULL_BODY"        block   # 1
  run_case "one-missing-blocks"          2 "$ONEMISSING_BODY"  block   # 2
  run_case "all-na-passes"               0 "$ALLNA_BODY"       block   # 3
  run_case "code-only-fails"             2 "$CODEONLY_BODY"    block   # 4
  run_case "docs-only-fails"             2 "$DOCSONLY_BODY"    block   # 5
  run_case "malformed-fails-gracefully"  2 "$MALFORMED_BODY"   block   # 6
  run_case "evidence-without-link-fails" 2 "$NOEVIDENCE_BODY"  block   # 7
  run_case "all-present-passes"          0 "$FULL_BODY"        block   # 8 (alias of full)

  # ===== Defensive extras (a gate without these is fragile) =====
  # No trigger phrase at all -> not a feature-shipment session -> allow.
  NOTRIGGER_BODY=$'Investigated the bug, root-caused it. No changes shipped yet.\n\nPAUSING: need your call on the fix approach.'
  run_case "no-trigger-noop"             0 "$NOTRIGGER_BODY"   block
  # Missing section in warn-mode -> allow + warn.
  run_case "missing-warn-mode-allows"    0 "$MISSING_BODY"     warn
  # Missing section in block-mode -> block.
  run_case "missing-blocks-block-mode"   2 "$MISSING_BODY"     block
  # Per-criterion SKIP closes the only gap -> allow + audit-log the skip.
  run_case "skip-closes-gap-allows"      0 "$ONEMISSING_BODY"  block "user_docs"

  # disable env -> allow regardless of trigger + missing section.
  TDIRD=$(mktemp -d 2>/dev/null || mktemp -d -t ccgd)
  make_transcript "$TDIRD/t.jsonl" "$MISSING_BODY"
  COMPLETION_GATE_TRANSCRIPT="$TDIRD/t.jsonl" COMPLETION_GATE_SESSION_ID="st-disable" \
  COMPLETION_GATE_DISABLE=1 \
    bash "${BASH_SOURCE[0]}" < /dev/null > /dev/null 2>&1
  if [[ $? -eq 0 ]]; then echo "PASS  disable-env-allows (exit 0)"; PASS=$((PASS+1)); else echo "FAIL  disable-env-allows"; FAIL=$((FAIL+1)); fi
  rm -rf "$TDIRD"

  # no transcript file -> defensive no-op.
  COMPLETION_GATE_TRANSCRIPT="/nonexistent/path/ccg.jsonl" COMPLETION_GATE_SESSION_ID="st-notx" \
  COMPLETION_GATE_MODE="block" \
    bash "${BASH_SOURCE[0]}" < /dev/null > /dev/null 2>&1
  if [[ $? -eq 0 ]]; then echo "PASS  no-transcript-noop (exit 0)"; PASS=$((PASS+1)); else echo "FAIL  no-transcript-noop"; FAIL=$((FAIL+1)); fi

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
[[ -n "${COMPLETION_GATE_TRANSCRIPT:-}" ]] && TRANSCRIPT_PATH="$COMPLETION_GATE_TRANSCRIPT"
[[ -n "${COMPLETION_GATE_SESSION_ID:-}" ]] && SESSION_ID="$COMPLETION_GATE_SESSION_ID"

# Defensive no-ops.
if [[ "${COMPLETION_GATE_DISABLE:-0}" = "1" ]]; then exit 0; fi
if [[ -z "$TRANSCRIPT_PATH" ]] || [[ ! -f "$TRANSCRIPT_PATH" ]]; then exit 0; fi
if ! command -v jq >/dev/null 2>&1; then exit 0; fi

# Mode resolution: env > local file > "warn" (default; set "block" in env/file to hard-block).
# 2026-06-20: default flipped block->warn (see pr-health-snapshot-gate.sh for rationale).
MODE="${COMPLETION_GATE_MODE:-}"
if [[ -z "$MODE" ]] && [[ -f "$HOME/.claude/local/completion-gate-mode" ]]; then
  MODE=$(tr -d '[:space:]' < "$HOME/.claude/local/completion-gate-mode" 2>/dev/null || echo "")
fi
[[ -z "$MODE" ]] && MODE="warn"
[[ "$MODE" != "block" ]] && MODE="warn"

# Extract the LAST assistant message (full text; base64 to survive newlines).
LAST_B64=$(jq -r '
  select(.role == "assistant" or .message.role == "assistant")
  | (.content // .text // .message.content // empty)
  | (if type == "string" then .
     elif type == "array" then ([.[] | select(type=="object" and (.type//"")=="text") | (.text // "")] | join("\n"))
     else (. | tostring) end)
  | select(. != "")
  | @base64
' "$TRANSCRIPT_PATH" 2>/dev/null | tail -n 1)

if [[ -z "$LAST_B64" ]]; then exit 0; fi
LAST_ASSISTANT=$(printf '%s' "$LAST_B64" | base64 --decode 2>/dev/null || printf '')

# ============================================================
# TRIGGER check — does this message DECLARE a feature shipped?
# ============================================================
TRIGGER_RE='feature[[:space:]]+(is[[:space:]]+|now[[:space:]]+)?(shipped|complete|completed|done|live)|(shipped|deployed)[[:space:]]+to[[:space:]]+(master|production|prod)|live[[:space:]]+in[[:space:]]+production|Status:[[:space:]]*COMPLETED|feature[[:space:]]+is[[:space:]]+now[[:space:]]+live'
if [[ -n "${COMPLETION_GATE_EXTRA_TRIGGER:-}" ]]; then
  TRIGGER_RE="${TRIGGER_RE}|${COMPLETION_GATE_EXTRA_TRIGGER}"
fi

if ! printf '%s' "$LAST_ASSISTANT" | grep -iqE "$TRIGGER_RE" 2>/dev/null; then
  # Not a feature-shipment declaration. The bare session-end DONE: marker is
  # session-end-protocol's job, not this gate's. Allow.
  exit 0
fi

# ============================================================
# Triggered — require + validate the Completion Criteria section
# ============================================================

# Parse COMPLETION_GATE_SKIP into a normalized list (accept comma/space; map
# a few friendly aliases to canonical keys).
declare -A SKIP_SET=()
normalize_skip_key() {
  case "$1" in
    acceptance_criteria|acceptance-criteria) echo "acceptance" ;;
    dev-docs|devdocs|dev_doc)                echo "dev_docs" ;;
    user-docs|userdocs|user_doc|support_docs) echo "user_docs" ;;
    deploy_verification|deployment)          echo "deploy" ;;
    *)                                       echo "$1" ;;
  esac
}
RAW_SKIP="${COMPLETION_GATE_SKIP:-}"
if [[ -n "$RAW_SKIP" ]]; then
  for tok in $(printf '%s' "$RAW_SKIP" | tr ',' ' '); do
    [[ -z "$tok" ]] && continue
    nk="$(normalize_skip_key "$tok")"
    SKIP_SET["$nk"]=1
  done
fi

# Extract the `## Completion Criteria` section (heading -> next `## ` or EOF).
SECTION=$(printf '%s\n' "$LAST_ASSISTANT" | awk '
  BEGIN { inSec=0 }
  /^[[:space:]]*#{2,3}[[:space:]]*[Cc]ompletion [Cc]riteria[[:space:]]*$/ { inSec=1; next }
  inSec==1 && /^[[:space:]]*##[[:space:]]/ { inSec=0 }
  inSec==1 { print }
')

HAS_SECTION=0
if printf '%s' "$LAST_ASSISTANT" | grep -qiE '^[[:space:]]*#{2,3}[[:space:]]*completion criteria[[:space:]]*$' 2>/dev/null; then
  HAS_SECTION=1
fi

# Audit-log any criterion skips (one line per skip; survives the session).
SKIPLOG="${COMPLETION_GATE_SKIPLOG:-.claude/state/completion-gate-skips.log}"
log_skip() {
  local key="$1"
  mkdir -p "$(dirname "$SKIPLOG")" 2>/dev/null || true
  local ts; ts=$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date)
  printf '%s\tsession=%s\tcriterion=%s\n' "$ts" "${SESSION_ID:-unknown}" "$key" >> "$SKIPLOG" 2>/dev/null || true
}

# Evaluate the 8 criteria. UNMET accumulates "key:status" for the block message.
UNMET=""
SATISFIED_COUNT=0
for key in "${CRIT_KEYS[@]}"; do
  if [[ -n "${SKIP_SET[$key]:-}" ]]; then
    log_skip "$key"
    SATISFIED_COUNT=$((SATISFIED_COUNT+1))
    continue
  fi
  if [[ "$HAS_SECTION" -eq 0 ]]; then
    UNMET="${UNMET}${key}:MISSING-SECTION "
    continue
  fi
  status="$(classify_criterion "$key" "$SECTION")"
  case "$status" in
    SATISFIED|NA) SATISFIED_COUNT=$((SATISFIED_COUNT+1)) ;;
    *)            UNMET="${UNMET}${key}:${status} " ;;
  esac
done
UNMET="${UNMET% }"

# All eight satisfied (or skipped) -> allow.
if [[ -z "$UNMET" ]]; then
  exit 0
fi

# ============================================================
# Build the block message
# ============================================================
explain_status() {
  case "$1" in
    MISSING-SECTION) echo "no '## Completion Criteria' section in the final message" ;;
    MISSING)         echo "criterion not mentioned in the section" ;;
    NOEVIDENCE)      echo "checked off but NO evidence (need a commit SHA / PR# / route / .mdx path / test or artifact ref)" ;;
    NOVERDICT)       echo "mentioned but neither checked-off-with-evidence nor a justified N/A" ;;
    *)               echo "$1" ;;
  esac
}

UNMET_LINES=""
for pair in $UNMET; do
  k="${pair%%:*}"; s="${pair#*:}"
  UNMET_LINES="${UNMET_LINES}  - ${k} ($(crit_display "$k")): $(explain_status "$s")\n"
done

BLOCKER_MSG="FEATURE-COMPLETION CRITERIA INCOMPLETE. This session's final message DECLARES a feature shipped, but ${#CRIT_KEYS[@]}-criteria completion is not fully accounted for (rules/completion-criteria.md). 'Code merged' is only criterion #1 — a feature is not shipped until tests, dev docs, user docs, migration-applied, deploy-verified, acceptance-verified, and stakeholder-notified are each either done-with-evidence or explicitly N/A-with-justification. Unmet: ${UNMET}"

if [[ "$MODE" = "warn" ]]; then
  echo "" >&2
  echo "[completion-criteria-gate] WARNING (warn-mode): ${BLOCKER_MSG}" >&2
  echo -e "$UNMET_LINES" >&2
  echo "" >&2
  exit 0
fi

# block-mode: route through the retry-guard (3-retry downgrade-to-warn).
{
  echo ""
  echo "================================================================"
  echo "COMPLETION-CRITERIA GATE: SESSION BLOCKED"
  echo "================================================================"
  echo "$BLOCKER_MSG"
  echo ""
  echo "Unmet criteria:"
  echo -e "$UNMET_LINES"
  echo "To clear: add a '## Completion Criteria' section to your final message"
  echo "covering ALL EIGHT, each as ✓ + evidence OR N/A + justification, e.g.:"
  echo ""
  echo "    ## Completion Criteria"
  echo ""
  echo "    - [x] Code merged to master — PR #NNN, commit <sha>"
  echo "    - [x] Tests added — <test file / spec>"
  echo "    - [x] Dev docs updated — <ADR / runbook path>   (or N/A — <why>)"
  echo "    - [x] User docs updated — docs/support/<page>.mdx (or N/A — <why>)"
  echo "    - [x] Migration applied to production — migration NNN verified (or N/A — no schema change)"
  echo "    - [x] Vercel master deploy succeeded — deploy green for <sha>"
  echo "    - [x] Acceptance criteria verified — <test / smoke / screenshot>"
  echo "    - [x] Stakeholder / team notified — <who / where>   (or N/A — <why>)"
  echo ""
  echo "Escape hatches: COMPLETION_GATE_SKIP=user_docs,migration (per-criterion,"
  echo "audit-logged); COMPLETION_GATE_DISABLE=1 (non-feature / harness-dev work)."
  echo ""
} >&2

RG_SESSION_ID=$(retry_guard_session_id "$INPUT")
[[ -z "$RG_SESSION_ID" ]] && RG_SESSION_ID="${SESSION_ID:-completion-nosid}"
# Failure signature: the sorted set of unmet keys (so fixing some but not all
# is a NEW signature and resets the retry counter — progress is recognized).
SIG="completion-unmet:$(printf '%s' "$UNMET" | tr ' ' '\n' | sort | tr '\n' ',')"
retry_guard_block_or_exit \
  "completion-criteria-gate" \
  "$RG_SESSION_ID" \
  "$SIG" \
  "$BLOCKER_MSG" \
  "{\"decision\": \"block\", \"reason\": \"Feature-completion criteria incomplete — account for all 8 (done+evidence or N/A+justification) in a '## Completion Criteria' section before wrapping. Unmet: ${UNMET}\"}" \
  2
