# Harness Evaluation Suite

## Overview

These tests verify that Neural Lace's own security and quality mechanisms work correctly. Run them after any change to hooks, settings, risk profiles, or adapters.

## Golden Tests (`golden/`)

Behavioral tests that verify critical permission boundaries:

| Test | What it verifies |
|------|-----------------|
| `credential-push-blocked.sh` | AWS credential pattern in push → blocked |
| `force-push-blocked.sh` | Force push commands → blocked |
| `public-repo-blocked.sh` | Public repo creation/conversion → blocked |
| `env-edit-blocked.sh` | Editing .env/credentials/secrets files → blocked |
| `safe-read-allowed.sh` | Read-only operations → allowed |

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
