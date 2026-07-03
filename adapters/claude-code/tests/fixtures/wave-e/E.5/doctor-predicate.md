# E.5 Doctor Predicate — KPI Script Wiring

## Check: harness-kpis.sh executable

**Purpose:** Verify that `scripts/harness-kpis.sh` exists and is executable.

**Command:**
```bash
[[ -x "$( nl_repo_root )/adapters/claude-code/scripts/harness-kpis.sh" ]]
```

**RED Condition:** Script does not exist or is not executable.

**Fixture:** None — checks filesystem state directly. No self-test-specific fixture needed beyond existence.

## Check: KPI report can be generated

**Purpose:** Verify that `harness-kpis.sh` can generate a report to `docs/reviews/` when run live.

**Command:**
```bash
bash "$( nl_repo_root )/adapters/claude-code/scripts/harness-kpis.sh" && \
  [[ -f "$( nl_repo_root )/docs/reviews/harness-kpis-$( date '+%Y-%m-%d' ).md" ]]
```

**RED Condition:** Script fails or report file is not created.

**Fixture:** Integration test; runs against live state. Assumes signal ledger exists (populated by live sessions).

## Check: --self-test passes

**Purpose:** Verify that `harness-kpis.sh --self-test` completes with all scenarios passing.

**Command:**
```bash
HARNESS_SELFTEST=1 bash "$( nl_repo_root )/adapters/claude-code/scripts/harness-kpis.sh" --self-test
```

**RED Condition:** Self-test exits non-zero or any scenario fails.

**Fixture:** Self-contained; fixture ledgers and nl-issues files are embedded in the `--self-test` code.
