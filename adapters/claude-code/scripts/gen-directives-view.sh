#!/bin/bash
# gen-directives-view.sh — regenerates docs/operator-directives.md FROM
# config/operator-directives.json (gated-pipeline-master-2026-08, Task 11;
# design docs/designs/gated-pipeline-master-2026-08-03.md §4, REQ-B1).
#
# WHY THIS EXISTS
# ===============
# The manifest -> docs/harness-architecture.md generation precedent
# (scripts/gen-architecture-doc.sh, task F.2): the register JSON is the sole
# source of truth; the human-readable view is a PURE FUNCTION of it, never
# hand-edited, so the doc and the register cannot silently diverge (the
# P-32 append-instead-of-revise defect this whole design exists to close —
# a hand-maintained view is exactly how a directive goes stale while
# looking documented). This generator is deliberately independent of
# hooks/lib/directives-register-lib.sh: that lib serves the three RUNTIME
# carriage consumers (plan-reviewer Check 21, dispatch-directives.sh,
# doctrine-jit's register walk); this is a one-shot renderer with no
# matching/lookup API to reuse, exactly like gen-architecture-doc.sh reads
# manifest.json directly rather than through a "manifest-lib.sh".
#
# SUBCOMMANDS
# ===========
#   (default)     : write docs/operator-directives.md from the register
#   --check       : regenerate to a tempfile and diff against the committed
#                   doc; exit 0 if byte-identical, 1 if drifted
#   --self-test   : fixture suite in mktemp -d (HARNESS_SELFTEST=1)
#
# ENV
# ===
#   GEN_DIRECTIVES_VIEW_ROOT      override repo-root resolution (self-test)
#   GEN_DIRECTIVES_VIEW_REGISTER  override register path (rare)
#
# DEPENDENCIES
# ============
# node preferred, jq structural fallback (same convention as
# gen-architecture-doc.sh); neither available -> ERROR (a generator has no
# graceful-degradation output to produce).

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"

resolve_root() {
  if [[ -n "${GEN_DIRECTIVES_VIEW_ROOT:-}" ]]; then
    printf '%s\n' "$GEN_DIRECTIVES_VIEW_ROOT"
    return 0
  fi
  local root
  root="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null)"
  if [[ -n "$root" ]]; then
    printf '%s\n' "$root"
    return 0
  fi
  root="$(cd "$SCRIPT_DIR/../../.." 2>/dev/null && pwd)"
  if [[ -n "$root" ]]; then
    printf '%s\n' "$root"
    return 0
  fi
  return 1
}

have_node() { command -v node >/dev/null 2>&1; }
have_jq() { command -v jq >/dev/null 2>&1; }

# ------------------------------------------------------------
# extract_stream <register> — normalized shape (the extract_stream
# convention shared with gen-architecture-doc.sh and directives-register-
# lib.sh's dr__stream, kept independent on purpose — see header).
#   E|id|title|status|operator_only|source
#   S|id|surface
#   U|id|supersedes-entry
#   I|id|instruction-line   (one line per instruction line, in order —
#                            the only way to carry embedded newlines through
#                            a pipe-delimited single-line stream)
# ------------------------------------------------------------
extract_stream() {
  local register="$1"
  if have_node; then
    node -e '
const fs = require("fs");
const m = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
for (const e of m.entries || []) {
  const id = e.id || "";
  const title = e.title || "";
  const status = e.status || "";
  const opOnly = e.operator_only ? "1" : "0";
  const source = e.source || "";
  console.log(["E", id, title, status, opOnly, source].join("|"));
  for (const s of (e.surfaces || [])) console.log(["S", id, s].join("|"));
  for (const u of (e.supersedes || [])) console.log(["U", id, u].join("|"));
  const instr = typeof e.instruction === "string" ? e.instruction : "";
  for (const line of instr.split("\n")) console.log(["I", id, line].join("|"));
}' "$register" 2>/dev/null
  else
    jq -r '
.entries[] as $e |
(["E", $e.id, ($e.title // ""), $e.status,
  (if $e.operator_only then "1" else "0" end),
  ($e.source // "")] | join("|")),
((($e.surfaces // [])[]) | "S|\($e.id)|\(.)"),
((($e.supersedes // [])[]) | "U|\($e.id)|\(.)"),
((($e.instruction // "") | split("\n")[]) | "I|\($e.id)|\(.)")' "$register" 2>/dev/null
  fi
}

# ------------------------------------------------------------
# render <register> — writes the generated doc body to stdout.
# Deterministic: entries sorted by id (LC_ALL=C).
# ------------------------------------------------------------
render() {
  local register="$1"
  local stream
  stream="$(extract_stream "$register")"
  if [[ -z "$stream" ]]; then
    echo "[gen-directives-view] ERROR: could not extract entries from ${register}" >&2
    return 2
  fi

  local n_total n_binding n_superseded n_operator_only
  n_total="$(printf '%s\n' "$stream" | awk -F'|' '$1=="E"' | wc -l | tr -d '[:space:]')"
  n_binding="$(printf '%s\n' "$stream" | awk -F'|' '$1=="E" && $4=="BINDING"' | wc -l | tr -d '[:space:]')"
  n_superseded="$(printf '%s\n' "$stream" | awk -F'|' '$1=="E" && $4=="SUPERSEDED"' | wc -l | tr -d '[:space:]')"
  n_operator_only="$(printf '%s\n' "$stream" | awk -F'|' '$1=="E" && $5=="1"' | wc -l | tr -d '[:space:]')"

  echo "# Operator Directives Register"
  echo ""
  echo "<!-- GENERATED FILE — do not hand-edit. Regenerate with:"
  echo "       bash adapters/claude-code/scripts/gen-directives-view.sh"
  echo "     Source of truth: adapters/claude-code/config/operator-directives.json."
  echo "     Consumed at runtime by hooks/lib/directives-register-lib.sh (Check 21,"
  echo "     scripts/dispatch-directives.sh, doctrine-jit.sh's register walk). This"
  echo "     file is the human-readable view only — never the canonical store. -->"
  echo ""
  echo "Canonical store for standing BINDING operator directives (DEC-3,"
  echo "docs/designs/gated-pipeline-master-2026-08-03.md §4). New standing rules"
  echo "enter here with a fresh \`OD-NNN\` id, never by appending to this file"
  echo "directly — the no-addendum rule (REQ-B10) applies to the JSON source, and"
  echo "this view is regenerated, not edited."
  echo ""
  echo "## Summary"
  echo ""
  echo "| Metric | Count |"
  echo "|---|---|"
  echo "| Total entries | ${n_total} |"
  echo "| BINDING | ${n_binding} |"
  echo "| SUPERSEDED | ${n_superseded} |"
  echo "| Operator-only (no code surface) | ${n_operator_only} |"
  echo ""

  echo "## Entries"
  echo ""
  while IFS='|' read -r tag id title status oponly source; do
    [[ "$tag" == "E" ]] || continue
    local op_label surfaces_cell supersedes_cell
    [[ "$oponly" == "1" ]] && op_label=" (OPERATOR-ONLY)" || op_label=""
    echo "### ${id} — ${title}${op_label}"
    echo ""
    echo "**Status:** ${status}"
    echo ""
    surfaces_cell="$(printf '%s\n' "$stream" | awk -F'|' -v want="$id" '$1=="S" && $2==want {print $3}')"
    if [[ -n "$surfaces_cell" ]]; then
      echo "**Surfaces:**"
      while IFS= read -r s; do
        [[ -n "$s" ]] && echo "- \`${s}\`"
      done <<< "$surfaces_cell"
    else
      echo "**Surfaces:** none (operator-only — no code surface an agent can act on)"
    fi
    echo ""
    supersedes_cell="$(printf '%s\n' "$stream" | awk -F'|' -v want="$id" '$1=="U" && $2==want {print $3}')"
    if [[ -n "$supersedes_cell" ]]; then
      echo "**Supersedes:**"
      while IFS= read -r u; do
        [[ -n "$u" ]] && echo "- ${u}"
      done <<< "$supersedes_cell"
      echo ""
    fi
    echo "**Instruction:**"
    echo ""
    printf '%s\n' "$stream" | awk -F'|' -v want="$id" '$1=="I" && $2==want {print $3}' | while IFS= read -r line; do
      echo "> ${line}"
    done
    echo ""
    if [[ -n "$source" ]]; then
      echo "*Source: ${source}*"
      echo ""
    fi
  done <<< "$(printf '%s\n' "$stream" | awk -F'|' '$1=="E"' | LC_ALL=C sort -t'|' -k2,2)"
}

run_gen() {
  local root="$1"
  local ac="${root}/adapters/claude-code"
  local register="${GEN_DIRECTIVES_VIEW_REGISTER:-${ac}/config/operator-directives.json}"
  local out="${root}/docs/operator-directives.md"

  if [[ ! -f "$register" ]]; then
    echo "[gen-directives-view] ERROR: register not found at ${register}" >&2
    return 2
  fi
  if ! have_node && ! have_jq; then
    echo "[gen-directives-view] ERROR: needs node or jq" >&2
    return 2
  fi

  render "$register" > "$out" || return $?
  echo "[gen-directives-view] wrote ${out}"
  return 0
}

run_check() {
  local root="$1"
  local ac="${root}/adapters/claude-code"
  local register="${GEN_DIRECTIVES_VIEW_REGISTER:-${ac}/config/operator-directives.json}"
  local committed="${root}/docs/operator-directives.md"

  if [[ ! -f "$register" ]]; then
    echo "[gen-directives-view] ERROR: register not found at ${register}" >&2
    return 2
  fi
  if [[ ! -f "$committed" ]]; then
    echo "[gen-directives-view] RED: committed doc missing at ${committed}" >&2
    return 1
  fi
  if ! have_node && ! have_jq; then
    echo "[gen-directives-view] WARN: needs node or jq — drift check skipped (graceful degradation)" >&2
    return 0
  fi

  local tmp
  tmp="$(mktemp 2>/dev/null || mktemp -t gendirview)"
  render "$register" > "$tmp"
  if diff -q "$tmp" "$committed" >/dev/null 2>&1; then
    echo "[gen-directives-view] GREEN — committed doc matches a fresh regen"
    rm -f "$tmp"
    return 0
  else
    echo "[gen-directives-view] RED — committed docs/operator-directives.md has drifted from the register"
    echo "  run: bash adapters/claude-code/scripts/gen-directives-view.sh"
    diff "$committed" "$tmp" | head -20 >&2
    rm -f "$tmp"
    return 1
  fi
}

# ============================================================
# --self-test
# ============================================================
run_self_test() {
  local SELF="$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")"
  if ! have_node && ! have_jq; then
    echo "self-test: SKIP — neither node nor jq available" >&2
    return 0
  fi

  export HARNESS_SELFTEST=1
  local PASSED=0 FAILED=0
  TMPROOT=$(mktemp -d 2>/dev/null || mktemp -d -t gendirviewself)
  if [[ -z "$TMPROOT" || ! -d "$TMPROOT" ]]; then
    echo "self-test: cannot create temp directory" >&2
    return 2
  fi
  trap 'rm -rf "$TMPROOT"' EXIT

  _fixture_register() {
    cat <<'EOF'
{
  "schema_version": 1,
  "entries": [
    {
      "id": "OD-002",
      "title": "b-entry",
      "status": "BINDING",
      "surfaces": ["adapters/claude-code/hooks/**"],
      "supersedes": [],
      "instruction": "Rule: b.\nGolden case: b.",
      "source": "fixture"
    },
    {
      "id": "OD-001",
      "title": "a-entry",
      "status": "SUPERSEDED",
      "operator_only": true,
      "surfaces": [],
      "supersedes": ["OD-000"],
      "instruction": "Rule: a."
    }
  ]
}
EOF
  }

  local D
  D="$TMPROOT/s1"
  mkdir -p "$D/adapters/claude-code/config" "$D/docs"
  _fixture_register > "$D/adapters/claude-code/config/operator-directives.json"

  # S1 — run_gen writes a file with the expected summary + sorted-by-id order
  OUT="$(GEN_DIRECTIVES_VIEW_ROOT="$D" bash "$SELF" 2>&1)"
  RC=$?
  if [[ $RC -eq 0 ]] && grep -q '| Total entries | 2 |' "$D/docs/operator-directives.md" \
     && grep -q '| Operator-only (no code surface) | 1 |' "$D/docs/operator-directives.md" \
     && [[ "$(grep -n '^### OD-' "$D/docs/operator-directives.md" | head -1)" == *"OD-001"* ]]; then
    echo "self-test (s1-gen-writes-correct-summary-and-order): PASS" >&2
    PASSED=$((PASSED + 1))
  else
    echo "self-test (s1-gen-writes-correct-summary-and-order): FAIL (rc=$RC)" >&2
    FAILED=$((FAILED + 1))
  fi

  # S2 — operator-only entry renders the "no code surface" line, not a glob list
  if grep -q 'no code surface an agent can act on' "$D/docs/operator-directives.md"; then
    echo "self-test (s2-operator-only-surfaces-label): PASS" >&2
    PASSED=$((PASSED + 1))
  else
    echo "self-test (s2-operator-only-surfaces-label): FAIL" >&2
    FAILED=$((FAILED + 1))
  fi

  # S3 — --check GREEN immediately after a gen (byte-identical)
  OUT2="$(GEN_DIRECTIVES_VIEW_ROOT="$D" bash "$SELF" --check 2>&1)"
  RC2=$?
  if [[ $RC2 -eq 0 ]] && echo "$OUT2" | grep -q "GREEN"; then
    echo "self-test (s3-check-green-after-gen): PASS" >&2
    PASSED=$((PASSED + 1))
  else
    echo "self-test (s3-check-green-after-gen): FAIL (rc=$RC2): $OUT2" >&2
    FAILED=$((FAILED + 1))
  fi

  # S4 — drift detection: hand-edit the committed doc, --check goes RED
  echo "hand-edited drift line" >> "$D/docs/operator-directives.md"
  OUT3="$(GEN_DIRECTIVES_VIEW_ROOT="$D" bash "$SELF" --check 2>&1)"
  RC3=$?
  if [[ $RC3 -ne 0 ]] && echo "$OUT3" | grep -q "RED"; then
    echo "self-test (s4-drift-detected-red): PASS" >&2
    PASSED=$((PASSED + 1))
  else
    echo "self-test (s4-drift-detected-red): FAIL (rc=$RC3): $OUT3" >&2
    FAILED=$((FAILED + 1))
  fi

  # S5 — missing register -> ERROR exit 2
  D5="$TMPROOT/s5"
  mkdir -p "$D5/adapters/claude-code/config" "$D5/docs"
  OUT5="$(GEN_DIRECTIVES_VIEW_ROOT="$D5" bash "$SELF" 2>&1)"
  RC5=$?
  if [[ $RC5 -eq 2 ]]; then
    echo "self-test (s5-missing-register-errors): PASS" >&2
    PASSED=$((PASSED + 1))
  else
    echo "self-test (s5-missing-register-errors): FAIL (rc=$RC5)" >&2
    FAILED=$((FAILED + 1))
  fi

  # S6 — determinism: two successive gens byte-identical (idempotent re-run,
  # the design's own T11 "Prove it works" #2 requirement)
  D6="$TMPROOT/s6"
  mkdir -p "$D6/adapters/claude-code/config" "$D6/docs"
  _fixture_register > "$D6/adapters/claude-code/config/operator-directives.json"
  GEN_DIRECTIVES_VIEW_ROOT="$D6" bash "$SELF" >/dev/null 2>&1
  cp "$D6/docs/operator-directives.md" "$D6/first.md"
  GEN_DIRECTIVES_VIEW_ROOT="$D6" bash "$SELF" >/dev/null 2>&1
  if diff -q "$D6/first.md" "$D6/docs/operator-directives.md" >/dev/null 2>&1; then
    echo "self-test (s6-deterministic-idempotent-regen): PASS" >&2
    PASSED=$((PASSED + 1))
  else
    echo "self-test (s6-deterministic-idempotent-regen): FAIL (non-deterministic output)" >&2
    FAILED=$((FAILED + 1))
  fi

  echo "" >&2
  echo "self-test summary: ${PASSED} passed, ${FAILED} failed" >&2
  [[ "$FAILED" -gt 0 ]] && return 1
  return 0
}

# ============================================================
# main
# ============================================================
case "${1:-}" in
  --self-test)
    run_self_test
    exit $?
    ;;
  --check)
    ROOT="$(resolve_root)" || { echo "[gen-directives-view] ERROR: cannot resolve repo root" >&2; exit 2; }
    run_check "$ROOT"
    exit $?
    ;;
  ""|--gen)
    ROOT="$(resolve_root)" || { echo "[gen-directives-view] ERROR: cannot resolve repo root" >&2; exit 2; }
    run_gen "$ROOT"
    exit $?
    ;;
  *)
    echo "usage: gen-directives-view.sh [--gen|--check|--self-test]" >&2
    exit 2
    ;;
esac
