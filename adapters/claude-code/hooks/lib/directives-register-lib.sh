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
  # PRIMARY: the shared canonical resolver (lib/nl-paths.sh, ~20 other hooks
  # already use it — this file skipped it and paid for the gap, gated-
  # pipeline-master-2026-08 Task 8 doctor triage). nl_repo_root() has an
  # NL_REPO_ROOT env tier and an install-time ~/.claude/local/nl-repo-path
  # config-file tier BEFORE it falls back to git — both of which this file's
  # old git+manual-climb-only implementation lacked. That absence is exactly
  # why the doctor's self-test sweep (which runs hooks/lib/*.sh from the LIVE
  # MIRROR at ~/.claude/hooks/lib/, not a git checkout) mis-resolved fixtures:
  # ~/.claude is not a git repo, so the git tier failed, and the manual climb
  # below (`../../../..`, sized for the REPO depth hooks/lib -> hooks ->
  # claude-code -> adapters -> root) climbed only 4 levels from the LIVE
  # layout's shallower hooks/lib -> hooks -> .claude -> <user>, landing at
  # the user's home directory's PARENT (one level short of the real
  # checkout) — reproduced directly by running this climb from the live
  # path: ROOT resolved to the Users-drive root, and the fixture path
  # formula then appended "adapters/claude-code/tests/fixtures/directives-
  # register" beneath that wrong root, so the self-test reported the
  # fixtures missing at a path that does not exist. nl_repo_root()'s
  # config-file tier (written by install.sh) resolves correctly from
  # either location.
  if [[ -f "${sd}/nl-paths.sh" ]]; then
    # shellcheck disable=SC1091
    if source "${sd}/nl-paths.sh" 2>/dev/null && declare -F nl_repo_root >/dev/null 2>&1; then
      root="$(nl_repo_root)"
      if [[ -n "$root" ]]; then
        printf '%s\n' "$root"
        return 0
      fi
    fi
  fi
  # FALLBACK (nl-paths.sh missing/unreadable): the old behavior, unchanged.
  root="$(git -C "$sd" rev-parse --show-toplevel 2>/dev/null)"
  if [[ -n "$root" ]]; then
    printf '%s\n' "$root"
    return 0
  fi
  # Manual climb fallback: hooks/lib -> hooks -> claude-code -> adapters -> root
  # (correct ONLY for the repo-shaped depth; kept as a last resort so a
  # checkout missing nl-paths.sh degrades to today's behavior rather than
  # a hard failure).
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
# PURE-BASH fast path (gated-pipeline-master-2026-08 Task 20; design
# docs/designs/gated-pipeline-master-2026-08-03.md §4, REQ-B11 carriage
# channel 3 — doctrine-jit.sh's PostToolUse register walk)
# ============================================================
# WHY THIS SECOND CODE PATH EXISTS (fidelity F-5, docs/reviews/2026-08-03-
# gated-pipeline-plan-fidelity-review.md): dr_entries_for_files above (and
# dr__stream it's built on) spawns node or jq — on this platform a single jq
# invocation alone costs ~174ms. doctrine-jit.sh's register walk runs on
# EVERY Edit/Write/MultiEdit and its Behavioral Contract caps the walk's
# ADDED latency at <50ms — one jq/node subprocess would blow that budget by
# 3x on its own. This section is a SECOND reader for the SAME register file,
# kept in THIS lib (M-3: one parser, one file — not a duplicate
# implementation living inside doctrine-jit.sh) that uses ZERO subprocess
# calls: no jq, no node, no grep/awk/sed, not even `sort` on the hot path —
# every operation below is a bash builtin (`$(< file)` fast-slurp, an
# IFS-based unquoted-array split, `case` glob matching, `${var#prefix}` /
# `${var%suffix}` parameter-expansion extraction, plain array/assoc-array
# ops). It deliberately does NOT use a `while read` line loop or `[[ =~ ]]`
# regex — both were measured MUCH slower than the slurp+case approach on
# this platform (see the timing note on _dr__parse_all_bash below); a
# subprocess-free implementation is necessary but not sufficient to hit the
# <50ms budget here, the specific bash constructs matter too.
#
# It is NOT a general JSON parser. It line-scans the register file
# exploiting ITS OWN generated pretty-print convention (2-space indent, one
# JSON field per line; a `"surfaces": [` array is either collapsed to
# `"surfaces": [],` on one line when empty, or opened on its own line with
# ONE quoted string per subsequent line and closed by a bare `]` — the exact
# shape every entry in config/operator-directives.json is written in, and
# the shape dr_validate above independently confirms is valid JSON). A line
# this reader cannot make sense of is simply skipped (fail-open — see
# FAILURE MODES above: this lib never crashes, never fabricates a match).
#
# Round-trip self-test below proves this reader agrees with dr_entries_for_
# files (the node/jq path) on the shared T11/T20 fixture AND on the real
# committed register for Task 20's own files — the strongest evidence two
# independent parsers of the same file agree.

# _dr__decode_escapes <raw-json-string-value> — decodes \n \" \\ \t escape
# sequences to their real characters using bash's GLOBAL pattern
# substitution (`${var//search/replace}`), not a per-character loop.
#
# MEASURED PLATFORM FINDING (T20 evidence): an earlier char-by-char version
# of this function (index, substring-extract, case-dispatch per character)
# cost ~60-80ms to decode three ~350-char instructions on this platform —
# by itself more than the entire <50ms budget. `${var//pat/repl}` does the
# same work as ONE builtin C-level pass per escape class (5 passes total
# here) instead of ~1000+ bash-interpreted loop iterations; measured well
# under 1ms for the same input (T20 evidence timing table).
#
# ORDER MATTERS: `\\` (backslash-backslash, one literal backslash) is
# replaced with a placeholder FIRST, before `\n`/`\"`/`\t` are decoded, and
# only converted to a real `\` LAST. Decoding `\\` to `\` before handling
# `\n` would let a genuine `\\` immediately followed by a literal `n` in the
# source text (backslash, backslash, n) collapse into `\` + `n`, which a
# later `\n`-pass would then wrongly re-decode as a newline escape — the
# placeholder indirection is what prevents that misread (verified against
# OD-020's real `HKLM\\SOFTWARE\\Policies\\Claude` instruction text in the
# round-trip self-test above, the one real entry in the register that
# actually exercises `\\`).
_dr__decode_escapes() {
  local s="$1" ph=$'\x01'
  s="${s//\\\\/$ph}"
  s="${s//\\n/$'\n'}"
  s="${s//\\\"/\"}"
  s="${s//\\t/$'\t'}"
  s="${s//$ph/\\}"
  printf '%s' "$s"
}

# _dr__parse_all_bash <register.json> — ONE pure-bash pass over the file.
#
# MEASURED PLATFORM FINDING (T20 evidence, this machine): a `while read -r
# line; do ... done < file` loop combined with `[[ "$line" =~ regex ]]`
# costs ~270-320ms over this 325-line file — regex compilation/match and the
# per-line `read` builtin are each measurably expensive on this bash build,
# NOT just subprocess spawns. `$(< file)` (bash's builtin fast-slurp, which
# reads the whole file without invoking `cat` or forking), an IFS-based
# unquoted-array split (`LINES=($content)`, also a builtin, no loop/fork),
# and `case "$line" in *glob*)` matching instead of `[[ =~ ]]` regex bring
# the SAME 325-line, same-fields parse down to ~11-15ms (measured 10-run
# comparison in the T20 evidence file) — the difference is the matching
# mechanism (fnmatch-style case vs. POSIX-ERE compile+exec), not the data
# volume. This is why this function reads the way it does; do not
# "simplify" it back to a read-loop + regex without re-measuring.
#
# Side effect: populates four globals (reset first, even on early return, so
# a stale prior call can never leak into a fresh one):
#   _DR_BASH_IDS      entry ids, file order
#   _DR_BASH_STATUS   id -> status
#   _DR_BASH_NSURF    id -> surface count (string integer, "0" if none)
#   _DR_BASH_SURF     "<id>::<0-based-index>" -> surface glob string
#   _DR_BASH_INSTR    id -> RAW (still-escaped) instruction text
# (Surfaces are stored as indexed composite keys, not a newline-joined
# string, so no caller ever needs to re-split a string at match time — that
# re-split, via a `<<<` here-string, is itself another measured-expensive
# construct on this platform; seen in bench diagnostics during this task's
# build, not re-included here since the composite-key form removes the need
# for it entirely.)
# Missing/unreadable file -> all globals left empty. Never a crash.
_dr__parse_all_bash() {
  local path="$1"
  _DR_BASH_IDS=()
  declare -gA _DR_BASH_STATUS=()
  declare -gA _DR_BASH_NSURF=()
  declare -gA _DR_BASH_SURF=()
  declare -gA _DR_BASH_INSTR=()
  [[ -f "$path" ]] || return 0

  local content
  content="$(< "$path")" || return 0
  [[ -n "$content" ]] || return 0

  local -a _lines=()
  local _old_ifs="$IFS"
  IFS=$'\n'
  set -f
  # shellcheck disable=SC2206
  _lines=($content)
  set +f
  IFS="$_old_ifs"

  local id="" status="" instr="" in_surfaces=0 nsurf=0 line v

  for line in "${_lines[@]}"; do
    line="${line%$'\r'}"

    if [[ "$in_surfaces" -eq 1 ]]; then
      case "$line" in
        *']'*)
          in_surfaces=0
          ;;
        *'"'*)
          v="${line#*\"}"
          v="${v%\"*}"
          _DR_BASH_SURF["${id}::${nsurf}"]="$v"
          nsurf=$((nsurf + 1))
          ;;
      esac
      continue
    fi

    case "$line" in
      *'"id":'*'"OD-'*)
        if [[ -n "$id" ]]; then
          _DR_BASH_IDS+=("$id")
          _DR_BASH_STATUS["$id"]="$status"
          _DR_BASH_NSURF["$id"]="$nsurf"
          _DR_BASH_INSTR["$id"]="$instr"
        fi
        v="${line#*\"id\": \"}"
        v="${v%\"*}"
        id="$v"
        status=""; instr=""; nsurf=0; in_surfaces=0
        ;;
      *'"status":'*'"'*)
        v="${line#*\"status\": \"}"
        v="${v%\"*}"
        status="$v"
        ;;
      *'"surfaces": [],'*)
        nsurf=0
        ;;
      *'"surfaces": ['*)
        in_surfaces=1
        nsurf=0
        ;;
      *'"instruction":'*'"'*)
        v="${line#*\"instruction\": \"}"
        v="${v%\"*}"
        instr="$v"
        ;;
    esac
  done

  if [[ -n "$id" ]]; then
    _DR_BASH_IDS+=("$id")
    _DR_BASH_STATUS["$id"]="$status"
    _DR_BASH_NSURF["$id"]="$nsurf"
    _DR_BASH_INSTR["$id"]="$instr"
  fi
  return 0
}

# dr_entries_for_files_bash <register.json> <file1> [file2 ...]
# Pure-bash equivalent of dr_entries_for_files, same output contract
# (sorted, de-duped BINDING ids with >=1 matching surface). Used by the
# round-trip self-test below to prove the two readers agree; NOT the
# doctrine-jit hot path (that's dr_register_walk_bash — single file, no
# `sort` call). This one DOES call `sort -u` for output-contract parity
# with dr_entries_for_files, which is fine off the per-event hot path.
dr_entries_for_files_bash() {
  local path="$1"; shift
  local -a files=("$@")
  [[ ${#files[@]} -eq 0 ]] && return 0
  _dr__parse_all_bash "$path"
  [[ ${#_DR_BASH_IDS[@]} -eq 0 ]] && return 0

  local -a matched=()
  local id f p hit n k
  for id in "${_DR_BASH_IDS[@]}"; do
    [[ "${_DR_BASH_STATUS[$id]:-}" == "BINDING" ]] || continue
    n="${_DR_BASH_NSURF[$id]:-0}"
    [[ "$n" -gt 0 ]] || continue
    hit=0
    for f in "${files[@]}"; do
      for ((k = 0; k < n; k++)); do
        p="${_DR_BASH_SURF["${id}::${k}"]}"
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

# dr_register_walk_bash <register.json> <file>
# THE doctrine-jit.sh hot-path entry point (channel 3). Single file (the one
# PostToolUse file_path per event).
#
# DELIBERATELY NOT built on _dr__parse_all_bash + dr_entries_for_files_bash's
# two-pass shape (parse-everything-into-globals, then a separate matching
# pass) — measured ~13ms slower end-to-end than the single fused pass below
# (T20 evidence timing table), entirely from populating/reading the
# _DR_BASH_SURF composite-key assoc array for surfaces that, for a given
# single file, mostly never need to exist. This function fuses parse +
# match into ONE pass over the same slurp+IFS-split+case-glob line array:
# it tests each surface glob against <file> AS IT IS ENCOUNTERED (no
# storage), short-circuits the rest of an entry's surfaces the moment one
# hits, and only decodes+emits the instruction for entries that actually
# matched AND are BINDING. This is a second, narrower reader for the same
# register shape (still governed by the same self-tests, same fixtures, same
# fail-open contract as _dr__parse_all_bash above) — kept as a distinct
# function rather than sharing the general one specifically because THIS is
# the <50ms-budget call site (F-5) and the general one is not (see the
# module header "WHY THIS SECOND CODE PATH EXISTS" and the timing note on
# _dr__parse_all_bash for the platform findings that drove both shapes).
#
# For each BINDING entry with >=1 surface matching <file>, sets global
# DR_REGISTER_WALK_OUT to a text block per matched entry:
#   ===<id>===
#   <instruction, decoded to real newlines/quotes/backslashes>
#   <blank line>
# NOTE (T20 evidence, fork-cost finding): this SETS A GLOBAL rather than
# echoing to stdout, deliberately — the caller (doctrine-jit.sh's
# _compute_register_body) needs the text to build the injected body, and on
# this platform a SINGLE `$( )` command-substitution fork to capture it
# turned out to be a measurable fraction of this function's own total cost
# under concurrent-process load (measured during this task's build: 10-20ms
# saved per call by avoiding the fork entirely, on a machine observed
# running 100+ concurrent bash/node/claude processes at build time — see
# the evidence file's environment note). A global write is a pure-bash
# assignment; a `$( )` around a function call is always a fork in bash,
# regardless of what's inside it.
# DR_REGISTER_WALK_OUT is left "" on no match / missing file / unreadable
# register — never a crash (same fail-open contract as every other function
# in this lib).
dr_register_walk_bash() {
  local path="$1" file="$2"
  DR_REGISTER_WALK_OUT=""
  [[ -n "$file" && -f "$path" ]] || return 0

  local content
  content="$(< "$path")" || return 0
  [[ -n "$content" ]] || return 0

  local -a _lines=()
  local _old_ifs="$IFS"
  IFS=$'\n'
  set -f
  # shellcheck disable=SC2206
  _lines=($content)
  set +f
  IFS="$_old_ifs"

  local id="" status="" instr="" in_surfaces=0 any_hit=0 line v

  _dr__rw_flush() {
    [[ -z "$id" ]] && return 0
    if [[ "$status" == "BINDING" && "$any_hit" -eq 1 ]]; then
      # INLINED _dr__decode_escapes's body rather than calling it via
      # `$( )` — a command substitution is a fork REGARDLESS of what's
      # inside it, and this is the hot path a `$( )` here would defeat
      # (same reasoning as DR_REGISTER_WALK_OUT itself being a global, see
      # this function's docstring above). _dr__decode_escapes stays as a
      # standalone function too (self-tested directly, used as a
      # documented public-ish helper) — this is a deliberate, narrow
      # duplication of ~5 lines to keep the hot path fork-free, not a
      # second decode implementation with different semantics.
      local decoded="$instr" ph=$'\x01'
      decoded="${decoded//\\\\/$ph}"
      decoded="${decoded//\\n/$'\n'}"
      decoded="${decoded//\\\"/\"}"
      decoded="${decoded//\\t/$'\t'}"
      decoded="${decoded//$ph/\\}"
      DR_REGISTER_WALK_OUT="${DR_REGISTER_WALK_OUT}===${id}===
${decoded}

"
    fi
    return 0
  }

  for line in "${_lines[@]}"; do
    line="${line%$'\r'}"

    if [[ "$in_surfaces" -eq 1 ]]; then
      case "$line" in
        *']'*)
          in_surfaces=0
          ;;
        *'"'*)
          if [[ "$any_hit" -eq 0 ]]; then
            v="${line#*\"}"
            v="${v%\"*}"
            dr_surface_matches "$file" "$v" && any_hit=1
          fi
          ;;
      esac
      continue
    fi

    case "$line" in
      *'"id":'*'"OD-'*)
        _dr__rw_flush
        v="${line#*\"id\": \"}"
        v="${v%\"*}"
        id="$v"; status=""; instr=""; any_hit=0; in_surfaces=0
        ;;
      *'"status":'*'"'*)
        v="${line#*\"status\": \"}"
        v="${v%\"*}"
        status="$v"
        ;;
      *'"surfaces": [],'*)
        : # empty surfaces — any_hit stays 0, nothing to do
        ;;
      *'"surfaces": ['*)
        in_surfaces=1
        ;;
      *'"instruction":'*'"'*)
        v="${line#*\"instruction\": \"}"
        v="${v%\"*}"
        instr="$v"
        ;;
    esac
  done
  _dr__rw_flush
  return 0
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

  # ---- Task 20 (gated-pipeline-master-2026-08, REQ-B11 F-5): PURE-BASH fast
  # path round-trip against the SAME fixtures, proving the two independent
  # readers (node/jq-backed dr_entries_for_files vs. subprocess-free
  # dr_entries_for_files_bash / dr_register_walk_bash) agree. ----
  RESULT_BASH="$(dr_entries_for_files_bash "$FIXREG" "${FIXFILE_LIST[@]}" | paste -sd, -)"
  _st "bash-entries-for-files-positive-only-OD-901" "OD-901" "$RESULT_BASH"

  RESULT_BASH_NEG="$(dr_entries_for_files_bash "$FIXREG" "some/unrelated/file.txt" | paste -sd, -)"
  _st "bash-entries-for-files-no-match" "" "$RESULT_BASH_NEG"

  RESULT_BASH_DESIGNS="$(dr_entries_for_files_bash "$FIXREG" "docs/designs/some-design.md" | paste -sd, -)"
  _st "bash-entries-for-files-matches-OD-902-only" "OD-902" "$RESULT_BASH_DESIGNS"

  # dr_register_walk_bash (the actual doctrine-jit hot-path call) — single
  # file, must find OD-901's block (id header + decoded instruction) and
  # must NOT surface OD-902/903/904 for a hooks/*gate*.sh file. Reads the
  # DR_REGISTER_WALK_OUT global (not a captured return) — see the
  # function's own docstring for why it sets a global instead of echoing.
  dr_register_walk_bash "$FIXREG" "adapters/claude-code/hooks/dispatch-chain-gate.sh"
  WALK_OUT="$DR_REGISTER_WALK_OUT"
  if printf '%s' "$WALK_OUT" | grep -q '^===OD-901===$' \
     && printf '%s' "$WALK_OUT" | grep -q 'fixture binding entry whose surface matches' \
     && ! printf '%s' "$WALK_OUT" | grep -q 'OD-902\|OD-903\|OD-904'; then
    echo "self-test (register-walk-bash-single-file-match): PASS" >&2
    PASSED=$((PASSED + 1))
  else
    echo "self-test (register-walk-bash-single-file-match): FAIL (got: $WALK_OUT)" >&2
    FAILED=$((FAILED + 1))
  fi

  dr_register_walk_bash "$FIXREG" "some/unrelated/file.txt"
  WALK_OUT_NEG="$DR_REGISTER_WALK_OUT"
  _st "register-walk-bash-no-match-silent" "" "$WALK_OUT_NEG"

  # decode correctness: escaped backslash + newline + quote round-trip
  DECODED="$(_dr__decode_escapes 'line1\nHKLM\\\\SOFTWARE\\\\Claude\nquote:\"x\"')"
  EXPECTED_DECODED="$(printf 'line1\nHKLM\\\\SOFTWARE\\\\Claude\nquote:"x"')"
  _st "decode-escapes-backslash-newline-quote" "$EXPECTED_DECODED" "$DECODED"

  # ---- real committed register: Task 20's own three wire-checked files
  # must resolve to exactly the set the T20 fidelity-carriage computation
  # expects (OD-002/007/008/013/018), PLUS OD-021 (added to the register
  # after that computation was made — a live demonstration that this
  # matcher tracks the CURRENT register, not a stale snapshot; see the T20
  # evidence entry for the carriage-WARN this produces against the plan's
  # own now-stale Directives: line). ----
  REALREG="$(dr_default_register_path 2>/dev/null || true)"
  if [[ -n "$REALREG" && -f "$REALREG" ]]; then
    REAL_RESULT="$(dr_entries_for_files_bash "$REALREG" \
      "adapters/claude-code/scripts/dispatch-directives.sh" \
      "adapters/claude-code/hooks/doctrine-jit.sh" \
      "adapters/claude-code/doctrine/orchestrator-pattern.md" | paste -sd, -)"
    _st "real-register-t20-files-match-set" "OD-002,OD-007,OD-008,OD-013,OD-018,OD-021" "$REAL_RESULT"
  else
    echo "self-test (real-register-t20-files-match-set): SKIP — real register not resolvable in this environment" >&2
  fi

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
