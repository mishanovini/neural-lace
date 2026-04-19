#!/bin/bash
# NEURAL-LACE-DECISIONS-INDEX-GATE v1 — enforces decision-record ↔ DECISIONS.md atomicity
#
# Classification: Mechanism (hook-enforced pre-commit blocker)
#
# Enforces the rule from `~/.claude/rules/planning.md` ("Decision Records"
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

# ---------- self-test ----------------------------------------------------

if [ "${1:-}" = "--self-test" ]; then
  TMPDIR_ST=$(mktemp -d)
  trap 'rm -rf "$TMPDIR_ST"' EXIT

  SCRIPT_PATH="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"

  # Initialize a temp repo
  (
    cd "$TMPDIR_ST" || exit 1
    git init -q . >/dev/null 2>&1
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

  FAIL=0
  run_case "a: record without index" 1 setup_a_record_only || FAIL=1
  run_case "b: index without record" 0 setup_b_index_only || FAIL=1
  run_case "c: both staged"          0 setup_c_both         || FAIL=1
  run_case "d: neither"              0 setup_d_neither      || FAIL=1
  run_case "e: record delete only"   0 setup_e_record_delete || FAIL=1

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
    echo "~/.claude/rules/planning.md 'Decision Records' section: decision"
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
