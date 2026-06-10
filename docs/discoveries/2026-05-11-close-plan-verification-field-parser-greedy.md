---
title: close-plan.sh Verification-field parser is greedy
date: 2026-05-11
type: failure-mode
status: implemented
auto_applied: true
originating_context: docs/plans/functionality-verification-pipeline.md (Task 3 closure)
decision_needed: Should close-plan.sh (and plan-reviewer.sh Check 12) anchor the `Verification:` field parse to end-of-line or to a specific separator, instead of taking the first occurrence on the line?
predicted_downstream:
  - adapters/claude-code/scripts/close-plan.sh
  - adapters/claude-code/hooks/plan-reviewer.sh
  - docs/failure-modes.md
---

## What was discovered

When closing the functionality-verification-pipeline plan via `close-plan.sh close functionality-verification-pipeline`, Task 3 was misclassified as `Verification: full` instead of the actual `Verification: mechanical` declared at end-of-line. The task line read:

```
- [ ] 3. Update `adapters/claude-code/agents/task-verifier.md` to add functionality-verifier requirement for `Verification: full` runtime tasks — Verification: mechanical
```

The parser found the first occurrence of `Verification: <token>` on the line — which was the literal phrase `Verification: full` inside the task description (a back-reference to the level the task's mechanism gates on) — and used `full` as the verification level. The actual trailing `— Verification: mechanical` field was ignored.

This produced a confusing FAIL: close-plan.sh demanded "prose evidence-block has Verdict: PASS" for a task that already had a valid mechanical `.evidence.json` artifact, with no remediation that worked short of rewording the task description.

Workaround applied this session: rephrased Task 3 to "add functionality-verifier requirement for **full-tier** runtime tasks" — avoided the literal `Verification: full` substring. After the rename, close-plan.sh parsed `mechanical` correctly and the close completed.

## Why it matters

The same failure class will recur every time a task description discusses verification levels in prose. Any task that builds, references, or documents the risk-tiered-verification mechanism is a candidate — and the new functionality-verifier introduced by this plan is exactly such a candidate. Future maintainers will hit this trap, and the failure message points them at the wrong remediation (write prose evidence) instead of the actual fix (reword the description OR fix the parser).

The same parser pattern likely exists in `plan-reviewer.sh` Check 12 (which validates `Verification: <level>` at plan-edit time). If that check is also greedy, it would silently accept the inline-phrase value as the field declaration without flagging the trailing `— Verification: <real-value>` as a contradiction — meaning the plan author has no signal at plan-edit time that the parser will misinterpret the task at close-plan time.

## Options

A. **Anchor parse to a separator before `Verification:`** — require a `—` (em-dash), `;`, `|`, or `--` immediately preceding the field. Per `risk-tiered-verification.md`: "The field MAY use any separator before `Verification:` (`—`, `--`, `;`, `|`); the parser scans the line for the literal `Verification:` token and reads the next word." The current parse takes the first `Verification:` occurrence; tightening it to "the LAST `Verification:` on the line" (or "the `Verification:` immediately following one of the canonical separators") would fix the greediness without breaking the documented contract.

B. **Anchor parse to end-of-line** — require `Verification: <level>` to be the trailing field with no further text after the level token. Most restrictive; would reject legitimate variations.

C. **Plan-reviewer Check 12 detects collision** — if a task line contains MULTIPLE `Verification:` occurrences, flag with a stderr message asking the author to disambiguate (e.g., use backticks around the inline phrase: `` `Verification: full` `` — note this is what Task 3's original wording HAD, with backticks around the inline phrase, and the parser still got greedy because backticks don't change the regex match).

D. **Documentation-only fix** — add a note to `risk-tiered-verification.md` and the plan template warning authors not to use literal `Verification: <token>` substrings in task descriptions. Pattern-level guidance; depends on author awareness.

## Recommendation

**A + C combined.** Fix the parser greediness in both `close-plan.sh` and `plan-reviewer.sh` Check 12 to use the LAST `Verification:` occurrence on the line (one-line regex change). Simultaneously add a Check 12 warning when multiple occurrences exist, so authors get an early signal at plan-edit time instead of discovering the issue at close-plan time. Documentation update (D) follows naturally — the rule's parser-contract section needs to say "last occurrence wins, with optional separator hint."

A alone would close the immediate bug; C alone would surface it earlier but not fix it. Both together close the loop at both edges.

## Decision

**A + C implemented (auto-applied, 2026-06-10 pending-discoveries triage).** Re-verified against the 2026-06-10 repo: close-plan.sh:143 still took the FIRST `Verification:` occurrence (`head -1`) — the bug was live. Note plan-reviewer.sh Check 12 and plan-edit-validator.sh were already last-occurrence (their greedy-`.*` sed anchors to the final occurrence), so the contract chosen is "LAST occurrence wins" everywhere. Class-sweep found two SIBLING any-occurrence exemption greps (plan-reviewer.sh Check-5 Tier A/B exemptions; wire-check-gate.sh flipped-line exemption) where a prose mention of `Verification: mechanical` could wrongly exempt a full-tier task — both converted to last-occurrence extraction. Reversible (single-revert per file); auto-applied per discovery-protocol.

## Implementation log

- `adapters/claude-code/scripts/close-plan.sh` — `head -1` → `tail -1` (last occurrence wins) + new S12 self-test scenario (inline-phrase collision closes successfully with mechanical evidence); self-test 12 scenarios, 0 fail.
- `adapters/claude-code/hooks/plan-reviewer.sh` — Check 12 emits a non-blocking disambiguation notice when a task line carries ≥2 `Verification: <level>` occurrences (recommendation C, warn-form); Check-5 Tier A + Tier B mechanical/contract exemptions converted from any-occurrence grep to last-occurrence sed; self-test green (0 unexpected failures).
- `adapters/claude-code/hooks/wire-check-gate.sh` — mechanical/contract exemption converted to last-occurrence sed; self-test all scenarios matched expectations.
- `adapters/claude-code/rules/risk-tiered-verification.md` — parser contract documents "when the token appears more than once, the LAST occurrence wins" (recommendation D).
- Landed via the 2026-06-10 pending-discoveries-triage branch (commit SHAs in the triage plan's evidence).
