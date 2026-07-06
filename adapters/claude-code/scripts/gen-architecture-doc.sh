#!/bin/bash
# gen-architecture-doc.sh — regenerates docs/harness-architecture.md FROM
# manifest.json (NL Overhaul Program Wave F, task F.2, §F.2 first bullet).
#
# WHY THIS EXISTS
# ===============
# Before this task, docs/harness-architecture.md was a hand-maintained
# 800+-line narrative catalog that drifted from the manifest the moment
# either was edited without the other (RC5 unmaintained gate sprawl —
# 2026-07-01 effectiveness audit). This script makes the INVENTORY portion
# of that file a pure function of manifest.json: hooks-by-event, blocking
# vs warn counts, budget-class breakdown, and a doctrine-file index. The
# doctor's drift predicate (tests/fixtures/wave-f/F.2/doctor-predicate.md)
# REDs when the committed doc's inventory section no longer byte-equals a
# fresh run of this script — the manifest and the doc cannot silently
# diverge again.
#
# The pre-existing narrative history (mechanism-by-mechanism changelog
# entries dating back to Gen 4) is NOT thrown away — it is preserved
# verbatim at docs/harness-architecture-history.md (this script does not
# touch that file) and cross-linked from the generated doc's header.
#
# SUBCOMMANDS
# ===========
#   (default)     : write docs/harness-architecture.md from manifest.json
#   --check       : regenerate to a tempfile and diff against the committed
#                   doc; exit 0 if byte-identical, 1 if drifted (this is
#                   the doctor predicate's check command)
#   --self-test   : fixture suite in mktemp -d (HARNESS_SELFTEST=1)
#
# ENV
# ===
#   GEN_ARCH_DOC_ROOT       override repo-root resolution (self-test + doctor)
#   GEN_ARCH_DOC_MANIFEST   override manifest path (rare)
#
# DEPENDENCIES
# ============
# bash-first; node preferred (same extraction shape as manifest-check.sh),
# jq structural fallback; neither available -> ERROR (this is a generator,
# not a checker — there is no graceful-degradation output to produce).

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"

resolve_root() {
  if [[ -n "${GEN_ARCH_DOC_ROOT:-}" ]]; then
    printf '%s\n' "$GEN_ARCH_DOC_ROOT"
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
# extract_stream <manifest> — same normalized shape as manifest-check.sh's
# extract_stream, so the two scripts never disagree about what an "entry"
# looks like. Additionally emits a "D" line per doctrine_file so the
# doctrine-index section can be built without a second manifest read.
#   E|id|kind|doctrine_or_-|wired01|selftest01|blocking01|budget|honest01
#   H|id|hook-basename
#   V|id|event   (one line per (id,event) pair — for the by-event tables)
# ------------------------------------------------------------
extract_stream() {
  local manifest="$1"
  if have_node; then
    node -e '
const fs = require("fs");
const m = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
for (const e of m.entries || []) {
  const honest = (typeof e.honest_status === "string" && e.honest_status.trim().length > 0) ? "1" : "0";
  console.log(["E", e.id, e.kind, e.doctrine_file || "-",
    e.wired_template ? "1" : "0", e.selftest ? "1" : "0",
    e.blocking ? "1" : "0", e.budget_class, honest].join("|"));
  for (const h of e.hooks || []) console.log(["H", e.id, h].join("|"));
  for (const v of e.events || []) console.log(["V", e.id, v].join("|"));
}' "$manifest" 2>/dev/null
  else
    jq -r '
.entries[] as $e |
(["E", $e.id, $e.kind, ($e.doctrine_file // "-"),
  (if $e.wired_template then "1" else "0" end),
  (if $e.selftest then "1" else "0" end),
  (if $e.blocking then "1" else "0" end),
  $e.budget_class,
  (if (($e.honest_status // "") | length) > 0 then "1" else "0" end)] | join("|")),
((($e.hooks // [])[]) | "H|\($e.id)|\(.)"),
((($e.events // [])[]) | "V|\($e.id)|\(.)")' "$manifest" 2>/dev/null
  fi
}

# ------------------------------------------------------------
# render <manifest> <doctrine_dir_rel> — writes the generated doc body to
# stdout. Deterministic: every listing sorted by id (LC_ALL=C).
# ------------------------------------------------------------
render() {
  local manifest="$1"
  local stream
  stream="$(extract_stream "$manifest")"
  if [[ -z "$stream" ]]; then
    echo "[gen-architecture-doc] ERROR: could not extract entries from ${manifest}" >&2
    return 2
  fi

  local n_entries n_hooks n_blocking
  n_entries="$(printf '%s\n' "$stream" | awk -F'|' '$1=="E"' | wc -l | tr -d '[:space:]')"
  n_hooks="$(printf '%s\n' "$stream" | awk -F'|' '$1=="H"{print $3}' | LC_ALL=C sort -u | grep -c . || true)"
  n_blocking="$(printf '%s\n' "$stream" | awk -F'|' '$1=="E" && $7=="1"' | wc -l | tr -d '[:space:]')"

  echo "# Claude Code Harness — Architecture Inventory"
  echo ""
  echo "<!-- GENERATED FILE — do not hand-edit. Regenerate with:"
  echo "       bash adapters/claude-code/scripts/gen-architecture-doc.sh"
  echo "     Source of truth: adapters/claude-code/manifest.json."
  echo "     Doctor predicate (drift = RED): tests/fixtures/wave-f/F.2/doctor-predicate.md -->"
  echo ""
  echo "For the pre-generation narrative history (mechanism-by-mechanism changelog"
  echo "back to Gen 4, preserved verbatim), see [\`harness-architecture-history.md\`](harness-architecture-history.md)."
  echo "For the Tier-3 unified narrative (team-role analogy + layer cross-walk), see"
  echo "[\`architecture-overview.md\`](architecture-overview.md). This file is the"
  echo "Tier-4 exhaustive machine-derived inventory."
  echo ""
  echo "## Summary"
  echo ""
  echo "| Metric | Count |"
  echo "|---|---|"
  echo "| Total manifest entries | ${n_entries} |"
  echo "| Unique hook scripts | ${n_hooks} |"
  echo "| Blocking gates (\`blocking: true\`) | ${n_blocking} |"
  echo ""

  echo "## Hooks by event"
  echo ""
  echo "One row per (entry, event) pair — an entry wired to N events appears N times, once per event, so this table doubles as the per-event hook count."
  echo ""
  echo "| event | id | kind | blocking | hooks |"
  echo "|---|---|---|---|---|"
  # V lines carry (id, event); join against E for kind/blocking; join against H for hooks cell.
  while IFS='|' read -r _ id event; do
    local kind blocking hooks_cell
    kind="$(printf '%s\n' "$stream" | awk -F'|' -v want="$id" '$1=="E" && $2==want{print $3}')"
    blocking_raw="$(printf '%s\n' "$stream" | awk -F'|' -v want="$id" '$1=="E" && $2==want{print $7}')"
    [[ "$blocking_raw" == "1" ]] && blocking="yes" || blocking="no"
    hooks_cell="$(printf '%s\n' "$stream" | awk -F'|' -v want="$id" '$1=="H" && $2==want{print $3}' | LC_ALL=C sort | paste -sd ',' - | sed 's/,/, /g')"
    [[ -z "$hooks_cell" ]] && hooks_cell="—"
    echo "| ${event} | ${id} | ${kind} | ${blocking} | ${hooks_cell} |"
  done <<< "$(printf '%s\n' "$stream" | awk -F'|' '$1=="V"' | LC_ALL=C sort -t'|' -k3,3 -k2,2)"
  echo ""

  echo "## Blocking vs warn, by kind"
  echo ""
  echo "| kind | blocking | warn/non-blocking |"
  echo "|---|---|---|"
  local k
  for k in gate writer surfacer pattern convention; do
    local bcount wcount
    bcount="$(printf '%s\n' "$stream" | awk -F'|' -v want="$k" '$1=="E" && $3==want && $7=="1"' | wc -l | tr -d '[:space:]')"
    wcount="$(printf '%s\n' "$stream" | awk -F'|' -v want="$k" '$1=="E" && $3==want && $7=="0"' | wc -l | tr -d '[:space:]')"
    [[ "$((bcount + wcount))" -eq 0 ]] && continue
    echo "| ${k} | ${bcount} | ${wcount} |"
  done
  echo ""

  echo "## Budgets"
  echo ""
  echo "Per §F.1 (\`blocking-budget-check.js\`): blocking gates ≤ 12 (counted structurally"
  echo "here as manifest \`blocking:true\` entries — the F.1 budget check counts the same"
  echo "field against the SAME-EVENT-CHAIN definition; see that check's own doc for the"
  echo "distinction between total blocking:true entries and blocking CHAIN POSITIONS)."
  echo ""
  echo "| budget_class | entries |"
  echo "|---|---|"
  local bc
  for bc in stop session-start pretool posttool none; do
    local cnt
    cnt="$(printf '%s\n' "$stream" | awk -F'|' -v want="$bc" '$1=="E" && $8==want' | wc -l | tr -d '[:space:]')"
    echo "| ${bc} | ${cnt} |"
  done
  echo ""

  echo "## Doctrine index"
  echo ""
  echo "Generated inventory of every entry's \`doctrine_file\` target. The canonical"
  echo "per-doctrine-file table (id/kind/hooks/blocking/honest_status, one row per"
  echo "entry) lives at [\`doctrine/INDEX.md\`](../adapters/claude-code/doctrine/INDEX.md)"
  echo "(generated by \`manifest-check.sh --gen-index\` — this section cross-references"
  echo "it rather than duplicating it, so the two generators cannot disagree)."
  echo ""
  echo "| doctrine_file | entries pointing to it |"
  echo "|---|---|"
  while IFS='|' read -r doc; do
    [[ -z "$doc" ]] && continue
    local cnt ids
    cnt="$(printf '%s\n' "$stream" | awk -F'|' -v want="$doc" '$1=="E" && $4==want' | wc -l | tr -d '[:space:]')"
    ids="$(printf '%s\n' "$stream" | awk -F'|' -v want="$doc" '$1=="E" && $4==want{print $2}' | LC_ALL=C sort | paste -sd ',' - | sed 's/,/, /g')"
    echo "| ${doc} | ${cnt} (${ids}) |"
  done <<< "$(printf '%s\n' "$stream" | awk -F'|' '$1=="E" && $4!="-"{print $4}' | LC_ALL=C sort -u)"
  echo ""
  echo "Entries with no doctrine_file (\`-\`): $(printf '%s\n' "$stream" | awk -F'|' '$1=="E" && $4=="-"' | wc -l | tr -d '[:space:]')."
  echo ""

  echo "## Full entry listing"
  echo ""
  echo "| id | kind | events | blocking | budget_class | honest_status |"
  echo "|---|---|---|---|---|---|"
  while IFS='|' read -r tag id kind doctrine wired selftest blocking budget honest; do
    [[ "$tag" == "E" ]] || continue
    local events_cell blocking_cell honest_cell
    events_cell="$(printf '%s\n' "$stream" | awk -F'|' -v want="$id" '$1=="V" && $2==want{print $3}' | LC_ALL=C sort | paste -sd ',' - | sed 's/,/, /g')"
    [[ -z "$events_cell" ]] && events_cell="—"
    [[ "$blocking" == "1" ]] && blocking_cell="yes" || blocking_cell="no"
    if [[ "$honest" == "1" ]]; then
      if have_node; then
        honest_cell="$(node -e '
const m = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
const e = (m.entries || []).find(x => x.id === process.argv[2]);
process.stdout.write((e && e.honest_status) ? String(e.honest_status) : "");' "$manifest" "$id" 2>/dev/null)"
      else
        honest_cell="$(jq -r --arg id "$id" '.entries[] | select(.id == $id) | .honest_status // ""' "$manifest" 2>/dev/null)"
      fi
      [[ -z "$honest_cell" ]] && honest_cell="—"
    else
      honest_cell="—"
    fi
    echo "| ${id} | ${kind} | ${events_cell} | ${blocking_cell} | ${budget} | ${honest_cell} |"
  done <<< "$(printf '%s\n' "$stream" | awk -F'|' '$1=="E"' | LC_ALL=C sort -t'|' -k2,2)"
}

run_gen() {
  local root="$1"
  local ac="${root}/adapters/claude-code"
  local manifest="${GEN_ARCH_DOC_MANIFEST:-${ac}/manifest.json}"
  local out="${root}/docs/harness-architecture.md"

  if [[ ! -f "$manifest" ]]; then
    echo "[gen-architecture-doc] ERROR: manifest not found at ${manifest}" >&2
    return 2
  fi
  if ! have_node && ! have_jq; then
    echo "[gen-architecture-doc] ERROR: needs node or jq" >&2
    return 2
  fi

  render "$manifest" > "$out" || return $?
  echo "[gen-architecture-doc] wrote ${out}"
  return 0
}

run_check() {
  local root="$1"
  local ac="${root}/adapters/claude-code"
  local manifest="${GEN_ARCH_DOC_MANIFEST:-${ac}/manifest.json}"
  local committed="${root}/docs/harness-architecture.md"

  if [[ ! -f "$manifest" ]]; then
    echo "[gen-architecture-doc] ERROR: manifest not found at ${manifest}" >&2
    return 2
  fi
  if [[ ! -f "$committed" ]]; then
    echo "[gen-architecture-doc] RED: committed doc missing at ${committed}" >&2
    return 1
  fi
  if ! have_node && ! have_jq; then
    echo "[gen-architecture-doc] WARN: needs node or jq — drift check skipped (graceful degradation)" >&2
    return 0
  fi

  local tmp
  tmp="$(mktemp 2>/dev/null || mktemp -t genarchdoc)"
  render "$manifest" > "$tmp"
  if diff -q "$tmp" "$committed" >/dev/null 2>&1; then
    echo "[gen-architecture-doc] GREEN — committed doc matches a fresh regen"
    rm -f "$tmp"
    return 0
  else
    echo "[gen-architecture-doc] RED — committed docs/harness-architecture.md has drifted from manifest.json"
    echo "  run: bash adapters/claude-code/scripts/gen-architecture-doc.sh"
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
  TMPROOT=$(mktemp -d 2>/dev/null || mktemp -d -t genarchself)
  if [[ -z "$TMPROOT" || ! -d "$TMPROOT" ]]; then
    echo "self-test: cannot create temp directory" >&2
    return 2
  fi
  trap 'rm -rf "$TMPROOT"' EXIT

  _fixture_manifest() {
    cat <<'EOF'
{
  "schema_version": 1,
  "entries": [
    {
      "id": "a-gate",
      "kind": "gate",
      "doctrine_file": "doctrine/a.md",
      "hooks": ["a-gate.sh"],
      "events": ["Stop"],
      "wired_template": true,
      "selftest": true,
      "jit_triggers": { "paths": [], "keywords": [] },
      "blocking": true,
      "budget_class": "stop"
    },
    {
      "id": "b-surfacer",
      "kind": "surfacer",
      "doctrine_file": null,
      "hooks": ["b-surfacer.sh"],
      "events": ["SessionStart"],
      "wired_template": false,
      "selftest": true,
      "jit_triggers": { "paths": [], "keywords": [] },
      "blocking": false,
      "honest_status": "dispatched via a pack",
      "budget_class": "session-start"
    }
  ]
}
EOF
  }

  local D
  D="$TMPROOT/s1"
  mkdir -p "$D/adapters/claude-code" "$D/docs"
  _fixture_manifest > "$D/adapters/claude-code/manifest.json"

  # S1 — run_gen writes a file that contains the expected summary counts
  OUT="$(GEN_ARCH_DOC_ROOT="$D" bash "$SELF" 2>&1)"
  RC=$?
  if [[ $RC -eq 0 ]] && grep -q '| Total manifest entries | 2 |' "$D/docs/harness-architecture.md" \
     && grep -q '| Blocking gates (`blocking: true`) | 1 |' "$D/docs/harness-architecture.md"; then
    echo "self-test (s1-gen-writes-correct-summary): PASS" >&2
    PASSED=$((PASSED + 1))
  else
    echo "self-test (s1-gen-writes-correct-summary): FAIL (rc=$RC)" >&2
    FAILED=$((FAILED + 1))
  fi

  # S2 — --check GREEN immediately after a gen (byte-identical)
  OUT2="$(GEN_ARCH_DOC_ROOT="$D" bash "$SELF" --check 2>&1)"
  RC2=$?
  if [[ $RC2 -eq 0 ]] && echo "$OUT2" | grep -q "GREEN"; then
    echo "self-test (s2-check-green-after-gen): PASS" >&2
    PASSED=$((PASSED + 1))
  else
    echo "self-test (s2-check-green-after-gen): FAIL (rc=$RC2): $OUT2" >&2
    FAILED=$((FAILED + 1))
  fi

  # S3 — drift detection: hand-edit the committed doc, --check goes RED
  echo "hand-edited drift line" >> "$D/docs/harness-architecture.md"
  OUT3="$(GEN_ARCH_DOC_ROOT="$D" bash "$SELF" --check 2>&1)"
  RC3=$?
  if [[ $RC3 -ne 0 ]] && echo "$OUT3" | grep -q "RED"; then
    echo "self-test (s3-drift-detected-red): PASS" >&2
    PASSED=$((PASSED + 1))
  else
    echo "self-test (s3-drift-detected-red): FAIL (rc=$RC3): $OUT3" >&2
    FAILED=$((FAILED + 1))
  fi

  # S4 — missing manifest -> ERROR exit 2
  D4="$TMPROOT/s4"
  mkdir -p "$D4/adapters/claude-code" "$D4/docs"
  OUT4="$(GEN_ARCH_DOC_ROOT="$D4" bash "$SELF" 2>&1)"
  RC4=$?
  if [[ $RC4 -eq 2 ]]; then
    echo "self-test (s4-missing-manifest-errors): PASS" >&2
    PASSED=$((PASSED + 1))
  else
    echo "self-test (s4-missing-manifest-errors): FAIL (rc=$RC4)" >&2
    FAILED=$((FAILED + 1))
  fi

  # S5 — determinism: two successive gens byte-identical (no timestamp/PID leakage)
  D5="$TMPROOT/s5"
  mkdir -p "$D5/adapters/claude-code" "$D5/docs"
  _fixture_manifest > "$D5/adapters/claude-code/manifest.json"
  GEN_ARCH_DOC_ROOT="$D5" bash "$SELF" >/dev/null 2>&1
  cp "$D5/docs/harness-architecture.md" "$D5/first.md"
  GEN_ARCH_DOC_ROOT="$D5" bash "$SELF" >/dev/null 2>&1
  if diff -q "$D5/first.md" "$D5/docs/harness-architecture.md" >/dev/null 2>&1; then
    echo "self-test (s5-deterministic-regen): PASS" >&2
    PASSED=$((PASSED + 1))
  else
    echo "self-test (s5-deterministic-regen): FAIL (non-deterministic output)" >&2
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
    ROOT="$(resolve_root)" || { echo "[gen-architecture-doc] ERROR: cannot resolve repo root" >&2; exit 2; }
    run_check "$ROOT"
    exit $?
    ;;
  ""|--gen)
    ROOT="$(resolve_root)" || { echo "[gen-architecture-doc] ERROR: cannot resolve repo root" >&2; exit 2; }
    run_gen "$ROOT"
    exit $?
    ;;
  *)
    echo "usage: gen-architecture-doc.sh [--gen|--check|--self-test]" >&2
    exit 2
    ;;
esac
