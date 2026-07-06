# F.2b task-verifier Docs-impact fixture

`task-verifier` is an LLM agent, not a deterministic script — its "Docs-impact
claim" check (`agents/task-verifier.md` Step 3) cannot be exercised by a bash
`--self-test` the way a hook can. This directory is the mechanical FIXTURE
`plan-edit-validator.sh`/`plan-reviewer.sh`-style verification would use if
invoked, plus the exact expected verifier transcript, so:

1. A human (or a future automated agent-eval harness) can replay this
   scenario against a live `task-verifier` invocation and confirm the verdict
   matches.
2. The scenario is pinned in source so a future prompt edit to
   `agents/task-verifier.md` that silently drops the Docs-impact check is
   detectable by re-running this fixture.

## Fixture: `plan.md` + `plan-evidence.md`

`plan.md` (below, inline — not a separate file, to keep the fixture minimal)
declares one task with a non-`none` Docs-impact claim:

```markdown
# Plan: F.2b fixture plan
Status: ACTIVE
...
## Tasks
- [ ] X.1. Add a new runbook stub — Verification: mechanical — Docs impact: adds docs/runbooks/foo.md
```

`plan-evidence.md` (the evidence the builder wrote before invoking
task-verifier) cites a commit that does NOT touch `docs/runbooks/foo.md`:

```
EVIDENCE BLOCK
==============
Task ID: X.1
Task description: Add a new runbook stub
Verified at: 2026-07-05T00:00:00Z
Verifier: builder (pre-verification)

Commit: <sha-that-only-touches-scripts/foo.sh, no docs/runbooks/foo.md>

Verdict: PASS
```

## Expected task-verifier behavior (the Done-when this fixture proves)

Per `agents/task-verifier.md`'s Step 3 Docs-impact sub-check:

1. Verifier reads the task line: `Docs impact: adds docs/runbooks/foo.md`.
2. Verifier runs (or is expected to run) `git show --stat <sha>` / `git log -- docs/runbooks/foo.md` against the cited commit.
3. Because `docs/runbooks/foo.md` does not appear in that commit's changed-files list, the verifier's Done-when is unmet.
4. **Expected verdict: REFUSE to flip the checkbox** — INCOMPLETE, not PASS, with the reason: "Docs impact claims `adds docs/runbooks/foo.md` but `git show --stat <sha>` shows no change to that path — the docs-impact obligation is unmet."

## Mechanical proxy check (what CAN be scripted)

While the verifier's judgment itself isn't scriptable, the STRUCTURAL
precondition it must check IS — "does the cited commit's diff include the
claimed path." This one-liner is the mechanical core of the check, and is
provided here so a future hook/script wiring (should one be added) has a
ready oracle:

```bash
# Given: $SHA (the cited commit), $CLAIMED_PATH (from the Docs impact: field)
git show --stat "$SHA" | grep -qF "$CLAIMED_PATH"
# exit 0  => doc delta present, claim satisfied
# exit 1  => doc delta ABSENT, task-verifier must refuse the flip
```

Run against this fixture's negative case (a commit that does NOT touch the
claimed path) to confirm the proxy correctly detects the gap:

```bash
cd /tmp && git init -q fixture-repo && cd fixture-repo
git config user.email t@example.test && git config user.name T
echo "x" > scripts/foo.sh 2>/dev/null || (mkdir -p scripts && echo "x" > scripts/foo.sh)
git add scripts/foo.sh && git commit -q -m "add scripts/foo.sh, no docs"
SHA=$(git rev-parse HEAD)
git show --stat "$SHA" | grep -qF "docs/runbooks/foo.md"; echo "exit: $?"   # expect 1 (absent -> gap detected)
```
