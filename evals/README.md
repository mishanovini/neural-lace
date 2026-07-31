# Harness Evaluation Suite

<!-- last-verified: 2026-07-05 (doctor-checked) -->

## Overview

These tests verify that Neural Lace's own security and quality mechanisms work correctly. Run them after any change to hooks, settings, risk profiles, or adapters. Run in CI by `.github/workflows/evals.yml` on every push and PR.

## Golden Tests (`golden/`)

Behavioral tests that verify critical permission boundaries (6 as of this writing):

| Test | What it verifies |
|------|-----------------|
| `credential-push-blocked.sh` | AWS credential pattern in push → blocked |
| `force-push-blocked.sh` | Force push commands → blocked |
| `public-repo-blocked.sh` | Public repo creation/conversion → blocked |
| `env-edit-blocked.sh` | Editing .env/credentials/secrets files → blocked |
| `safe-read-allowed.sh` | Read-only operations → allowed |
| `rules-index-coverage.sh` | Post-Wave-C doctrine invariants (filename kept for CI continuity): `rules/` contains only `constitution.md`; `doctrine/INDEX.md` exists; every non-`-full` `doctrine/*.md` has a row in it; every compact doctrine file stays ≤ 3000 bytes |

## Running Tests

```bash
# Run all golden tests
cd evals
for test in golden/*.sh; do
  echo "Running $test..."
  bash "$test"
  echo ""
done

# Run a specific test
bash golden/force-push-blocked.sh
```

## Structural Tests (`structural/`)

Integrity checks that verify the harness configuration is valid and complete. (Planned)

## Adding Tests

When adding a new hook, risk profile, or permission boundary:
1. Write a golden test that exercises the boundary
2. Include both positive cases (should block) and negative cases (should allow)
3. Test should be runnable standalone with no external dependencies
4. Test should exit 0 on pass, 1 on fail
