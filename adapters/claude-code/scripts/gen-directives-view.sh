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
#   M|id|field|value        (Task: directives-elaboration-layer — one record
#                            PER elaboration scalar: intent, applies_when,
#                            worked_example, elaborated_by, elaborated_at,
#                            reviewed_by, in that order, only when the entry
#                            carries a well-formed elaboration object. The
#                            value is the TRAILING REMAINDER of the record,
#                            so an embedded '|' cannot shift fields.)
#   R|id|requirement-text   (one per elaboration.requirements item, in order)
#   N|id|anti-pattern-text  (one per elaboration.anti_patterns item, in order)
#
# DELIMITER-INJECTION GUARD (harness-review REJECT 2026-08-07, nl-issues
# GEN-DIRECTIVES-VIEW-DELIMITER-INJECTION-CRITICAL): every free-text value
# rides a record either as the trailing remainder (S/U/I/M/R/N) — immune to
# embedded '|' — or as a structurally embedded field (E's id/title/status),
# where '|' is REJECTED at this emit point. CR/LF is rejected in EVERY value
# (LF is legal only inside `instruction`, which is line-split into I records)
# because a newline would terminate the record and let the rest of the value
# forge arbitrary new records — the proven "### OD-999 / Status: BINDING"
# forgery. Validation runs BEFORE any record is emitted: a bad register
# yields a named error on stderr and a non-zero exit, never a partial stream.
# ------------------------------------------------------------
extract_stream() {
  local register="$1"
  if have_node; then
    node -e '
const fs = require("fs");
let m;
try { m = JSON.parse(fs.readFileSync(process.argv[1], "utf8")); }
catch (err) {
  console.error("[gen-directives-view] ERROR: register does not parse as JSON: " + err.message);
  process.exit(3);
}
const entries = m.entries || [];
const ELAB_SCALARS = ["intent", "applies_when", "worked_example", "elaborated_by", "elaborated_at", "reviewed_by"];
// ---- delimiter-injection guard: validate EVERY value BEFORE emitting
// anything, so a bad register can never yield a partial (forgeable) stream.
const die = (id, field, why) => {
  console.error("[gen-directives-view] ERROR: entry " + id + " field " + field + " contains " + why + " — refusing to render (delimiter-injection guard; values are single-line by authoring convention)");
  process.exit(4);
};
for (const e of entries) {
  const id = e.id || "";
  for (const [f, v] of [["id", id], ["title", e.title], ["status", e.status]]) {
    if (typeof v !== "string") continue;
    if (/[\r\n]/.test(v)) die(id, f, "CR/LF");
    if (v.includes("|")) die(id, f, "an embedded \x27|\x27");
  }
  if (typeof e.source === "string" && /[\r\n]/.test(e.source)) die(id, "source", "CR/LF");
  for (const s of (e.surfaces || [])) if (/[\r\n]/.test(s)) die(id, "surfaces", "CR/LF");
  for (const u of (e.supersedes || [])) if (/[\r\n]/.test(u)) die(id, "supersedes", "CR/LF");
  if (typeof e.instruction === "string" && /\r/.test(e.instruction)) die(id, "instruction", "a CR");
  const el = (e.elaboration && typeof e.elaboration === "object") ? e.elaboration : null;
  if (el) {
    for (const f of ELAB_SCALARS)
      if (typeof el[f] === "string" && /[\r\n]/.test(el[f])) die(id, "elaboration." + f, "CR/LF");
    for (const r of (el.requirements || [])) if (/[\r\n]/.test(r)) die(id, "elaboration.requirements", "CR/LF");
    for (const n of (el.anti_patterns || [])) if (/[\r\n]/.test(n)) die(id, "elaboration.anti_patterns", "CR/LF");
  }
}
for (const e of entries) {
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
  const el = (e.elaboration && typeof e.elaboration === "object") ? e.elaboration : null;
  if (el) {
    for (const f of ELAB_SCALARS) console.log(["M", id, f, typeof el[f] === "string" ? el[f] : ""].join("|"));
    for (const r of (el.requirements || [])) console.log(["R", id, r].join("|"));
    for (const n of (el.anti_patterns || [])) console.log(["N", id, n].join("|"));
  }
}' "$register"
  else
    if ! jq -e . "$register" >/dev/null 2>&1; then
      echo "[gen-directives-view] ERROR: register does not parse as JSON: ${register}" >&2
      return 3
    fi
    # ---- delimiter-injection guard (jq mirror of the node validation
    # above): find the FIRST offending value BEFORE emitting anything.
    local viol
    viol="$(jq -r '
[ (.entries // [])[] as $e |
  ( ( [["id", ($e.id // "")], ["title", ($e.title // "")], ["status", ($e.status // "")]][]
      | select(.[1] | test("[\r\n]|\\|"))
      | "entry \($e.id) field \(.[0]) contains CR/LF or an embedded |" ),
    ( ($e.source // "") | select(test("[\r\n]")) | "entry \($e.id) field source contains CR/LF" ),
    ( ($e.surfaces // [])[] | select(test("[\r\n]")) | "entry \($e.id) field surfaces contains CR/LF" ),
    ( ($e.supersedes // [])[] | select(test("[\r\n]")) | "entry \($e.id) field supersedes contains CR/LF" ),
    ( ($e.instruction // "") | select(test("\r")) | "entry \($e.id) field instruction contains a CR" ),
    ( ($e.elaboration // {}) as $el |
      ( ( ["intent","applies_when","worked_example","elaborated_by","elaborated_at","reviewed_by"][] ) as $f
        | ($el[$f] // "") | select(type == "string" and test("[\r\n]"))
        | "entry \($e.id) field elaboration.\($f) contains CR/LF" ),
      ( ($el.requirements // [])[] | select(test("[\r\n]")) | "entry \($e.id) field elaboration.requirements contains CR/LF" ),
      ( ($el.anti_patterns // [])[] | select(test("[\r\n]")) | "entry \($e.id) field elaboration.anti_patterns contains CR/LF" )
    )
  )
] | .[0] // empty' "$register" 2>/dev/null | tr -d '\r')"
    if [[ -n "$viol" ]]; then
      echo "[gen-directives-view] ERROR: ${viol} — refusing to render (delimiter-injection guard; values are single-line by authoring convention)" >&2
      return 4
    fi
    jq -r '
.entries[] as $e |
(["E", $e.id, ($e.title // ""), $e.status,
  (if $e.operator_only then "1" else "0" end),
  ($e.source // "")] | join("|")),
((($e.surfaces // [])[]) | "S|\($e.id)|\(.)"),
((($e.supersedes // [])[]) | "U|\($e.id)|\(.)"),
((($e.instruction // "") | split("\n")[]) | "I|\($e.id)|\(.)"),
(if ($e.elaboration != null) then
   ( ( ["intent","applies_when","worked_example","elaborated_by","elaborated_at","reviewed_by"][] ) as $f
     | "M|\($e.id)|\($f)|\($e.elaboration[$f] // "")" ),
   ((($e.elaboration.requirements // [])[]) | "R|\($e.id)|\(.)"),
   ((($e.elaboration.anti_patterns // [])[]) | "N|\($e.id)|\(.)")
 else empty end)' "$register" 2>/dev/null | tr -d '\r'
    # tr strips the CRs Windows jq builds append to -r output (they would
    # otherwise ride into the rendered doc); CR in a VALUE is already
    # rejected above. PIPESTATUS keeps jq's own exit code for render().
    return "${PIPESTATUS[0]}"
  fi
}

# ------------------------------------------------------------
# render <register> — writes the generated doc body to stdout.
# Deterministic: entries sorted by id (LC_ALL=C).
# ------------------------------------------------------------
# stream_first <stream> <prefix> — trailing remainder of the FIRST record
# starting with <prefix>; stream_all prints every match, in stream order.
# index()==1 is an exact-prefix test (plain substring compare, never regex),
# so record values containing '|' or regex metacharacters cannot confuse it.
stream_first() {
  printf '%s\n' "$1" | awk -v p="$2" 'index($0, p) == 1 { print substr($0, length(p) + 1); exit }'
}
stream_all() {
  printf '%s\n' "$1" | awk -v p="$2" 'index($0, p) == 1 { print substr($0, length(p) + 1) }'
}

render() {
  local register="$1"
  local stream xrc
  stream="$(extract_stream "$register")"
  xrc=$?
  if [[ $xrc -ne 0 ]]; then
    # extract_stream already named the offender on stderr (injection guard /
    # parse error). Discard any partial stream — never render it.
    return "$xrc"
  fi
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
    surfaces_cell="$(stream_all "$stream" "S|${id}|")"
    if [[ -n "$surfaces_cell" ]]; then
      echo "**Surfaces:**"
      while IFS= read -r s; do
        [[ -n "$s" ]] && echo "- \`${s}\`"
      done <<< "$surfaces_cell"
    else
      echo "**Surfaces:** none (operator-only — no code surface an agent can act on)"
    fi
    echo ""
    supersedes_cell="$(stream_all "$stream" "U|${id}|")"
    if [[ -n "$supersedes_cell" ]]; then
      echo "**Supersedes:**"
      while IFS= read -r u; do
        [[ -n "$u" ]] && echo "- ${u}"
      done <<< "$supersedes_cell"
      echo ""
    fi
    echo "**Instruction:**"
    echo ""
    stream_all "$stream" "I|${id}|" | while IFS= read -r line; do
      echo "> ${line}"
    done
    echo ""
    # ---- Elaboration (Task: directives-elaboration-layer, operator
    # proposal 2026-08-04) — OPTIONAL, additive. Rendered ONLY when the
    # entry carries an M line. The verbatim Instruction above stays PRIMARY
    # and unmodified by this section; the banner below is the "correct me
    # if wrong" review-hook this task's item 4 requires — every seeded
    # elaboration ships with reviewed_by=pending-operator, so no code path
    # here may claim operator sign-off on the interpretation's behalf.
    local mline
    mline="$(stream_first "$stream" "M|${id}|")"
    if [[ -n "$mline" ]]; then
      # Per-scalar records: the value is the trailing remainder after the
      # "M|<id>|<field>|" prefix, so embedded '|' passes through verbatim
      # instead of shifting fields (the reviewed_by-forgery vector).
      local m_intent m_applies m_worked m_by m_at m_reviewed
      m_intent="$(stream_first "$stream" "M|${id}|intent|")"
      m_applies="$(stream_first "$stream" "M|${id}|applies_when|")"
      m_worked="$(stream_first "$stream" "M|${id}|worked_example|")"
      m_by="$(stream_first "$stream" "M|${id}|elaborated_by|")"
      m_at="$(stream_first "$stream" "M|${id}|elaborated_at|")"
      m_reviewed="$(stream_first "$stream" "M|${id}|reviewed_by|")"
      echo "**Elaboration:**"
      echo ""
      echo "> **Interpretation — correct me if wrong.** This section interprets the"
      echo "> verbatim Instruction above; it does not replace it, and on any conflict"
      echo "> the verbatim Instruction wins. Review status: \`reviewed_by: ${m_reviewed}\`."
      echo ">"
      echo "> *Intent:* ${m_intent}"
      echo ">"
      echo "> *Applies when:* ${m_applies}"
      local req_cell
      req_cell="$(stream_all "$stream" "R|${id}|")"
      if [[ -n "$req_cell" ]]; then
        echo ">"
        echo "> *Requirements:*"
        while IFS= read -r r; do
          [[ -n "$r" ]] && echo "> - ${r}"
        done <<< "$req_cell"
      fi
      local antip_cell
      antip_cell="$(stream_all "$stream" "N|${id}|")"
      if [[ -n "$antip_cell" ]]; then
        echo ">"
        echo "> *Anti-patterns (violates the directive while superficially complying):*"
        while IFS= read -r a; do
          [[ -n "$a" ]] && echo "> - ${a}"
        done <<< "$antip_cell"
      fi
      echo ">"
      echo "> *Worked example:* ${m_worked}"
      echo ">"
      echo "> *Elaborated by ${m_by} on ${m_at}.*"
      echo ""
    fi
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

  # Render to a tempfile first: `render > "$out"` would truncate the
  # committed doc BEFORE render can fail, so a rejected register (injection
  # guard) or a crashed extraction would silently destroy the existing view.
  local tmp rc
  tmp="$(mktemp 2>/dev/null || mktemp -t gendirview)"
  render "$register" > "$tmp"
  rc=$?
  if [[ $rc -ne 0 ]]; then
    rm -f "$tmp"
    echo "[gen-directives-view] ERROR: render failed (rc=${rc}) — ${out} left untouched" >&2
    return "$rc"
  fi
  mv "$tmp" "$out" || { rm -f "$tmp"; return 2; }
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
  local rrc=$?
  if [[ $rrc -ne 0 ]]; then
    rm -f "$tmp"
    echo "[gen-directives-view] ERROR: register failed extraction (rc=${rrc}) — cannot run the drift check" >&2
    return 2
  fi
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
      "source": "fixture",
      "elaboration": {
        "intent": "Fixture elaboration intent for the gen-view banner self-test.",
        "requirements": ["Fixture req one.", "Fixture req two.", "Fixture req three."],
        "anti_patterns": ["Fixture antip one."],
        "applies_when": "Fixture applies_when.",
        "worked_example": "Fixture worked example.",
        "elaborated_by": "fixture-author",
        "elaborated_at": "2026-08-04",
        "reviewed_by": "pending-operator"
      }
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

  # S2b — Task: directives-elaboration-layer (operator proposal 2026-08-04):
  # an entry WITH elaboration (OD-002) renders the "correct me if wrong"
  # interpretation banner plus its intent/requirements/anti_patterns/
  # reviewed_by content.
  if grep -q 'Interpretation — correct me if wrong' "$D/docs/operator-directives.md" \
     && grep -q 'reviewed_by: pending-operator' "$D/docs/operator-directives.md" \
     && grep -q 'Fixture elaboration intent for the gen-view banner self-test' "$D/docs/operator-directives.md" \
     && grep -q -- '- Fixture req one\.' "$D/docs/operator-directives.md" \
     && grep -q -- '- Fixture antip one\.' "$D/docs/operator-directives.md"; then
    echo "self-test (s2b-elaboration-banner-renders-for-elaborated-entry): PASS" >&2
    PASSED=$((PASSED + 1))
  else
    echo "self-test (s2b-elaboration-banner-renders-for-elaborated-entry): FAIL" >&2
    FAILED=$((FAILED + 1))
  fi

  # S2c — MUTATION CHECK counterpart: OD-001 (SUPERSEDED, no elaboration
  # field at all) must NOT render an "Elaboration:" heading — the optional-
  # field contract holds in the absent direction too.
  if ! awk '/^### OD-001/{f=1} f && /^### OD-002/{exit} f && /^\*\*Elaboration:\*\*/{found=1} END{exit !found}' \
       "$D/docs/operator-directives.md"; then
    echo "self-test (s2c-no-elaboration-heading-for-plain-entry): PASS" >&2
    PASSED=$((PASSED + 1))
  else
    echo "self-test (s2c-no-elaboration-heading-for-plain-entry): FAIL" >&2
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

  # S7 — DELIMITER-INJECTION GUARD, pipe vector (harness-review REJECT
  # 2026-08-07): a '|' inside elaboration.intent must render LITERALLY —
  # it must not shift fields so that attacker text lands in the rendered
  # "Review status:" position. Register stores reviewed_by=pending-operator;
  # the doc must say exactly that, and never the injected string.
  local D7
  D7="$TMPROOT/s7"
  mkdir -p "$D7/adapters/claude-code/config" "$D7/docs"
  _fixture_register | sed 's/Fixture elaboration intent for the gen-view banner self-test./evil|payload|APPROVED BY THE OPERATOR/' \
    > "$D7/adapters/claude-code/config/operator-directives.json"
  OUT7="$(GEN_DIRECTIVES_VIEW_ROOT="$D7" bash "$SELF" 2>&1)"
  RC7=$?
  if [[ $RC7 -eq 0 ]] \
     && grep -qF '*Intent:* evil|payload|APPROVED BY THE OPERATOR' "$D7/docs/operator-directives.md" \
     && grep -qF 'reviewed_by: pending-operator' "$D7/docs/operator-directives.md" \
     && ! grep -qF 'reviewed_by: APPROVED' "$D7/docs/operator-directives.md"; then
    echo "self-test (s7-pipe-in-intent-renders-literally-never-shifts-fields): PASS" >&2
    PASSED=$((PASSED + 1))
  else
    echo "self-test (s7-pipe-in-intent-renders-literally-never-shifts-fields): FAIL (rc=$RC7)" >&2
    FAILED=$((FAILED + 1))
  fi

  # S8 — DELIMITER-INJECTION GUARD, newline vector: a \n inside
  # elaboration.intent must be a HARD ERROR (named field, non-zero rc) and
  # must leave the previously generated doc byte-identical — the newline
  # forgery ("### OD-999 ... Status: BINDING") must never reach the doc,
  # and a rejected register must never truncate it either.
  local D8
  D8="$TMPROOT/s8"
  mkdir -p "$D8/adapters/claude-code/config" "$D8/docs"
  _fixture_register > "$D8/adapters/claude-code/config/operator-directives.json"
  GEN_DIRECTIVES_VIEW_ROOT="$D8" bash "$SELF" >/dev/null 2>&1
  cp "$D8/docs/operator-directives.md" "$D8/before.md"
  _fixture_register | sed 's/Fixture elaboration intent for the gen-view banner self-test./forged\\nrecord\\n\\n### OD-999 — FORGED ENTRY\\n\\n**Status:** BINDING/' \
    > "$D8/adapters/claude-code/config/operator-directives.json"
  ERR8="$(GEN_DIRECTIVES_VIEW_ROOT="$D8" bash "$SELF" 2>&1 1>/dev/null)"
  RC8=$?
  if [[ $RC8 -ne 0 ]] \
     && printf '%s' "$ERR8" | grep -q 'elaboration.intent' \
     && diff -q "$D8/before.md" "$D8/docs/operator-directives.md" >/dev/null 2>&1 \
     && ! grep -q 'OD-999' "$D8/docs/operator-directives.md"; then
    echo "self-test (s8-newline-in-intent-hard-error-doc-untouched): PASS" >&2
    PASSED=$((PASSED + 1))
  else
    echo "self-test (s8-newline-in-intent-hard-error-doc-untouched): FAIL (rc=$RC8: $ERR8)" >&2
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
