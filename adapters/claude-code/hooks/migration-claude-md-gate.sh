#!/bin/bash
# NEURAL-LACE-MIGRATION-CLAUDE-MD-GATE v1 — enforces Rule 3: migration atomic with CLAUDE.md update
#
# Classification: Mechanism (hook-enforced pre-commit blocker)
#
# Rule 3 (Document Freshness System): when a commit adds a new migration
# file under `supabase/migrations/` AND the project's CLAUDE.md declares a
# `Migrations: through <N>` line, the highest staged migration number must
# match the CLAUDE.md line — OR the CLAUDE.md must be updated in the same
# commit. This keeps the "migrations: through N" claim accurate.
#
# Opt-in: only applies to projects whose CLAUDE.md contains the pattern
# `^Migrations: through [0-9]+$`. Repos without this convention are
# unaffected (silent no-op).
#
# BEHAVIOR
#   1. No staged *.sql under supabase/migrations/ → ALLOW (no-op)
#   2. No project-level CLAUDE.md at repo root    → ALLOW (no-op)
#   3. CLAUDE.md has no "Migrations: through N"   → ALLOW (opt-in)
#   4. Highest staged migration <= N              → ALLOW (claim still accurate)
#   5. Highest staged migration > N AND CLAUDE.md
#      IS ALSO staged                             → ALLOW (claim updated)
#   6. Highest staged migration > N AND CLAUDE.md
#      is NOT staged                              → BLOCK (exit 1)
#
# Migration filenames: extracts the first run of digits anywhere in the
# basename. Supports both `20240415123000_description.sql` and
# `NNNN_description.sql` styles. Filenames without any digits are ignored.
#
# Deletions of migration files do not trigger the gate (unusual operation;
# assume the user knows what they are doing).
#
# INVOCATION
#   1. Pre-commit chain:   migration-claude-md-gate.sh
#                          (no args — reads `git diff --cached --name-status -z`)
#   2. Self-test:          migration-claude-md-gate.sh --self-test
#                          (runs internal assertions, prints OK/FAIL, exits)
#
# EXIT CODES
#   0 — allowed
#   1 — blocked (CLAUDE.md claim is stale and not being updated in this commit)

set -u

# ---------- helpers ------------------------------------------------------

# Extract the first run of digits from a string. Echoes nothing if none found.
extract_first_number() {
  local s="$1"
  # Strip non-digits, keep only the first run via parameter expansion logic.
  local stripped=""
  local i=0 ch
  local started=0
  while [ "$i" -lt "${#s}" ]; do
    ch="${s:$i:1}"
    case "$ch" in
      [0-9])
        stripped="${stripped}${ch}"
        started=1
        ;;
      *)
        if [ "$started" -eq 1 ]; then
          break
        fi
        ;;
    esac
    i=$((i + 1))
  done
  printf '%s' "$stripped"
}

# ---------- self-test ----------------------------------------------------

if [ "${1:-}" = "--self-test" ]; then
  TMPDIR_ST=$(mktemp -d)
  trap 'rm -rf "$TMPDIR_ST"' EXIT

  SCRIPT_PATH="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"

  # Initialize a temp repo with a CLAUDE.md declaring "Migrations: through 050"
  (
    cd "$TMPDIR_ST" || exit 1
    git init -q . >/dev/null 2>&1
    git config user.email "selftest@example.test"
    git config user.name "selftest"
    mkdir -p supabase/migrations
    printf '# Project CLAUDE.md\n\nMigrations: through 050\n\nMore text.\n' > CLAUDE.md
    echo "placeholder" > README.md
    git add CLAUDE.md README.md
    git commit -q -m "init" >/dev/null 2>&1
  ) || { echo "self-test: FAIL — repo init failed" >&2; exit 1; }

  run_case() {
    local label="$1"; local expected_rc="$2"; local setup_fn="$3"
    (
      cd "$TMPDIR_ST" || exit 99
      # Reset state
      git reset -q >/dev/null 2>&1
      # Remove any tmp migration files + restore CLAUDE.md
      rm -f supabase/migrations/*.sql 2>/dev/null || true
      # Ensure migrations dir exists — git reset --hard may purge empty
      # untracked dirs on some platforms.
      mkdir -p supabase/migrations
      git checkout -q -- CLAUDE.md 2>/dev/null || true
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

  # (a) add migration 051 without CLAUDE.md update → BLOCK
  setup_a_migration_no_update() {
    printf 'SELECT 1;\n' > supabase/migrations/051_new_thing.sql
    git add supabase/migrations/051_new_thing.sql
  }

  # (b) add migration 051 WITH CLAUDE.md update → ALLOW
  setup_b_migration_with_update() {
    printf 'SELECT 1;\n' > supabase/migrations/051_new_thing.sql
    # Update CLAUDE.md to claim "through 051"
    sed -i.bak 's/Migrations: through 050/Migrations: through 051/' CLAUDE.md
    rm -f CLAUDE.md.bak
    git add supabase/migrations/051_new_thing.sql CLAUDE.md
  }

  # (c) migration staged but CLAUDE.md has no "Migrations:" line → ALLOW (opt-in)
  setup_c_no_convention() {
    # Rewrite CLAUDE.md without the Migrations line
    printf '# Project CLAUDE.md\n\nSomething else.\n' > CLAUDE.md
    git add CLAUDE.md
    git commit -q -m "strip migrations line" >/dev/null
    printf 'SELECT 1;\n' > supabase/migrations/051_new_thing.sql
    git add supabase/migrations/051_new_thing.sql
  }

  # (d) no migrations staged → ALLOW
  setup_d_no_migrations() {
    echo "another line" >> README.md
    git add README.md
  }

  FAIL=0
  run_case "a: migration added without CLAUDE.md update" 1 setup_a_migration_no_update || FAIL=1

  # Reset back to initial state between cases (c mutates HEAD)
  (
    cd "$TMPDIR_ST" || exit 99
    git reset -q --hard HEAD >/dev/null 2>&1
    mkdir -p supabase/migrations
  )

  run_case "b: migration added with CLAUDE.md update"    0 setup_b_migration_with_update || FAIL=1

  (
    cd "$TMPDIR_ST" || exit 99
    git reset -q --hard HEAD >/dev/null 2>&1
    mkdir -p supabase/migrations
  )

  run_case "c: no Migrations line in CLAUDE.md"          0 setup_c_no_convention || FAIL=1

  # Restore CLAUDE.md with the convention for case d
  (
    cd "$TMPDIR_ST" || exit 99
    printf '# Project CLAUDE.md\n\nMigrations: through 050\n\nMore text.\n' > CLAUDE.md
    git add CLAUDE.md
    git commit -q -m "restore convention" >/dev/null
  )

  run_case "d: no migrations staged"                     0 setup_d_no_migrations || FAIL=1

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

# ---------- opt-in check: CLAUDE.md must exist and declare the convention

CLAUDE_MD="$REPO_ROOT/CLAUDE.md"
if [ ! -f "$CLAUDE_MD" ]; then
  exit 0
fi

# Grep for "Migrations: through <N>" (anchored to line start). Take the
# first match only. Extract N.
CLAIM_LINE=$(grep -E '^Migrations: through [0-9]+$' "$CLAUDE_MD" 2>/dev/null | head -n 1 || true)
if [ -z "$CLAIM_LINE" ]; then
  # Convention not declared in this project's CLAUDE.md — opt-in, silent no-op.
  exit 0
fi

CLAIMED_N=$(echo "$CLAIM_LINE" | grep -oE '[0-9]+' | head -n 1)
if [ -z "$CLAIMED_N" ]; then
  exit 0
fi

# ---------- collect staged files (name-status, null-delimited) -----------

STAGED_LIST_TMP=$(mktemp)
trap 'rm -f "$STAGED_LIST_TMP"' EXIT

( cd "$REPO_ROOT" && git diff --cached --name-status -z --diff-filter=ACMRD ) > "$STAGED_LIST_TMP" 2>/dev/null || true

if [ ! -s "$STAGED_LIST_TMP" ]; then
  exit 0
fi

HIGHEST_STAGED=-1
STAGED_MIGRATIONS=""   # newline-separated list of migration paths (for error msg)
CLAUDE_MD_STAGED=0

mapfile -d '' -t TOKENS < "$STAGED_LIST_TMP"

i=0
N=${#TOKENS[@]}
while [ "$i" -lt "$N" ]; do
  status="${TOKENS[$i]}"
  i=$((i + 1))
  [ "$i" -lt "$N" ] || break
  path="${TOKENS[$i]}"
  i=$((i + 1))

  # Renames consume an extra token (new path). Use destination.
  case "$status" in
    R*)
      if [ "$i" -lt "$N" ]; then
        path="${TOKENS[$i]}"
        i=$((i + 1))
      fi
      status="A"
      ;;
  esac

  # Is this the project CLAUDE.md?
  if [ "$path" = "CLAUDE.md" ]; then
    CLAUDE_MD_STAGED=1
    continue
  fi

  # Migration file? supabase/migrations/*.sql
  case "$path" in
    supabase/migrations/*.sql)
      # Pure deletion: do not trigger.
      if [ "$status" = "D" ]; then
        continue
      fi
      # Extract first run of digits from the basename.
      base="${path##*/}"
      num=$(extract_first_number "$base")
      if [ -z "$num" ]; then
        # Unnumbered migration filename — skip silently.
        continue
      fi
      # Strip leading zeros for numeric comparison (force base-10).
      num_dec=$((10#$num))
      if [ "$num_dec" -gt "$HIGHEST_STAGED" ]; then
        HIGHEST_STAGED="$num_dec"
      fi
      STAGED_MIGRATIONS="${STAGED_MIGRATIONS}${path}"$'\n'
      ;;
  esac
done

# No migrations staged? Nothing to check.
if [ "$HIGHEST_STAGED" -lt 0 ]; then
  exit 0
fi

# Normalize claimed N to base-10.
CLAIMED_DEC=$((10#$CLAIMED_N))

# If highest staged <= claimed, CLAUDE.md is still accurate — allow.
if [ "$HIGHEST_STAGED" -le "$CLAIMED_DEC" ]; then
  exit 0
fi

# Highest staged > claimed. If CLAUDE.md is also staged, allow (user updating
# the claim in the same commit).
if [ "$CLAUDE_MD_STAGED" -eq 1 ]; then
  exit 0
fi

# BLOCK.
{
  echo ""
  echo "================================================================"
  echo "MIGRATION / CLAUDE.md GATE — BLOCKED"
  echo "================================================================"
  echo ""
  echo "New migration(s) staged, but CLAUDE.md is not staged in this commit:"
  echo ""
  printf '%s' "$STAGED_MIGRATIONS" | sed 's/^/  - /'
  echo ""
  echo "CLAUDE.md currently claims:  Migrations: through $CLAIMED_DEC"
  echo "Highest staged migration:    $HIGHEST_STAGED"
  echo ""
  echo "The 'Migrations: through N' line in CLAUDE.md must be updated in the"
  echo "SAME commit as the new migration so the project documentation stays"
  echo "atomic with schema changes."
  echo ""
  echo "To fix:"
  echo "  1. Open CLAUDE.md"
  echo "  2. Update the line to: Migrations: through $HIGHEST_STAGED"
  echo "  3. git add CLAUDE.md"
  echo "  4. Re-run the commit"
  echo ""
  echo "To bypass (not recommended): git commit --no-verify"
  echo "================================================================"
} >&2
exit 1
