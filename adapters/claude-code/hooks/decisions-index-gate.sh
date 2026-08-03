#!/bin/bash
# NEURAL-LACE-DECISIONS-INDEX-GATE v1 — enforces decision-record ↔ DECISIONS.md atomicity
#
# Classification: Mechanism (hook-enforced pre-commit blocker)
#
# Enforces the rule from `~/.claude/doctrine/planning.md` ("Decision Records"
# section): every Tier 2+ decision gets a standalone `docs/decisions/NNN-*.md`
# file AND an index row in `docs/DECISIONS.md`, both committed together. This
# gate blocks commits that stage a new decision record without also updating
# the index.
#
# BEHAVIOR
#   (a) A file matching `docs/decisions/[0-9]{3}-.*\.md$` is staged AND
#       `docs/DECISIONS.md` is NOT staged       → BLOCK (exit 1)
#   (b) `docs/DECISIONS.md` is staged AND no NNN-*.md is staged → ALLOW
#       but print a stderr advisory (you may be editing existing rows, which
#       is fine — but if you're adding a new entry, the record file should
#       be staged too)
#   (c) Both staged                              → ALLOW silently
#   (d) Neither staged                           → ALLOW silently (no-op)
#
# Deletions of decision records are always allowed: if a record file is
# staged as a pure delete (git status `D`), it does not trigger (a).
#
# INVOCATION
#   1. Pre-commit chain:   decisions-index-gate.sh
#                          (no args — reads `git diff --cached --name-only -z`)
#   2. Self-test:          decisions-index-gate.sh --self-test
#                          (runs internal assertions, prints OK/FAIL, exits)
#
# EXIT CODES
#   0 — allowed
#   1 — blocked (decision record staged without index update)
#
# Not wired into the repo's pre-commit hook automatically. Follow-up task:
# extend `install-repo-hooks.sh` to chain this gate alongside the hygiene
# scanner, or have both run through a single wrapper.

set -u

# ---------- ADR forward-guard (WARN-only; arch-L1 / REQ-B1) --------------
#
# DEC-3 (docs/designs/gated-pipeline-master-2026-08-03.md §3) consolidates
# directive truth to 4 named stores: the operator-directives register
# (adapters/claude-code/config/operator-directives.json) is the sole
# citation target for standing BINDING rules; docs/decisions/ stays
# immutable ADRs. Without a forward guard, a future Tier-2+ decision could
# silently re-create an eighth directive store the moment it states a new
# standing rule without ever registering it -- the architecture review's
# finding (docs/reviews/2026-08-03-gated-pipeline-design-architecture-
# review.md): "any [ADR] that establishes standing rules silently
# re-create[s] a directive store beside the register." This check is
# WARN-only, never BLOCK (design §4: "WARN-lint on decisions/ files
# asserting standing rules without register_ref") -- this file's EXISTING
# atomicity rule (record<->index, below) is the only thing that blocks;
# this check never changes that rule's exit code.
#
# Heuristic: a record whose staged text contains binding-standing-rule
# language (case-insensitive BINDING/MUST/NEVER/ALWAYS, or the phrase
# "standing rule") must ALSO mention `register_ref` (pointing at the
# OD-NNN entry that now owns the rule) OR an explicit "no standing rule"
# opt-out phrase. Missing both -> WARN naming the fix. Reads the STAGED
# blob (`git show :<path>`), not the working-tree file, matching what is
# actually about to be committed.
adr_forward_guard_check() {
  local repo_root="$1" path="$2"
  local content
  content="$(git -C "$repo_root" show ":${path}" 2>/dev/null)"
  [ -z "$content" ] && return 0
  printf '%s' "$content" | grep -qiE '\b(BINDING|MUST|NEVER|ALWAYS)\b|standing rule' || return 0
  printf '%s' "$content" | grep -qi 'register_ref' && return 0
  printf '%s' "$content" | grep -qi 'no standing rule' && return 0
  echo "decisions-index-gate: WARN — ${path} asserts binding standing-rule language (BINDING/MUST/NEVER/ALWAYS/'standing rule') but has neither a 'register_ref' mention nor an explicit 'no standing rule' opt-out. If this decision states a standing rule that should be mechanically carried, register it in adapters/claude-code/config/operator-directives.json and add 'register_ref: OD-NNN' to this file; if it does not state a standing rule, add a line containing the words 'no standing rule' to silence this WARN. See docs/operator-directives.md (generated view)." >&2
  return 0
}

# ---------- self-test ----------------------------------------------------

if [ "${1:-}" = "--self-test" ]; then
  TMPDIR_ST=$(mktemp -d)
  trap 'rm -rf "$TMPDIR_ST"' EXIT

  SCRIPT_PATH="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"

  # Initialize a temp repo
  (
    cd "$TMPDIR_ST" || exit 1
    git init -q . >/dev/null 2>&1
    git config core.hooksPath ""  # don't fire machine-global harness git hooks in fixtures
    git config user.email "selftest@example.test"
    git config user.name "selftest"
    mkdir -p docs/decisions
    # Seed an initial commit so we have HEAD for diff-cached semantics
    echo "placeholder" > README.md
    git add README.md
    git commit -q -m "init" >/dev/null 2>&1
  ) || { echo "self-test: FAIL — repo init failed" >&2; exit 1; }

  run_case() {
    # args: case_label expected_rc setup_fn
    local label="$1"; local expected_rc="$2"; local setup_fn="$3"
    (
      cd "$TMPDIR_ST" || exit 99
      # Reset any staged state + remove tmp files from previous case
      git reset -q >/dev/null 2>&1
      rm -f docs/decisions/099-tmp.md docs/DECISIONS.md
      git checkout -q -- . 2>/dev/null || true
      $setup_fn
    )
    set +e
    local out
    out=$(cd "$TMPDIR_ST" && bash "$SCRIPT_PATH" 2>&1)
    local rc=$?
    set -e
    if [ "$rc" -ne "$expected_rc" ]; then
      echo "self-test: FAIL — case '$label' expected rc=$expected_rc, got rc=$rc" >&2
      echo "  output was:" >&2
      printf '    %s\n' "$out" >&2
      return 1
    fi
    echo "self-test: case '$label' OK (rc=$rc)"
    return 0
  }

  # args: case_label expected_rc setup_fn expect_warn(0|1)
  # Same shape as run_case, plus asserts the ADR-forward-guard WARN marker
  # is present (expect_warn=1) or absent (expect_warn=0) in combined output.
  # Never asserts on rc alone -- the WARN must never change the exit code.
  run_case_warn() {
    local label="$1"; local expected_rc="$2"; local setup_fn="$3"; local expect_warn="$4"
    (
      cd "$TMPDIR_ST" || exit 99
      git reset -q >/dev/null 2>&1
      rm -f docs/decisions/099-tmp.md docs/DECISIONS.md
      git checkout -q -- . 2>/dev/null || true
      $setup_fn
    )
    set +e
    local out
    out=$(cd "$TMPDIR_ST" && bash "$SCRIPT_PATH" 2>&1)
    local rc=$?
    set -e
    if [ "$rc" -ne "$expected_rc" ]; then
      echo "self-test: FAIL — case '$label' expected rc=$expected_rc, got rc=$rc" >&2
      printf '    %s\n' "$out" >&2
      return 1
    fi
    local has_warn=0
    if printf '%s' "$out" | grep -q 'asserts binding standing-rule language'; then
      has_warn=1
    fi
    if [ "$has_warn" -ne "$expect_warn" ]; then
      echo "self-test: FAIL — case '$label' expected WARN-present=$expect_warn, got $has_warn" >&2
      printf '    %s\n' "$out" >&2
      return 1
    fi
    echo "self-test: case '$label' OK (rc=$rc, warn=$has_warn)"
    return 0
  }

  setup_a_record_only() {
    # New decision record, no index — should BLOCK
    printf '# Decision 099\n\nBody.\n' > docs/decisions/099-tmp.md
    git add docs/decisions/099-tmp.md
  }

  setup_b_index_only() {
    # Index change, no record — should ALLOW (with advisory)
    printf '# Decisions Index\n\n| # | Title |\n|---|---|\n| 001 | Something |\n' > docs/DECISIONS.md
    git add docs/DECISIONS.md
  }

  setup_c_both() {
    # Both staged — should ALLOW silently
    printf '# Decision 099\n\nBody.\n' > docs/decisions/099-tmp.md
    printf '# Decisions Index\n\n| # | Title |\n|---|---|\n| 099 | Tmp |\n' > docs/DECISIONS.md
    git add docs/decisions/099-tmp.md docs/DECISIONS.md
  }

  setup_d_neither() {
    # Unrelated change — should ALLOW silently
    echo "another line" >> README.md
    git add README.md
  }

  setup_e_record_delete() {
    # First commit a record so we can delete it, then stage the delete only
    printf '# Decision 098\n\nBody.\n' > docs/decisions/098-tmp.md
    git add docs/decisions/098-tmp.md
    git commit -q -m "add 098" >/dev/null
    git rm -q docs/decisions/098-tmp.md
  }

  # ---- ADR forward-guard (arch-L1 / REQ-B1) scenarios --------------------
  # Each pairs record+index (the "both staged" shape) so rc stays 0 and the
  # WARN presence/absence is the only thing under test.

  setup_f_binding_no_ref() {
    # Binding standing-rule language, no register_ref, no opt-out -> WARN
    printf '# Decision 099\n\n**Status:** BINDING. This MUST always apply.\n' > docs/decisions/099-tmp.md
    printf '# Decisions Index\n\n| # | Title |\n|---|---|\n| 099 | Tmp |\n' > docs/DECISIONS.md
    git add docs/decisions/099-tmp.md docs/DECISIONS.md
  }

  setup_g_binding_with_ref() {
    # Same binding language, but carries register_ref -> no WARN
    printf '# Decision 099\n\n**Status:** BINDING. This MUST always apply.\nregister_ref: OD-001\n' > docs/decisions/099-tmp.md
    printf '# Decisions Index\n\n| # | Title |\n|---|---|\n| 099 | Tmp |\n' > docs/DECISIONS.md
    git add docs/decisions/099-tmp.md docs/DECISIONS.md
  }

  setup_h_binding_opt_out() {
    # Same binding language, explicit opt-out -> no WARN
    printf '# Decision 099\n\n**Status:** BINDING. This MUST always apply.\nThis decision states no standing rule for future work.\n' > docs/decisions/099-tmp.md
    printf '# Decisions Index\n\n| # | Title |\n|---|---|\n| 099 | Tmp |\n' > docs/DECISIONS.md
    git add docs/decisions/099-tmp.md docs/DECISIONS.md
  }

  setup_i_no_binding_language() {
    # Plain record, no binding language at all -> not applicable, no WARN
    printf '# Decision 099\n\nJust a routine reversible config change.\n' > docs/decisions/099-tmp.md
    printf '# Decisions Index\n\n| # | Title |\n|---|---|\n| 099 | Tmp |\n' > docs/DECISIONS.md
    git add docs/decisions/099-tmp.md docs/DECISIONS.md
  }

  FAIL=0
  run_case "a: record without index" 1 setup_a_record_only || FAIL=1
  run_case "b: index without record" 0 setup_b_index_only || FAIL=1
  run_case "c: both staged"          0 setup_c_both         || FAIL=1
  run_case "d: neither"              0 setup_d_neither      || FAIL=1
  run_case "e: record delete only"   0 setup_e_record_delete || FAIL=1
  run_case_warn "f: binding language, no register_ref -> WARN"      0 setup_f_binding_no_ref      1 || FAIL=1
  run_case_warn "g: binding language, register_ref present -> quiet" 0 setup_g_binding_with_ref     0 || FAIL=1
  run_case_warn "h: binding language, opt-out present -> quiet"      0 setup_h_binding_opt_out      0 || FAIL=1
  run_case_warn "i: no binding language -> quiet"                    0 setup_i_no_binding_language  0 || FAIL=1

  if [ "$FAIL" -eq 0 ]; then
    echo "self-test: OK"
    exit 0
  fi
  exit 1
fi

# ---------- repo discovery -----------------------------------------------

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
if [ -z "$REPO_ROOT" ]; then
  # Not in a git repo — silent no-op.
  exit 0
fi

# ---------- collect staged files -----------------------------------------
#
# We need both the file path AND the status (A/M/D/R) so we can ignore
# pure deletions of decision records. `diff --cached --name-status -z`
# emits records as <STATUS>\0<path>\0  (and for renames: R*\0<old>\0<new>\0).
# We pair status with the effective destination path.

STAGED_LIST_TMP=$(mktemp)
trap 'rm -f "$STAGED_LIST_TMP"' EXIT

( cd "$REPO_ROOT" && git diff --cached --name-status -z --diff-filter=ACMRD ) > "$STAGED_LIST_TMP" 2>/dev/null || true

# If no staged files at all, nothing to do.
if [ ! -s "$STAGED_LIST_TMP" ]; then
  exit 0
fi

HAS_RECORD_ADD_OR_MOD=0
RECORD_FILES=""          # newline-separated list of detected record paths (for error msg)
HAS_INDEX=0

# Parse null-delimited name-status output. Each logical record is:
#   <status>\0<path>\0           for A/C/M/D/T
#   R<score>\0<old>\0<new>\0     for R (rename)
# We read tokens one by one.

# Read ALL tokens into an array (indexed)
# shellcheck disable=SC2207
mapfile -d '' -t TOKENS < "$STAGED_LIST_TMP"

i=0
N=${#TOKENS[@]}
while [ "$i" -lt "$N" ]; do
  status="${TOKENS[$i]}"
  i=$((i + 1))
  [ "$i" -lt "$N" ] || break
  path="${TOKENS[$i]}"
  i=$((i + 1))

  # Renames consume an extra token (the new path); we treat the destination
  # as the effective path.
  case "$status" in
    R*)
      if [ "$i" -lt "$N" ]; then
        path="${TOKENS[$i]}"
        i=$((i + 1))
      fi
      # A rename acts as an add at the new location — count it as add/mod.
      status="A"
      ;;
  esac

  # Index file?
  if [ "$path" = "docs/DECISIONS.md" ]; then
    # Any status (A/M/D) on the index counts as "index staged"; a delete
    # is unusual but still is an index change worth acknowledging.
    HAS_INDEX=1
    continue
  fi

  # Decision record?  docs/decisions/NNN-*.md  (NNN = exactly 3 digits)
  case "$path" in
    docs/decisions/[0-9][0-9][0-9]-*.md)
      # Pure deletion of a record: allow (outdated records may be removed).
      if [ "$status" = "D" ]; then
        continue
      fi
      HAS_RECORD_ADD_OR_MOD=1
      RECORD_FILES="${RECORD_FILES}${path}"$'\n'
      ;;
  esac
done

# ADR forward-guard: run on every staged add/mod record, regardless of the
# atomicity outcome below (a WARN here never changes this gate's exit code).
if [ "$HAS_RECORD_ADD_OR_MOD" -eq 1 ]; then
  printf '%s' "$RECORD_FILES" | while IFS= read -r rf; do
    [ -z "$rf" ] && continue
    adr_forward_guard_check "$REPO_ROOT" "$rf"
  done
fi

# ---------- decision table -----------------------------------------------

# (a) record without index → BLOCK
if [ "$HAS_RECORD_ADD_OR_MOD" -eq 1 ] && [ "$HAS_INDEX" -eq 0 ]; then
  {
    echo ""
    echo "================================================================"
    echo "DECISIONS-INDEX GATE — BLOCKED"
    echo "================================================================"
    echo ""
    echo "Decision record(s) staged without a corresponding DECISIONS.md update:"
    echo ""
    printf '%s' "$RECORD_FILES" | sed 's/^/  - /'
    echo ""
    echo "Every new decision record must be accompanied by an index entry in"
    echo "docs/DECISIONS.md in the SAME commit. This is the rule from"
    echo "~/.claude/doctrine/planning.md 'Decision Records' section: decision"
    echo "records are permanent artifacts and must be discoverable via the"
    echo "index the moment they land."
    echo ""
    echo "To fix:"
    echo "  1. Open docs/DECISIONS.md (create it if it does not exist yet)"
    echo "  2. Add/update the row pointing at the new record"
    echo "  3. git add docs/DECISIONS.md"
    echo "  4. Re-run the commit"
    echo ""
    echo "If the record is being deleted (stale / superseded), stage the"
    echo "deletion via 'git rm'; pure deletions are allowed without touching"
    echo "the index."
    echo ""
    echo "To bypass (not recommended): git commit --no-verify"
    echo ""
    echo "This gate: ~/.claude/hooks/decisions-index-gate.sh (source: adapters/claude-code/hooks/decisions-index-gate.sh)"
    echo "================================================================"
  } >&2
  exit 1
fi

# (b) index without record → ALLOW + advisory
if [ "$HAS_INDEX" -eq 1 ] && [ "$HAS_RECORD_ADD_OR_MOD" -eq 0 ]; then
  echo "decisions-index-gate: note — docs/DECISIONS.md is staged without a corresponding docs/decisions/NNN-*.md file. That's fine if you're updating existing rows, but if you're adding a new entry, make sure the record file is also staged." >&2
  exit 0
fi

# (c) both, or (d) neither → ALLOW silently
exit 0
