#!/bin/bash
# NEURAL-LACE-HOOK
# migration-naming-gate.sh
#
# PreToolUse hook on Bash (`git commit`) that BLOCKS any NEWLY-ADDED
# database migration file whose name begins with a BARE SEQUENTIAL INTEGER
# prefix (`168_`, `0042_`, `7-`, ...). It REQUIRES a timestamp prefix
# (`YYYYMMDDHHMMSS_` or `YYYYMMDDHHMMSS-`, 14 digits) instead.
#
# WHY (the failure this prevents — real, 2026-06):
#   Two machines, each working on its own branch, both reached for "the
#   next migration number" against a SHARED SEQUENTIAL COUNTER and both
#   created `168_*.sql`. On merge, `supabase db push` applies migrations
#   in lexical order and treats the first `168_*` it sees as already
#   applied — the SECOND `168_*` is SILENTLY SKIPPED. A schema change
#   vanishes with no error. A monotonic-per-machine sequential counter
#   is a coordination point that cannot be coordinated across parallel
#   machines; a timestamp prefix needs no coordination — two machines
#   one second apart produce distinct, correctly-ordered names.
#
#   This is the single highest-leverage parallel-dev gate: the cost of
#   the collision is silent data/schema loss; the cost of the gate is a
#   rename before commit.
#
# SCOPE (what counts as a migration file):
#   A NEWLY-ADDED file (git diff --cached --diff-filter=A) whose path is
#   under a recognized migrations directory:
#     - supabase/migrations/        (Supabase)
#     - **/migrations/              (generic — Django, Rails, Alembic, etc.)
#     - prisma/migrations/          (Prisma — number lives in the dir name)
#   AND whose migration-name component begins with a bare integer prefix.
#
# GRANDFATHERING:
#   Only ADDED files are checked (--diff-filter=A). Existing integer-named
#   migrations already in history are never re-flagged — modifying or even
#   re-staging an existing integer migration does not trip the gate. The
#   discipline binds NEW migrations only; the back-catalog is frozen.
#
# Rule: ~/.claude/doctrine/parallel-dev-discipline.md (Practice 7)
#
# Exit codes:
#   0 — commit allowed (no offending newly-added migration)
#   1 — commit blocked (stderr names every offending file + remediation)
#
# Self-test: invoke with --self-test to exercise the scenario matrix.

set -u

# ============================================================
# Input parsing (PreToolUse Bash contract)
# ============================================================
# Claude Code passes the tool input either via the CLAUDE_TOOL_INPUT env
# var or as a JSON blob on stdin. Mirror the established pattern used by
# observed-errors-gate.sh / findings-ledger-schema-gate.sh.

_read_command() {
  local input="${CLAUDE_TOOL_INPUT:-}"
  if [ -z "$input" ] && [ ! -t 0 ]; then
    input="$(cat 2>/dev/null || echo "")"
  fi
  [ -z "$input" ] && { echo ""; return 0; }
  # Try .tool_input.command, then .command. jq absence → empty (fail-open).
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$input" | jq -r '.tool_input.command // .command // empty' 2>/dev/null || echo ""
  else
    echo ""
  fi
}

# ============================================================
# Migration-naming logic (pure; unit-testable in isolation)
# ============================================================

# Is this path under a recognized migrations directory?
# Echoes the migration-name component to check for an integer prefix:
#   supabase/migrations/168_foo.sql  -> 168_foo.sql        (filename)
#   db/migrations/0042-bar.sql       -> 0042-bar.sql       (filename)
#   prisma/migrations/168_init/...   -> 168_init           (DIRECTORY name)
# Echoes nothing (and returns 1) if the path is not a migration file.
_migration_name_component() {
  local path="$1"

  # Prisma: the integer/timestamp lives in the immediate child DIRECTORY
  # of prisma/migrations/, not the file. Capture that directory name.
  if printf '%s' "$path" | grep -qE '(^|/)prisma/migrations/[^/]+/'; then
    printf '%s' "$path" | sed -E 's#^.*(^|/)prisma/migrations/([^/]+)/.*$#\2#'
    return 0
  fi

  # Supabase + generic: the file itself lives directly in a migrations/ dir
  # and the file's basename carries the prefix. Match both the explicit
  # supabase/migrations/ path and any **/migrations/<file> path.
  if printf '%s' "$path" | grep -qE '(^|/)migrations/[^/]+$'; then
    basename "$path"
    return 0
  fi

  return 1
}

# Does this migration-name component begin with a BARE SEQUENTIAL INTEGER
# prefix that is NOT a 14-digit timestamp?
#   168_foo.sql            -> YES (bare integer)
#   0042-bar.sql           -> YES (bare integer, zero-padded)
#   7_init                 -> YES (bare integer)
#   20260614120000_foo.sql -> NO  (14-digit timestamp)
#   20260614-120000_foo    -> NO  (timestamp w/ separator, still 14 digits)
#   create_users.sql       -> NO  (no leading digits)
#   V1__init.sql           -> NO  (Flyway "V" prefix — not a bare integer)
# Returns 0 (true → BLOCK) for a bare-integer prefix; 1 otherwise.
_has_bare_integer_prefix() {
  local name="$1"

  # Strategy: a valid timestamp prefix is exactly 14 contiguous digits
  # OR a 14-digit value split as 8 digits (date) + sep + 6 digits (time),
  # i.e. YYYYMMDD[-_]HHMMSS. Anything else with a leading integer and a
  # name-separator (`_` or `-` or `.`) — or end-of-name — is a bare
  # sequential prefix → BLOCK.

  # No leading digit at all → not an integer-prefixed migration → ALLOW.
  printf '%s' "$name" | grep -qE '^[0-9]' || return 1

  # 14 contiguous digits then a separator → timestamp → ALLOW.
  printf '%s' "$name" | grep -qE '^[0-9]{14}[_.-]' && return 1
  # 14 contiguous digits then end (e.g. a bare-timestamp dir) → ALLOW.
  printf '%s' "$name" | grep -qE '^[0-9]{14}$' && return 1
  # YYYYMMDD-HHMMSS or YYYYMMDD_HHMMSS (8 + sep + 6) → timestamp → ALLOW.
  printf '%s' "$name" | grep -qE '^[0-9]{8}[_-][0-9]{6}([_.-]|$)' && return 1

  # A leading integer prefix followed by a name-separator (`_`, `-`, `.`)
  # or end-of-name, that did NOT match a timestamp form above → BLOCK.
  printf '%s' "$name" | grep -qE '^[0-9]+([_.-]|$)' && return 0

  return 1
}

# ============================================================
# Main check
# ============================================================

_main_check() {
  local command staged offenders=()
  command="$(_read_command)"

  # Only fire on `git commit`. Allow every other Bash invocation.
  [ -z "$command" ] && return 0
  printf '%s' "$command" | grep -qE '(^|[[:space:];&|])git[[:space:]]+commit([[:space:]]|$)' || return 0

  # Must be inside a git repo to inspect the index.
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0

  # Only NEWLY-ADDED files (grandfathers existing integer migrations).
  staged="$(git diff --cached --name-only --diff-filter=A 2>/dev/null || echo "")"
  [ -z "$staged" ] && return 0

  while IFS= read -r path; do
    [ -z "$path" ] && continue
    local nc
    nc="$(_migration_name_component "$path")" || continue
    [ -z "$nc" ] && continue
    if _has_bare_integer_prefix "$nc"; then
      offenders+=("$path")
    fi
  done <<< "$staged"

  if [ "${#offenders[@]}" -eq 0 ]; then
    return 0
  fi

  # BLOCK with a clear remediation.
  {
    echo "[migration-naming-gate] BLOCKED: newly-added migration(s) use a BARE SEQUENTIAL INTEGER prefix."
    echo ""
    for f in "${offenders[@]}"; do
      echo "  • $f"
    done
    echo ""
    echo "WHY this is blocked:"
    echo "  A sequential counter (168_, 0042_) is a coordination point two"
    echo "  parallel machines/branches cannot coordinate. Both reach for"
    echo "  'the next number', both create 168_*, and on merge 'supabase db"
    echo "  push' SILENTLY SKIPS the second one — a schema change vanishes"
    echo "  with no error. (Real incident, 2026-06.)"
    echo ""
    echo "FIX — rename each file to a UTC-timestamp prefix (no shared counter):"
    echo "  prefix=\$(date -u +%Y%m%d%H%M%S)   # e.g. $(date -u +%Y%m%d%H%M%S)"
    echo "  git mv <old> <dir>/\${prefix}_<descriptive-slug>.sql"
    echo "  # then re-stage and commit. Two machines one second apart still differ."
    echo ""
    echo "Accepted prefix forms: YYYYMMDDHHMMSS_  |  YYYYMMDDHHMMSS-  |  YYYYMMDD-HHMMSS_"
    echo "Rule: ~/.claude/doctrine/parallel-dev-discipline.md (Practice 7)"
    echo ""
    echo "(Existing integer-named migrations already in history are grandfathered —"
    echo " only NEWLY-ADDED files are checked. This binds NEW migrations only.)"
  } >&2
  return 1
}

# ============================================================
# Self-test
# ============================================================

_self_test() {
  local tmp pass=0 fail=0
  tmp="$(mktemp -d)"
  trap "rm -rf '$tmp'" RETURN
  echo "[self-test] tmpdir=$tmp"

  # --- Unit tests for the pure predicates (no git needed) -------------

  _assert_block() { # name should-block
    local name="$1" expect="$2" got
    if _has_bare_integer_prefix "$name"; then got="BLOCK"; else got="ALLOW"; fi
    if [ "$got" = "$expect" ]; then
      echo "  U[$name] -> $got: PASS"; pass=$((pass+1))
    else
      echo "  U[$name] -> $got (expected $expect): FAIL"; fail=$((fail+1))
    fi
  }
  _assert_block "168_add_state_card.sql"        BLOCK
  _assert_block "0042-create-users.sql"         BLOCK
  _assert_block "7_init.sql"                     BLOCK
  _assert_block "168_init"                       BLOCK   # prisma-style dir
  _assert_block "20260614120000_add_card.sql"   ALLOW   # 14-digit ts
  _assert_block "20260614120000-add_card.sql"   ALLOW   # ts w/ dash
  _assert_block "20260614-120000_add_card.sql"  ALLOW   # 8+sep+6 ts
  _assert_block "20260614120000"                ALLOW   # bare ts dir
  _assert_block "create_users_table.sql"        ALLOW   # no leading digit
  _assert_block "V1__init.sql"                  ALLOW   # Flyway V-prefix
  _assert_block "add_foo.sql"                    ALLOW

  # --- Name-component extraction --------------------------------------
  _assert_nc() { # path expected
    local path="$1" expect="$2" got
    got="$(_migration_name_component "$path" || echo "<none>")"
    [ -z "$got" ] && got="<none>"
    if [ "$got" = "$expect" ]; then
      echo "  N[$path] -> $got: PASS"; pass=$((pass+1))
    else
      echo "  N[$path] -> $got (expected $expect): FAIL"; fail=$((fail+1))
    fi
  }
  _assert_nc "supabase/migrations/168_foo.sql"        "168_foo.sql"
  _assert_nc "db/migrations/0042-bar.sql"             "0042-bar.sql"
  _assert_nc "prisma/migrations/168_init/migration.sql" "168_init"
  _assert_nc "src/components/Button.tsx"              "<none>"   # not a migration

  # --- Integration scenarios (real git repo, real index) -------------

  _scenario() { # name setup_fn expect(BLOCK|ALLOW)
    local name="$1" setup="$2" expect="$3"
    local d="$tmp/$name"
    mkdir -p "$d" && ( cd "$d" && git init --quiet && git config user.email t@example.com && git config user.name T )
    ( cd "$d" && eval "$setup" )
    local rc=0
    ( cd "$d" && CLAUDE_TOOL_INPUT='{"tool_input":{"command":"git commit -m x"}}' _main_check 2>/dev/null ) || rc=$?
    if [ "$expect" = "BLOCK" ] && [ "$rc" = "1" ]; then
      echo "  S[$name] BLOCK: PASS"; pass=$((pass+1))
    elif [ "$expect" = "ALLOW" ] && [ "$rc" = "0" ]; then
      echo "  S[$name] ALLOW: PASS"; pass=$((pass+1))
    else
      echo "  S[$name] expected $expect got rc=$rc: FAIL"; fail=$((fail+1))
    fi
  }

  # S1: integer-prefixed newly-added supabase migration → BLOCK
  _scenario "s1_integer_blocked" '
    mkdir -p supabase/migrations
    echo "create table t();" > supabase/migrations/168_add_card.sql
    git add supabase/migrations/168_add_card.sql
  ' BLOCK

  # S2: timestamp-prefixed newly-added migration → ALLOW
  _scenario "s2_timestamp_allowed" '
    mkdir -p supabase/migrations
    echo "create table t();" > supabase/migrations/20260614120000_add_card.sql
    git add supabase/migrations/20260614120000_add_card.sql
  ' ALLOW

  # S3: non-migration file (integer-named but not in a migrations dir) → ALLOW (IGNORED)
  _scenario "s3_non_migration_ignored" '
    mkdir -p src
    echo "x" > src/168_config.ts
    git add src/168_config.ts
  ' ALLOW

  # S4: existing integer migration MODIFIED (not added) → ALLOW (grandfathered)
  _scenario "s4_existing_untouched_allowed" '
    mkdir -p supabase/migrations
    echo "create table t();" > supabase/migrations/168_legacy.sql
    git add . && git commit --quiet -m base
    echo "-- amended" >> supabase/migrations/168_legacy.sql
    git add supabase/migrations/168_legacy.sql
  ' ALLOW

  # S5: no staged files → no-op ALLOW
  _scenario "s5_no_staged_noop" '
    echo "untracked" > floating.txt
  ' ALLOW

  # S6: generic **/migrations/ dir with integer prefix → BLOCK
  _scenario "s6_generic_migrations_blocked" '
    mkdir -p backend/db/migrations
    echo "ALTER TABLE x;" > backend/db/migrations/0042-add-index.sql
    git add backend/db/migrations/0042-add-index.sql
  ' BLOCK

  # S7: prisma integer dir → BLOCK
  _scenario "s7_prisma_integer_blocked" '
    mkdir -p prisma/migrations/168_init
    echo "x" > prisma/migrations/168_init/migration.sql
    git add prisma/migrations/168_init/migration.sql
  ' BLOCK

  # S8: mixed — one good timestamp + one bad integer added together → BLOCK
  _scenario "s8_mixed_blocks_on_offender" '
    mkdir -p supabase/migrations
    echo "a" > supabase/migrations/20260614120000_good.sql
    echo "b" > supabase/migrations/169_bad.sql
    git add supabase/migrations/20260614120000_good.sql supabase/migrations/169_bad.sql
  ' BLOCK

  # S9: non-commit Bash command → no-op ALLOW (gate ignores non-commit)
  (
    d="$tmp/s9_noncommit"; mkdir -p "$d/supabase/migrations"
    ( cd "$d" && git init --quiet && git config user.email t@example.com && git config user.name T
      echo "x" > supabase/migrations/168_bad.sql && git add . )
    rc=0
    ( cd "$d" && CLAUDE_TOOL_INPUT='{"tool_input":{"command":"git status"}}' _main_check 2>/dev/null ) || rc=$?
    if [ "$rc" = "0" ]; then echo "  S[s9_noncommit_ignored] ALLOW: PASS"; pass=$((pass+1))
    else echo "  S[s9_noncommit_ignored] expected ALLOW got rc=$rc: FAIL"; fail=$((fail+1)); fi
  )

  # S10: malformed input (no command) → fail-safe ALLOW
  (
    rc=0
    ( CLAUDE_TOOL_INPUT='not json at all' _main_check 2>/dev/null ) || rc=$?
    if [ "$rc" = "0" ]; then echo "  S[s10_malformed_failsafe] ALLOW: PASS"; pass=$((pass+1))
    else echo "  S[s10_malformed_failsafe] expected ALLOW got rc=$rc: FAIL"; fail=$((fail+1)); fi
  )

  echo ""
  echo "[self-test] $pass passed, $fail failed"
  return "$fail"
}

# ============================================================
# Entry point
# ============================================================

case "${1:-}" in
  --self-test)
    _self_test
    exit $?
    ;;
  *)
    _main_check
    exit $?
    ;;
esac
