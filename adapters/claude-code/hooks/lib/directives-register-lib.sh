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
# ELABORATION (OPTIONAL, ADDITIVE field — operator proposal 2026-08-04:
# "translate my verbatim words into something more complete and thorough").
# ============================================================
# An entry MAY carry an "elaboration" object alongside the 5-field contract
# above. The verbatim `instruction` field stays PRIMARY and untouched by
# this feature — elaboration INTERPRETS, never replaces; on any conflict
# between an elaboration and the verbatim instruction, the verbatim wins,
# and each elaboration's own `intent` text says so explicitly (a lib-level
# validation cannot check semantic fidelity, only shape — see dr_validate's
# elaboration checks below, and reviewed_by for the human-review tracking).
#   elaboration.intent            one paragraph: the outcome the operator is
#                                  actually buying, beyond the literal words.
#   elaboration.requirements      array of 3-7 derived, testable bullets.
#   elaboration.anti_patterns     array of >=1 bullets — what violates the
#                                  directive while superficially complying
#                                  (the Goodhart list).
#   elaboration.applies_when      trigger conditions, one line.
#   elaboration.worked_example    a real incident where following/violating
#                                  the directive mattered, one line.
#   elaboration.elaborated_by     who/what wrote this elaboration.
#   elaboration.elaborated_at     date written.
#   elaboration.reviewed_by       "pending-operator" until a human operator
#                                  signs off — no code path may claim
#                                  operator sign-off on an elaboration's
#                                  behalf; the generated view (gen-
#                                  directives-view.sh) renders every
#                                  elaboration with a visible "interpretation
#                                  — correct me if wrong" banner.
# Validated shape only (presence, nonempty, requirements count 3-7,
# anti_patterns count >=1) — semantic correctness of the interpretation is a
# human-review concern this lib cannot and does not judge.
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
#   dr_has_elaboration <register.json> <id>
#       rc 0 iff entry <id> carries a well-formed elaboration object (has a
#       non-empty intent), rc 1 otherwise (absent field, absent entry, or
#       missing/unreadable register — same fail-open posture as every other
#       function here).
#   dr_get_elaboration_field <register.json> <id> <field>
#       field is one of: intent | applies_when | worked_example |
#       elaborated_by | elaborated_at | reviewed_by | requirements |
#       anti_patterns. Scalar fields echo one line (empty if absent); array
#       fields (requirements, anti_patterns) echo one value per line. Node/jq
#       backed (same as dr_get_field) — NOT the doctrine-jit hot path; see
#       dr_register_walk_bash below for that.
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
# (id/status/operator_only/n_surfaces/n_supersedes/instruction_line_count/
# badfield — badfield is the delimiter-injection flag: the first field whose
# value violates the single-line convention, as "<field>:crlf|cr|pipe", or
# empty when the entry is clean; dr_validate turns a non-empty badfield into
# a named ERROR so a dirty register cannot validate),
# one S line per (id, surface) pair, one U line per (id, supersedes) pair,
# and (Task: directives-elaboration-layer) one M line per entry that
# carries a well-formed `elaboration` object —
# id/n_requirements/n_anti_patterns/len(intent)/len(applies_when)/
# len(worked_example)/len(elaborated_by)/len(elaborated_at)/len(reviewed_by)
# — used ONLY by dr_validate's shape checks below; an entry with no
# elaboration field emits no M line at all (absence, not zeros — dr_validate
# must not require the field). `instruction` itself is deliberately NOT
# streamed here (it contains embedded newlines that would break the
# one-line-per-record contract) — dr_get_field fetches it via a dedicated
# single-entry extraction; elaboration.intent/applies_when/worked_example/
# elaborated_by/elaborated_at/reviewed_by are single-line-only — an
# authoring convention now MECHANICALLY ENFORCED via the E-line badfield
# above (CR/LF banned in every value; '|' additionally banned in id/title/
# status/surfaces/supersedes, the fields some consumer parses positionally).
# dr_get_elaboration_field fetches scalar text via dedicated single-entry
# extraction, and M-line length counts here are a cheap proxy for "field is
# present and non-empty" without needing to stream the text itself.
# (gen-directives-view.sh independently guards its own richer text stream
# at its own emit point — two layers, same rule.)
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
// badfield: first single-line-convention violation, "<field>:crlf|cr|pipe",
// or "" when clean. CR/LF is banned in every value (a newline terminates a
// stream record and lets the remainder forge new records); a pipe char is
// banned in the fields some consumer parses positionally (id/title/status/
// surfaces/supersedes). LF is legal only inside the instruction field
// (line-split by every consumer); a CR there is still flagged.
// NOTE: this whole script rides a bash single-quoted string — no
// apostrophes or backticks in comments here.
const badOf = (e) => {
  const crlf = (v) => typeof v === "string" && /[\r\n]/.test(v);
  const pipe = (v) => typeof v === "string" && v.includes("|");
  for (const [f, v] of [["id", e.id], ["title", e.title], ["status", e.status]]) {
    if (crlf(v)) return f + ":crlf";
    if (pipe(v)) return f + ":pipe";
  }
  if (crlf(e.source)) return "source:crlf";
  for (const s of (Array.isArray(e.surfaces) ? e.surfaces : [])) {
    if (crlf(s)) return "surfaces:crlf";
    if (pipe(s)) return "surfaces:pipe";
  }
  for (const u of (Array.isArray(e.supersedes) ? e.supersedes : [])) {
    if (crlf(u)) return "supersedes:crlf";
    if (pipe(u)) return "supersedes:pipe";
  }
  if (typeof e.instruction === "string" && /\r/.test(e.instruction)) return "instruction:cr";
  const el = (e.elaboration && typeof e.elaboration === "object") ? e.elaboration : null;
  if (el) {
    for (const f of ["intent", "applies_when", "worked_example", "elaborated_by", "elaborated_at", "reviewed_by"])
      if (crlf(el[f])) return "elaboration." + f + ":crlf";
    for (const r of (Array.isArray(el.requirements) ? el.requirements : []))
      if (crlf(r)) return "elaboration.requirements:crlf";
    for (const n of (Array.isArray(el.anti_patterns) ? el.anti_patterns : []))
      if (crlf(n)) return "elaboration.anti_patterns:crlf";
  }
  return "";
};
for (const e of entries) {
  const id = e.id || "";
  const status = e.status || "";
  const opOnly = e.operator_only ? "1" : "0";
  const surfaces = Array.isArray(e.surfaces) ? e.surfaces : [];
  const supersedes = Array.isArray(e.supersedes) ? e.supersedes : [];
  const instr = typeof e.instruction === "string" ? e.instruction : "";
  const lines = instr.length ? instr.split("\n").length : 0;
  console.log(["E", id, status, opOnly, surfaces.length, supersedes.length, lines, badOf(e)].join("|"));
  for (const s of surfaces) console.log(["S", id, s].join("|"));
  for (const u of supersedes) console.log(["U", id, u].join("|"));
  const el = (e.elaboration && typeof e.elaboration === "object") ? e.elaboration : null;
  if (el) {
    const reqs = Array.isArray(el.requirements) ? el.requirements : [];
    const antip = Array.isArray(el.anti_patterns) ? el.anti_patterns : [];
    const len = (s) => (typeof s === "string" ? s.length : 0);
    console.log(["M", id, reqs.length, antip.length, len(el.intent), len(el.applies_when), len(el.worked_example), len(el.elaborated_by), len(el.elaborated_at), len(el.reviewed_by)].join("|"));
  }
}
' "$path" 2>/dev/null
    return $?
  elif dr__have_jq; then
    jq -e . "$path" >/dev/null 2>&1 || return 3
    jq -r '
def badfield($e):
  [ ( [["id", ($e.id // "")], ["title", ($e.title // "")], ["status", ($e.status // "")]][]
      | (if (.[1] | tostring | test("[\r\n]")) then "\(.[0]):crlf"
         elif (.[1] | tostring | test("\\|")) then "\(.[0]):pipe"
         else empty end) ),
    (if (($e.source // "") | tostring | test("[\r\n]")) then "source:crlf" else empty end),
    ( ($e.surfaces // [])[] | tostring
      | (if test("[\r\n]") then "surfaces:crlf" elif test("\\|") then "surfaces:pipe" else empty end) ),
    ( ($e.supersedes // [])[] | tostring
      | (if test("[\r\n]") then "supersedes:crlf" elif test("\\|") then "supersedes:pipe" else empty end) ),
    (if (($e.instruction // "") | tostring | test("\r")) then "instruction:cr" else empty end),
    ( ($e.elaboration // {}) as $el |
      ( ( ["intent","applies_when","worked_example","elaborated_by","elaborated_at","reviewed_by"][] ) as $f
        | (if (($el[$f] // "") | tostring | test("[\r\n]")) then "elaboration.\($f):crlf" else empty end) ),
      ( ($el.requirements // [])[] | tostring
        | (if test("[\r\n]") then "elaboration.requirements:crlf" else empty end) ),
      ( ($el.anti_patterns // [])[] | tostring
        | (if test("[\r\n]") then "elaboration.anti_patterns:crlf" else empty end) )
    )
  ] | .[0] // "";
(.entries // [])[] as $e |
([ "E", ($e.id // ""), ($e.status // ""),
   ((($e.operator_only // false) | if . then "1" else "0" end)),
   (($e.surfaces // []) | length | tostring),
   (($e.supersedes // []) | length | tostring),
   ((($e.instruction // "") | split("\n") | length) | tostring),
   badfield($e)
 ] | join("|")),

((($e.surfaces // [])[]) | "S|\($e.id)|\(.)"),
((($e.supersedes // [])[]) | "U|\($e.id)|\(.)"),
(if ($e.elaboration != null) then
   ([ "M", $e.id,
      (($e.elaboration.requirements // []) | length | tostring),
      (($e.elaboration.anti_patterns // []) | length | tostring),
      (($e.elaboration.intent // "") | length | tostring),
      (($e.elaboration.applies_when // "") | length | tostring),
      (($e.elaboration.worked_example // "") | length | tostring),
      (($e.elaboration.elaborated_by // "") | length | tostring),
      (($e.elaboration.elaborated_at // "") | length | tostring),
      (($e.elaboration.reviewed_by // "") | length | tostring)
    ] | join("|"))
 else empty end)
' "$path" 2>/dev/null | tr -d '\r'
    # tr strips the CRs Windows jq builds append to every -r output line
    # (they would make badfield read as "\r" and break numeric-field
    # arithmetic); values themselves cannot legitimately contain CR — the
    # badfield guard rejects them. PIPESTATUS keeps jq's own exit code.
    return "${PIPESTATUS[0]}"
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
  while IFS='|' read -r tag id status oponly nsurf nsup ilines badfield; do
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
    # ---- delimiter-injection guard (harness-review REJECT 2026-08-07):
    # badfield is dr__stream's "<field>:crlf|cr|pipe" flag. A value with an
    # embedded newline can terminate a stream record and forge new ones
    # downstream; a '|' in a positionally-parsed field shifts every field
    # after it. Reject at validation so the dirty state never travels.
    if [[ -n "${badfield:-}" ]]; then
      local bf_field="${badfield%%:*}" bf_kind="${badfield##*:}" bf_why
      case "$bf_kind" in
        crlf) bf_why="an embedded CR/LF" ;;
        cr)   bf_why="an embedded CR" ;;
        pipe) bf_why="an embedded '|'" ;;
        *)    bf_why="a disallowed character (${bf_kind})" ;;
      esac
      echo "[directives-register] ERROR: entry ${id} field ${bf_field} contains ${bf_why} — values are single-line; '|' is banned in id/title/status/surfaces/supersedes (delimiter-injection guard)" >&2
      errors=$((errors + 1))
    fi
  done <<< "$stream"

  # ---- elaboration shape checks (Task: directives-elaboration-layer) ----
  # An M line exists ONLY for an entry that carries an elaboration object at
  # all (dr__stream's absence-not-zeros contract above) — an entry with no
  # elaboration field is skipped entirely here, never flagged, since the
  # field is OPTIONAL. Shape only: presence/nonempty + requirements count
  # 3-7 + anti_patterns count >=1. Semantic correctness is a human-review
  # concern (reviewed_by), not this lib's job.
  while IFS='|' read -r tag id nreq nanti ilen alen wlen blen tlen rlen; do
    [[ "$tag" == "M" ]] || continue
    if [[ "$nreq" -lt 3 || "$nreq" -gt 7 ]]; then
      echo "[directives-register] ERROR: entry ${id} elaboration.requirements has ${nreq} items (must be 3-7)" >&2
      errors=$((errors + 1))
    fi
    if [[ "$nanti" -lt 1 ]]; then
      echo "[directives-register] ERROR: entry ${id} elaboration.anti_patterns is empty (must be >=1)" >&2
      errors=$((errors + 1))
    fi
    [[ "$ilen" -eq 0 ]] && { echo "[directives-register] ERROR: entry ${id} elaboration.intent is empty" >&2; errors=$((errors + 1)); }
    [[ "$alen" -eq 0 ]] && { echo "[directives-register] ERROR: entry ${id} elaboration.applies_when is empty" >&2; errors=$((errors + 1)); }
    [[ "$wlen" -eq 0 ]] && { echo "[directives-register] ERROR: entry ${id} elaboration.worked_example is empty" >&2; errors=$((errors + 1)); }
    [[ "$blen" -eq 0 ]] && { echo "[directives-register] ERROR: entry ${id} elaboration.elaborated_by is empty" >&2; errors=$((errors + 1)); }
    [[ "$tlen" -eq 0 ]] && { echo "[directives-register] ERROR: entry ${id} elaboration.elaborated_at is empty" >&2; errors=$((errors + 1)); }
    [[ "$rlen" -eq 0 ]] && { echo "[directives-register] ERROR: entry ${id} elaboration.reviewed_by is empty" >&2; errors=$((errors + 1)); }
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
        jq -r --arg id "$id" '(.entries[] | select(.id==$id) | .instruction) // ""' "$path" 2>/dev/null | tr -d '\r'
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
# dr_has_elaboration <register.json> <id>
# dr_get_elaboration_field <register.json> <id> <field>
# (Task: directives-elaboration-layer, operator proposal 2026-08-04)
#
# Node/jq backed, same convention as dr_get_field above — NOT the doctrine-
# jit hot path (that's dr_register_walk_bash's fused pure-bash reader
# further down, which reads intent/requirements/anti_patterns directly off
# the same JSON text with zero subprocess calls). This pair is for channel-2
# (dispatch-directives.sh, run once per orchestrator dispatch decision, not
# once per Edit) and any other non-hot-path caller.
# ============================================================
dr_has_elaboration() {
  local path="$1" id="$2" v
  v="$(dr_get_elaboration_field "$path" "$id" intent 2>/dev/null)"
  [[ -n "$v" ]]
}

dr_get_elaboration_field() {
  local path="$1" id="$2" field="$3"
  case "$field" in
    intent|applies_when|worked_example|elaborated_by|elaborated_at|reviewed_by)
      if dr__have_node; then
        node -e '
const fs = require("fs");
let m;
try { m = JSON.parse(fs.readFileSync(process.argv[1], "utf8")); } catch (e) { process.exit(0); }
const e = (m.entries || []).find(x => x.id === process.argv[2]);
const el = e && e.elaboration && typeof e.elaboration === "object" ? e.elaboration : null;
const f = process.argv[3];
process.stdout.write(el && typeof el[f] === "string" ? el[f] : "");
' "$path" "$id" "$field" 2>/dev/null
      elif dr__have_jq; then
        jq -r --arg id "$id" --arg f "$field" '(.entries[] | select(.id==$id) | .elaboration[$f]) // ""' "$path" 2>/dev/null | tr -d '\r'
      fi
      ;;
    requirements|anti_patterns)
      if dr__have_node; then
        node -e '
const fs = require("fs");
let m;
try { m = JSON.parse(fs.readFileSync(process.argv[1], "utf8")); } catch (e) { process.exit(0); }
const e = (m.entries || []).find(x => x.id === process.argv[2]);
const el = e && e.elaboration && typeof e.elaboration === "object" ? e.elaboration : null;
const f = process.argv[3];
const arr = el && Array.isArray(el[f]) ? el[f] : [];
for (const v of arr) console.log(v);
' "$path" "$id" "$field" 2>/dev/null
      elif dr__have_jq; then
        jq -r --arg id "$id" --arg f "$field" '(.entries[] | select(.id==$id) | .elaboration[$f] // [])[]' "$path" 2>/dev/null | tr -d '\r'
      fi
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
  while IFS='|' read -r tag id status oponly nsurf nsup ilines badfield; do
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

  local id="" status="" instr="" any_hit=0 line v
  # array_target: 0=not-collecting, 1=surfaces, 2=elaboration.requirements,
  # 3=elaboration.anti_patterns (Task: directives-elaboration-layer —
  # carries elaboration.{intent,requirements,anti_patterns} in compact form
  # alongside the verbatim instruction when a directive matches, per the
  # operator's elaboration-layer proposal 2026-08-04). REPLACES the earlier
  # two-variable (in_surfaces + elab_mode) draft of this addition: measured
  # ~12-29ms slower end-to-end (T-elab-timing evidence, this task's build)
  # than this single-variable, single-gate version, because the earlier
  # draft added a SECOND top-of-loop `if` gate (elab_mode==1, "in the
  # elaboration object but not inside one of its arrays") evaluated on
  # EVERY line of the ENTIRE file regardless of whether that line has
  # anything to do with elaboration — the file's own established finding
  # (module header, "each line iterated 300+ times") is that per-line
  # overhead on this hot path is NOT proportional to the feature's own
  # content size, it is paid by every line in the file. This version has
  # exactly ONE array-collecting gate (unifying surfaces + both elaboration
  # arrays behind array_target) and folds elaboration's scalar fields
  # (intent/requirements-open/anti_patterns-open) into the SAME top-level
  # `case` already used for id/status/surfaces/instruction — safe because
  # "intent"/"requirements"/"anti_patterns" key text never appears outside
  # an elaboration object in the real register or its fixtures (a
  # documented authoring convention, not enforced by this parser), and
  # elab_intent/elab_reqs/elab_antip are reset on every entry ("id":) line
  # boundary below, the same boundary instr/status/any_hit already reset
  # on — elaboration is always nested inside exactly one entry.
  local elab_intent="" elab_reqs=() elab_antip=()

  # _dr__rw_decode <raw> — the SAME 5-pass escape decode as the original
  # inlined instruction-decode this replaces, factored to one place since
  # elaboration now needs it at up to 1+N+M call sites (intent + each
  # requirement/anti_pattern item) instead of the historical single
  # instruction call site. SETS THE GLOBAL _DR_RW_DECODED rather than
  # echoing/printing — a plain function call is fork-free in bash, but
  # ANY `$( )` around it (even wrapping a bash function, not just an
  # external binary) is always a fork; capturing via a global preserves the
  # exact zero-subprocess-per-line contract this hot path is measured
  # against (module header "WHY THIS SECOND CODE PATH EXISTS" /
  # DR_REGISTER_WALK_OUT's own docstring make the identical argument for
  # why THAT is a global instead of a return value).
  _dr__rw_decode() {
    local s="$1" ph=$'\x01'
    s="${s//\\\\/$ph}"
    s="${s//\\n/$'\n'}"
    s="${s//\\\"/\"}"
    s="${s//\\t/$'\t'}"
    s="${s//$ph/\\}"
    _DR_RW_DECODED="$s"
  }

  _dr__rw_flush() {
    [[ -z "$id" ]] && return 0
    if [[ "$status" == "BINDING" && "$any_hit" -eq 1 ]]; then
      _dr__rw_decode "$instr"
      DR_REGISTER_WALK_OUT="${DR_REGISTER_WALK_OUT}===${id}===
${_DR_RW_DECODED}
"
      if [[ -n "$elab_intent" ]]; then
        _dr__rw_decode "$elab_intent"
        local elab_block="[ELABORATION -- interpretation, not verbatim; on conflict the Rule above wins]
Intent: ${_DR_RW_DECODED}"
        if [[ ${#elab_reqs[@]} -gt 0 ]]; then
          elab_block="${elab_block}
Requirements:"
          local ri
          for ri in "${elab_reqs[@]}"; do
            _dr__rw_decode "$ri"
            elab_block="${elab_block}
  - ${_DR_RW_DECODED}"
          done
        fi
        if [[ ${#elab_antip[@]} -gt 0 ]]; then
          elab_block="${elab_block}
Anti-patterns:"
          local ai
          for ai in "${elab_antip[@]}"; do
            _dr__rw_decode "$ai"
            elab_block="${elab_block}
  - ${_DR_RW_DECODED}"
          done
        fi
        DR_REGISTER_WALK_OUT="${DR_REGISTER_WALK_OUT}
${elab_block}
"
      fi
      DR_REGISTER_WALK_OUT="${DR_REGISTER_WALK_OUT}
"
    fi
    return 0
  }

  local array_target=0

  for line in "${_lines[@]}"; do
    line="${line%$'\r'}"

    if [[ "$array_target" -ne 0 ]]; then
      case "$line" in
        *']'*)
          array_target=0
          ;;
        *'"'*)
          case "$array_target" in
            1)
              if [[ "$any_hit" -eq 0 ]]; then
                v="${line#*\"}"
                v="${v%\"*}"
                dr_surface_matches "$file" "$v" && any_hit=1
              fi
              ;;
            2)
              v="${line#*\"}"
              v="${v%\"*}"
              elab_reqs+=("$v")
              ;;
            3)
              v="${line#*\"}"
              v="${v%\"*}"
              elab_antip+=("$v")
              ;;
          esac
          ;;
      esac
      continue
    fi

    case "$line" in
      *'"id":'*'"OD-'*)
        _dr__rw_flush
        v="${line#*\"id\": \"}"
        v="${v%\"*}"
        id="$v"; status=""; instr=""; any_hit=0; array_target=0
        elab_intent=""; elab_reqs=(); elab_antip=()
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
        array_target=1
        ;;
      *'"instruction":'*'"'*)
        v="${line#*\"instruction\": \"}"
        v="${v%\"*}"
        instr="$v"
        ;;
      *'"intent":'*'"'*)
        v="${line#*\"intent\": \"}"
        v="${v%\"*}"
        elab_intent="$v"
        ;;
      *'"requirements": [],'*)
        : # empty requirements array — nothing to collect
        ;;
      *'"requirements": ['*)
        array_target=2
        ;;
      *'"anti_patterns": [],'*)
        :
        ;;
      *'"anti_patterns": ['*)
        array_target=3
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

  # ---- delimiter-injection guard (harness-review REJECT 2026-08-07):
  # a register value violating the single-line convention must FAIL
  # validation with the offending field named. ----
  VTMP="$(mktemp -d 2>/dev/null || mktemp -d -t drlibvalst)"
  trap 'rm -rf "${VTMP:-}"' EXIT
  cat > "$VTMP/bad-intent.json" <<'EOF'
{"schema_version":1,"entries":[{"id":"OD-950","title":"clean","status":"BINDING","surfaces":["docs/**"],"supersedes":[],"instruction":"Rule: x.","elaboration":{"intent":"line1\nFORGED","requirements":["r1","r2","r3"],"anti_patterns":["a1"],"applies_when":"w","worked_example":"e","elaborated_by":"b","elaborated_at":"d","reviewed_by":"pending-operator"}}]}
EOF
  ERR_BI="$(dr_validate "$VTMP/bad-intent.json" 2>&1 >/dev/null)"
  RC_BI=$?
  _st_rc "validate-rejects-newline-in-elaboration-intent" "1" "$RC_BI"
  _st "validate-names-the-offending-field" "1" "$(printf '%s' "$ERR_BI" | grep -q 'elaboration.intent' && echo 1 || echo 0)"

  cat > "$VTMP/bad-title.json" <<'EOF'
{"schema_version":1,"entries":[{"id":"OD-951","title":"evil|title","status":"BINDING","surfaces":["docs/**"],"supersedes":[],"instruction":"Rule: x."}]}
EOF
  dr_validate "$VTMP/bad-title.json" >/dev/null 2>&1
  _st_rc "validate-rejects-pipe-in-title" "1" "$?"

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

  # ---- Task: directives-elaboration-layer (operator proposal 2026-08-04)
  # ---- elaboration carriage on the SAME OD-901 walk from above: the
  # compact intent/requirements/anti_patterns block must be present,
  # correctly decoded, and appear AFTER the verbatim instruction (never
  # replacing it — WALK_OUT above already proved the verbatim text is
  # still there unchanged).
  if printf '%s' "$WALK_OUT" | grep -q '\[ELABORATION' \
     && printf '%s' "$WALK_OUT" | grep -q 'Intent: Fixture intent paragraph' \
     && printf '%s' "$WALK_OUT" | grep -q '  - Fixture requirement one\.' \
     && printf '%s' "$WALK_OUT" | grep -q '  - Fixture anti-pattern one\.'; then
    echo "self-test (register-walk-bash-elaboration-block-present): PASS" >&2
    PASSED=$((PASSED + 1))
  else
    echo "self-test (register-walk-bash-elaboration-block-present): FAIL (got: $WALK_OUT)" >&2
    FAILED=$((FAILED + 1))
  fi

  # MUTATION CHECK counterpart: OD-902 (surface docs/designs/**, NO
  # elaboration field) must produce its instruction with NO [ELABORATION
  # block — proves the optional-field contract holds in the absent
  # direction too, not just "elaboration renders when present."
  dr_register_walk_bash "$FIXREG" "docs/designs/some-design.md"
  WALK_OUT_902="$DR_REGISTER_WALK_OUT"
  if printf '%s' "$WALK_OUT_902" | grep -q '^===OD-902===$' \
     && ! printf '%s' "$WALK_OUT_902" | grep -q '\[ELABORATION'; then
    echo "self-test (register-walk-bash-no-elaboration-for-plain-entry): PASS" >&2
    PASSED=$((PASSED + 1))
  else
    echo "self-test (register-walk-bash-no-elaboration-for-plain-entry): FAIL (got: $WALK_OUT_902)" >&2
    FAILED=$((FAILED + 1))
  fi

  # ---- dr_has_elaboration / dr_get_elaboration_field (node/jq path) ----
  dr_has_elaboration "$FIXREG" "OD-901"
  _st_rc "has-elaboration-true-OD-901" "0" "$?"
  dr_has_elaboration "$FIXREG" "OD-902"
  _st_rc "has-elaboration-false-OD-902" "1" "$?"
  _st "get-elaboration-intent-OD-901" \
    "Fixture intent paragraph for the elaboration-carriage round-trip self-test." \
    "$(dr_get_elaboration_field "$FIXREG" "OD-901" intent)"
  _st "get-elaboration-reviewed-by-OD-901" "pending-operator" \
    "$(dr_get_elaboration_field "$FIXREG" "OD-901" reviewed_by)"
  REQ_COUNT="$(dr_get_elaboration_field "$FIXREG" "OD-901" requirements | wc -l | tr -d '[:space:]')"
  _st "get-elaboration-requirements-count-OD-901" "3" "$REQ_COUNT"
  _st "get-elaboration-field-empty-for-no-elab-entry" "" \
    "$(dr_get_elaboration_field "$FIXREG" "OD-902" intent)"

  # decode correctness: escaped backslash + newline + quote round-trip
  DECODED="$(_dr__decode_escapes 'line1\nHKLM\\\\SOFTWARE\\\\Claude\nquote:\"x\"')"
  EXPECTED_DECODED="$(printf 'line1\nHKLM\\\\SOFTWARE\\\\Claude\nquote:"x"')"
  _st "decode-escapes-backslash-newline-quote" "$EXPECTED_DECODED" "$DECODED"

  # ---- real committed register: Task 20's own three wire-checked files
  # must resolve to exactly the set the T20 fidelity-carriage computation
  # expects (OD-002/007/008/013/018), PLUS OD-021 (added to the register
  # after that computation was made), PLUS OD-024 (added later still,
  # surfaces include adapters/claude-code/doctrine/orchestrator-pattern.md
  # — one of these three test files) — a live demonstration that this
  # matcher tracks the CURRENT register, not a stale snapshot; see the T20
  # evidence entry for the carriage-WARN this produces against the plan's
  # own now-stale Directives: line, and this task's own elaboration-layer
  # build for the OD-024 addition. ----
  REALREG="$(dr_default_register_path 2>/dev/null || true)"
  if [[ -n "$REALREG" && -f "$REALREG" ]]; then
    REAL_RESULT="$(dr_entries_for_files_bash "$REALREG" \
      "adapters/claude-code/scripts/dispatch-directives.sh" \
      "adapters/claude-code/hooks/doctrine-jit.sh" \
      "adapters/claude-code/doctrine/orchestrator-pattern.md" | paste -sd, -)"
    _st "real-register-t20-files-match-set" "OD-002,OD-007,OD-008,OD-013,OD-018,OD-021,OD-024" "$REAL_RESULT"
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

  # ---- Task: directives-elaboration-layer — elaboration shape checks ----
  # S1: well-formed elaboration on an otherwise-valid entry is ACCEPTED
  # (schema accepts entries WITH elaboration).
  cat > "$TMPD/elab-good.json" <<'EOF'
{"entries":[{"id":"OD-001","status":"BINDING","surfaces":[],"supersedes":[],"instruction":"a",
"elaboration":{"intent":"i","requirements":["r1","r2","r3"],"anti_patterns":["a1"],
"applies_when":"w","worked_example":"e","elaborated_by":"b","elaborated_at":"2026-08-04","reviewed_by":"pending-operator"}}]}
EOF
  dr_validate "$TMPD/elab-good.json" >/dev/null 2>&1
  _st_rc "validate-elaboration-well-formed-passes" "0" "$?"

  # S2: an entry with NO elaboration field at all is still ACCEPTED (schema
  # accepts entries WITHOUT elaboration — the optional-field contract).
  cat > "$TMPD/elab-absent.json" <<'EOF'
{"entries":[{"id":"OD-001","status":"BINDING","surfaces":[],"supersedes":[],"instruction":"a"}]}
EOF
  dr_validate "$TMPD/elab-absent.json" >/dev/null 2>&1
  _st_rc "validate-elaboration-absent-passes" "0" "$?"

  # S3: MUTATION CHECK — requirements below the 3-item floor is REJECTED
  # (proves the count-bound check actually fires, not just present-by-name).
  cat > "$TMPD/elab-toofewreq.json" <<'EOF'
{"entries":[{"id":"OD-001","status":"BINDING","surfaces":[],"supersedes":[],"instruction":"a",
"elaboration":{"intent":"i","requirements":["r1","r2"],"anti_patterns":["a1"],
"applies_when":"w","worked_example":"e","elaborated_by":"b","elaborated_at":"2026-08-04","reviewed_by":"pending-operator"}}]}
EOF
  dr_validate "$TMPD/elab-toofewreq.json" >/dev/null 2>&1
  _st_rc "validate-elaboration-too-few-requirements-fails" "1" "$?"

  # S4: requirements above the 7-item ceiling is REJECTED.
  cat > "$TMPD/elab-toomanyreq.json" <<'EOF'
{"entries":[{"id":"OD-001","status":"BINDING","surfaces":[],"supersedes":[],"instruction":"a",
"elaboration":{"intent":"i","requirements":["r1","r2","r3","r4","r5","r6","r7","r8"],"anti_patterns":["a1"],
"applies_when":"w","worked_example":"e","elaborated_by":"b","elaborated_at":"2026-08-04","reviewed_by":"pending-operator"}}]}
EOF
  dr_validate "$TMPD/elab-toomanyreq.json" >/dev/null 2>&1
  _st_rc "validate-elaboration-too-many-requirements-fails" "1" "$?"

  # S5: empty anti_patterns array is REJECTED (must be >=1).
  cat > "$TMPD/elab-noantip.json" <<'EOF'
{"entries":[{"id":"OD-001","status":"BINDING","surfaces":[],"supersedes":[],"instruction":"a",
"elaboration":{"intent":"i","requirements":["r1","r2","r3"],"anti_patterns":[],
"applies_when":"w","worked_example":"e","elaborated_by":"b","elaborated_at":"2026-08-04","reviewed_by":"pending-operator"}}]}
EOF
  dr_validate "$TMPD/elab-noantip.json" >/dev/null 2>&1
  _st_rc "validate-elaboration-empty-anti-patterns-fails" "1" "$?"

  # S6: empty intent is REJECTED.
  cat > "$TMPD/elab-nointent.json" <<'EOF'
{"entries":[{"id":"OD-001","status":"BINDING","surfaces":[],"supersedes":[],"instruction":"a",
"elaboration":{"intent":"","requirements":["r1","r2","r3"],"anti_patterns":["a1"],
"applies_when":"w","worked_example":"e","elaborated_by":"b","elaborated_at":"2026-08-04","reviewed_by":"pending-operator"}}]}
EOF
  dr_validate "$TMPD/elab-nointent.json" >/dev/null 2>&1
  _st_rc "validate-elaboration-empty-intent-fails" "1" "$?"

  # S7: empty reviewed_by is REJECTED (the review-hook field this task's
  # item 4 requires must actually be populated, never silently blank).
  cat > "$TMPD/elab-noreviewed.json" <<'EOF'
{"entries":[{"id":"OD-001","status":"BINDING","surfaces":[],"supersedes":[],"instruction":"a",
"elaboration":{"intent":"i","requirements":["r1","r2","r3"],"anti_patterns":["a1"],
"applies_when":"w","worked_example":"e","elaborated_by":"b","elaborated_at":"2026-08-04","reviewed_by":""}}]}
EOF
  dr_validate "$TMPD/elab-noreviewed.json" >/dev/null 2>&1
  _st_rc "validate-elaboration-empty-reviewed-by-fails" "1" "$?"

  echo "" >&2
  echo "self-test summary: ${PASSED} passed, ${FAILED} failed (of $((PASSED + FAILED)) scenarios)" >&2
  if [[ "$FAILED" -eq 0 ]]; then
    exit 0
  else
    exit 1
  fi
fi
