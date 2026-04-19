#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# verify-existing-data.sh — Check existing records work with new schema
#
# Usage:
#   ./scripts/verify-existing-data.sh check-nulls <table> <column>
#   ./scripts/verify-existing-data.sh check-fk <table> <column> <ref_table> <ref_column>
#   ./scripts/verify-existing-data.sh check-enum <table> <column> <val1,val2,val3>
#   ./scripts/verify-existing-data.sh run-query "<SQL>"
#
# Requires: DATABASE_URL or SUPABASE_DB_URL environment variable
# Install psql: winget install PostgreSQL.Client
# ═══════════════════════════════════════════════════════════════

set -euo pipefail

DB_URL="${DATABASE_URL:-${SUPABASE_DB_URL:-}}"

if [ -z "$DB_URL" ]; then
  echo "FAIL: Neither DATABASE_URL nor SUPABASE_DB_URL is set"
  echo "Get your connection string from Supabase Dashboard → Settings → Database → Connection string"
  exit 1
fi

if ! command -v psql &> /dev/null; then
  echo "FAIL: psql not found. Install with: winget install PostgreSQL.Client"
  exit 1
fi

MODE="${1:-}"

case "$MODE" in

  check-nulls)
    TABLE="${2:?Usage: check-nulls <table> <column>}"
    COLUMN="${3:?Usage: check-nulls <table> <column>}"

    NULL_COUNT=$(psql "$DB_URL" -t -A -c "SELECT COUNT(*) FROM \"$TABLE\" WHERE \"$COLUMN\" IS NULL")
    TOTAL=$(psql "$DB_URL" -t -A -c "SELECT COUNT(*) FROM \"$TABLE\"")

    if [ "$NULL_COUNT" -gt 0 ]; then
      echo "FAIL: $NULL_COUNT/$TOTAL rows in $TABLE have NULL $COLUMN"
      psql "$DB_URL" -c "SELECT id, created_at FROM \"$TABLE\" WHERE \"$COLUMN\" IS NULL LIMIT 5" 2>/dev/null || true
      exit 1
    else
      echo "PASS: All $TOTAL rows in $TABLE have $COLUMN populated"
      exit 0
    fi
    ;;

  check-fk)
    TABLE="${2:?Usage: check-fk <table> <column> <ref_table> <ref_column>}"
    COLUMN="${3:?}"
    REF_TABLE="${4:?}"
    REF_COLUMN="${5:?}"

    ORPHAN_COUNT=$(psql "$DB_URL" -t -A -c "
      SELECT COUNT(*) FROM \"$TABLE\" t
      LEFT JOIN \"$REF_TABLE\" r ON t.\"$COLUMN\" = r.\"$REF_COLUMN\"
      WHERE t.\"$COLUMN\" IS NOT NULL AND r.\"$REF_COLUMN\" IS NULL
    ")

    if [ "$ORPHAN_COUNT" -gt 0 ]; then
      echo "FAIL: $ORPHAN_COUNT orphaned FK references in $TABLE.$COLUMN → $REF_TABLE.$REF_COLUMN"
      exit 1
    else
      echo "PASS: All FK references valid"
      exit 0
    fi
    ;;

  check-enum)
    TABLE="${2:?Usage: check-enum <table> <column> <val1,val2,val3>}"
    COLUMN="${3:?}"
    VALID_VALUES="${4:?}"

    IN_CLAUSE=$(echo "$VALID_VALUES" | sed "s/,/','/g" | sed "s/^/'/" | sed "s/$/'/")

    INVALID_COUNT=$(psql "$DB_URL" -t -A -c "
      SELECT COUNT(*) FROM \"$TABLE\"
      WHERE \"$COLUMN\" IS NOT NULL AND \"$COLUMN\" NOT IN ($IN_CLAUSE)
    ")

    if [ "$INVALID_COUNT" -gt 0 ]; then
      echo "FAIL: $INVALID_COUNT rows have invalid values in $TABLE.$COLUMN"
      psql "$DB_URL" -c "
        SELECT DISTINCT \"$COLUMN\", COUNT(*) FROM \"$TABLE\"
        WHERE \"$COLUMN\" NOT IN ($IN_CLAUSE)
        GROUP BY \"$COLUMN\" LIMIT 10
      " 2>/dev/null || true
      exit 1
    else
      echo "PASS: All values in $TABLE.$COLUMN are valid"
      exit 0
    fi
    ;;

  run-query)
    QUERY="${2:?Usage: run-query \"<SQL>\"}"
    RESULT=$(psql "$DB_URL" -t -A -c "$QUERY")

    if [ -z "$RESULT" ]; then
      echo "FAIL: Query returned no results"
      echo "Query: $QUERY"
      exit 1
    else
      echo "PASS: Query returned results"
      echo "$RESULT" | head -10
      exit 0
    fi
    ;;

  *)
    echo "Usage: $0 {check-nulls|check-fk|check-enum|run-query} [args...]"
    exit 1
    ;;
esac
