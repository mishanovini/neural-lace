## Decision Log Entry Format

### In the plan file (Decisions Log section):

```
### Decision: [descriptive title]
- **Tier:** 1 / 2 / 3
- **Status:** proceeded with recommendation / awaiting review
- **Chosen:** [what was decided]
- **Alternatives:** [other options with brief pros/cons]
- **Reasoning:** [why this was recommended]
- **Checkpoint:** [commit SHA if Tier 2, or N/A]
- **To reverse:** [what reverting would involve]
```

### In conversation (visible decision block):

```
⚑ Decision ─────────────────────────────────────
[Title] (Tier X — continued with recommendation / awaiting review)
[Brief description of what was decided and why]
Checkpoint: [commit SHA if Tier 2, or N/A]
To reverse: [what reverting would involve]
─────────────────────────────────────────────────
```
