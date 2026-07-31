# Evidence Log — Operator-requirement ledger

> BUILDER RUNTIME EVIDENCE, not a verifier verdict. No `Verdict:` line appears
> below because `task-verifier` has not been invoked on this plan — the
> checkboxes in `docs/plans/operator-requirement-ledger.md` are correctly still
> unflipped. Recorded here so the verifier can replay rather than re-derive.

## Wire check executed — the golden case, replayed end-to-end

Command (real CLI subprocess, sandboxed store):
`bash /private/tmp/.../proveit.sh` — the plan's numbered **Prove it works**
scenario. Every step is a `bash adapters/claude-code/scripts/ask-registry.sh
<verb>` invocation; no function is called in-process.

```
STEP 1  record-requirement --verbatim 'I do not want the agents to pin Opus.
        Opus is a fallback, not the primary option.'   -> req-20260729-c3abd9
STEP 2  declare-invariant x2                            -> inv-1 / inv-2
STEP 3  invariant-verdict inv-2 holds  (the clause the shipped build satisfied)
        invariant-verdict inv-1 violated (the clause it destroyed)
STEP 4  invariant-check --plan-slug operator-requirement-ledger
          violated  .../inv-1  Fable remains the declared primary
                               [21 agents/*.md carry an explicit `model: opus` pin]
          HOLDS     .../inv-2  Opus is used only while Fable is unavailable
                               [model-policy.json: chains are primary->fallback]
          invariant-check: 1/2 invariants hold; 1 unmet
          EXIT = 1
CONTRAST once inv-1 is genuinely fixed:
          invariant-check: 2/2 invariants hold; 0 unmet     EXIT = 0
STORED VERBATIM read back:
          I do not want the agents to pin Opus. Opus is a fallback, not the
          primary option.
```

This is the 2026-07-29 failure replayed against the mechanism built to catch
it: the satisfied invariant does not discharge its violated sibling, and the
resolution is reached through `--plan-slug`, which is the only handle
`task-verifier` has at Step 1.6.

## Runtime verification: self-test, both interpreters

- `/opt/homebrew/bin/bash adapters/claude-code/scripts/ask-registry.sh --self-test`
  → `71 passed, 5 failed`
- `/bin/bash adapters/claude-code/scripts/ask-registry.sh --self-test` (3.2.57)
  → `71 passed, 5 failed`

The 5 failures are PRE-EXISTING and unrelated (BSD `date` in the `set-deadline`
verb). Measured on unmodified HEAD, run from the real `scripts/` directory so
`SCRIPT_DIR`-relative lib sourcing resolves identically: `50 passed, 5 failed`
on both interpreters. Delta introduced by this work: **+21 passes, +0 failures.**

## Runtime verification: mutation testing (every scenario proven discriminating)

14 mutations, each a semantically-valid reversion of the code under test, each
required to turn its named scenario RED. Run on both interpreters; identical
results. Guards: the mutant must differ from source, and must still pass
`bash -n` (so a scenario cannot go red merely because the file became invalid).

`RL1 RL2 RL4 RL5 RL7 RL8 RL9 RL10 RL12 RL13 RL14 RL15 RL16` → DISCRIMINATING.
`RL3` → named scenario red with its own assertion message, flagged SUSPECT only
because collapsing every invariant id to `inv-1` inherently cascades into
downstream scenarios (11 total failures vs the 5 baseline); the cascade is
expected for an id generator, not blanket breakage.

Two real defects were found by this process and are now regression-covered:
1. **Tab-collapse column shift.** TAB is IFS-whitespace, so bash `read -r` folds
   consecutive tabs and an empty evidence cell shifted every later column. Fixed
   at the emitter (every cell non-blank, `-` when empty). RL14 + RL16.
2. **A non-discriminating assertion of my own.** RL14 originally grepped for the
   invariant text as a bare substring — green against the broken code, because a
   shifted column still contains the text, just in the wrong slot. Now positional.

## Runtime verification: manifest

`bash adapters/claude-code/scripts/manifest-check.sh` → `2 red, 0 warn (137
entries)`. Both REDs are pre-existing (`estate-janitor`, `estate-brief`, hook
paths); measured identical at HEAD with 136 entries. The new entry adds no
problem. `--gen-index` regenerated `doctrine/INDEX.md`.

`bash adapters/claude-code/hooks/plan-reviewer.sh docs/plans/operator-requirement-ledger.md`
→ `no findings` (one advisory Check-16 WARN about a missing `ask-id:` header,
left in place deliberately: no ask was registered for this dispatch, and
inventing an id to silence an advisory would be the dishonesty this plan is about).
