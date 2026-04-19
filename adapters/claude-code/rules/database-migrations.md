# Rules for database migrations (supabase/migrations/**)

When creating or modifying a migration:

1. BEFORE writing, check existing data: `SELECT COUNT(*) FROM <table>`
   If count > 0, your migration MUST handle existing rows.

2. For new NOT NULL columns:
   - Add a DEFAULT value, OR
   - Add as nullable, backfill, THEN alter to NOT NULL
   - NEVER add NOT NULL without a default on a populated table

3. For new tables:
   - Add RLS policies immediately — not in a follow-up
   - Include in the seed_org_defaults function if org-scoped

4. After running, verify:
   - Schema: check column exists with correct type
   - Existing data: ./scripts/verify-existing-data.sh check-nulls <table> <column>

5. For enum/check constraints, verify compliance:
   - ./scripts/verify-existing-data.sh check-enum <table> <column> <val1,val2,...>

6. Use ON CONFLICT for idempotent inserts in seed functions
