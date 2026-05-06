# Floor 7 — Testing — Express

Default: **co-located unit tests** (`<name>.test.<ext>` next to source), **integration tests in `tests/integration/`**, no mocking of databases or external services in integration tests, ≥ 80% line coverage on new code, every bug fix ships with a regression test.

- Co-located unit: `<name>.test.ts`, `test_<name>.py`, `<name>_test.go`, etc.
- Integration: real DB (test instance), real network calls (recordings or test endpoints), real fixtures.
- Coverage target: 80% line on new code; reasonable branch coverage on critical paths.
- Bug fixes: failing test FIRST, then the fix.
