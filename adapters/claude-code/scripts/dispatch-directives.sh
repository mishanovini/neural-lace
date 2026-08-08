#!/bin/bash
# dispatch-directives.sh — carriage channel 2 (gated-pipeline-master-2026-08
# Task 20; docs/plans/gated-pipeline-master-2026-08.md Task 20; design
# docs/designs/gated-pipeline-master-2026-08-03.md §4 "Directives register +
# carriage", REQ-B11/REQ-B12) + the NL-ATTRIBUTION header generator
# (operator directive 2026-08-03: "identifiers in standard processes must be
# generated, never hand-typed" — a hand-typed `task=T7`-style id broke
# cockpit attribution the same day; plan task ids are numeric, no `T`
# prefix, per doctrine/orchestrator-pattern.md and workstreams-emit.sh's
# actual parser).
#
# WHY THIS EXISTS
# ================
# Channel 1 (the plan's per-task `Directives:` field, Task 14) is a
# point-in-time snapshot computed when the field was written — the register
# can gain a BINDING entry, or a task's Files-to-Modify can change, after
# that snapshot, and nothing re-checks it. This script's own self-test
# demonstrates the exact class: this task's own plan line was computed
# against the register as it stood on 2026-08-03 (OD-002/007/008/013/018),
# but OD-021 (added the SAME day, later) also matches Task 20's files —
# the plan's own Directives: field is stale the moment a new BINDING entry
# lands (see the T20 evidence file for the live re-run). Channel 2 closes
# that: run this at DISPATCH time (the orchestrator pastes its output into
# the builder prompt) so the citation is always freshly computed against
# the CURRENT register, never a stale plan-authoring-time snapshot.
#
# It ALSO generates the NL-ATTRIBUTION header (operator directive,
# 2026-08-03): every dispatch prompt must open with
#   NL-ATTRIBUTION: plan=<slug> task=<id> role=<builder|verifier|reviewer|advocate>
# and per that directive this must be GENERATED, never hand-typed — a
# hand-typed id is exactly how a `task=T7`-shaped (non-numeric) id slipped
# past workstreams-emit.sh's parser and broke cockpit attribution. This
# script is now the single generator: it computes the slug from the plan
# path, VALIDATES the task id against the plan's own `- [ ]`/`- [x]` task
# list (hard error + the valid id set on a mismatch — never silently emit a
# header for a task that doesn't exist), and defaults role to `builder`
# with the doctrine's closed set as the only other options.
#
# USAGE
# =====
#   dispatch-directives.sh <plan> <task-number> [role]
#     <plan>          a path to a plan .md file, OR a bare slug resolved to
#                      docs/plans/<slug>.md
#     <task-number>   the task's numeric id as it appears in "- [ ] N." /
#                      "- [x] N." in the plan's ## Tasks section — VALIDATED
#                      against that list; a non-matching id is a hard error
#                      naming every valid id, never a best-effort guess.
#     [role]          builder (default) | verifier | reviewer | advocate —
#                      the doctrine/orchestrator-pattern.md closed set. Any
#                      other value is a hard error.
#   dispatch-directives.sh --self-test
#
# BEHAVIOR
# ========
#   1. Resolve <plan>, validate <task-number> exists in its ## Tasks list,
#      validate [role] against the closed set. On success, print the
#      ready-to-paste NL-ATTRIBUTION header as the FIRST line of stdout —
#      this is now the ONLY sanctioned way to produce that header (doctrine
#      updated in the same commit: "generate the header via dispatch-
#      directives.sh, never hand-type it").
#   2. Locate the task's own block in ## Tasks (from "- [ ] N." / "- [x] N."
#      up to the next numbered task line) — used ONLY to read its EXISTING
#      `Directives:` field for the carriage-WARN comparison (step 5); the
#      MATCH computation itself never reads task-block text.
#   3. Locate ## Files to Modify/Create; collect every backtick-quoted path
#      containing '/' on a line whose LAST parenthetical group contains the
#      task number as a whole token (handles "(T20)", "(T3, T15, T17, T20)",
#      "(T6 + each new mechanism)" — the plan's actual tagging idioms).
#   4. Call hooks/lib/directives-register-lib.sh's dr_entries_for_files (the
#      ONE parser/matcher — M-3) against that file list; for each matched
#      id print its instruction block, ready to paste into a dispatch
#      prompt.
#   5. CARRIAGE WARN v1 (REQ-B12): if the task's OWN existing Directives:
#      field (step 2) is missing any id computed in step 4, print a
#      non-blocking WARN (stderr) naming the gap. This is dispatch-
#      directives.sh's own contribution to the "G1/G2 WARN on tagged-surface
#      plan/dispatch lacking matched OD citations" posture — run at the
#      point the orchestrator actually pastes citations into a dispatch
#      (G2's real moment), without touching plan-reviewer.sh (G1, Task 14's
#      file) or wiring dispatch-chain-gate.sh live (G2's PreToolUse form is
#      Task 17's explicit remit — its own header warns against building
#      that early; see that file's "WHAT THIS FILE IS RIGHT NOW" comment).
#      A live PreToolUse WARN inside G2 itself remains Task 17's job.
#
# Exit codes: 0 on success; 2 on usage/validation error (bad task id, bad
# role, plan not found — the ATTRIBUTION-id-validation class this task adds
# is deliberately a HARD error, not a WARN, since a wrong id is exactly the
# defect class the operator directive names); 1 on --self-test failure.
#
# NOT the hot path: doctrine-jit.sh's PostToolUse register walk (channel 3)
# has its own <50ms pure-bash-only budget (F-5) and does NOT call this
# script or dr_entries_for_files — see hooks/lib/directives-register-
# lib.sh's dr_register_walk_bash / dr_entries_for_files_bash instead. This
# script runs once per orchestrator dispatch decision, not once per Edit,
# so the node/jq-backed dr_entries_for_files is the right tool here.

set -u
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"

ROLE_SET="builder verifier reviewer advocate"

resolve_root() {
  if [[ -n "${DISPATCH_DIRECTIVES_ROOT:-}" ]]; then
    printf '%s\n' "$DISPATCH_DIRECTIVES_ROOT"
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

resolve_plan_path() {
  local root="$1" arg="$2"
  if [[ "$arg" == *.md && ( "$arg" == /* || "$arg" == */* ) ]]; then
    if [[ "$arg" == /* ]]; then
      printf '%s\n' "$arg"
    else
      printf '%s/%s\n' "$root" "$arg"
    fi
    return 0
  fi
  printf '%s/docs/plans/%s.md\n' "$root" "$arg"
}

# plan_slug <plan-path> — basename minus .md, the NL-ATTRIBUTION plan= value.
plan_slug() {
  local base
  base="$(basename -- "$1")"
  printf '%s\n' "${base%.md}"
}

# valid_task_ids <plan> — every numeric id from "- [ ] N." / "- [x] N."
# lines in the plan's ## Tasks list, one per line, in file order.
valid_task_ids() {
  local plan="$1"
  awk '
    /^## Tasks/ { flag=1; next }
    flag && /^## / { exit }
    flag && match($0, /^- \[.\] ([0-9]+)\./, m) { print m[1] }
  ' "$plan" 2>/dev/null
}

# task_id_valid <plan> <task-num> — rc 0 iff <task-num> is one of
# valid_task_ids's output.
task_id_valid() {
  local plan="$1" n="$2" id
  while IFS= read -r id; do
    [[ "$id" == "$n" ]] && return 0
  done < <(valid_task_ids "$plan")
  return 1
}

# extract_task_block <plan> <task-num> -- prints every line from the
# "- [ ] N." / "- [x] N." line up to (excluding) the next numbered task
# line, from ## Tasks.
extract_task_block() {
  local plan="$1" n="$2"
  awk -v n="$n" '
    $0 ~ "^- \\[.\\] " n "\\." { flag=1; print; next }
    flag && $0 ~ "^- \\[.\\] [0-9]+\\." { exit }
    flag { print }
  ' "$plan"
}

# extract_declared_directives <task-block-text> -- prints one OD-NNN per
# line found inside the block's "Directives:" field (text between
# "Directives:" and the next em-dash "—" field separator or newline).
extract_declared_directives() {
  local text="$1"
  printf '%s' "$text" \
    | tr '\n' ' ' \
    | grep -oE 'Directives:[^—]*' \
    | head -1 \
    | grep -oE 'OD-[0-9]{3}' \
    | LC_ALL=C sort -u
}

# extract_tagged_files <plan> <task-num> -- prints every backtick-quoted
# path (containing '/') from a ## Files to Modify/Create line whose LAST
# parenthetical group contains the task number as a whole token.
extract_tagged_files() {
  local plan="$1" n="$2"
  awk '
    /^## Files to Modify\/Create/ { flag=1; next }
    flag && /^## / { exit }
    flag { print }
  ' "$plan" | while IFS= read -r line; do
    last_group=""
    rest="$line"
    while [[ "$rest" =~ \(([^()]*)\) ]]; do
      last_group="${BASH_REMATCH[1]}"
      rest="${rest#*"${BASH_REMATCH[0]}"}"
    done
    [[ -z "$last_group" ]] && continue
    if [[ "$last_group" =~ (^|[^0-9A-Za-z])T${n}($|[^0-9A-Za-z]) ]]; then
      while [[ "$line" =~ \`([^\`]*/[^\`]*)\` ]]; do
        printf '%s\n' "${BASH_REMATCH[1]}"
        line="${line#*"${BASH_REMATCH[0]}"}"
      done
    fi
  done
}

# role_valid <role> — rc 0 iff <role> is in the doctrine's closed set.
role_valid() {
  local role="$1" r
  for r in $ROLE_SET; do
    [[ "$role" == "$r" ]] && return 0
  done
  return 1
}

run() {
  local plan_arg="$1" task_num="$2" role="${3:-builder}"
  local root plan
  root="$(resolve_root)" || { echo "[dispatch-directives] ERROR: cannot resolve repo root" >&2; return 2; }
  plan="$(resolve_plan_path "$root" "$plan_arg")"
  [[ -f "$plan" ]] || { echo "[dispatch-directives] ERROR: plan not found at $plan" >&2; return 2; }
  [[ "$task_num" =~ ^[0-9]+$ ]] || { echo "[dispatch-directives] ERROR: task number must be numeric (no 'T' prefix — plan task ids are numeric per doctrine/orchestrator-pattern.md), got '$task_num'" >&2; return 2; }

  if ! role_valid "$role"; then
    echo "[dispatch-directives] ERROR: role '$role' is not in the doctrine's closed set ($ROLE_SET)" >&2
    return 2
  fi

  if ! task_id_valid "$plan" "$task_num"; then
    local valid_ids
    valid_ids="$(valid_task_ids "$plan" | paste -sd, - 2>/dev/null)"
    echo "[dispatch-directives] ERROR: task '$task_num' does not exist in ${plan}'s ## Tasks list. Valid task ids: ${valid_ids:-<none found>}" >&2
    return 2
  fi

  local slug
  slug="$(plan_slug "$plan")"

  # THE generated header — operator directive 2026-08-03: identifiers in
  # standard processes are generated here, never hand-typed into a dispatch
  # prompt. This is the FIRST line of stdout, always.
  echo "NL-ATTRIBUTION: plan=${slug} task=${task_num} role=${role}"
  echo ""

  local register="${DISPATCH_DIRECTIVES_REGISTER:-$root/adapters/claude-code/config/operator-directives.json}"
  local lib="$root/adapters/claude-code/hooks/lib/directives-register-lib.sh"
  [[ -f "$lib" ]] || { echo "[dispatch-directives] ERROR: lib not found at $lib" >&2; return 2; }
  # shellcheck source=../hooks/lib/directives-register-lib.sh
  source "$lib"

  # ---- register validation (wires dr_validate, previously caller-less —
  # the "validator-with-no-caller" finding in nl-issues
  # GEN-DIRECTIVES-VIEW-DELIMITER-INJECTION-CRITICAL): never compute
  # carriage from a register that fails its own validator. dr_validate
  # names each offense on stderr, including the delimiter-injection
  # badfield check (CR/LF in any value, '|' in positionally-parsed fields).
  if ! dr_validate "$register"; then
    echo "[dispatch-directives] ERROR: register failed dr_validate — refusing to compute carriage from an invalid register (${register})" >&2
    return 2
  fi

  local -a files=()
  while IFS= read -r f; do
    [[ -n "$f" ]] && files+=("$f")
  done < <(extract_tagged_files "$plan" "$task_num")

  if [[ ${#files[@]} -eq 0 ]]; then
    echo "[dispatch-directives] no Files-to-Modify entries tagged (T${task_num}) in $plan" >&2
    echo "Directives: none"
    return 0
  fi

  local matched
  matched="$(dr_entries_for_files "$register" "${files[@]}")"

  if [[ -z "$matched" ]]; then
    echo "Directives: none"
  else
    echo "Directives: $(printf '%s\n' "$matched" | paste -sd, -)"
    echo ""
    local id
    while IFS= read -r id; do
      [[ -z "$id" ]] && continue
      echo "### ${id}"
      dr_get_field "$register" "$id" instruction
      echo ""
      # ---- elaboration carriage (Task: directives-elaboration-layer,
      # operator proposal 2026-08-04) — intent + requirements + anti_
      # patterns in compact form, printed right after the verbatim
      # instruction so a dispatch prompt carries both. Node/jq backed
      # (dr_has_elaboration / dr_get_elaboration_field) — this script runs
      # once per orchestrator dispatch decision, not once per Edit, so it
      # is not the <50ms F-5 hot path (that budget applies only to
      # doctrine-jit.sh's PostToolUse register walk). Silent when the
      # entry has no elaboration — additive only, never required.
      if dr_has_elaboration "$register" "$id"; then
        echo "[ELABORATION -- interpretation, not verbatim; on conflict the Rule above wins; reviewed_by: $(dr_get_elaboration_field "$register" "$id" reviewed_by)]"
        echo "Intent: $(dr_get_elaboration_field "$register" "$id" intent)"
        local req_lines
        req_lines="$(dr_get_elaboration_field "$register" "$id" requirements)"
        if [[ -n "$req_lines" ]]; then
          echo "Requirements:"
          printf '%s\n' "$req_lines" | while IFS= read -r r; do
            [[ -n "$r" ]] && echo "  - $r"
          done
        fi
        local antip_lines
        antip_lines="$(dr_get_elaboration_field "$register" "$id" anti_patterns)"
        if [[ -n "$antip_lines" ]]; then
          echo "Anti-patterns:"
          printf '%s\n' "$antip_lines" | while IFS= read -r a; do
            [[ -n "$a" ]] && echo "  - $a"
          done
        fi
        echo ""
      fi
    done <<< "$matched"
  fi

  # ---- CARRIAGE WARN v1 (REQ-B12) ----
  if [[ -n "$matched" ]]; then
    local block declared missing=""
    block="$(extract_task_block "$plan" "$task_num")"
    declared="$(extract_declared_directives "$block")"
    local id
    while IFS= read -r id; do
      [[ -z "$id" ]] && continue
      if ! printf '%s\n' "$declared" | grep -qxF "$id"; then
        missing="${missing}${missing:+,}${id}"
      fi
    done <<< "$matched"
    if [[ -n "$missing" ]]; then
      echo "[dispatch-directives] CARRIAGE WARN (REQ-B12): task ${task_num}'s plan-declared Directives: field is missing ${missing} — the register has changed since the field was last computed (or it was never set); paste the block(s) above into the dispatch prompt and consider updating the plan's Directives: line." >&2
    fi
  fi

  return 0
}

# ============================================================
# --self-test
# ============================================================
run_self_test() {
  local PASSED=0 FAILED=0
  local SELF="$SCRIPT_DIR/$(basename -- "${BASH_SOURCE[0]}")"

  _st_rc() { # <label> <expected-rc> <actual-rc>
    if [[ "$2" == "$3" ]]; then
      echo "self-test ($1): PASS" >&2
      PASSED=$((PASSED + 1))
    else
      echo "self-test ($1): FAIL (expected rc $2, got $3)" >&2
      FAILED=$((FAILED + 1))
    fi
  }

  local TMPD
  TMPD="$(mktemp -d 2>/dev/null || mktemp -d -t dispdirst)"
  # ${TMPD:-} not "$TMPD": the EXIT trap is process-scoped, not function-
  # scoped — it still fires after run_self_test returns and TMPD (a local)
  # has gone out of scope, which under `set -u` would otherwise be an
  # "unbound variable" error at exit.
  trap 'rm -rf "${TMPD:-}"' EXIT

  mkdir -p "$TMPD/docs/plans" "$TMPD/adapters/claude-code/config" "$TMPD/adapters/claude-code/hooks/lib"
  cp "$SCRIPT_DIR/../hooks/lib/directives-register-lib.sh" "$TMPD/adapters/claude-code/hooks/lib/directives-register-lib.sh" 2>/dev/null

  # Reuse the T11 shared round-trip fixture register (per its own README:
  # "Task 20 consumes this lib — schema agreed HERE via the shared fixture
  # ... do not fork a second copy") — OD-901 matches
  # adapters/claude-code/hooks/*gate*.sh.
  local FIXREG="$SCRIPT_DIR/../tests/fixtures/directives-register/fixture-register.json"
  if [[ ! -f "$FIXREG" ]]; then
    echo "self-test: FAIL — shared fixture missing at $FIXREG" >&2
    exit 1
  fi
  cp "$FIXREG" "$TMPD/adapters/claude-code/config/operator-directives.json"

  cat > "$TMPD/docs/plans/fixture-plan.md" <<'EOF'
# Plan: fixture

## Tasks

- [ ] 1. Some earlier task — Verification: mechanical
- [ ] 99. Fixture task exercising the shared T11/T20 round-trip fixture — Verification: full — Implements: REQ-X1 — Directives: n/a
- [x] 100. Another task, already checked

## Files to Modify/Create

Modify:
- `adapters/claude-code/hooks/dispatch-chain-gate.sh` (T99)
- `adapters/claude-code/scripts/nl-maintenance.sh` (T99)
- `docs/unrelated-file.md` (T1)
EOF

  cat > "$TMPD/docs/plans/fixture-plan-cited.md" <<'EOF'
# Plan: fixture-cited

## Tasks

- [ ] 99. Fixture task WITH the correct citation already present — Verification: full — Directives: OD-901

## Files to Modify/Create

Modify:
- `adapters/claude-code/hooks/dispatch-chain-gate.sh` (T99)
EOF

  export DISPATCH_DIRECTIVES_ROOT="$TMPD"
  export DISPATCH_DIRECTIVES_REGISTER="$TMPD/adapters/claude-code/config/operator-directives.json"

  # ---- S1: NL-ATTRIBUTION header is the FIRST line, correct slug/task/role ----
  OUT="$(bash "$SELF" "$TMPD/docs/plans/fixture-plan.md" 99 2>/dev/null)"
  FIRST_LINE="$(printf '%s\n' "$OUT" | head -1)"
  if [[ "$FIRST_LINE" == "NL-ATTRIBUTION: plan=fixture-plan task=99 role=builder" ]]; then
    echo "self-test (s1-attribution-header-first-line-default-role): PASS" >&2
    PASSED=$((PASSED + 1))
  else
    echo "self-test (s1-attribution-header-first-line-default-role): FAIL (got: '$FIRST_LINE')" >&2
    FAILED=$((FAILED + 1))
  fi

  # ---- S2: explicit role honored ----
  OUT2="$(bash "$SELF" "$TMPD/docs/plans/fixture-plan.md" 99 reviewer 2>/dev/null)"
  FIRST_LINE2="$(printf '%s\n' "$OUT2" | head -1)"
  if [[ "$FIRST_LINE2" == "NL-ATTRIBUTION: plan=fixture-plan task=99 role=reviewer" ]]; then
    echo "self-test (s2-explicit-role-honored): PASS" >&2
    PASSED=$((PASSED + 1))
  else
    echo "self-test (s2-explicit-role-honored): FAIL (got: '$FIRST_LINE2')" >&2
    FAILED=$((FAILED + 1))
  fi

  # ---- S3: invalid task id -> hard error naming the valid id set, rc 2 ----
  ERR3="$(bash "$SELF" "$TMPD/docs/plans/fixture-plan.md" 42 2>&1 1>/dev/null)"
  bash "$SELF" "$TMPD/docs/plans/fixture-plan.md" 42 >/dev/null 2>&1
  RC3=$?
  _st_rc "s3-invalid-task-id-errors" "2" "$RC3"
  if printf '%s' "$ERR3" | grep -q '1,99,100'; then
    echo "self-test (s3b-error-lists-valid-ids): PASS" >&2
    PASSED=$((PASSED + 1))
  else
    echo "self-test (s3b-error-lists-valid-ids): FAIL (got: $ERR3)" >&2
    FAILED=$((FAILED + 1))
  fi

  # ---- S4: invalid role -> hard error, rc 2 ----
  bash "$SELF" "$TMPD/docs/plans/fixture-plan.md" 99 hacker >/dev/null 2>&1
  _st_rc "s4-invalid-role-errors" "2" "$?"

  # ---- S5: Directives computation matches the T11 shared fixture round-trip ----
  if printf '%s' "$OUT" | grep -q '^Directives: OD-901$'; then
    echo "self-test (s5-directives-computed-OD-901): PASS" >&2
    PASSED=$((PASSED + 1))
  else
    echo "self-test (s5-directives-computed-OD-901): FAIL (got: $OUT)" >&2
    FAILED=$((FAILED + 1))
  fi
  if printf '%s' "$OUT" | grep -q 'fixture binding entry whose surface matches'; then
    echo "self-test (s5b-instruction-block-printed): PASS" >&2
    PASSED=$((PASSED + 1))
  else
    echo "self-test (s5b-instruction-block-printed): FAIL" >&2
    FAILED=$((FAILED + 1))
  fi

  # ---- S6: carriage WARN fires when the task's own Directives: field is
  # missing the computed id (fixture-plan.md's task 99 has "Directives:
  # n/a") ----
  ERR6="$(bash "$SELF" "$TMPD/docs/plans/fixture-plan.md" 99 2>&1 1>/dev/null)"
  if printf '%s' "$ERR6" | grep -q 'CARRIAGE WARN' && printf '%s' "$ERR6" | grep -q 'OD-901'; then
    echo "self-test (s6-carriage-warn-fires-on-missing-citation): PASS" >&2
    PASSED=$((PASSED + 1))
  else
    echo "self-test (s6-carriage-warn-fires-on-missing-citation): FAIL (got: $ERR6)" >&2
    FAILED=$((FAILED + 1))
  fi

  # ---- S7: carriage WARN does NOT fire when the citation is already
  # correct (fixture-plan-cited.md's task 99 already has "Directives:
  # OD-901") ----
  ERR7="$(bash "$SELF" "$TMPD/docs/plans/fixture-plan-cited.md" 99 2>&1 1>/dev/null)"
  if ! printf '%s' "$ERR7" | grep -q 'CARRIAGE WARN'; then
    echo "self-test (s7-carriage-warn-silent-when-cited): PASS" >&2
    PASSED=$((PASSED + 1))
  else
    echo "self-test (s7-carriage-warn-silent-when-cited): FAIL (got: $ERR7)" >&2
    FAILED=$((FAILED + 1))
  fi

  # ---- S8: no Files-to-Modify entries tagged for a valid task -> "Directives: none", rc 0 ----
  OUT8="$(bash "$SELF" "$TMPD/docs/plans/fixture-plan.md" 1 2>/dev/null)"
  RC8=$?
  if [[ "$RC8" -eq 0 ]] && printf '%s' "$OUT8" | grep -q '^Directives: none$'; then
    echo "self-test (s8-no-tagged-files-directives-none): PASS" >&2
    PASSED=$((PASSED + 1))
  else
    echo "self-test (s8-no-tagged-files-directives-none): FAIL (rc=$RC8 got: $OUT8)" >&2
    FAILED=$((FAILED + 1))
  fi

  # ---- S9: elaboration carriage (Task: directives-elaboration-layer,
  # operator proposal 2026-08-04) — OD-901's fixture elaboration prints
  # right after its instruction block, using the SAME OUT ($OUT from S1,
  # which already ran task 99 against fixture-plan.md and matched OD-901). ----
  if printf '%s' "$OUT" | grep -q '\[ELABORATION' \
     && printf '%s' "$OUT" | grep -q 'Intent: Fixture intent paragraph' \
     && printf '%s' "$OUT" | grep -q '  - Fixture requirement one\.' \
     && printf '%s' "$OUT" | grep -q '  - Fixture anti-pattern one\.' \
     && printf '%s' "$OUT" | grep -q 'reviewed_by: pending-operator'; then
    echo "self-test (s9-elaboration-carriage-printed): PASS" >&2
    PASSED=$((PASSED + 1))
  else
    echo "self-test (s9-elaboration-carriage-printed): FAIL (got: $OUT)" >&2
    FAILED=$((FAILED + 1))
  fi

  # ---- S10: a register that fails dr_validate -> hard error rc 2, never
  # a computed carriage (wires the previously caller-less validator; the
  # fixture violates the single-line convention with a newline inside
  # elaboration.intent — the delimiter-injection guard's forgery vector) ----
  cat > "$TMPD/bad-register.json" <<'EOF'
{"schema_version":1,"entries":[{"id":"OD-950","title":"clean","status":"BINDING","surfaces":["adapters/claude-code/hooks/*gate*.sh"],"supersedes":[],"instruction":"Rule: x.","elaboration":{"intent":"line1\nFORGED","requirements":["r1","r2","r3"],"anti_patterns":["a1"],"applies_when":"w","worked_example":"e","elaborated_by":"b","elaborated_at":"d","reviewed_by":"pending-operator"}}]}
EOF
  ERR10="$(DISPATCH_DIRECTIVES_REGISTER="$TMPD/bad-register.json" bash "$SELF" "$TMPD/docs/plans/fixture-plan.md" 99 2>&1 1>/dev/null)"
  RC10=$?
  _st_rc "s10-invalid-register-hard-error" "2" "$RC10"
  if printf '%s' "$ERR10" | grep -q 'refusing to compute carriage' \
     && printf '%s' "$ERR10" | grep -q 'elaboration.intent'; then
    echo "self-test (s10b-error-names-validator-and-field): PASS" >&2
    PASSED=$((PASSED + 1))
  else
    echo "self-test (s10b-error-names-validator-and-field): FAIL (got: $ERR10)" >&2
    FAILED=$((FAILED + 1))
  fi

  echo "" >&2
  echo "self-test summary: ${PASSED} passed, ${FAILED} failed (of $((PASSED + FAILED)) scenarios)" >&2
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
  ""|-h|--help)
    cat >&2 <<'EOF'
usage: dispatch-directives.sh <plan> <task-number> [role]
       dispatch-directives.sh --self-test

<plan>        path to a plan .md file, or a bare slug (docs/plans/<slug>.md)
<task-number> numeric task id as it appears in the plan's ## Tasks list
              ("- [ ] N." / "- [x] N.") -- validated against that list
[role]        builder (default) | verifier | reviewer | advocate

Prints the generated NL-ATTRIBUTION header as the first line, then the
register-computed Directives: line and per-entry instruction blocks for
prompt inlining. Non-blocking CARRIAGE WARN (stderr) when the plan's own
Directives: field is missing an id the register currently computes.
EOF
    exit 2
    ;;
  *)
    run "$@"
    exit $?
    ;;
esac
