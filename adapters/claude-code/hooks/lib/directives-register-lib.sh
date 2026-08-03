#!/bin/bash
# directives-register-lib.sh — ONE parser for the operator-directives register
# (gated-pipeline-master-2026-08, Task 11; docs/plans/gated-pipeline-master-
# 2026-08.md Task 11; design docs/designs/gated-pipeline-master-2026-08-03.md
# §4 "Directives register + carriage", REQ-B1/REQ-B4).
#
# ============================================================
# WHY THIS EXISTS
# ============================================================
# P-32/P-33 (docs/handoffs/2026-08-03-EXHAUSTIVE-issue-inventory.md): binding
# operator directives lived in 7 uncoordinated stores with no id, no
# supersession, and no single citation target — a push directive lived in
# "Addendum item 1" and never reached plan task text (P-32); the SAME
# push-vs-pull defect was repeated within one hour by two different actors
# because "a directive that is not in the dispatch prompt does not exist"
# (nl-issue 2026-08-02e). DEC-3 consolidates directive truth to 4 named
# roles; this lib is the ONE parser/matcher that serves every consumer of
# the canonical register (config/operator-directives.json) so no two
# callers can silently disagree about what an entry means or which files it
# covers (the same M-3 "no second implementation" rule review-chain-lib.sh
# follows for the review chain).
#
# THREE CONSUMERS (design §4), all reading through this lib:
#   1. plan-reviewer.sh Check 21 (Task 14)      — per-task Directives: field
#      validity + design MUST-REQ coverage.
#   2. scripts/dispatch-directives.sh (Task 20) — tag-matched entries for a
#      task's Files-to-Modify, printed for prompt inlining.
#   3. hooks/doctrine-jit.sh's register walk (Task 20) — carriage channel 3,
#      merged into the SAME hookSpecificOutput emission as the doctrine walk.
# A 4th, separate concern — the generated human-readable view
# (docs/operator-directives.md, scripts/gen-directives-view.sh) — reads the
# JSON directly (the gen-architecture-doc.sh precedent: a one-shot renderer
# needs no runtime matching API), so it is NOT one of the three consumers
# above and does not source this lib.
#
# ============================================================
# ENTRY SCHEMA (config/operator-directives.json; design §4's exact 5-field
# contract this lib validates — see that file's own "note" field for the
# two ADDITIVE, non-validated traceability fields riding alongside)
# ============================================================
#   id            "OD-NNN" (exactly 3 digits)
#   status        "BINDING" | "SUPERSEDED"
#   surfaces      array of glob patterns (bash pattern-match semantics, see
#                 dr_surface_matches below — NOT full picomatch/globstar)
#   supersedes    array of OD-ids or named in-repo laws (free text)
#   instruction   <=5 lines (Rule / Golden case / Anti-pattern / Sanctioned
#                 alternative), a single string with embedded \n
#
# ============================================================
# PUBLIC API
# ============================================================
#   dr_default_register_path
#       Echoes the resolved default path to config/operator-directives.json
#       (repo-root discovery via git, with a manual-climb fallback).
#   dr_validate <register.json>
#       rc 0 iff the file parses as JSON, every entry's id/status/instruction
#       shape is valid, and no id is duplicated. Prints one [directives-
#       register] ERROR line per violation to stderr; rc 1 on any violation,
#       rc 2 if the file is missing or unparseable.
#   dr_entry_ids <register.json> [status-filter]
#       Echoes one entry id per line, in file order. Optional second arg
#       ("BINDING" | "SUPERSEDED") restricts to that status.
#   dr_get_field <register.json> <id> <field>
#       field is one of: status | operator_only | surfaces | supersedes |
#       instruction. Scalar fields echo one line; array fields (surfaces,
#       supersedes) echo one value per line; instruction echoes its raw
#       multi-line text verbatim (the one field this lib does NOT flatten
#       through the pipe-delimited stream, since it legitimately contains
#       embedded newlines).
#   dr_surface_matches <file-path> <glob-pattern>
#       rc 0 iff file-path matches glob-pattern under bash `[[ == ]]` pattern
#       semantics. A bare `*` already matches across `/` — there is no
#       distinct `**` behavior (documented simplification; every glob in the
#       real register and its fixtures is written with this in mind).
#   dr_entries_for_files <register.json> <file1> [file2 ...]
#       THE matching function every carriage consumer calls: echoes the
#       sorted, de-duplicated ids of every BINDING entry (never SUPERSEDED,
#       never one with empty/absent surfaces — an operator_only entry has no
#       code surface to carry) whose surfaces list matches ANY of the given
#       files. Pure lib computation, never judgment (design §4: "glob match
#       on Files-to-Modify; lib computation, not judgment").
#
# ============================================================
# FAILURE MODES (design "Failure modes" section — this lib's contract)
# ============================================================
# Register JSON invalid/missing ⇒ dr_validate returns nonzero with a named
# error; dr_entry_ids/dr_get_field/dr_entries_for_files degrade to EMPTY
# output (never a crash, never a fabricated match) so every consumer's own
# fail-open WARN path fires uniformly from the SAME underlying parse error —
# "register JSON invalid ⇒ all three consumers surface the same parse error
# from the shared lib" (design, verbatim).
#
# NOTE: this lib deliberately does NOT `set -u`/`set -e` at source time (same
# convention as lib/review-chain-lib.sh, lib/gate-contract-lib.sh, lib/
# single-flight-lib.sh) — a sourced lib must never change the calling
# script's shell options out from under it.

# ============================================================
# repo-root / default path resolution
# ============================================================

dr__script_dir() {
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd
}

dr__resolve_root() {
  local sd root
  sd="$(dr__script_dir)"
  root="$(git -C "$sd" rev-parse --show-toplevel 2>/dev/null)"
  if [[ -n "$root" ]]; then
    printf '%s\n' "$root"
    return 0
  fi
  # Manual climb fallback: hooks/lib -> hooks -> claude-code -> adapters -> root
  root="$(cd "$sd/../../../.." 2>/dev/null && pwd)"
  if [[ -n "$root" ]]; then
    printf '%s\n' "$root"
    return 0
  fi
  return 1
}

# dr_default_register_path — the real, committed register. Self-test never
# calls this (it always passes an explicit fixture path).
dr_default_register_path() {
  local root
  root="$(dr__resolve_root)" || return 1
  printf '%s/adapters/claude-code/config/operator-directives.json\n' "$root"
}

# ============================================================
# JSON backend detection (node preferred, jq fallback — the gen-
# architecture-doc.sh / manifest-check.sh convention; neither present ⇒
# every function degrades to empty output, never a crash)
# ============================================================

dr__have_node() { command -v node >/dev/null 2>&1; }
dr__have_jq() { command -v jq >/dev/null 2>&1; }

# dr__stream <register.json> — normalized pipe-delimited extraction, the
# gen-architecture-doc.sh extract_stream convention. One E line per entry
# (id/status/operator_only/n_surfaces/n_supersedes/instruction_line_count),
# one S line per (id, surface) pair, one U line per (id, supersedes) pair.
# `instruction` itself is deliberately NOT streamed here (it contains
# embedded newlines that would break the one-line-per-record contract) —
# dr_get_field fetches it via a dedicated single-entry extraction.
dr__stream() {
  local path="$1"
  [[ -f "$path" ]] || return 2
  if dr__have_node; then
    node -e '
const fs = require("fs");
let m;
try { m = JSON.parse(fs.readFileSync(process.argv[1], "utf8")); }
catch (e) { process.exit(3); }
const entries = Array.isArray(m.entries) ? m.entries : [];
for (const e of entries) {
  const id = e.id || "";
  const status = e.status || "";
  const opOnly = e.operator_only ? "1" : "0";
  const surfaces = Array.isArray(e.surfaces) ? e.surfaces : [];
  const supersedes = Array.isArray(e.supersedes) ? e.supersedes : [];
  const instr = typeof e.instruction === "string" ? e.instruction : "";
  const lines = instr.length ? instr.split("\n").length : 0;
  console.log(["E", id, status, opOnly, surfaces.length, supersedes.length, lines].join("|"));
  for (const s of surfaces) console.log(["S", id, s].join("|"));
  for (const u of supersedes) console.log(["U", id, u].join("|"));
}
' "$path" 2>/dev/null
    return $?
  elif dr__have_jq; then
    jq -e . "$path" >/dev/null 2>&1 || return 3
    jq -r '
(.entries // [])[] as $e |
([ "E", ($e.id // ""), ($e.status // ""),
   ((($e.operator_only // false) | if . then "1" else "0" end)),
   (($e.surfaces // []) | length | tostring),
   (($e.supersedes // []) | length | tostring),
   ((($e.instruction // "") | split("\n") | length) | tostring)
 ] | join("|")),
((($e.surfaces // [])[]) | "S|\($e.id)|\(.)"),
((($e.supersedes // [])[]) | "U|\($e.id)|\(.)")
' "$path" 2>/dev/null
    return $?
  fi
  return 2
}

# ============================================================
# dr_validate <register.json>
# ============================================================
dr_validate() {
  local path="$1"
  if [[ -z "$path" || ! -f "$path" ]]; then
    echo "[directives-register] ERROR: register not found at '${path}'" >&2
    return 2
  fi
  if ! dr__have_node && ! dr__have_jq; then
    echo "[directives-register] ERROR: needs node or jq to validate" >&2
    return 2
  fi

  local stream
  stream="$(dr__stream "$path")"
  local rc=$?
  if [[ $rc -ne 0 ]]; then
    echo "[directives-register] ERROR: '${path}' does not parse as JSON" >&2
    return 1
  fi
  if [[ -z "$stream" ]]; then
    echo "[directives-register] ERROR: '${path}' has zero entries" >&2
    return 1
  fi

  local errors=0
  while IFS='|' read -r tag id status oponly nsurf nsup ilines; do
    [[ "$tag" == "E" ]] || continue
    if [[ ! "$id" =~ ^OD-[0-9]{3}$ ]]; then
      echo "[directives-register] ERROR: entry id '${id}' does not match ^OD-[0-9]{3}\$" >&2
      errors=$((errors + 1))
    fi
    if [[ "$status" != "BINDING" && "$status" != "SUPERSEDED" ]]; then
      echo "[directives-register] ERROR: entry ${id} has invalid status '${status}' (must be BINDING|SUPERSEDED)" >&2
      errors=$((errors + 1))
    fi
    if [[ "$ilines" -eq 0 ]]; then
      echo "[directives-register] ERROR: entry ${id} has an empty instruction" >&2
      errors=$((errors + 1))
    elif [[ "$ilines" -gt 5 ]]; then
      echo "[directives-register] ERROR: entry ${id} instruction is ${ilines} lines (must be <=5)" >&2
      errors=$((errors + 1))
    fi
  done <<< "$stream"

  local dupes
  dupes="$(printf '%s\n' "$stream" | awk -F'|' '$1=="E"{print $2}' | LC_ALL=C sort | uniq -d)"
  if [[ -n "$dupes" ]]; then
    echo "[directives-register] ERROR: duplicate entry id(s): $(printf '%s' "$dupes" | tr '\n' ' ')" >&2
    errors=$((errors + 1))
  fi

  [[ "$errors" -eq 0 ]] && return 0
  return 1
}

# ============================================================
# dr_entry_ids <register.json> [status-filter]
# ============================================================
dr_entry_ids() {
  local path="$1" want="${2:-}"
  dr__stream "$path" 2>/dev/null | awk -F'|' -v want="$want" '$1=="E" && (want=="" || $3==want) {print $2}'
}

# ============================================================
# dr_get_field <register.json> <id> <field>
# ============================================================
dr_get_field() {
  local path="$1" id="$2" field="$3"
  case "$field" in
    instruction)
      if dr__have_node; then
        node -e '
const fs = require("fs");
let m;
try { m = JSON.parse(fs.readFileSync(process.argv[1], "utf8")); } catch (e) { process.exit(0); }
const e = (m.entries || []).find(x => x.id === process.argv[2]);
process.stdout.write(e && typeof e.instruction === "string" ? e.instruction : "");
' "$path" "$id" 2>/dev/null
      elif dr__have_jq; then
        jq -r --arg id "$id" '(.entries[] | select(.id==$id) | .instruction) // ""' "$path" 2>/dev/null
      fi
      ;;
    surfaces)
      dr__stream "$path" 2>/dev/null | awk -F'|' -v want="$id" '$1=="S" && $2==want {print $3}'
      ;;
    supersedes)
      dr__stream "$path" 2>/dev/null | awk -F'|' -v want="$id" '$1=="U" && $2==want {print $3}'
      ;;
    status)
      dr__stream "$path" 2>/dev/null | awk -F'|' -v want="$id" '$1=="E" && $2==want {print $3}'
      ;;
    operator_only)
      dr__stream "$path" 2>/dev/null | awk -F'|' -v want="$id" '$1=="E" && $2==want {print $4}'
      ;;
    *)
      return 2
      ;;
  esac
}

# ============================================================
# dr_surface_matches <file-path> <glob-pattern>
# ============================================================
dr_surface_matches() {
  local file="$1" pattern="$2"
  [[ -z "$pattern" ]] && return 1
  case "$file" in
    $pattern) return 0 ;;
    *) return 1 ;;
  esac
}

# ============================================================
# dr_entries_for_files <register.json> <file1> [file2 ...]
# ============================================================
dr_entries_for_files() {
  local path="$1"; shift
  local -a files=("$@")
  [[ ${#files[@]} -eq 0 ]] && return 0

  local stream
  stream="$(dr__stream "$path" 2>/dev/null)"
  [[ -z "$stream" ]] && return 0

  local -a binding_ids=()
  while IFS='|' read -r tag id status oponly nsurf nsup ilines; do
    [[ "$tag" == "E" ]] || continue
    [[ "$status" == "BINDING" ]] || continue
    [[ "$nsurf" -gt 0 ]] || continue
    binding_ids+=("$id")
  done <<< "$stream"

  [[ ${#binding_ids[@]} -eq 0 ]] && return 0

  local -a matched=()
  local id
  for id in "${binding_ids[@]}"; do
    local -a surfs=()
    while IFS= read -r s; do
      [[ -n "$s" ]] && surfs+=("$s")
    done < <(printf '%s\n' "$stream" | awk -F'|' -v want="$id" '$1=="S" && $2==want {print $3}')
    [[ ${#surfs[@]} -eq 0 ]] && continue

    local f p hit=0
    for f in "${files[@]}"; do
      for p in "${surfs[@]}"; do
        if dr_surface_matches "$f" "$p"; then
          hit=1
          break 2
        fi
      done
    done
    [[ "$hit" -eq 1 ]] && matched+=("$id")
  done

  [[ ${#matched[@]} -eq 0 ]] && return 0
  printf '%s\n' "${matched[@]}" | LC_ALL=C sort -u
}

# ============================================================
# --self-test (direct-execution guard — same convention as
# lib/gate-contract-lib.sh and lib/review-chain-lib.sh)
# ============================================================
if [[ "${BASH_SOURCE[0]:-$0}" == "${0}" ]] && [[ "${1:-}" == "--self-test" ]]; then
  PASSED=0
  FAILED=0
  _st() { # <label> <expected> <actual>
    if [[ "$2" == "$3" ]]; then
      echo "self-test ($1): PASS" >&2
      PASSED=$((PASSED + 1))
    else
      echo "self-test ($1): FAIL (expected '$2', got '$3')" >&2
      FAILED=$((FAILED + 1))
    fi
  }
  _st_rc() { # <label> <expected-rc> <actual-rc>
    _st "$1" "$2" "$3"
  }

  if ! dr__have_node && ! dr__have_jq; then
    echo "self-test: SKIP — neither node nor jq available" >&2
    exit 0
  fi

  SELF_DIR="$(dr__script_dir)"
  ROOT="$(dr__resolve_root)"
  FIXDIR="${ROOT}/adapters/claude-code/tests/fixtures/directives-register"
  FIXREG="${FIXDIR}/fixture-register.json"
  FIXFILES="${FIXDIR}/fixture-files.txt"

  if [[ ! -f "$FIXREG" || ! -f "$FIXFILES" ]]; then
    echo "self-test: FAIL — fixtures missing at ${FIXDIR}" >&2
    exit 1
  fi

  # ---- round-trip fixture: dr_validate ----
  dr_validate "$FIXREG" >/dev/null 2>&1
  _st "round-trip-fixture-validates" "0" "$?"

  # ---- round-trip fixture: dr_entry_ids ----
  IDS="$(dr_entry_ids "$FIXREG" | LC_ALL=C sort | paste -sd, -)"
  _st "round-trip-entry-ids" "OD-901,OD-902,OD-903,OD-904" "$IDS"

  BINDING_IDS="$(dr_entry_ids "$FIXREG" "BINDING" | LC_ALL=C sort | paste -sd, -)"
  _st "round-trip-binding-filter" "OD-901,OD-902,OD-904" "$BINDING_IDS"

  SUPERSEDED_IDS="$(dr_entry_ids "$FIXREG" "SUPERSEDED" | LC_ALL=C sort | paste -sd, -)"
  _st "round-trip-superseded-filter" "OD-903" "$SUPERSEDED_IDS"

  # ---- round-trip fixture: dr_get_field ----
  _st "get-field-status-OD-901" "BINDING" "$(dr_get_field "$FIXREG" "OD-901" status)"
  _st "get-field-status-OD-903" "SUPERSEDED" "$(dr_get_field "$FIXREG" "OD-903" status)"
  _st "get-field-operator-only-OD-904" "1" "$(dr_get_field "$FIXREG" "OD-904" operator_only)"
  _st "get-field-operator-only-OD-901" "0" "$(dr_get_field "$FIXREG" "OD-901" operator_only)"
  INSTR_LINES="$(dr_get_field "$FIXREG" "OD-901" instruction | wc -l | tr -d '[:space:]')"
  _st "get-field-instruction-nonempty-and-in-budget" "1" "$([[ -n "$(dr_get_field "$FIXREG" "OD-901" instruction)" && "$INSTR_LINES" -le 5 ]] && echo 1 || echo 0)"
  _st "get-field-supersedes-OD-903" "OD-901" "$(dr_get_field "$FIXREG" "OD-903" supersedes)"

  # ---- dr_surface_matches unit checks ----
  dr_surface_matches "adapters/claude-code/hooks/foo-gate.sh" "adapters/claude-code/hooks/*gate*.sh"
  _st_rc "surface-matches-positive" "0" "$?"
  dr_surface_matches "docs/foo.md" "adapters/claude-code/hooks/*gate*.sh"
  _st_rc "surface-matches-negative" "1" "$?"
  dr_surface_matches "adapters/claude-code/hooks/sub/foo-gate.sh" "adapters/claude-code/hooks/*gate*.sh"
  _st_rc "surface-matches-star-crosses-slash" "0" "$?"

  # ---- THE shared round-trip: dr_entries_for_files against fixture-files.txt ----
  mapfile -t FIXFILE_LIST < "$FIXFILES"
  RESULT="$(dr_entries_for_files "$FIXREG" "${FIXFILE_LIST[@]}" | paste -sd, -)"
  _st "entries-for-files-positive-only-OD-901" "OD-901" "$RESULT"

  # negative-only file list (matches nothing)
  RESULT_NEG="$(dr_entries_for_files "$FIXREG" "some/unrelated/file.txt" | paste -sd, -)"
  _st "entries-for-files-no-match" "" "$RESULT_NEG"

  # a file list that would match OD-902's docs/designs/** surface
  RESULT_DESIGNS="$(dr_entries_for_files "$FIXREG" "docs/designs/some-design.md" | paste -sd, -)"
  _st "entries-for-files-matches-OD-902-only" "OD-902" "$RESULT_DESIGNS"

  # ---- dr_validate negative fixtures (mktemp, never touch the real register) ----
  TMPD=$(mktemp -d 2>/dev/null || mktemp -d -t drlibst)
  trap 'rm -rf "$TMPD"' EXIT

  echo '{ this is not json' > "$TMPD/malformed.json"
  dr_validate "$TMPD/malformed.json" >/dev/null 2>&1
  _st_rc "validate-malformed-json-fails" "1" "$?"

  cat > "$TMPD/dupes.json" <<'EOF'
{"entries":[
  {"id":"OD-001","status":"BINDING","surfaces":[],"supersedes":[],"instruction":"a"},
  {"id":"OD-001","status":"BINDING","surfaces":[],"supersedes":[],"instruction":"b"}
]}
EOF
  dr_validate "$TMPD/dupes.json" >/dev/null 2>&1
  _st_rc "validate-duplicate-id-fails" "1" "$?"

  cat > "$TMPD/badid.json" <<'EOF'
{"entries":[{"id":"OD-1","status":"BINDING","surfaces":[],"supersedes":[],"instruction":"a"}]}
EOF
  dr_validate "$TMPD/badid.json" >/dev/null 2>&1
  _st_rc "validate-bad-id-format-fails" "1" "$?"

  cat > "$TMPD/badstatus.json" <<'EOF'
{"entries":[{"id":"OD-001","status":"ACTIVE","surfaces":[],"supersedes":[],"instruction":"a"}]}
EOF
  dr_validate "$TMPD/badstatus.json" >/dev/null 2>&1
  _st_rc "validate-bad-status-fails" "1" "$?"

  cat > "$TMPD/toolong.json" <<'EOF'
{"entries":[{"id":"OD-001","status":"BINDING","surfaces":[],"supersedes":[],"instruction":"1\n2\n3\n4\n5\n6"}]}
EOF
  dr_validate "$TMPD/toolong.json" >/dev/null 2>&1
  _st_rc "validate-instruction-too-long-fails" "1" "$?"

  dr_validate "$TMPD/does-not-exist.json" >/dev/null 2>&1
  _st_rc "validate-missing-file-errors" "2" "$?"

  echo "" >&2
  echo "self-test summary: ${PASSED} passed, ${FAILED} failed (of $((PASSED + FAILED)) scenarios)" >&2
  if [[ "$FAILED" -eq 0 ]]; then
    exit 0
  else
    exit 1
  fi
fi
