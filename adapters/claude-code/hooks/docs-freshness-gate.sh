#!/bin/bash
# NEURAL-LACE-DOCS-FRESHNESS-GATE v1 — enforces Rule 8: structural harness changes touch docs
#
# Classification: Mechanism (hook-enforced pre-commit blocker)
#
# Enforces Rule 8 of the document-freshness system. When a commit contains
# STRUCTURAL changes (Added / Deleted / Renamed) to files under:
#   - adapters/claude-code/hooks/
#   - adapters/claude-code/rules/
#   - adapters/claude-code/agents/
#   - adapters/claude-code/skills/
#   - adapters/claude-code/commands/
#   - principles/
# then the same commit MUST also stage at least one of:
#   - docs/harness-architecture.md
#   - docs/harness-guide.md
#   - docs/best-practices.md
#
# Rationale: adding or removing a hook/rule/agent/skill/command changes what
# the harness DOES — and readers of docs/harness-architecture.md need to see
# that change surfaced. Modifications to an existing file (status M) do NOT
# trigger: most tweaks don't change the harness's surface area and requiring
# a doc touch on every edit is too noisy.
#
# BEHAVIOR
#   1. Get staged name-status: git diff --cached --name-status -z
#   2. Filter to STRUCTURAL changes (status ∈ {A, D, R}) in watched dirs.
#   3. If no structural changes in watched dirs → ALLOW silently.
#   4. If structural changes exist AND at least one of the three doc files
#      is also staged (any status) → ALLOW silently.
#   5. Otherwise → BLOCK (exit 1) with a message listing the structural
#      changes and naming the doc files to update.
#
#   Modifications (M) to existing files in watched dirs: ALLOW.
#   Structural changes outside watched dirs (e.g., docs/, patterns/, evals/,
#   adapters/claude-code/examples/, adapters/claude-code/schemas/): ALLOW.
#
# INVOCATION
#   1. Pre-commit chain: docs-freshness-gate.sh
#                        (no args — reads `git diff --cached --name-status -z`)
#   2. Self-test:        docs-freshness-gate.sh --self-test
#
# EXIT CODES
#   0 — allowed
#   1 — blocked (structural change without doc update)
#
# Not wired into the repo's pre-commit hook automatically. Follow-up work
# (Wave 2 of the doc-freshness plan) chains this gate alongside the other
# freshness hooks.

set -u

# ---------- self-test ----------------------------------------------------

if [ "${1:-}" = "--self-test" ]; then
  TMPDIR_ST=$(mktemp -d)
  trap 'rm -rf "$TMPDIR_ST"' EXIT

  SCRIPT_PATH="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"

  (
    cd "$TMPDIR_ST" || exit 1
    git init -q . >/dev/null 2>&1
    git config user.email "selftest@example.test"
    git config user.name "selftest"
    mkdir -p adapters/claude-code/hooks
    mkdir -p adapters/claude-code/examples
    mkdir -p docs
    echo "placeholder" > README.md
    echo "#!/bin/bash" > adapters/claude-code/hooks/existing-hook.sh
    chmod +x adapters/claude-code/hooks/existing-hook.sh
    echo "# Harness Architecture" > docs/harness-architecture.md
    git add README.md adapters/claude-code/hooks/existing-hook.sh docs/harness-architecture.md
    git commit -q -m "init" >/dev/null 2>&1
  ) || { echo "self-test: FAIL — repo init failed" >&2; exit 1; }

  run_case() {
    local label="$1"; local expected_rc="$2"; local setup_fn="$3"
    (
      cd "$TMPDIR_ST" || exit 99
      git reset -q >/dev/null 2>&1
      git checkout -q -- . 2>/dev/null || true
      # Clean any tmp files from prior cases
      rm -f adapters/claude-code/hooks/new-hook.sh \
            adapters/claude-code/hooks/renamed-hook.sh \
            adapters/claude-code/examples/new-example.md
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

  setup_a_new_hook_no_doc() {
    # Add new hook file, no doc staged → BLOCK
    echo "#!/bin/bash" > adapters/claude-code/hooks/new-hook.sh
    git add adapters/claude-code/hooks/new-hook.sh
  }

  setup_b_new_hook_with_doc() {
    # Add new hook + stage harness-architecture.md → ALLOW
    echo "#!/bin/bash" > adapters/claude-code/hooks/new-hook.sh
    echo "# Harness Architecture v2" > docs/harness-architecture.md
    git add adapters/claude-code/hooks/new-hook.sh docs/harness-architecture.md
  }

  setup_c_modify_existing_hook() {
    # Modify existing hook, no doc → ALLOW (M is not structural)
    echo "# changed" >> adapters/claude-code/hooks/existing-hook.sh
    git add adapters/claude-code/hooks/existing-hook.sh
  }

  setup_d_rename_without_doc() {
    # Rename file in watched dir without doc → BLOCK
    # Use git mv so the status is a rename
    git mv adapters/claude-code/hooks/existing-hook.sh \
           adapters/claude-code/hooks/renamed-hook.sh
  }

  setup_e_new_example_no_doc() {
    # Add file to non-watched dir (examples/) without doc → ALLOW
    echo "# Example" > adapters/claude-code/examples/new-example.md
    git add adapters/claude-code/examples/new-example.md
  }

  FAIL=0
  run_case "a: new hook without doc"          1 setup_a_new_hook_no_doc       || FAIL=1
  run_case "b: new hook with doc"             0 setup_b_new_hook_with_doc     || FAIL=1
  run_case "c: modify existing hook only"     0 setup_c_modify_existing_hook  || FAIL=1
  run_case "d: rename without doc"            1 setup_d_rename_without_doc    || FAIL=1
  run_case "e: new example file (not watched)" 0 setup_e_new_example_no_doc   || FAIL=1

  if [ "$FAIL" -eq 0 ]; then
    echo "self-test: OK"
    exit 0
  fi
  exit 1
fi

# ---------- repo discovery -----------------------------------------------

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
if [ -z "$REPO_ROOT" ]; then
  exit 0
fi

# ---------- collect staged files -----------------------------------------

STAGED_LIST_TMP=$(mktemp)
trap 'rm -f "$STAGED_LIST_TMP"' EXIT

( cd "$REPO_ROOT" && git diff --cached --name-status -z --diff-filter=ACMRD ) > "$STAGED_LIST_TMP" 2>/dev/null || true

if [ ! -s "$STAGED_LIST_TMP" ]; then
  exit 0
fi

mapfile -d '' -t TOKENS < "$STAGED_LIST_TMP"

HAS_DOC_STAGED=0
STRUCTURAL_CHANGES=()   # "<status> <path>" strings for the error message

# Returns 0 if the path is under a watched directory.
is_watched_path() {
  case "$1" in
    adapters/claude-code/hooks/*|\
    adapters/claude-code/rules/*|\
    adapters/claude-code/agents/*|\
    adapters/claude-code/skills/*|\
    adapters/claude-code/commands/*|\
    principles/*)
      return 0
      ;;
  esac
  return 1
}

# Returns 0 if the path is one of the three doc files.
is_doc_path() {
  case "$1" in
    docs/harness-architecture.md|docs/harness-guide.md|docs/best-practices.md)
      return 0
      ;;
  esac
  return 1
}

i=0
N=${#TOKENS[@]}
while [ "$i" -lt "$N" ]; do
  status="${TOKENS[$i]}"
  i=$((i + 1))
  [ "$i" -lt "$N" ] || break
  path="${TOKENS[$i]}"
  i=$((i + 1))

  old_path=""
  case "$status" in
    R*)
      # Rename: the first path was old, next token is new
      old_path="$path"
      if [ "$i" -lt "$N" ]; then
        path="${TOKENS[$i]}"
        i=$((i + 1))
      fi
      ;;
  esac

  # Doc file? (any status)
  if is_doc_path "$path"; then
    HAS_DOC_STAGED=1
    # A doc file path is not itself a "structural harness change" — continue.
    continue
  fi

  # Structural change in a watched dir?
  # For renames (R), record the change if EITHER old or new path is watched
  # (renaming INTO a watched dir should count; renaming OUT of one should
  # also count — either changes the harness surface).
  case "$status" in
    A|D)
      if is_watched_path "$path"; then
        STRUCTURAL_CHANGES+=("$status $path")
      fi
      ;;
    R*)
      watched_old=0; watched_new=0
      if [ -n "$old_path" ] && is_watched_path "$old_path"; then watched_old=1; fi
      if is_watched_path "$path"; then watched_new=1; fi
      if [ "$watched_old" -eq 1 ] || [ "$watched_new" -eq 1 ]; then
        if [ -n "$old_path" ]; then
          STRUCTURAL_CHANGES+=("R $old_path -> $path")
        else
          STRUCTURAL_CHANGES+=("R $path")
        fi
      fi
      ;;
    # M (modify), T (type change), C (copy): not structural for this gate.
    *)
      ;;
  esac
done

# ---------- decision -----------------------------------------------------

if [ "${#STRUCTURAL_CHANGES[@]}" -gt 0 ] && [ "$HAS_DOC_STAGED" -eq 0 ]; then
  {
    echo ""
    echo "================================================================"
    echo "DOCS-FRESHNESS GATE — BLOCKED"
    echo "================================================================"
    echo ""
    echo "Structural changes (Added / Deleted / Renamed) to the harness were"
    echo "staged without a matching doc update:"
    echo ""
    for entry in "${STRUCTURAL_CHANGES[@]}"; do
      echo "  - $entry"
    done
    echo ""
    echo "Rule 8 of the document-freshness system: adding, deleting, or"
    echo "renaming hooks/rules/agents/skills/commands/principles changes the"
    echo "harness's surface area, and readers of the architecture docs need"
    echo "to see that change in the same commit."
    echo ""
    echo "Stage at least one of these files alongside the structural change:"
    echo "  - docs/harness-architecture.md"
    echo "  - docs/harness-guide.md"
    echo "  - docs/best-practices.md"
    echo ""
    echo "If the change truly has no documentation impact (rare — usually"
    echo "means 'this is internal plumbing nobody should learn about'),"
    echo "still add a one-line note to harness-architecture.md explaining"
    echo "the addition/removal."
    echo ""
    echo "Modifications to existing files in these directories do NOT trigger"
    echo "this gate — only structural changes (A/D/R) do."
    echo ""
    echo "To bypass (not recommended): git commit --no-verify"
    echo "================================================================"
  } >&2
  exit 1
fi

exit 0
