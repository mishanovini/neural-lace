Mode: design-skip
Status: COMPLETED

## Why design-skip

Temporary 3-line diagnostic dump (od/wc/awk of `$PR_BODY`) inserted before the
existing `validate_pr_body` call in `pr-template-check.yml` to capture the exact
bytes the runner's env transport delivers — a body that validates PASS locally on
byte-identical content fails only in CI (PR #80, NL-FINDING-030 investigation);
the step will be removed (or replaced by a reviewed robustness fix) before merge.

## Change

Add `printf '%s' "$PR_BODY" | od -c | head` (+ wc -c, awk line count) debug lines
to the Validate step of `.github/workflows/pr-template-check.yml`; no change to
validation semantics or verdicts.

## Outcome

Diagnosis complete in one run: the od dump proved the delivered body was CRLF
(`## Summary

`), root-causing the false FAILs (autocrlf-smudged tracked
`.pr-description.md` uploaded via `gh pr edit --body-file`; validator grep -Fxq
is CR-intolerant; MSYS tools mask the CR locally). Debug step removed in the
same follow-up commit; NL-FINDING-030 records the class and the proposed
validator normalization fix.
